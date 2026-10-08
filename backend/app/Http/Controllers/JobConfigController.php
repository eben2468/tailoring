<?php

namespace App\Http\Controllers;

use App\Http\Requests\Config\JobTypeRequest;
use App\Http\Requests\Config\TaskTypeRequest;
use App\Http\Requests\Config\TemplatesRequest;
use App\Models\JobType;
use App\Models\JobTypeTaskTemplate;
use App\Models\TaskType;
use App\Services\JobTemplateService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Production configuration: garment types (job types) with their routing templates, and the
 * production stage catalogue (task types). Lists show active rows; ?include_inactive=1 for settings.
 */
final class JobConfigController extends Controller
{
    public function __construct(private readonly JobTemplateService $templates) {}

    public function jobTypes(Request $request): JsonResponse
    {
        $types = JobType::query()
            ->with('templates.taskType')
            ->when(! $request->boolean('include_inactive'), fn ($q) => $q->where('is_active', true))
            ->orderBy('sort_order')
            ->orderBy('type_name')
            ->get();

        return ApiResponse::success($types->map(fn (JobType $t) => $this->jobType($t))->values());
    }

    public function showJobType(JobType $jobType): JsonResponse
    {
        return ApiResponse::success($this->jobType($jobType->load('templates.taskType')));
    }

    public function storeJobType(JobTypeRequest $request): JsonResponse
    {
        $jobType = $this->templates->createJobType($request->validated(), $this->context($request));

        return ApiResponse::created($this->jobType($jobType->load('templates.taskType')), 'Garment type added.');
    }

    public function updateJobType(JobTypeRequest $request, JobType $jobType): JsonResponse
    {
        $jobType = $this->templates->updateJobType($jobType, $request->validated(), $this->context($request));

        return ApiResponse::success($this->jobType($jobType->load('templates.taskType')), 'Garment type updated.');
    }

    public function replaceTemplates(TemplatesRequest $request, JobType $jobType): JsonResponse
    {
        $jobType = $this->templates->replaceTemplates($jobType, $request->validated('tasks'), $this->context($request));

        return ApiResponse::success($this->jobType($jobType->load('templates.taskType')), 'Production stages saved. New jobs will use them.');
    }

    public function taskTypes(Request $request): JsonResponse
    {
        $types = TaskType::query()
            ->when(! $request->boolean('include_inactive'), fn ($q) => $q->where('is_active', true))
            ->orderBy('sort_order')
            ->get();

        return ApiResponse::success($types->map(fn (TaskType $t) => $t->toApi())->values());
    }

    public function storeTaskType(TaskTypeRequest $request): JsonResponse
    {
        return ApiResponse::created($this->templates->createTaskType($request->validated(), $this->context($request))->toApi(), 'Stage added.');
    }

    public function updateTaskType(TaskTypeRequest $request, TaskType $taskType): JsonResponse
    {
        return ApiResponse::success($this->templates->updateTaskType($taskType, $request->validated(), $this->context($request))->toApi(), 'Stage updated.');
    }

    /** @return array<string, mixed> */
    private function jobType(JobType $type): array
    {
        return [
            'id' => $type->id,
            'code' => $type->code,
            'name' => $type->type_name,
            'components' => $type->components,
            'description' => $type->description,
            'default_quantity' => $type->default_quantity,
            'sort_order' => $type->sort_order,
            'is_active' => $type->is_active,
            'estimated_seconds' => (int) $type->templates->sum('default_estimated_seconds'),
            'tasks' => $type->templates->map(fn (JobTypeTaskTemplate $tpl) => [
                'task_type' => $tpl->taskType->toApi(),
                'name' => $tpl->displayName(),
                'custom_name' => $tpl->task_name,
                'sort_order' => $tpl->sort_order,
                'default_estimated_seconds' => $tpl->default_estimated_seconds,
            ])->values(),
        ];
    }
}
