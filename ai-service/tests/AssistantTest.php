<?php

declare(strict_types=1);

namespace Nutofe\Ai\Tests;

use DateTimeImmutable;
use DateTimeZone;
use Nutofe\Ai\Analytics\Analysis;
use Nutofe\Ai\Http\Kernel;
use Nutofe\Ai\Insights\InsightGenerator;
use Nutofe\Ai\Llm\Assistant;
use Nutofe\Ai\Llm\GeminiClient;
use PHPUnit\Framework\TestCase;

final class AssistantTest extends TestCase
{
    private FakeRepository $repo;

    private Analysis $analysis;

    private string $counterDir;

    protected function setUp(): void
    {
        $this->repo = new FakeRepository;
        $this->repo->addJob('027', 12, '2026-10-20', started: true);
        $this->repo->addJob('024', 10, '2026-10-13', priority: 'high');
        $this->repo->items = [['id' => 'i1', 'item_name' => 'Silk thread', 'unit' => 'spool', 'quantity_on_hand' => 3.0, 'min_stock_level' => 10.0, 'reorder_quantity' => 10.0, 'used' => 30.0, 'first_used_at' => '2026-08-13 10:00:00']];
        $this->analysis = new Analysis($this->repo, new DateTimeImmutable('2026-10-12 08:00', new DateTimeZone('UTC')));
        $this->counterDir = sys_get_temp_dir().'/nutofe-ai-test-'.bin2hex(random_bytes(4));
        mkdir($this->counterDir);
    }

    /**
     * @param  list<array<string, mixed>>  $replies  scripted Gemini responses, in order
     * @param  list<array<string, mixed>>  $sent  receives every request body
     */
    private function gemini(array $replies, array &$sent, int $limit = 50): GeminiClient
    {
        return new GeminiClient('test-key', 'gemini-test', $limit, $this->counterDir, function (string $url, array $body) use (&$replies, &$sent): array {
            $sent[] = $body;

            return ['status' => 200, 'body' => (string) json_encode(array_shift($replies))];
        });
    }

    public function test_without_a_model_the_common_questions_are_answered_from_the_analytics(): void
    {
        $sent = [];
        $offline = new GeminiClient('', 'gemini-test', 50, $this->counterDir);
        $assistant = new Assistant($this->analysis, $offline);

        $today = $assistant->answer([['role' => 'user', 'text' => 'What should I work on today?']]);
        $this->assertSame('analytics', $today['source']);
        $this->assertStringContainsString("Work in this order:\n• #027 3-Piece Suit: 12 h left, due Tue 20 Oct", $today['answer']);
        $this->assertSame(['027', '024'], $today['job_numbers']);

        $this->assertStringContainsString('#024 3-Piece Suit finishes Wed 14 Oct, due Tue 13 Oct (1 day late)', $assistant->answer([['role' => 'user', 'text' => 'Which jobs are at risk of being late?']])['answer']);
        $this->assertStringContainsString('Silk thread: about 6 days left', $assistant->answer([['role' => 'user', 'text' => 'Any material running out?']])['answer']);
        $this->assertStringContainsString('the bench has 48 h', $assistant->answer([['role' => 'user', 'text' => 'Can I accept another commission this week?']])['answer']);
        $this->assertStringContainsString('#024 3-Piece Suit: 10 h left, position 2', $assistant->answer([['role' => 'user', 'text' => 'How is #024 doing?']])['answer']);
        $ask = fn (string $q): string => $assistant->answer([['role' => 'user', 'text' => $q]])['answer'];
        $this->assertStringStartsWith('The full assistant (Google Gemini) is not switched on', $ask('Tell me a joke'), 'says why, then what it can do');
        $this->assertStringContainsString('Ask me, for example', $ask('Tell me a joke'));
        $this->assertStringStartsWith("Hello! I'm the Nutɔfe assistant.", $ask('Hello'));
        $this->assertStringStartsWith("I'm the Nutɔfe assistant. With Google Gemini", $ask('Which model are you?'));
        $this->assertStringStartsWith('Nutɔfe in short:', $ask('help mw understand this system'));
        $this->assertStringStartsWith('Work in this order', $ask('Hi, what should I work on today?'), 'a greeting with a question answers the question');
        $this->assertSame([], $sent);
    }

