<?php

namespace App\Http\Resources;

use App\Models\JobTaskChecklistItem;
use App\Support\Iso;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin JobTaskChecklistItem */
final class ChecklistItemResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->uuid(),
            'label' => $this->label,
            'is_done' => $this->is_done,
            'done_at' => Iso::format($this->done_at),
            'sort_order' => $this->sort_order,
            'version' => $this->version,
        ];
    }
}
