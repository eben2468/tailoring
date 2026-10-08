<?php

namespace App\Http\Requests;

/** Any paginated list: ?page=&per_page= (max 100). Subclasses add filters via filterRules(). */
class ListRequest extends ApiRequest
{
    protected int $defaultPerPage = 25;

    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'page' => ['sometimes', 'integer', 'min:1', 'max:100000'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
        ] + $this->filterRules();
    }

    /** @return array<string, mixed> */
    protected function filterRules(): array
    {
        return [];
    }

    public function perPage(): int
    {
        return (int) ($this->validated('per_page') ?? $this->defaultPerPage);
    }

    /** @return array<string, mixed> validated filters (without paging keys) */
    public function filters(): array
    {
        return array_diff_key($this->validated(), ['page' => true, 'per_page' => true]);
    }
}
