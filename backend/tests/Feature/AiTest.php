<?php

namespace Tests\Feature;

use App\Models\JobType;
use App\Models\TaskType;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

final class AiTest extends ApiTestCase
{
    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        config(['nutofe.ai.service_url' => 'http://ai.test', 'nutofe.ai.secret' => 'test-secret']);
        $this->createUser('owner@test.local');
        $this->token = $this->login('owner@test.local')['access_token'];
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = []): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($this->token));
    }

    /** @param  array<string, mixed>  $card */
    private function card(array $card): array
    {
        return $card + ['severity' => 'info', 'body' => 'Body', 'payload' => ['action' => ['type' => 'open_job']], 'entity_type' => null, 'entity_id' => null, 'expires_in_hours' => 36];
    }

    public function test_requests_are_signed_and_proxied(): void
    {
        Http::fake(['ai.test/overview' => Http::response(['completed_jobs' => 3, 'workload' => ['state' => 'light']])]);
        $this->api('GET', '/ai/overview')->assertOk()->assertJsonPath('data.completed_jobs', 3);

        Http::assertSent(function (HttpRequest $r): bool {
            $time = $r->header('X-Nutofe-Time')[0];

            return $r->url() === 'http://ai.test/overview'
                && hash_equals(hash_hmac('sha256', $time."\nGET\n/overview\n", 'test-secret'), $r->header('X-Nutofe-Signature')[0]);
        });
    }

    public function test_the_estimate_uses_the_garment_template_without_milestones(): void
    {
        Http::fake(['ai.test/estimate' => Http::response(['tasks' => [['task_type_id' => 2, 'basis' => 'history', 'suggested_seconds' => 7200]]])]);
        $suit = (int) JobType::query()->where('code', 'three_piece_suit')->value('id');
        $this->api('POST', '/ai/estimate', ['job_type_id' => $suit, 'quantity' => 2])->assertOk()->assertJsonPath('data.tasks.0.basis', 'history');

        Http::assertSent(function (HttpRequest $r) use ($suit): bool {
            $body = json_decode($r->body(), true);
            $milestones = TaskType::query()->where('kind', 'milestone')->pluck('id')->all();

            return $body['job_type_id'] === $suit && $body['quantity'] === 2 && $body['tasks'] !== []
                && array_intersect(array_column($body['tasks'], 'task_type_id'), $milestones) === [];
        });
        $this->assertApiError($this->api('POST', '/ai/estimate', ['job_type_id' => 9999]), 422, 'VALIDATION_FAILED');
    }

    public function test_chat_is_validated_and_answers_from_the_service(): void
    {
        Http::fake(['ai.test/chat' => Http::response(['answer' => 'Work on #024 first.', 'source' => 'analytics', 'job_numbers' => ['024']])]);
        $this->api('POST', '/ai/chat', ['messages' => [['role' => 'user', 'text' => 'What next?']]])->assertOk()->assertJsonPath('data.answer', 'Work on #024 first.');
        $this->assertApiError($this->api('POST', '/ai/chat', ['messages' => [['role' => 'system', 'text' => 'x']]]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('POST', '/ai/chat', ['messages' => []]), 422, 'VALIDATION_FAILED');
    }

    public function test_an_unavailable_ai_service_never_breaks_the_api(): void
    {
        Http::fake(['ai.test/*' => fn () => throw new \Illuminate\Http\Client\ConnectionException('down')]);
        $this->assertApiError($this->api('GET', '/ai/overview'), 503, 'AI_UNAVAILABLE');
        $this->artisan('ai:refresh')->expectsOutputToContain('AI service unavailable')->assertSuccessful();
        $this->api('GET', '/customers')->assertOk();

        Http::fake(['ai.test/*' => Http::response(['error' => 'internal_error'], 500)]);
        $this->assertApiError($this->api('GET', '/ai/overview'), 503, 'AI_UNAVAILABLE');

        DB::table('settings')->where('setting_key', 'ai.enabled')->update(['setting_value' => 'false']);
        $this->assertApiError($this->api('GET', '/ai/overview'), 503, 'AI_UNAVAILABLE')->assertJsonPath('message', 'The AI assistant is switched off in the settings.');

        config(['nutofe.ai.secret' => '']);
        $this->assertApiError($this->api('GET', '/ai/overview'), 503, 'AI_UNAVAILABLE');
    }

    public function test_insight_cards_are_stored_once_expired_when_gone_and_alert_the_owner(): void
    {
        $jobId = (string) Str::uuid7();
        $risk = $this->card(['insight_type' => 'delay_risk', 'severity' => 'critical', 'title' => '#024 is likely to finish late', 'entity_type' => 'job', 'entity_id' => $jobId, 'inputs_hash' => hash('sha256', 'a')]);
        $room = $this->card(['insight_type' => 'workload', 'title' => 'Room for about 12 h more this week', 'inputs_hash' => hash('sha256', 'b')]);
        $reworded = ['body' => 'New wording'] + $room;
        Http::fake(['ai.test/insights' => Http::sequence()->push(['insights' => [$risk, $room], 'method' => 'rules-v1'])->push(['insights' => [$risk, $reworded], 'method' => 'rules-v1'])->push(['insights' => [$reworded], 'method' => 'rules-v1'])]);

        $this->artisan('ai:refresh')->expectsOutput('Insights: 2 new, 0 expired, 2 active');
        $this->artisan('ai:refresh')->expectsOutput('Insights: 0 new, 0 expired, 2 active');
        $notification = DB::table('notifications')->where('notification_type', 'ai_insight')->first();
        $this->assertSame(['#024 is likely to finish late', 'critical', "/jobs/{$jobId}"], [$notification->title, $notification->severity, $notification->route]);
        $this->assertSame(1, DB::table('notifications')->count(), 'info cards do not notify');
        $this->assertSame('New wording', DB::table('ai_insights')->where('insight_type', 'workload')->value('body'), 'same situation, updated text');
        $this->assertSame(2, DB::table('ai_insights')->count());

        $cards = $this->api('GET', '/sync/pull')->json('data.changes.ai_insights');
        $this->assertSame(['#024 is likely to finish late', 'Room for about 12 h more this week'], array_column($cards, 'title'));
        $this->assertSame(['type' => 'open_job'], $cards[0]['payload']['action']);
        $this->assertSame('new', $cards[0]['insight_status']);

        // The risk is gone in the next run: its card expires.
        $this->artisan('ai:refresh')->expectsOutput('Insights: 0 new, 1 expired, 1 active');
        $this->assertSame('expired', DB::table('ai_insights')->where('insight_type', 'delay_risk')->value('insight_status'));
    }

    public function test_the_owner_marks_cards_seen_or_dismisses_them(): void
    {
        Http::fake(['ai.test/insights' => Http::response(['insights' => [$this->card(['insight_type' => 'workload', 'title' => 'Room', 'inputs_hash' => hash('sha256', 'b')])], 'method' => 'rules-v1'])]);
        $this->artisan('ai:refresh');
        $id = (int) DB::table('ai_insights')->value('id');

        $this->api('POST', "/ai/insights/{$id}/seen")->assertOk()->assertJsonPath('data.insight_status', 'seen');
        $this->api('POST', "/ai/insights/{$id}/dismiss")->assertOk()->assertJsonPath('data.insight_status', 'dismissed');
        $this->api('POST', "/ai/insights/{$id}/seen")->assertOk()->assertJsonPath('data.insight_status', 'dismissed', 'never goes back');
        $this->assertNotNull(DB::table('ai_insights')->value('acted_at'));
        $this->assertApiError($this->api('POST', '/ai/insights/9999/dismiss'), 404, 'NOT_FOUND');
        $this->assertApiError($this->api('POST', "/ai/insights/{$id}/delete"), 404, 'NOT_FOUND');
        $this->assertApiError($this->api('GET', '/jobs/'.Str::uuid7().'/ai/forecast'), 404, 'NOT_FOUND');
        $this->assertApiError($this->getJson('/api/v1/ai/overview'), 401, 'UNAUTHENTICATED');
    }
}
