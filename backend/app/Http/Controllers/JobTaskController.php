<?php

namespace App\Http\Controllers;

use App\Http\Requests\Jobs\ChecklistItemRequest;
use App\Http\Requests\Jobs\ProgressOverrideRequest;
use App\Http\Requests\Jobs\ReorderTasksRequest;
use App\Http\Requests\Jobs\TaskRequest;
use App\Http\Requests\Jobs\TaskStatusRequest;
use App\Http\Resources\JobResource;
use App\Models\Job;
use App\Models\JobTask;
use App\Models\JobTaskChecklistItem;
use App\Services\JobHours;
use App\Services\JobTaskService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Production tasks and their checklists. Every mutation returns the whole job sheet, so the app
 * shows recalculated hours, progress and the current stage without another request.
 */
final class JobTaskController extends Controller
{
    public function __construct(
        private readonly JobTaskService $tasks,
        private readonly JobHours $hours,
    ) {}

    public function store(TaskRequest $request, Job $job): JsonResponse
    {
        $this->tasks->add($job, $request->payload(), $this->context($request));

        return $this->sheet($job->getKey(), 'Stage added.', 201);
    }

    public function reorder(ReorderTasksRequest $request, Job $job): JsonResponse
    {
        $this->tasks->reorder($job, $request->validated('task_ids'), $this->context($request));

        return $this->sheet($job->getKey(), 'Stages reordered.');
    }

    public function update(TaskRequest $request, JobTask $task): JsonResponse
    {
        $this->tasks->update($task, $request->payload(), $this->context($request));

        return $this->sheet($task->job_id, 'Stage updated.');
    }

    public function status(TaskStatusRequest $request, JobTask $task): JsonResponse
    {
        $status = (string) $request->validated('status');
        $version = $request->validated('version');
        $this->tasks->setStatus($task, $status, $version === null ? null : (int) $version, $this->context($request));

        return $this->sheet($task->job_id, match ($status) {
            'completed' => "{$task->task_name} completed.",
            'in_progress' => "{$task->task_name} started.",
            'skipped' => "{$task->task_name} skipped.",
            default => "{$task->task_name} reopened.",
        });
    }

    public function progressOverride(ProgressOverrideRequest $request, JobTask $task): JsonResponse
    {
        $this->tasks->setProgressOverride($task, $request->percent(), $this->context($request));

        return $this->sheet($task->job_id, 'Stage progress updated.');
    }

    public function destroy(Request $request, JobTask $task): JsonResponse
    {
        $this->tasks->delete($task, $this->context($request));

        return $this->sheet($task->job_id, 'Stage removed.');
    }

    public function storeChecklistItem(ChecklistItemRequest $request, JobTask $task): JsonResponse
    {
        $this->tasks->addChecklistItem($task, $request->validated(), $this->context($request));

        return $this->sheet($task->job_id, 'Subtask added.', 201);
    }

    public function updateChecklistItem(ChecklistItemRequest $request, JobTaskChecklistItem $item): JsonResponse
    {
        $item = $this->tasks->updateChecklistItem($item, $request->validated(), $this->context($request));

        return $this->sheet($this->jobKeyOf($item), 'Subtask updated.');
    }

    public function destroyChecklistItem(Request $request, JobTaskChecklistItem $item): JsonResponse
    {
        $jobKey = $this->jobKeyOf($item);
        $this->tasks->deleteChecklistItem($item, $this->context($request));

        return $this->sheet($jobKey, 'Subtask removed.');
    }

    private function jobKeyOf(JobTaskChecklistItem $item): string
    {
        return (string) JobTask::query()->whereKey($item->job_task_id)->value('job_id');
    }

    private function sheet(string $jobKey, string $message, int $status = 200): JsonResponse
    {
        $job = $this->hours->loadDetail(Job::query()->whereKey($jobKey)->firstOrFail());

        return ApiResponse::success(JobResource::make($job)->detail(), $message, $status);
    }
}
