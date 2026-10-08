<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use LogicException;

/**
 * counters('sync') — must be called inside the writing transaction. The row lock serialises writers,
 * so sync_seq order equals commit order and devices never miss a row when pulling changes.
 */
final class SyncSequence
{
    public function next(): int
    {
        if (DB::transactionLevel() === 0) {
            throw new LogicException('SyncSequence::next() must run inside a transaction.');
        }
        DB::update("UPDATE counters SET counter_value = LAST_INSERT_ID(counter_value + 1) WHERE counter_key = 'sync'");

        return (int) DB::selectOne('SELECT LAST_INSERT_ID() AS v')->v;
    }

    /** Devices re-download the configuration bundle when this changes. */
    public function bumpConfigVersion(): void
    {
        DB::update("UPDATE counters SET counter_value = counter_value + 1 WHERE counter_key = 'config_version'");
    }
}
