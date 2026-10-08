<?php

namespace App\Models\Concerns;

use App\Support\SyncSequence;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use LogicException;

/**
 * Offline-sync bookkeeping for business tables (DATABASE_DESIGN §3.4), applied automatically on every save:
 *  - sync_seq  ← counters('sync') inside the same transaction (devices pull rows with sync_seq > cursor)
 *  - version   ← +1 on every update (optimistic locking / conflict detection)
 *  - created_by / updated_by ← the authenticated user
 *  - deleted_at tombstones: hidden by a global scope; use tombstone() (never hard delete)
 *
 * Saving outside DB::transaction() throws, so a forgotten transaction can never break sync ordering.
 */
trait Syncable
{
    public static function bootSyncable(): void
    {
        static::addGlobalScope('not_tombstoned', fn (Builder $query) => $query->whereNull($query->getModel()->qualifyColumn('deleted_at')));

        static::creating(function (Model $model): void {
            $model->setAttribute('version', 1);
            if ($model->getAttribute('created_by') === null) {
                $model->setAttribute('created_by', auth()->id() ?? throw new LogicException('Synced records need an authenticated user (created_by).'));
            }
        });

        static::saving(function (Model $model): void {
            if (DB::transactionLevel() === 0) {
                throw new LogicException(static::class.' must be saved inside DB::transaction() (sync ordering).');
            }
            $model->setAttribute('sync_seq', app(SyncSequence::class)->next());
            if ($model->exists) {
                $model->setAttribute('version', (int) $model->getAttribute('version') + 1);
                $model->setAttribute('updated_by', auth()->id() ?? $model->getAttribute('updated_by'));
            }
        });
    }

    /** Soft-delete that devices learn about through sync. */
    public function tombstone(): void
    {
        $this->setAttribute('deleted_at', now());
        $this->save();
    }
}
