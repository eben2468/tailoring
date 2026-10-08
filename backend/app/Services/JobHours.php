<?php

namespace App\Services;

use App\Models\Job;
use App\Models\JobTask;
use App\Support\Iso;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Reads calculated hours and progress from the views (v_job_hours, v_task_hours) and attaches them
 * to models as $job->hours / $task->hours. One query per call, whatever the number of jobs or tasks.
 */
final class JobHours
{
    /** @param  iterable<Job>  $jobs */
    public function attachToJobs(iterable $jobs): void
    {
        $byId = [];
        foreach ($jobs as $job) {
            $byId[$job->getKey()] = $job;
        }
        if ($byId === []) {
            return;
        }

        $rows = DB::table('v_job_hours')->whereIn('job_id', array_keys($byId))->get()->keyBy('job_id');
        foreach ($byId as $id => $job) {
            $row = $rows->get($id);
            $job->hours = [
                'estimated_seconds' => (int) ($row->estimated_seconds ?? 0),
                'actual_seconds' => (int) ($row->actual_seconds ?? 0),
                'remaining_seconds' => (int) ($row->remaining_seconds ?? 0),
                'overrun_seconds' => (int) ($row->overrun_seconds ?? 0),
                'task_count' => (int) ($row->task_count ?? 0),
                'completed_task_count' => (int) ($row->completed_task_count ?? 0),
                'progress_percent' => (float) ($row->progress_percent ?? 0),
                'is_progress_manual' => (bool) ($row->is_progress_manual ?? false),
                'has_running_timer' => (bool) ($row->has_running_timer ?? false),
                'actual_start' => isset($row->actual_start) ? Iso::format(Carbon::parse($row->actual_start, 'UTC')) : null,
            ];
        }
    }

    /** @param  iterable<JobTask>  $tasks */
    public function attachToTasks(iterable $tasks): void
    {
        $byId = [];
        foreach ($tasks as $task) {
            $byId[$task->getKey()] = $task;
        }
        if ($byId === []) {
            return;
        }

        $rows = DB::table('v_task_hours')->whereIn('job_task_id', array_keys($byId))->get()->keyBy('job_task_id');
        foreach ($byId as $id => $task) {
            $row = $rows->get($id);
            $task->hours = [
                'actual_seconds' => (int) ($row->actual_seconds ?? 0),
                'remaining_seconds' => (int) ($row->remaining_seconds ?? 0),
                'overrun_seconds' => (int) ($row->overrun_seconds ?? 0),
                'progress_percent' => (float) ($row->progress_percent ?? 0),
                'is_progress_manual' => (bool) ($row->is_progress_manual ?? false),
                'is_running' => (bool) ($row->is_running ?? false),
                'log_count' => (int) ($row->log_count ?? 0),
                'actual_start' => isset($row->actual_start) ? Iso::format(Carbon::parse($row->actual_start, 'UTC')) : null,
                'actual_end' => isset($row->actual_end) ? Iso::format(Carbon::parse($row->actual_end, 'UTC')) : null,
            ];
        }
    }

    /** Loads everything the job detail screen needs, with hours attached to the job and every task. */
    public function loadDetail(Job $job): Job
    {
        $job = Job::query()
            ->with(['customer', 'jobType', 'measurementSet', 'tasks.taskType', 'tasks.checklist'])
            ->whereKey($job->getKey())
            ->firstOrFail();
        $this->attachToJobs([$job]);
        $this->attachToTasks($job->tasks);

        return $job;
    }
}
