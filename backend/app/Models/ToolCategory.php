<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;

/**
 * Tool category (configuration: Sewing Machines, Irons & Pressing …), owner-editable.
 *
 * @property int $id
 * @property string $category_name
 * @property int $sort_order
 * @property bool $is_active
 */
class ToolCategory extends Model
{
    use UsesMillisecondTimestamps;

    protected $fillable = ['category_name', 'sort_order', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean', 'sort_order' => 'integer'];
    }

    /** @return array<string, mixed> */
    public function toApi(): array
    {
        return ['id' => $this->id, 'name' => $this->category_name, 'sort_order' => $this->sort_order, 'is_active' => $this->is_active];
    }
}
