<?php

namespace App\Services;

use App\Models\InventoryItem;
use App\Support\BusinessClock;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Stock figures, read from v_inventory_stock (never stored). The app computes the same values from its
 * local copy of the ledger (Presenter.inventoryItem), so these rules are mirrored there:
 *  - quantity_on_hand = Σ quantity_change of non-voided transactions;
 *  - stock_status: negative (< 0) → out (≤ 0) → low (≤ min_stock_level) → ok;
 *  - jobs_used_this_month = distinct jobs with usage this calendar month (business timezone).
 */
final class InventoryStock
{
    public const STATUSES = ['ok', 'low', 'out', 'negative'];

    public function __construct(private readonly BusinessClock $clock) {}

    public static function status(float $onHand, float $minLevel): string
    {
        return match (true) {
            $onHand < 0 => 'negative',
            $onHand <= 0 => 'out',
            $onHand <= $minLevel => 'low',
            default => 'ok',
        };
    }

    /**
     * @param  list<string>  $itemKeys  binary ids
     * @return array<string, array{quantity_on_hand: float, stock_status: string, last_transaction_at: Carbon|null, jobs_used_this_month: int}>  keyed by binary id
     */
    public function forItems(array $itemKeys): array
    {
        if ($itemKeys === []) {
            return [];
        }
        $monthStart = $this->clock->today()->startOfMonth()->utc();
        $jobs = DB::table('inventory_transactions')
            ->whereIn('item_id', $itemKeys)
            ->where('transaction_type', 'usage')
            ->whereNotNull('job_id')
            ->whereNull('deleted_at')
            ->where('occurred_at', '>=', $monthStart)
            ->groupBy('item_id')
            ->selectRaw('item_id, COUNT(DISTINCT job_id) AS n')
            ->pluck('n', 'item_id');

        $out = [];
        foreach (DB::table('v_inventory_stock')->whereIn('item_id', $itemKeys)->get(['item_id', 'min_stock_level', 'quantity_on_hand', 'last_transaction_at']) as $row) {
            $onHand = round((float) $row->quantity_on_hand, 3);
            $out[$row->item_id] = [
                'quantity_on_hand' => $onHand,
                'stock_status' => self::status($onHand, (float) $row->min_stock_level),
                'last_transaction_at' => $row->last_transaction_at === null ? null : Carbon::parse($row->last_transaction_at, 'UTC'),
                'jobs_used_this_month' => (int) ($jobs[$row->item_id] ?? 0),
            ];
        }

        return $out;
    }

    /** @return array{quantity_on_hand: float, stock_status: string, last_transaction_at: Carbon|null, jobs_used_this_month: int} */
    public function forItem(InventoryItem $item): array
    {
        return $this->forItems([$item->getKey()])[$item->getKey()] ?? ['quantity_on_hand' => 0.0, 'stock_status' => 'out', 'last_transaction_at' => null, 'jobs_used_this_month' => 0];
    }

    /**
     * Materials that need attention, most urgent first: negative → out → low, then by name
     * (inventory summary and dashboard; mirrored in Presenter.inventorySummary).
     *
     * @param  Collection<int, InventoryItem>  $items
     * @param  array<string, array{stock_status: string}>  $stock  keyed by binary id
     * @return Collection<int, InventoryItem>
     */
    public static function alerts(Collection $items, array $stock): Collection
    {
        $rank = ['negative' => 0, 'out' => 1, 'low' => 2];

        return $items
            ->filter(fn (InventoryItem $i) => ($stock[$i->getKey()]['stock_status'] ?? 'ok') !== 'ok')
            ->sortBy(fn (InventoryItem $i) => sprintf('%d|%s', $rank[$stock[$i->getKey()]['stock_status']], mb_strtolower($i->item_name)))
            ->values();
    }

    /** The balance straight from the ledger (call with the item row locked). */
    public function onHand(InventoryItem $item): float
    {
        return round((float) DB::table('inventory_transactions')->where('item_id', $item->getKey())->whereNull('deleted_at')->sum('quantity_change'), 3);
    }
}
