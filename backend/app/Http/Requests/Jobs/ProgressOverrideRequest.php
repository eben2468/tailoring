<?php

namespace App\Http\Requests\Jobs;

use App\Http\Requests\ApiRequest;

/** POST /jobs/{id}/progress-override and /tasks/{id}/progress-override. null returns to calculated progress. */
final class ProgressOverrideRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return ['progress_percent' => ['present', 'nullable', 'numeric', 'min:0', 'max:100']];
    }

    public function percent(): ?float
    {
        $value = $this->validated('progress_percent');

        return $value === null ? null : round((float) $value, 2);
    }
}
