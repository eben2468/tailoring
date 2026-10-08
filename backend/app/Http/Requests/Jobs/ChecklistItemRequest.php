<?php

namespace App\Http\Requests\Jobs;

use App\Http\Requests\ApiRequest;

/** Add (POST /tasks/{id}/checklist) and edit (PATCH /checklist-items/{id}) a subtask. */
final class ChecklistItemRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');

        return [
            'id' => $creating ? ['nullable', 'uuid'] : ['prohibited'],
            'label' => [$creating ? 'required' : 'sometimes', 'string', 'min:1', 'max:150'],
            'is_done' => $creating ? ['prohibited'] : ['sometimes', 'boolean'],
            'version' => $creating ? ['prohibited'] : ['sometimes', 'nullable', 'integer', 'min:1'],
        ];
    }
}
