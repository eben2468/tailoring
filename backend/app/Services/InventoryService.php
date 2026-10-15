<?php

namespace App\Services;

use App\Models\InventoryCategory;
use App\Models\InventoryItem;
use App\Models\InventoryTransaction;
use App\Models\Job;
use App\Support\ApiException;
use App\Support\RequestContext;
use App\Support\SyncSequence;
use App\Support\Uuid;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Inventory rules (ARCHITECTURE §11, DATABASE_DESIGN §6.6). The app applies the same rules offline
 * (local_ops.dart), so keep the two in step:
 *  - stock on hand is the sum of the ledger; the ledger is append-only (mistakes are voided with a reason);
 *  - quantities are positive; count units (pcs, spool, set …) take whole numbers;
 *  - a stock count (adjustment) sends the counted quantity and records the difference;
 *  - online, nothing may take stock below zero (422 INSUFFICIENT_STOCK). A change recorded offline
 *    (`offline: true`) is accepted anyway, because the material was really used, and is audit-logged;
 *    the item then shows stock_status "negative" until it is recounted;
 *  - archived items keep their history but take no new transactions;
 *  - every write locks the item row, so concurrent changes see each other's balance.
 */
final class InventoryService
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly InventoryStock $stock,
        private readonly SyncSequence $sequence,
        private readonly NotificationRules $rules,
    ) {}

    /**
     * @param  array<string, mixed>  $input
     * @return array{item: InventoryItem, created: bool}
     */
    public function createItem(array $input, RequestContext $context): array
    {
        if (! empty($input['id']) && ($existing = InventoryItem::findByUuid($input['id'])) !== null) {
            return ['item' => $existing, 'created' => false];
        }
        $data = $this->itemData($input, null);
        $opening = (float) ($input['opening_quantity'] ?? 0);

        $item = DB::transaction(function () use ($data, $input, $opening, $context): InventoryItem {
            $item = new InventoryItem($data);
            if (! empty($input['id'])) {
                $item->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $this->guardQuantity($item, $opening, 'opening_quantity', allowZero: true);
            $item->save();
            if ($opening > 0) {
                $tx = new InventoryTransaction([
                    'item_id' => $item->getKey(),
                    'transaction_type' => 'opening',
                    'quantity_change' => $this->decimal($opening),
                    'unit_cost' => $item->unit_cost,
                    'note' => 'Opening balance',
                    'occurred_at' => isset($input['occurred_at']) ? $this->occurredAt((string) $input['occurred_at']) : now(),
                ]);
                if (! empty($input['opening_transaction_id'])) {
                    $tx->setAttribute('id', Uuid::toBytes($input['opening_transaction_id']));
                }
                $tx->save();
            }
            $this->audit->log($context, 'inventory.item_created', 'inventory_item', $item->uuid(), ['item_name' => $item->item_name, 'opening_quantity' => $opening]);

            return $item;
        });

        return ['item' => $item, 'created' => true];
    }

    /** @param  array<string, mixed>  $input  changed fields + `version` */
    public function updateItem(InventoryItem $item, array $input, RequestContext $context): InventoryItem
    {
        return DB::transaction(function () use ($item, $input, $context): InventoryItem {
            $locked = $this->lock($item);
            if ($locked->version !== (int) $input['version']) {
                throw ApiException::conflict('This material was changed on another device. Reload to see the latest details.', 'CONFLICT_VERSION');
            }
            $data = $this->itemData($input, $locked);
            if (isset($data['unit']) && $data['unit'] !== $locked->unit
                && InventoryTransaction::query()->where('item_id', $locked->getKey())->exists()) {
                throw ApiException::validation('unit', 'The unit cannot change once stock has been recorded. Add a new material instead.');
            }
            $before = $locked->only(array_keys($data));
            $locked->fill($data)->save();
            $this->audit->log($context, 'inventory.item_updated', 'inventory_item', $locked->uuid(), ['before' => $before, 'after' => $locked->only(array_keys($data))]);

            return $locked;
        });
    }

    public function setArchived(InventoryItem $item, bool $archived, RequestContext $context): InventoryItem
    {
        return DB::transaction(function () use ($item, $archived, $context): InventoryItem {
            $locked = $this->lock($item);
            if (($locked->archived_at !== null) === $archived) {
                return $locked; // replay
            }
            $locked->setAttribute('archived_at', $archived ? now() : null);
            $locked->save();
            $this->audit->log($context, $archived ? 'inventory.item_archived' : 'inventory.item_unarchived', 'inventory_item', $locked->uuid(), ['item_name' => $locked->item_name]);

            return $locked;
        });
    }

    /**
     * Records a stock transaction.
     *
     * @param  array<string, mixed>  $input  {id?, transaction_type, quantity | counted_quantity, job_id?, unit_cost?, reference?, note?, occurred_at?, offline?}
     * @return array{transaction: InventoryTransaction, created: bool}
     */
    public function record(InventoryItem $item, array $input, RequestContext $context): array
    {
        if (! empty($input['id']) && ($existing = $this->findTransaction((string) $input['id'])) !== null) {
            return ['transaction' => $existing, 'created' => false];
        }
        $type = (string) $input['transaction_type'];
        $offline = (bool) ($input['offline'] ?? false);

        $tx = DB::transaction(function () use ($item, $input, $type, $offline, $context): InventoryTransaction {
            $locked = $this->lock($item);
            if ($locked->archived_at !== null) {
                throw ApiException::conflict('This material is archived. Restore it to record stock.', 'ITEM_ARCHIVED');
            }
            $onHand = $this->stock->onHand($locked);

            if ($type === 'adjustment') {
                $counted = (float) $input['counted_quantity'];
                $this->guardQuantity($locked, $counted, 'counted_quantity', allowZero: true);
                $change = round($counted - $onHand, 3);
                if ($change == 0.0) {
                    throw ApiException::validation('counted_quantity', sprintf('The stock already shows %s.', $this->quantity($onHand, $locked->unit)));
                }
            } else {
                $quantity = (float) $input['quantity'];
                $this->guardQuantity($locked, $quantity, 'quantity');
                $change = in_array($type, InventoryTransaction::REDUCTIONS, true) ? -$quantity : $quantity;
            }

            $jobKey = null;
            if (! empty($input['job_id'])) {
                if (! in_array($type, InventoryTransaction::JOB_TYPES, true)) {
                    throw ApiException::validation('job_id', 'Only usage and returns can be linked to a job.');
                }
                $jobKey = (Job::findByUuid((string) $input['job_id']) ?? throw ApiException::validation('job_id', 'This job does not exist.'))->getKey();
            }
            if (isset($input['unit_cost']) && $type !== 'purchase') {
                throw ApiException::validation('unit_cost', 'A cost can only be recorded with a purchase.');
            }

            $after = round($onHand + $change, 3);
            if ($change < 0 && $after < 0) {
                if (! $offline) {
                    throw $this->insufficient($onHand, $locked, $type === 'adjustment' ? 'counted_quantity' : 'quantity');
                }
                $this->audit->log($context, 'inventory.negative_stock', 'inventory_item', $locked->uuid(), ['quantity_on_hand' => $after, 'transaction_type' => $type]);
            }

            $tx = new InventoryTransaction([
                'item_id' => $locked->getKey(),
                'transaction_type' => $type,
                'quantity_change' => $this->decimal($change),
                'job_id' => $jobKey,
                'unit_cost' => $input['unit_cost'] ?? null,
                'reference' => $this->clean($input['reference'] ?? null),
                'note' => $this->clean($input['note'] ?? null),
                'occurred_at' => isset($input['occurred_at']) ? $this->occurredAt((string) $input['occurred_at']) : now(),
            ]);
            if (! empty($input['id'])) {
                $tx->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $tx->save();
            if (in_array($type, ['adjustment', 'write_off'], true)) {
                $this->audit->log($context, 'inventory.'.($type === 'adjustment' ? 'stock_counted' : 'written_off'), 'inventory_transaction', $tx->uuid(), [
                    'item' => $locked->item_name, 'before' => $onHand, 'change' => $change, 'after' => $after, 'note' => $tx->note,
                ]);
            }

            return $tx;
        });

        $this->alertStock($tx->item_id);

        return ['transaction' => $tx, 'created' => true];
    }

    /** Voids a transaction entered by mistake: it stays in the ledger but no longer counts. */
    public function void(InventoryTransaction $tx, string $reason, bool $offline, RequestContext $context): InventoryTransaction
    {
        if ($tx->deleted_at !== null) {
            return $tx; // replay
        }

        $voided = DB::transaction(function () use ($tx, $reason, $offline, $context): InventoryTransaction {
            /** @var InventoryItem $item */
            $item = InventoryItem::query()->whereKey($tx->item_id)->lockForUpdate()->firstOrFail();
            /** @var InventoryTransaction $locked */
            $locked = InventoryTransaction::query()->whereKey($tx->getKey())->lockForUpdate()->firstOrFail();
            $onHand = $this->stock->onHand($item);
            $after = round($onHand - (float) $locked->quantity_change, 3);
            if ($after < 0 && (float) $locked->quantity_change > 0 && ! $offline) {
                throw new ApiException(422, 'INSUFFICIENT_STOCK', sprintf(
                    'Voiding this would leave %s in stock. Record the usage correction or a stock count instead.',
                    $this->quantity($after, $item->unit),
                ));
            }
            $locked->setAttribute('void_reason', mb_substr(trim($reason), 0, 255));
            $locked->tombstone();
            $this->audit->log($context, 'inventory.transaction_voided', 'inventory_transaction', $locked->uuid(), [
                'item' => $item->item_name, 'type' => $locked->transaction_type, 'quantity_change' => (float) $locked->quantity_change, 'reason' => $reason,
            ]);

            return $locked;
        });
        $this->alertStock($voided->item_id);

        return $voided;
    }

    /** Low / depleted / negative stock alerts after a change (never fails the change itself). */
    private function alertStock(string $itemKey): void
    {
        try {
            $item = InventoryItem::query()->find($itemKey);
            if ($item !== null) {
                $this->rules->stockChanged($item);
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /** A transaction by id, voided ones included (for replays and the ledger). */
    public function findTransaction(string $id): ?InventoryTransaction
    {
        if (! Uuid::isValid($id)) {
            return null;
        }

        /** @var InventoryTransaction|null */
        return InventoryTransaction::query()->withoutGlobalScope('not_tombstoned')->whereKey(Uuid::toBytes($id))->first();
    }

    /** @param  array{category_name: string, sort_order?: int|null}  $input */
    public function createCategory(array $input, RequestContext $context): InventoryCategory
    {
        return DB::transaction(function () use ($input, $context): InventoryCategory {
            $name = trim($input['category_name']);
            $this->guardCategoryName($name, null);
            $category = new InventoryCategory([
                'category_name' => $name,
                'sort_order' => $input['sort_order'] ?? (int) InventoryCategory::query()->max('sort_order') + 10,
            ]);
            $category->save();
            $category->refresh(); // is_active comes from the column default
            $this->sequence->bumpConfigVersion();
            $this->audit->log($context, 'config.inventory_category_created', 'inventory_category', $category->id, ['category_name' => $name]);

            return $category;
        });
    }

    /** @param  array<string, mixed>  $input */
    public function updateCategory(InventoryCategory $category, array $input, RequestContext $context): InventoryCategory
    {
        return DB::transaction(function () use ($category, $input, $context): InventoryCategory {
            $data = array_intersect_key($input, array_flip(['category_name', 'sort_order', 'is_active']));
            if (isset($data['category_name'])) {
                $data['category_name'] = trim($data['category_name']);
                $this->guardCategoryName($data['category_name'], $category->id);
            }
            $before = $category->only(array_keys($data));
            $category->fill($data)->save();
            $this->sequence->bumpConfigVersion();
            $this->audit->log($context, 'config.inventory_category_updated', 'inventory_category', $category->id, ['before' => $before, 'after' => $data]);

            return $category;
        });
    }

    /**
     * @param  array<string, mixed>  $input
     * @return array<string, mixed>
     */
    private function itemData(array $input, ?InventoryItem $existing): array
    {
        $data = array_intersect_key($input, array_flip([
            'category_id', 'item_name', 'sku', 'description', 'unit', 'min_stock_level', 'reorder_quantity', 'unit_cost',
            'supplier_name', 'supplier_contact', 'storage_location', 'notes',
        ]));
        foreach (['item_name', 'sku', 'description', 'supplier_name', 'supplier_contact', 'storage_location', 'notes'] as $key) {
            if (array_key_exists($key, $data)) {
                $data[$key] = $this->clean($data[$key]);
            }
        }
        if (array_key_exists('item_name', $data) && $data['item_name'] === null) {
            throw ApiException::validation('item_name', 'Give the material a name.');
        }
        if (isset($data['category_id']) && (int) $data['category_id'] !== $existing?->category_id) {
            $category = InventoryCategory::query()->find($data['category_id']);
            if ($category === null || ! $category->is_active) {
                throw ApiException::validation('category_id', 'Choose an active category.');
            }
        }
        if (isset($data['sku'])) {
            $taken = InventoryItem::query()->withoutGlobalScope('not_tombstoned')
                ->where('sku', $data['sku'])
                ->when($existing !== null, fn ($q) => $q->whereKeyNot($existing->getKey()))
                ->exists();
            if ($taken) {
                throw ApiException::validation('sku', 'Another material already uses this code.');
            }
        }
        $unit = $data['unit'] ?? $existing?->unit;
        foreach (['min_stock_level', 'reorder_quantity'] as $key) {
            if (isset($data[$key]) && in_array($unit, InventoryItem::COUNT_UNITS, true) && floor((float) $data[$key]) != (float) $data[$key]) {
                throw ApiException::validation($key, sprintf('Use a whole number of %s.', $this->unitName($unit, 2)));
            }
        }
        if (array_key_exists('min_stock_level', $data) && $data['min_stock_level'] === null) {
            $data['min_stock_level'] = 0;
        }

        return $data;
    }

    private function guardQuantity(InventoryItem $item, float $quantity, string $field, bool $allowZero = false): void
    {
        if ($quantity < 0 || (! $allowZero && $quantity <= 0)) {
            throw ApiException::validation($field, 'Enter a quantity above zero.');
        }
        if ($item->isCounted() && floor($quantity) != $quantity) {
            throw ApiException::validation($field, sprintf('Use a whole number of %s.', $this->unitName($item->unit, 2)));
        }
    }

    private function insufficient(float $onHand, InventoryItem $item, string $field): ApiException
    {
        $message = $onHand <= 0
            ? 'There is no stock of this material. Record what came in, or a stock count, first.'
            : sprintf('Only %s in stock. If the shelf holds more, record a stock count first.', $this->quantity($onHand, $item->unit));

        return new ApiException(422, 'INSUFFICIENT_STOCK', $message, [$field => [$message]]);
    }

    /** When it happened: not in the future (a minute of clock skew is fine), at most a year back. */
    private function occurredAt(string $value): Carbon
    {
        $at = Carbon::parse($value)->utc();
        if ($at->greaterThan(now()->addMinute())) {
            throw ApiException::validation('occurred_at', 'This time is in the future. Check the phone\'s clock.');
        }
        if ($at->lessThan(now()->subYear())) {
            throw ApiException::validation('occurred_at', 'Stock changes older than a year cannot be recorded.');
        }

        return $at;
    }

    private function guardCategoryName(string $name, ?int $exceptId): void
    {
        $taken = InventoryCategory::query()->where('category_name', $name)->when($exceptId !== null, fn ($q) => $q->whereKeyNot($exceptId))->exists();
        if ($taken) {
            throw ApiException::validation('category_name', 'A category with this name already exists.');
        }
    }

    private function lock(InventoryItem $item): InventoryItem
    {
        /** @var InventoryItem */
        return InventoryItem::query()->whereKey($item->getKey())->lockForUpdate()->firstOrFail();
    }

    private function clean(mixed $value): ?string
    {
        $value = is_string($value) ? trim($value) : $value;

        return $value === null || $value === '' ? null : (string) $value;
    }

    private function decimal(float $value): string
    {
        return number_format($value, 3, '.', '');
    }

    /** "3 spools", "18.5 m". */
    public function quantity(float $value, string $unit): string
    {
        return InventoryItem::formatQuantity($value, $unit);
    }

    private function unitName(string $unit, float $count): string
    {
        return InventoryItem::unitName($unit, $count);
    }
}
