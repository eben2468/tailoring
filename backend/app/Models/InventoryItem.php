<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A material. Stock on hand is not stored: it is the sum of the item's non-voided transactions
 * (v_inventory_stock, read through InventoryStock).
 *
 * @property string $id
 * @property int $category_id
 * @property string $item_name
 * @property string|null $sku
 * @property string|null $description
 * @property string $unit
 * @property string $min_stock_level
 * @property string|null $reorder_quantity
 * @property string|null $unit_cost
 * @property string|null $supplier_name
 * @property string|null $supplier_contact
 * @property string|null $storage_location
 * @property string|null $notes
 * @property \Illuminate\Support\Carbon|null $archived_at
 * @property int $version
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon $updated_at
 * @property-read InventoryCategory $category
 */
class InventoryItem extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    public const UNITS = ['m', 'yd', 'cm', 'pcs', 'spool', 'cone', 'roll', 'set', 'box', 'pack', 'kg', 'g'];

    /** Units counted in whole numbers; the others (lengths, weights) take up to 3 decimals. */
    public const COUNT_UNITS = ['pcs', 'spool', 'cone', 'roll', 'set', 'box', 'pack'];

    protected $fillable = [
        'category_id', 'item_name', 'sku', 'description', 'unit', 'min_stock_level', 'reorder_quantity', 'unit_cost',
        'supplier_name', 'supplier_contact', 'storage_location', 'notes',
    ];

    protected function casts(): array
    {
        return ['archived_at' => 'datetime', 'deleted_at' => 'datetime', 'category_id' => 'integer', 'version' => 'integer'];
    }

    /** @return BelongsTo<InventoryCategory, $this> */
    public function category(): BelongsTo
    {
        return $this->belongsTo(InventoryCategory::class, 'category_id');
    }

    public function isCounted(): bool
    {
        return in_array($this->unit, self::COUNT_UNITS, true);
    }

    /** "3 spools", "1 spool", "18.5 m" (up to 3 decimals; the app's StockRules.quantity is the same). */
    public static function formatQuantity(float $value, string $unit): string
    {
        $number = rtrim(rtrim(number_format($value, 3, '.', ''), '0'), '.');

        return $number.' '.self::unitName($unit, $value);
    }

    public static function unitName(string $unit, float $count): string
    {
        if (! in_array($unit, self::COUNT_UNITS, true) || $unit === 'pcs' || abs($count) == 1.0) {
            return $unit;
        }

        return $unit === 'box' ? 'boxes' : $unit.'s';
    }
}
