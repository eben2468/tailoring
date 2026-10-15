<?php

namespace App\Http\Controllers;

use App\Http\Requests\ListRequest;
use App\Http\Requests\Tools\CategoryRequest;
use App\Http\Requests\Tools\MaintenanceRequest;
use App\Http\Requests\Tools\ToolRequest;
use App\Http\Resources\ToolMaintenanceLogResource;
use App\Http\Resources\ToolResource;
use App\Models\Tool;
use App\Models\ToolCategory;
use App\Models\ToolMaintenanceLog;
use App\Services\ToolMaintenance;
use App\Services\ToolService;
use App\Support\ApiException;
use App\Support\ApiResponse;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * /api/v1/tools: tools and equipment, their maintenance history and tool categories. The app reads its
 * synced copy (offline-first); the lists and summary here serve the same figures from v_tool_maintenance_status.
 */
final class ToolController extends Controller
{
    public function __construct(
        private readonly ToolService $tools,
        private readonly ToolMaintenance $maintenance,
    ) {}

    /** GET /tools?q=&category_id=&status=&due=soon|overdue|attention&archived=0|1 — by name. */
    public function index(ListRequest $request): JsonResponse
    {
        $filters = $request->validate([
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'category_id' => ['sometimes', 'integer'],
            'status' => ['sometimes', Rule::in(Tool::STATUSES)],
            'due' => ['sometimes', Rule::in(['soon', 'overdue', 'attention'])],
            'archived' => ['sometimes', 'boolean'],
        ]);
        $tools = Tool::query()
            ->with('category')
            ->when(($filters['archived'] ?? false) == true, fn ($q) => $q->whereNotNull('archived_at'), fn ($q) => $q->whereNull('archived_at'))
            ->when(isset($filters['category_id']), fn ($q) => $q->where('category_id', $filters['category_id']))
            ->when(isset($filters['status']), fn ($q) => $q->where('operational_status', $filters['status']))
            ->when(! empty($filters['q']), function (Builder $q) use ($filters): void {
                $term = '%'.addcslashes((string) $filters['q'], '%_\\').'%';
                $q->where(fn ($w) => $w->where('tool_name', 'like', $term)->orWhere('brand_model', 'like', $term)->orWhere('serial_number', 'like', $term)->orWhere('storage_location', 'like', $term));
            })
            ->orderBy('tool_name')
            ->get();
        $figures = $this->figures($tools);
        if (isset($filters['due'])) {
            $wanted = ['soon' => ['due_soon'], 'overdue' => ['overdue'], 'attention' => ['due_soon', 'overdue']][$filters['due']];
            $tools = $tools->filter(fn (Tool $t) => in_array($figures[$t->getKey()]['maintenance_state'], $wanted, true))->values();
        }
        // The list is small (one workshop): filtered in memory because the due state needs "today".
        $page = (int) ($request->validated('page') ?? 1);
        $perPage = $request->perPage();
        $slice = $tools->slice(($page - 1) * $perPage, $perPage)->values();

        return ApiResponse::success($slice->map(fn (Tool $t) => ToolResource::make($t)->withMaintenance($figures[$t->getKey()]))->all(), 'OK', 200, ['pagination' => [
            'page' => $page, 'per_page' => $perPage, 'total' => $tools->count(), 'total_pages' => max(1, (int) ceil($tools->count() / $perPage)),
        ]]);
    }

    /**
     * GET /tools/summary — tiles and alerts for active (not archived) tools: counts per status, due soon,
     * overdue, per category, and the tools needing attention (overdue → out of service → needs service → due soon).
     */
    public function summary(): JsonResponse
    {
        $tools = Tool::query()->with('category')->whereNull('archived_at')->orderBy('tool_name')->get();
        $figures = $this->figures($tools);
        $status = fn (string $s) => $tools->where('operational_status', $s)->count();
        $state = fn (string $s) => $tools->filter(fn (Tool $t) => $figures[$t->getKey()]['maintenance_state'] === $s)->count();
        $alerts = ToolMaintenance::alerts($tools, $figures);

        return ApiResponse::success([
            'total_tools' => $tools->count(),
            'operational' => $status('operational'),
            'needs_service' => $status('needs_service'),
            'out_of_service' => $status('out_of_service'),
            'retired' => $status('retired'),
            'due_soon' => $state('due_soon'),
            'overdue' => $state('overdue'),
            'by_category' => $tools->groupBy('category_id')->map(fn ($group, $id) => ['category_id' => (int) $id, 'tools' => $group->count()])->values(),
            'alerts' => $alerts->map(fn (Tool $t) => ToolResource::make($t)->withMaintenance($figures[$t->getKey()]))->all(),
        ]);
    }

