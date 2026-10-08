<?php

namespace App\Http\Controllers;

use App\Http\Requests\Jobs\JobIndexRequest;
use App\Http\Requests\Jobs\JobRequest;
use App\Http\Requests\Jobs\JobStatusRequest;
use App\Http\Requests\Jobs\ProgressOverrideRequest;
use App\Http\Resources\JobResource;
use App\Models\Job;
use App\Services\JobHours;
use App\Services\JobQuery;
use App\Services\JobService;
use App\Support\ApiResponse;
use App\Support\JobStatusMachine;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** /api/v1/jobs — owner and admin (can:business). Mutations return the full job sheet. */
final class JobController extends Controller
{
    public function __construct(
        private readonly JobService $jobs,
        private readonly JobHours $hours,
        private readonly JobQuery $query,
    ) {}

    public function index(JobIndexRequest $request): JsonResponse
    {
        $page = $this->query->list($request->filters())->paginate($request->perPage());
        $this->hours->attachToJobs($page->getCollection());

        return ApiResponse::paginated($page, JobResource::class);
    }

    /** GET /jobs/counts?customer_id= — numbers for the filter chips. */
    public function counts(Request $request): JsonResponse
    {
        $request->validate(['customer_id' => ['sometimes', 'uuid']]);

        return ApiResponse::success($this->query->counts($request->input('customer_id')));
    }

    public function show(Job $job): JsonResponse
    {
        return $this->sheet($job);
    }

    public function store(JobRequest $request): JsonResponse
    {
        $result = $this->jobs->create($request->validated(), $this->context($request));
        $resource = JobResource::make($this->hours->loadDetail($result['job']))->detail();

        return $result['created']
            ? ApiResponse::created($resource, $result['job']->status === 'draft' ? 'Draft saved.' : 'Job queued for production.')
            : ApiResponse::success($resource, 'Job already exists.');
    }

    public function update(JobRequest $request, Job $job): JsonResponse
    {
        return $this->sheet($this->jobs->update($job, $request->validated(), $this->context($request)), 'Job updated.');
    }

    public function status(JobStatusRequest $request, Job $job): JsonResponse
    {
        $to = (string) $request->validated('status');
        $job = $this->jobs->changeStatus(
            $job,
            $to,
            $request->validated('reason'),
            (bool) $request->validated('force', false),
            $request->validated('version') === null ? null : (int) $request->validated('version'),
            $this->context($request),
        );

        return $this->sheet($job, 'Job is now '.mb_strtolower(JobStatusMachine::label($to)).'.');
    }

    public function progressOverride(ProgressOverrideRequest $request, Job $job): JsonResponse
    {
        $percent = $request->percent();
        $job = $this->jobs->setProgressOverride($job, $percent, $this->context($request));

        return $this->sheet($job, $percent === null ? 'Progress is calculated from hours again.' : 'Progress set manually.');
    }

    public function destroy(Request $request, Job $job): JsonResponse
    {
        $this->jobs->deleteDraft($job, $this->context($request));

        return ApiResponse::success(null, 'Draft deleted.');
    }

    private function sheet(Job $job, string $message = 'OK'): JsonResponse
    {
        return ApiResponse::success(JobResource::make($this->hours->loadDetail($job))->detail(), $message);
    }
}
