<?php

namespace App\Http\Requests\Inventory;

use App\Http\Requests\ApiRequest;
use Illuminate\Validation\Rule;

/**
 * POST /inventory/items/{id}/transactions. purchase / return / usage / write_off take a positive
 * `quantity`; a stock count (adjustment) takes `counted_quantity`. `offline: true` marks a change that
 * was recorded without a connection and is being replayed (accepted even if stock goes negative).
 */
final class TransactionRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'id' => ['nullable', 'uuid'],
            'transaction_type' => ['required', Rule::in(['purchase', 'return', 'usage', 'write_off', 'adjustment'])],
            'quantity' => ['required_unless:transaction_type,adjustment', 'prohibited_if:transaction_type,adjustment', 'numeric', 'gt:0', 'max:999999', 'decimal:0,3'],
            'counted_quantity' => ['required_if:transaction_type,adjustment', 'prohibited_unless:transaction_type,adjustment', 'numeric', 'min:0', 'max:999999', 'decimal:0,3'],
            'job_id' => ['sometimes', 'nullable', 'uuid'],
            'unit_cost' => ['sometimes', 'nullable', 'numeric', 'min:0', 'max:9999999', 'decimal:0,2'],
            'reference' => ['sometimes', 'nullable', 'string', 'max:80'],
            'note' => ['sometimes', 'nullable', 'string', 'max:255'],
            'occurred_at' => ['sometimes', 'nullable', 'date'],
            'offline' => ['sometimes', 'boolean'],
        ];
    }

    public function messages(): array
    {
        return [
            'quantity.required_unless' => 'Enter the quantity.',
            'counted_quantity.required_if' => 'Enter the quantity you counted.',
            'quantity.decimal' => 'Use at most 3 decimals.',
            'counted_quantity.decimal' => 'Use at most 3 decimals.',
        ];
    }
}