    public function test_when_gemini_is_unavailable_the_reason_is_given(): void
    {
        $quota = new GeminiClient('test-key', 'gemini-quota', 50, $this->counterDir, fn () => ['status' => 429, 'body' => '{}']);
        $this->assertStringStartsWith('The full assistant (Google Gemini) has used up its free allowance for today', (new Assistant($this->analysis, $quota))->answer([['role' => 'user', 'text' => 'Tell me a joke']])['answer']);
        $down = new GeminiClient('test-key', 'gemini-down', 50, $this->counterDir, fn () => throw new \Nutofe\Ai\Llm\LlmUnavailable('The language model could not be reached.', 'unreachable'));
        $this->assertStringStartsWith("The full assistant (Google Gemini) can't be reached right now", (new Assistant($this->analysis, $down))->answer([['role' => 'user', 'text' => 'Tell me a joke']])['answer']);
    }

    public function test_figures_are_sent_with_the_question_so_one_call_is_enough(): void
    {
        $sent = [];
        $llm = $this->gemini([['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => 'Start #027, then #024.']]]]]]], $sent);
        $answer = (new Assistant($this->analysis, $llm))->answer([['role' => 'user', 'text' => 'What should I work on today?']]);

        $this->assertSame('Start #027, then #024.', $answer['answer']);
        $this->assertCount(1, $sent, 'one request: the figures travel with the question');
        $system = $sent[0]['systemInstruction']['parts'][0]['text'];
        $this->assertStringContainsString('Today is Monday 12 October 2026', $system);
        $this->assertStringContainsString('"work_queue":{"jobs":[{"job_number":"027"', $system);
        $this->assertStringContainsString('App guide (Nutɔfe)', $system);
        $this->assertStringContainsString('General tailoring and workshop know-how', $system);
        foreach (['Kofi', 'Mensah', 'phone', '+233'] as $personal) {
            $this->assertStringNotContainsString($personal, (string) json_encode($sent[0]['contents']).substr($system, (int) strpos($system, 'Today is')), 'no personal data in the figures');
        }
    }

    public function test_when_the_main_model_is_used_up_the_next_one_answers_and_it_is_remembered(): void
    {
        $calls = [];
        $reply = fn (string $text) => ['status' => 200, 'body' => (string) json_encode(['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => $text]]]]]])];
        $main = new GeminiClient('test-key', 'gemini-main', 50, $this->counterDir, function () use (&$calls) {
            $calls[] = 'main';

            return ['status' => 429, 'body' => (string) json_encode(['error' => ['code' => 429, 'details' => [['@type' => 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay' => '37057s']]]])];
        });
        $lite = new GeminiClient('test-key', 'gemini-lite', 50, $this->counterDir, function () use (&$calls, $reply) {
            $calls[] = 'lite';

            return $reply('From the lighter model.');
        });
        $chain = new \Nutofe\Ai\Llm\ModelChain([$main, $lite]);
        $answer = (new Assistant($this->analysis, $chain))->answer([['role' => 'user', 'text' => 'Anything late?']]);

        $this->assertSame(['From the lighter model.', 'gemini-lite'], [$answer['answer'], $answer['source']]);
        $this->assertEqualsWithDelta(time() + 37057, $main->blockedUntil(), 5, "Google's reset time is remembered");
        (new Assistant($this->analysis, $chain))->answer([['role' => 'user', 'text' => 'Anything else?']]);
        $this->assertSame(['main', 'lite', 'lite'], $calls, 'the used-up model is skipped without a request');
    }

    public function test_with_gemini_the_answer_is_grounded_in_tool_results_and_carries_no_personal_data(): void
    {
        $sent = [];
        $llm = $this->gemini([
            ['candidates' => [['content' => ['role' => 'model', 'parts' => [['functionCall' => ['name' => 'delay_risks', 'args' => new \stdClass]]]]]]],
            ['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => 'Job #024 will finish a day late. Start it right after #027.']]]]]],
        ], $sent);
        $answer = (new Assistant($this->analysis, $llm))->answer([['role' => 'user', 'text' => 'Anything late?']]);

        $this->assertSame(['answer' => 'Job #024 will finish a day late. Start it right after #027.', 'source' => 'gemini-test', 'job_numbers' => ['024', '027']], $answer);
        $this->assertCount(2, $sent);
        $this->assertSame(['work_queue', 'delay_risks', 'job', 'workload', 'stock_forecast', 'estimate_accuracy'], array_column($sent[0]['tools'][0]['functionDeclarations'], 'name'));
        $this->assertStringContainsString('"args":{}', (string) json_encode($sent[1]['contents'][1]), 'empty arguments go back as an object, not a list (Gemini refuses [])');
        $toolReply = $sent[1]['contents'][2]['parts'][0]['functionResponse'];
        $this->assertSame('delay_risks', $toolReply['name']);
        $this->assertSame('024', $toolReply['response']['jobs'][0]['job_number']);
        // Only figures travel: no ids, names or free text about customers.
        $wire = (string) json_encode(array_column($sent, 'contents')); // the data sent, not the instructions
        foreach (['customer', 'full_name', 'phone', '0192f0a1'] as $forbidden) {
            $this->assertStringNotContainsString($forbidden, $wire);
        }
    }

    public function test_quota_or_provider_errors_fall_back_to_the_analytics(): void
    {
        $sent = [];
        $quota = new GeminiClient('test-key', 'gemini-test', 50, $this->counterDir, fn () => ['status' => 429, 'body' => '{}']);
        $this->assertSame('analytics', (new Assistant($this->analysis, $quota))->answer([['role' => 'user', 'text' => 'What should I work on today?']])['source']);

        $capped = $this->gemini([], $sent, 0);
        $this->assertSame('analytics', (new Assistant($this->analysis, $capped))->answer([['role' => 'user', 'text' => 'What next?']])['source']);
        $this->assertSame([], $sent, 'the daily cap stops calls before they are made');

        $noWait = static fn (int $ms) => null;
        $calls = 0;
        $busy = new GeminiClient('test-key', 'gemini-busy', 50, $this->counterDir, function () use (&$calls) {
            $calls++;

            return ['status' => 503, 'body' => '{"error":{"code":503}}'];
        }, $noWait);
        $this->assertSame('analytics', (new Assistant($this->analysis, $busy))->answer([['role' => 'user', 'text' => 'What next?']])['source'], 'model overloaded');
        $this->assertSame(2, $calls, 'one retry, then the figures');

        $replies = [['status' => 503, 'body' => '{}'], ['status' => 200, 'body' => (string) json_encode(['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => 'Start #027.']]]]]])]];
        $brief = new GeminiClient('test-key', 'gemini-brief', 50, $this->counterDir, function () use (&$replies) {
            return array_shift($replies);
        }, $noWait);
        $this->assertSame(['Start #027.', 'gemini-brief'], array_values(array_slice((new Assistant($this->analysis, $brief))->answer([['role' => 'user', 'text' => 'What next?']]), 0, 2)), 'a brief spike is retried');
    }

    public function test_gemini_3_thinks_briefly_and_leaves_room_for_the_answer(): void
    {
        $sent = [];
        $reply = ['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => 'All on schedule.', 'thoughtSignature' => 'abc']]]]]];
        $gemini3 = new GeminiClient('test-key', 'gemini-3.5-flash', 50, $this->counterDir, function (string $url, array $body) use (&$sent, $reply): array {
            $sent[] = $body;

            return ['status' => 200, 'body' => (string) json_encode($reply)];
        });
        $answer = (new Assistant($this->analysis, $gemini3))->answer([['role' => 'user', 'text' => 'Anything late?']]);

        $this->assertSame(['All on schedule.', 'gemini-3.5-flash'], [$answer['answer'], $answer['source']]);
        $this->assertSame(['temperature' => 0.2, 'maxOutputTokens' => 2048, 'thinkingConfig' => ['thinkingLevel' => 'low']], $sent[0]['generationConfig']);

        $older = $this->gemini([$reply], $sent);
        (new Assistant($this->analysis, $older))->answer([['role' => 'user', 'text' => 'Anything late?']]);
        $this->assertArrayNotHasKey('thinkingConfig', $sent[1]['generationConfig'], 'other models do not take a thinking level');
    }

    public function test_insight_cards_with_evidence_and_stable_hashes(): void
    {
        $gen = new InsightGenerator;
        $cards = $gen->generate($this->analysis->forecast(), $this->analysis->jobs(), $this->analysis->workload(), ['stages' => 0, 'accuracy_percent' => null, 'within_10_percent' => null, 'bias_percent' => null, 'by_stage' => []], $this->analysis->stock());
        $byType = [];
        foreach ($cards as $c) {
            $byType[$c['insight_type']][] = $c;
        }
        $this->assertSame('#024 is likely to finish late', $byType['delay_risk'][0]['title']);
        $this->assertSame(['type' => 'open_job', 'job_id' => $this->repo->jobs[1]['id'], 'label' => 'Open job'], $byType['delay_risk'][0]['payload']['action']);
        $this->assertSame('Start #024 before going on with #027', $byType['priority'][0]['title']);
        $this->assertSame('Silk thread runs out in about 6 days', $byType['inventory_forecast'][0]['title']);
        $this->assertSame('restock', $byType['inventory_forecast'][0]['payload']['action']['type']);
        $this->assertSame('Using about 3.5 spools a week; 3 spools left. Usual restock: 10 spools.', $byType['inventory_forecast'][0]['body']);
        $this->assertSame('1 spool', InsightGenerator::qty(1.0, 'spool'));
        $this->assertSame('2 boxes', InsightGenerator::qty(2.0, 'box'));
        $this->assertSame('18.5 m', InsightGenerator::qty(18.5, 'm'));

        $again = $gen->generate($this->analysis->forecast(), $this->analysis->jobs(), $this->analysis->workload(), ['stages' => 0, 'accuracy_percent' => null, 'within_10_percent' => null, 'bias_percent' => null, 'by_stage' => []], $this->analysis->stock());
        $this->assertSame(array_column($cards, 'inputs_hash'), array_column($again, 'inputs_hash'), 'same situation, same hash');
    }

    public function test_requests_must_be_signed(): void
    {
        $sent = [];
        $kernel = new Kernel('s3cret', $this->repo, $this->gemini([], $sent), $this->analysis);
        $now = 1_800_000_000;
        $ok = fn (string $m, string $p, string $b = '') => $kernel->handle($m, $p, $b, (string) $now, Kernel::sign('s3cret', (string) $now, $m, $p, $b), $now);

        $this->assertSame(200, $ok('GET', '/health')['status']);
        $this->assertTrue($ok('GET', '/health')['body']['llm']['enabled']);
        $this->assertSame(401, $kernel->handle('GET', '/health', '', (string) $now, 'bad', $now)['status']);
        $this->assertSame(401, $kernel->handle('GET', '/health', '', (string) ($now - 600), Kernel::sign('s3cret', (string) ($now - 600), 'GET', '/health', ''), $now)['status'], 'too old: replay refused');
        $this->assertSame(401, (new Kernel('', $this->repo, $this->gemini([], $sent), $this->analysis))->handle('GET', '/health', '', (string) $now, Kernel::sign('', (string) $now, 'GET', '/health', ''), $now)['status'], 'no secret configured: refuse everything');
        $this->assertSame(404, $ok('GET', '/nope')['status']);
        $this->assertSame(422, $ok('POST', '/chat', '{bad')['status']);

        $forecast = $ok('GET', '/jobs/'.$this->repo->jobs[1]['id'].'/forecast')['body']['forecast'];
        $this->assertSame(['024', 'high', 1], [$forecast['job_number'], $forecast['risk'], $forecast['days_late']]);
        $insights = $ok('POST', '/insights')['body'];
        $this->assertNotEmpty($insights['insights']);
        $this->assertNotEmpty($this->repo->predictions, 'forecasts are stored for later accuracy checks');
        $overview = $ok('GET', '/overview')['body'];
        $this->assertSame(4, $overview['completed_jobs']);
        $this->assertSame(['024'], array_column($overview['risks'], 'job_number'));
        $estimate = $ok('POST', '/estimate', (string) json_encode(['job_type_id' => 1, 'quantity' => 1, 'tasks' => [['task_type_id' => 2, 'name' => 'Cutting', 'default_seconds' => 7200]]]))['body'];
        $this->assertSame('defaults', $estimate['tasks'][0]['basis']);
    }
}