    public function show(Tool $tool): JsonResponse
    {
        return ApiResponse::success($this->resource($tool));
    }

    public function store(ToolRequest $request): JsonResponse
    {
        $result = $this->tools->create($request->validated(), $this->context($request));

        return $result['created'] ? ApiResponse::created($this->resource($result['tool']), 'Tool added.') : ApiResponse::success($this->resource($result['tool']), 'Tool already exists.');
    }

    public function update(ToolRequest $request, Tool $tool): JsonResponse
    {
        return ApiResponse::success($this->resource($this->tools->update($tool, $request->validated(), $this->context($request))), 'Tool updated.');
    }

    public function archive(Request $request, Tool $tool): JsonResponse
    {
        return ApiResponse::success($this->resource($this->tools->setArchived($tool, true, $this->context($request))), 'Tool archived.');
    }

    public function unarchive(Request $request, Tool $tool): JsonResponse
    {
        return ApiResponse::success($this->resource($this->tools->setArchived($tool, false, $this->context($request))), 'Tool restored.');
    }

    /** GET /tools/{id}/maintenance — the history, newest first. */
    public function logs(ListRequest $request, Tool $tool): JsonResponse
    {
        $query = ToolMaintenanceLog::query()->with('creator:id,full_name')->where('tool_id', $tool->getKey())->orderByDesc('performed_on')->orderByDesc('id');

        return ApiResponse::paginated($query->paginate($request->perPage()), ToolMaintenanceLogResource::class);
    }

    public function logMaintenance(MaintenanceRequest $request, Tool $tool): JsonResponse
    {
        $result = $this->tools->logMaintenance($tool, $request->validated(), $this->context($request));
        $data = [
            'log' => ToolMaintenanceLogResource::make($result['log']->load('creator:id,full_name')),
            'tool' => $this->resource($tool->refresh()),
        ];

        return $result['created'] ? ApiResponse::created($data, 'Maintenance logged.') : ApiResponse::success($data, 'Already logged.');
    }

    /** DELETE /tool-maintenance/{id} — an entry made by mistake (also answers a replay). */
    public function deleteLog(Request $request, string $log): JsonResponse
    {
        $entry = $this->tools->findLog($log) ?? throw ApiException::notFound();
        $this->tools->deleteLog($entry, $this->context($request));

        return ApiResponse::success(null, 'Maintenance entry removed.');
    }

    /** GET /tool-categories — all categories (inactive too) with their number of active tools. */
    public function categories(): JsonResponse
    {
        $counts = Tool::query()->whereNull('archived_at')->groupBy('category_id')->selectRaw('category_id, COUNT(*) AS n')->pluck('n', 'category_id');

        return ApiResponse::success(ToolCategory::query()->orderBy('sort_order')->orderBy('category_name')->get()->map(
            fn (ToolCategory $c) => $c->toApi() + ['item_count' => (int) ($counts[$c->id] ?? 0)],
        ));
    }

    public function storeCategory(CategoryRequest $request): JsonResponse
    {
        return ApiResponse::created($this->tools->createCategory($request->validated(), $this->context($request))->toApi(), 'Category added.');
    }

    public function updateCategory(CategoryRequest $request, ToolCategory $category): JsonResponse
    {
        return ApiResponse::success($this->tools->updateCategory($category, $request->validated(), $this->context($request))->toApi(), 'Category updated.');
    }

    private function resource(Tool $tool): ToolResource
    {
        return ToolResource::make($tool->load('category'))->withMaintenance($this->maintenance->forTool($tool));
    }

    /**
     * @param  Collection<int, Tool>  $tools
     * @return array<string, array{last_maintenance_date: string|null, maintenance_count: int, next_maintenance_date: string|null, maintenance_state: string, days_until_due: int|null}>
     */
    private function figures(Collection $tools): array
    {
        return $this->maintenance->forTools($tools->map(fn (Tool $t) => $t->getKey())->values()->all());
    }
}
