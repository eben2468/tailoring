<?php

namespace App\Http\Requests\Config;

use App\Http\Requests\ApiRequest;
use App\Models\TaskType;
use Illuminate\Validation\Rule;

/** Create (POST /task-types) and edit (PATCH /task-types/{id}) a production stage. */
final class TaskTypeRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');

        return [
            'type_name' => [$creating ? 'required' : 'sometimes', 'string', 'min:2', 'max:80'],
            'kind' => $creating ? ['sometimes', Rule::in(['work', 'milestone'])] : ['prohibited'],
            'is_fitting' => ['sometimes', 'boolean'],
            'color_key' => ['sometimes', 'nullable', Rule::in(TaskType::COLOR_KEYS)],
            'sort_order' => $creating ? ['prohibited'] : ['sometimes', 'integer', 'min:-32768', 'max:32767'],
            'is_active' => $creating ? ['prohibited'] : ['sometimes', 'boolean'],
        ];
    }

    public function messages(): array
    {
        return ['kind.prohibited' => 'A stage cannot change between work and milestone. Create a new stage instead.'];
    }
}
