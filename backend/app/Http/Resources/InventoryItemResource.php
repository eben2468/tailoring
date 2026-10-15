<?php

namespace App\Http\Resources;

use App\Models\InventoryItem;
use App\Support\Iso;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Carbon;

/**
 * A material with its calculated stock (figures from InventoryStock, passed with withStock()).
 * The app's Presenter builds the same shape offline.
 *
 * @mixin InventoryItem
 */
final class InventoryItemResource extends JsonResource
{
    /** @var array{quantity_on_hand: float, stock_status: string, last_transaction_at: Carbon|null, jobs_used_this_month: int}|null */
    private ?array $stock = null;

    /** @param  array{quantity_on_hand: float, stock_status: string, last_transaction_at: Carbon|null, jobs_used_this_month: int}  $stock */
    public function withStock(array $stock): self
    {
        $this->stock = $stock;

        return $this;
    }

    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        $stock = $this->stock ?? ['quantity_on_hand' => 0.0, 'stock_status' => 'out', 'last_transaction_at' => null, 'jobs_used_this_month' => 0];

        return [
            'id' => $this->uuid(),
            'category_id' => $this->category_id,
            'category_name' => $this->whenLoaded('category', fn () => $this->category->category_name),
            'item_name' => $this->item_name,
            'sku' => $this->sku,
            'description' => $this->description,
            'unit' => $this->unit,
            'min_stock_level' => (float) $this->min_stock_level,
            'reorder_quantity' => $this->reorder_quantity === null ? null : (float) $this->reorder_quantity,
            'unit_cost' => $this->unit_cost === null ? null : (float) $this->unit_cost,
            'supplier_name' => $this->supplier_name,
            'supplier_contact' => $this->supplier_contact,
            'storage_location' => $this->storage_location,
            'notes' => $this->notes,
            'quantity_on_hand' => $stock['quantity_on_hand'],
            'stock_status' => $stock['stock_status'],
            'last_transaction_at' => Iso::format($stock['last_transaction_at']),
            'jobs_used_this_month' => $stock['jobs_used_this_month'],
            'archived_at' => Iso::format($this->archived_at),
            'version' => $this->version,
            'created_at' => Iso::format($this->created_at),
            'updated_at' => Iso::format($this->updated_at),
        ];
    }
}
