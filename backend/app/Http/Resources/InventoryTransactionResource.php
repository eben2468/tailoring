<?php

namespace App\Http\Resources;

use App\Models\InventoryTransaction;
use App\Support\Iso;
use App\Support\Uuid;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One stock-ledger line. quantity_change is signed. Voided lines are listed with is_voided.
 *
 * @mixin InventoryTransaction
 */
final class InventoryTransactionResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->uuid(),
            'item_id' => Uuid::toString($this->item_id),
            'item_name' => $this->whenLoaded('item', fn () => $this->item->item_name),
            'unit' => $this->whenLoaded('item', fn () => $this->item->unit),
            'transaction_type' => $this->transaction_type,
            'quantity_change' => (float) $this->quantity_change,
            'job_id' => $this->job_id === null ? null : Uuid::toString($this->job_id),
            'job_number' => $this->whenLoaded('job', fn () => $this->job?->job_number),
            'unit_cost' => $this->unit_cost === null ? null : (float) $this->unit_cost,
            'reference' => $this->reference,
            'note' => $this->note,
            'occurred_at' => Iso::format($this->occurred_at),
            'is_voided' => $this->deleted_at !== null,
            'void_reason' => $this->void_reason,
            'recorded_by' => $this->whenLoaded('creator', fn () => $this->creator?->full_name),
            'version' => $this->version,
            'created_at' => Iso::format($this->created_at),
        ];
    }
}
