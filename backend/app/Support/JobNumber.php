<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use LogicException;

/**
 * Job numbers: counters('job_number'), never reset, formatted by jobs.number_format
 * ({"prefix":"","padding":3} → "024"; the app shows "#024"). Assigned by the server only,
 * inside the transaction that creates the job, so numbers are unique and gap-free per commit.
 */
final class JobNumber
{
    public function __construct(private readonly BusinessClock $clock) {}

    public function next(): string
    {
        if (DB::transactionLevel() === 0) {
            throw new LogicException('JobNumber::next() must run inside a transaction.');
        }
        DB::update("UPDATE counters SET counter_value = LAST_INSERT_ID(counter_value + 1) WHERE counter_key = 'job_number'");
        $value = (int) DB::selectOne('SELECT LAST_INSERT_ID() AS v')->v;
        $format = $this->clock->jobNumberFormat();

        return $format['prefix'].str_pad((string) $value, $format['padding'], '0', STR_PAD_LEFT);
    }
}
