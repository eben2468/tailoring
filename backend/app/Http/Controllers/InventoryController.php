<?php

namespace App\Http\Controllers;

use App\Http\Requests\Inventory\CategoryRequest;
use App\Http\Requests\Inventory\ItemRequest;
use App\Http\Requests\Inventory\TransactionRequest;
use App\Http\Requests\ListRequest;
use App\Http\Resources\InventoryItemResource;
use App\Http\Resources\InventoryTransactionResource;
use App\Models\InventoryCategory;
use App\Models\InventoryItem;
use App\Models\InventoryTransaction;
use App\Models\Job;
use App\Services\InventoryService;
use App\Services\InventoryStock;
use App\Support\ApiException;
use App\Support\ApiResponse;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * /api/v1/inventory: materials, the stock ledger and material categories. The app reads its synced copy
 * (offline-first); the lists and summary here serve the same figures from v_inventory_stock.
 */
final class InventoryController extends Controller
{
    /** stock filter → condition on v_inventory_stock (alias s). */
    private const STOCK_FILTERS = ['ok', 'low', 'out', 'negative', 'attention'];

    public function __construct(
        private readonly InventoryService $inventory,
        private readonly InventoryStock $stock,
    ) {}

    /** GET /inventory/items?q=&category_id=&stock=ok|low|out|negative|attention&archived=0|1 — by name. */
    public function index(ListRequest $request): JsonResponse
    {
        $filters = $request->validate([
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'category_id' => ['sometimes', 'integer'],
            'stock' => ['sometimes', Rule::in(self::STOCK_FILTERS)],
            'archived' => ['sometimes', 'boolean'],
        ]);
        $query = InventoryItem::query()
            ->with('category')
            ->join('v_inventory_stock as s', 's.item_id', '=', 'inventory_items.id')
            ->select('inventory_items.*')
            ->when(($filters['archived'] ?? false) == true, fn ($q) => $q->whereNotNull('inventory_items.archived_at'), fn ($q) => $q->whereNull('inventory_items.archived_at'))
            ->when(isset($filters['category_id']), fn ($q) => $q->where('inventory_items.category_id', $filters['category_id']))
            ->when(! empty($filters['q']), function (Builder $q) use ($filters): void {
                $term = '%'.addcslashes((string) $filters['q'], '%_\\').'%';
                $q->where(fn ($w) => $w->where('inventory_items.item_name', 'like', $term)->orWhere('inventory_items.sku', 'like', $term)->orWhere('inventory_items.description', 'like', $term));
            })
            ->when(isset($filters['stock']), fn ($q) => match ($filters['stock']) {
                'ok' => $q->where('s.is_low_stock', 0),
                'low' => $q->where('s.is_low_stock', 1)->where('s.quantity_on_hand', '>', 0),
                'out' => $q->where('s.quantity_on_hand', 0),
                'negative' => $q->where('s.quantity_on_hand', '<', 0),
                default => $q->where('s.is_low_stock', 1),
            })
            ->orderBy('inventory_items.item_name');
        $page = $query->paginate($request->perPage());
        /** @var Collection<int, InventoryItem> $items */
        $items = $page->getCollection();

        return ApiResponse::success($this->itemResources($items), 'OK', 200, ['pagination' => [
            'page' => $page->currentPage(), 'per_page' => $page->perPage(), 'total' => $page->total(), 'total_pages' => $page->lastPage(),
        ]]);
    }

    /**
     * GET /inventory/summary — the tiles and the replenishment list (active materials only):
     * counts per stock status and per category, and every material that needs attention (negative, out, low).
     */
    public function summary(): JsonResponse
    {
        $items = InventoryItem::query()->with('category')->whereNull('archived_at')->orderBy('item_name')->get();
        $stock = $this->stock->forItems($items->map(fn (InventoryItem $i) => $i->getKey())->values()->all());
        $count = fn (string $status) => $items->filter(fn (InventoryItem $i) => $stock[$i->getKey()]['stock_status'] === $status)->count();
        $alerts = InventoryStock::alerts($items, $stock);

        return ApiResponse::success([
            'total_items' => $items->count(),
            'category_count' => $items->pluck('category_id')->unique()->count(),
            'low_stock' => $count('low'),
            'out_of_stock' => $count('out'),
            'negative' => $count('negative'),
            // Σ stock on hand × unit cost, for materials with a cost (negative stock counts as none).
            'stock_value' => round($items->sum(fn (InventoryItem $i) => $i->unit_cost === null ? 0 : max(0, $stock[$i->getKey()]['quantity_on_hand']) * (float) $i->unit_cost), 2),
            'valued_items' => $items->whereNotNull('unit_cost')->count(),
            'by_category' => $items->groupBy('category_id')->map(fn ($group, $id) => ['category_id' => (int) $id, 'items' => $group->count()])->values(),
            'alerts' => $alerts->map(fn (InventoryItem $i) => InventoryItemResource::make($i)->withStock($stock[$i->getKey()]))->all(),
        ]);
    }

