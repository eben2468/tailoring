<?php

namespace App\Http\Controllers;

use App\Models\Job;
use App\Models\JobType;
use App\Services\Ai\AiClient;
use App\Services\Ai\AiInsightService;
use App\Support\ApiException;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * /api/v1/ai/*: the app's door to the AI service (proxied, signed). Insight cards also reach the app
 * through /sync/pull. Any AI failure is 503 AI_UNAVAILABLE and never affects the rest of the API.
 */
final class AiController extends Controller
{
    public function __construct(
        private readonly AiClient $ai,
        private readonly AiInsightService $insights,
    ) {}

    /** GET /ai/overview — estimate accuracy, the coming week, jobs at risk, the work queue, stock running out. */
    public function overview(): JsonResponse
    {
        return ApiResponse::success($this->ai->get('/overview'));
    }

    /** GET /jobs/{id}/ai/forecast — predicted finish, delay risk and reasons (null when not in production). */
    public function forecast(Job $job): JsonResponse
    {
        return ApiResponse::success($this->ai->get('/jobs/'.$job->uuid().'/forecast')['forecast'] ?? null);
    }

    /**
     * POST /ai/estimate {job_type_id, quantity?} — suggested hours per work stage of the garment's template,
     * from the workshop's history. A suggestion only: the owner edits and saves the job.
     */
    public function estimate(Request $request): JsonResponse
    {
        $data = $request->validate(['job_type_id' => ['required', 'integer'], 'quantity' => ['sometimes', 'integer', 'min:1', 'max:100']]);
        /** @var JobType|null $type */
        $type = JobType::query()->with('templates.taskType')->find($data['job_type_id']);
        if ($type === null) {
            throw ApiException::validation('job_type_id', 'This garment type does not exist.');
        }
        $tasks = $type->templates->filter(fn ($t) => ! $t->taskType->isMilestone())->map(fn ($t) => [
            'task_type_id' => $t->task_type_id, 'name' => $t->displayName(), 'default_seconds' => (int) $t->default_estimated_seconds,
        ])->values()->all();

        return ApiResponse::success($this->ai->post('/estimate', ['job_type_id' => $type->id, 'quantity' => (int) ($data['quantity'] ?? 1), 'tasks' => $tasks]));
    }

    /** POST /ai/chat {messages:[{role: user|assistant, text}]} — the last message is the question. */
    public function chat(Request $request): JsonResponse
    {
        $data = $request->validate([
            'messages' => ['required', 'array', 'min:1', 'max:8'],
            'messages.*.role' => ['required', Rule::in(['user', 'assistant'])],
            'messages.*.text' => ['required', 'string', 'max:1000'],
        ]);

        return ApiResponse::success($this->ai->post('/chat', ['messages' => array_values($data['messages'])], 45));
    }

    /** POST /ai/insights/{id}/{seen|dismiss|applied} */
    public function setStatus(Request $request, string $insight, string $action): JsonResponse
    {
        $status = ['seen' => 'seen', 'dismiss' => 'dismissed', 'applied' => 'applied'][$action] ?? throw ApiException::notFound();
        $row = ctype_digit($insight) ? $this->insights->setStatus((int) $insight, $status, $this->user($request)->id) : null;
        if ($row === null) {
            throw ApiException::notFound();
        }

        return ApiResponse::success(['id' => (int) $row->id, 'insight_status' => $row->insight_status]);
    }
}
