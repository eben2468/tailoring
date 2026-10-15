<?php

namespace App\Http\Controllers;

use App\Http\Requests\Jobs\WorkLogRequest;
use App\Http\Resources\JobResource;
use App\Http\Resources\WorkLogResource;
use App\Models\Job;
use App\Models\JobTask;
use App\Models\WorkLog;
use App\Services\JobHours;
use App\Services\TimerService;
use App\Support\ApiException;
use App\Support\ApiResponse;
use App\Support\Iso;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * Work timer and work logs. Timer responses are {timer, job, server_time}: the running session (or
 * null), the recalculated job sheet, and the server clock so the app shows elapsed time accurately.
 */
final class TimerController extends Controller
{
    public function __construct(
        private readonly TimerService $timers,
        private readonly JobHours $hours,
    ) {}

    /** GET /timers/active — the signed-in user's running timer (restores the timer after an app restart). */
    public function active(Request $request): JsonResponse
    {
        $log = $this->timers->active($this->user($request));

        return $this->timerResponse($log, $log?->job_task_id);
    }

    /** POST /tasks/{task}/timer/start {id?, note?} */
    public function start(Request $request, JobTask $task): JsonResponse
    {
        $data = $request->validate(['id' => ['nullable', 'uuid'], 'note' => ['sometimes', 'nullable', 'string', 'max:500'], 'occurred_at' => ['sometimes', 'nullable', 'date']]);
        $log = $this->timers->start($task, $data['id'] ?? null, $data['note'] ?? null, $this->context($request), $this->at($data));

        return $this->timerResponse($log, $log->job_task_id, "Timer started on {$task->task_name}.");
    }

    /** POST /timers/stop {note?, complete_task?} — "Pause Work" / "Log & Finish". */
    public function stop(Request $request): JsonResponse
    {
        $data = $request->validate([
            'note' => ['sometimes', 'nullable', 'string', 'max:500'],
            'complete_task' => ['sometimes', 'boolean'],
            'entry_id' => ['sometimes', 'nullable', 'uuid'],
            'occurred_at' => ['sometimes', 'nullable', 'date'],
        ]);
        $complete = (bool) ($data['complete_task'] ?? false);
        $log = $this->timers->stop($data['note'] ?? null, $complete, $this->context($request), $data['entry_id'] ?? null, $this->at($data));

        return $this->timerResponse(null, $log->job_task_id, $complete ? 'Work logged and stage completed.' : 'Timer paused. Work logged.', $log);
    }

    /** POST /timers/switch {task_id, id?, note?} */
    public function switch(Request $request): JsonResponse
    {
        $data = $request->validate([
            'task_id' => ['required', 'uuid'],
            'id' => ['nullable', 'uuid'],
            'note' => ['sometimes', 'nullable', 'string', 'max:500'],
            'occurred_at' => ['sometimes', 'nullable', 'date'],
        ]);
        $task = JobTask::findByUuid($data['task_id']) ?? throw ApiException::validation('task_id', 'This stage does not exist.');
        $log = $this->timers->switch($task, $data['id'] ?? null, $data['note'] ?? null, $this->context($request), $this->at($data));

        return $this->timerResponse($log, $log->job_task_id, "Switched to {$task->task_name}.");
    }

    /** GET /tasks/{task}/work-logs — every entry of a stage, newest first, voided ones included. */
    public function index(JobTask $task): JsonResponse
    {
        $logs = WorkLog::query()
            ->withoutGlobalScope('not_tombstoned')
            ->with('creator:id,full_name')
            ->where('job_task_id', $task->getKey())
            ->orderByDesc('started_at')
            ->limit(500)
            ->get();

        return ApiResponse::success(WorkLogResource::collection($logs)->resolve());
    }

    /** POST /tasks/{task}/work-logs — manual entry or adjustment. */
    public function storeEntry(WorkLogRequest $request, JobTask $task): JsonResponse
    {
        $log = $this->timers->addEntry($task, $request->validated(), $this->context($request));

        return $this->logResponse($log, 'Work added.', 201);
    }

    public function updateEntry(WorkLogRequest $request, WorkLog $workLog): JsonResponse
    {
        $log = $this->timers->update($workLog, $request->validated(), $this->context($request));

        return $this->logResponse($log, 'Entry updated.');
    }

    /** POST /work-logs/{workLog}/void {reason} */
    public function void(Request $request, WorkLog $workLog): JsonResponse
    {
        $data = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255']]);
        $log = $this->timers->void($workLog, $data['reason'], $this->context($request));

        return $this->logResponse($log, 'Entry voided. It no longer counts towards the hours.');
    }

    /** @param  array<string, mixed>  $data */
    private function at(array $data): ?Carbon
    {
        return empty($data['occurred_at']) ? null : $this->timers->occurredAt((string) $data['occurred_at']);
    }

    /** {entry, job} — the changed entry and the recalculated job sheet. */
    private function logResponse(WorkLog $log, string $message, int $status = 200): JsonResponse
    {
        return ApiResponse::success([
            'entry' => WorkLogResource::make($log->load('creator:id,full_name'))->resolve(),
            'job' => $this->sheet($log->job_task_id),
        ], $message, $status);
    }

    private function timerResponse(?WorkLog $running, ?string $taskKey, string $message = 'OK', ?WorkLog $stopped = null): JsonResponse
    {
        return ApiResponse::success([
            'timer' => $running === null ? null : WorkLogResource::make($running)->resolve() + ['task' => $this->taskSummary($running->job_task_id)],
            'stopped' => $stopped === null ? null : WorkLogResource::make($stopped)->resolve(),
            'job' => $taskKey === null ? null : $this->sheet($taskKey),
            'server_time' => Iso::format(now()),
        ], $message);
    }

    /** @return array<string, mixed> */
    private function taskSummary(string $taskKey): array
    {
        /** @var JobTask $task */
        $task = JobTask::query()->with(['taskType', 'job.customer'])->whereKey($taskKey)->firstOrFail();

        return [
            'id' => $task->uuid(),
            'name' => $task->task_name,
            'type_name' => $task->taskType->type_name,
            'job_id' => $task->job->uuid(),
            'job_number' => $task->job->job_number,
            'job_title' => $task->job->title,
            'customer_name' => $task->job->customer->full_name,
        ];
    }

    /** @return array<string, mixed> */
    private function sheet(string $taskKey): array
    {
        $jobKey = (string) JobTask::query()->whereKey($taskKey)->value('job_id');
        $job = $this->hours->loadDetail(Job::query()->whereKey($jobKey)->firstOrFail());

        return JobResource::make($job)->detail()->resolve();
    }
}