    public function show(InventoryItem $item): JsonResponse
    {
        return ApiResponse::success($this->itemResource($item));
    }

    public function store(ItemRequest $request): JsonResponse
    {
        $result = $this->inventory->createItem($request->validated(), $this->context($request));
        $resource = $this->itemResource($result['item']);

        return $result['created'] ? ApiResponse::created($resource, 'Material added.') : ApiResponse::success($resource, 'Material already exists.');
    }

    public function update(ItemRequest $request, InventoryItem $item): JsonResponse
    {
        return ApiResponse::success($this->itemResource($this->inventory->updateItem($item, $request->validated(), $this->context($request))), 'Material updated.');
    }

    public function archive(Request $request, InventoryItem $item): JsonResponse
    {
        return ApiResponse::success($this->itemResource($this->inventory->setArchived($item, true, $this->context($request))), 'Material archived.');
    }

    public function unarchive(Request $request, InventoryItem $item): JsonResponse
    {
        return ApiResponse::success($this->itemResource($this->inventory->setArchived($item, false, $this->context($request))), 'Material restored.');
    }

    /** GET /inventory/items/{id}/transactions — the ledger, newest first, voided lines included. */
    public function transactions(ListRequest $request, InventoryItem $item): JsonResponse
    {
        $query = InventoryTransaction::query()
            ->withoutGlobalScope('not_tombstoned')
            ->with(['job:id,job_number', 'creator:id,full_name'])
            ->where('item_id', $item->getKey())
            ->orderByDesc('occurred_at')
            ->orderByDesc('id');

        return ApiResponse::paginated($query->paginate($request->perPage()), InventoryTransactionResource::class);
    }

    public function record(TransactionRequest $request, InventoryItem $item): JsonResponse
    {
        $result = $this->inventory->record($item, $request->validated(), $this->context($request));
        $resource = InventoryTransactionResource::make($result['transaction']->load(['item', 'job:id,job_number', 'creator:id,full_name']));
        $messages = ['purchase' => 'Stock received.', 'return' => 'Return recorded.', 'usage' => 'Usage recorded.', 'write_off' => 'Write-off recorded.', 'adjustment' => 'Stock count recorded.', 'opening' => 'Opening balance recorded.'];

        return $result['created']
            ? ApiResponse::created($resource, $messages[$result['transaction']->transaction_type])
            : ApiResponse::success($resource, 'Already recorded.');
    }

    /** POST /inventory/transactions/{id}/void {reason, offline?} — also answers a replay of an earlier void. */
    public function void(Request $request, string $transaction): JsonResponse
    {
        $data = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255'], 'offline' => ['sometimes', 'boolean']]);
        $tx = $this->inventory->findTransaction($transaction) ?? throw ApiException::notFound();
        $tx = $this->inventory->void($tx, $data['reason'], (bool) ($data['offline'] ?? false), $this->context($request));

        return ApiResponse::success(InventoryTransactionResource::make($tx->load(['item', 'job:id,job_number', 'creator:id,full_name'])), 'Entry voided. It no longer counts towards the stock.');
    }

    /** GET /jobs/{job}/materials — what was used for (and returned from) a job, oldest first. */
    public function jobMaterials(Job $job): JsonResponse
    {
        $rows = InventoryTransaction::query()
            ->with(['item', 'creator:id,full_name'])
            ->where('job_id', $job->getKey())
            ->orderBy('occurred_at')
            ->get();

        return ApiResponse::success(InventoryTransactionResource::collection($rows));
    }

    /** GET /inventory/categories — all categories (inactive ones too) with their number of active materials. */
    public function categories(): JsonResponse
    {
        $counts = InventoryItem::query()->whereNull('archived_at')->groupBy('category_id')->selectRaw('category_id, COUNT(*) AS n')->pluck('n', 'category_id');

        return ApiResponse::success(InventoryCategory::query()->orderBy('sort_order')->orderBy('category_name')->get()->map(
            fn (InventoryCategory $c) => $c->toApi() + ['item_count' => (int) ($counts[$c->id] ?? 0)],
        ));
    }

    public function storeCategory(CategoryRequest $request): JsonResponse
    {
        return ApiResponse::created($this->inventory->createCategory($request->validated(), $this->context($request))->toApi(), 'Category added.');
    }

    public function updateCategory(CategoryRequest $request, InventoryCategory $category): JsonResponse
    {
        return ApiResponse::success($this->inventory->updateCategory($category, $request->validated(), $this->context($request))->toApi(), 'Category updated.');
    }

    private function itemResource(InventoryItem $item): InventoryItemResource
    {
        return InventoryItemResource::make($item->load('category'))->withStock($this->stock->forItem($item));
    }

    /**
     * @param  Collection<int, InventoryItem>  $items
     * @return list<InventoryItemResource>
     */
    private function itemResources(Collection $items): array
    {
        $stock = $this->stock->forItems($items->map(fn (InventoryItem $i) => $i->getKey())->values()->all());

        return $items->map(fn (InventoryItem $i) => InventoryItemResource::make($i)->withStock($stock[$i->getKey()]))->values()->all();
    }
}
