<?php

namespace App\Models\Concerns;

/** Our DATETIME(3) columns store milliseconds, always in UTC. */
trait UsesMillisecondTimestamps
{
    public function getDateFormat(): string
    {
        return 'Y-m-d H:i:s.v';
    }
}
