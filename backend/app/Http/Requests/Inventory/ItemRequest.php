<?php

namespace App\Http\Requests\Inventory;

use App\Http\Requests\ApiRequest;
use App\Models\InventoryItem;
use Illuminate\Validation\Rule;

/** Create (POST /inventory/items) and edit (PATCH /inventory/items/{id}) a material. */
final class ItemRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');
        $required = $creating ? 'required' : 'sometimes';

        return [
            'id' => $creating ? ['nullable', 'uuid'] : ['prohibited'],
            'version' => $creating ? ['prohibited'] : ['required', 'integer', 'min:1'],
            'category_id' => [$required, 'integer', 'min:1'],
            'item_name' => [$required, 'string', 'min:2', 'max:150'],
            'sku' => ['sometimes', 'nullable', 'string', 'max:60'],
            'description' => ['sometimes', 'nullable', 'string', 'max:255'],
            'unit' => [$required, Rule::in(InventoryItem::UNITS)],
            'min_stock_level' => ['sometimes', 'nullable', 'numeric', 'min:0', 'max:999999'],
            'reorder_quantity' => ['sometimes', 'nullable', 'numeric', 'gt:0', 'max:999999'],
            'unit_cost' => ['sometimes', 'nullable', 'numeric', 'min:0', 'max:9999999', 'decimal:0,2'],
            'supplier_name' => ['sometimes', 'nullable', 'string', 'max:150'],
            'supplier_contact' => ['sometimes', 'nullable', 'string', 'max:150'],
            'storage_location' => ['sometimes', 'nullable', 'string', 'max:80'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'opening_quantity' => $creating ? ['sometimes', 'nullable', 'numeric', 'min:0', 'max:999999', 'decimal:0,3'] : ['prohibited'],
            'opening_transaction_id' => $creating ? ['sometimes', 'nullable', 'uuid'] : ['prohibited'],
            'occurred_at' => $creating ? ['sometimes', 'nullable', 'date'] : ['prohibited'],
        ];
    }

    public function messages(): array
    {
        return [
            'version.required' => 'Send the version you edited, so changes made on another device are not overwritten.',
            'opening_quantity.prohibited' => 'Record stock changes as transactions.',
            'unit_cost.decimal' => 'Use at most 2 decimals for the cost.',
        ];
    }
}
