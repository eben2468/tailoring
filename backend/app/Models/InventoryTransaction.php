<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One line of the append-only stock ledger. quantity_change is signed (+ adds stock, − removes it).
 * Mistakes are voided (void_reason + tombstone), never edited or deleted.
 *
 * @property string $id
 * @property string $item_id
 * @property string $transaction_type
 * @property string $quantity_change
 * @property string|null $job_id
 * @property string|null $unit_cost
 * @property string|null $reference
 * @property string|null $note
 * @property \Illuminate\Support\Carbon $occurred_at
 * @property string|null $void_reason
 * @property int $created_by
 * @property int $version
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon|null $deleted_at
 * @property-read InventoryItem $item
 * @property-read Job|null $job
 * @property-read User|null $creator
 */
class InventoryTransaction extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    public const TYPES = ['opening', 'purchase', 'return', 'usage', 'write_off', 'adjustment'];

    /** Types that add stock; usage and write_off remove it; an adjustment (stock count) can go either way. */
    public const ADDITIONS = ['opening', 'purchase', 'return'];

    public const REDUCTIONS = ['usage', 'write_off'];

    /** Types that may name the job the material was used for (or came back from). */
    public const JOB_TYPES = ['usage', 'return'];

    protected $table = 'inventory_transactions';

    protected $fillable = ['item_id', 'transaction_type', 'quantity_change', 'job_id', 'unit_cost', 'reference', 'note', 'occurred_at'];

    protected function casts(): array
    {
        return ['occurred_at' => 'datetime', 'deleted_at' => 'datetime', 'created_by' => 'integer', 'version' => 'integer'];
    }

    /** @return BelongsTo<InventoryItem, $this> */
    public function item(): BelongsTo
    {
        return $this->belongsTo(InventoryItem::class, 'item_id');
    }

    /** @return BelongsTo<Job, $this> */
    public function job(): BelongsTo
    {
        return $this->belongsTo(Job::class);
    }

    /** @return BelongsTo<User, $this> */
    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
