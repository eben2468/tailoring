<?php

declare(strict_types=1);

namespace Nutofe\Ai\Llm;

use RuntimeException;

/** The language model cannot answer now (not configured, quota used up, network or provider error). */
final class LlmUnavailable extends RuntimeException
{
    /** Why: not_configured · quota · busy · unreachable · timeout · error */
    public function __construct(string $message, public readonly string $reason = 'error')
    {
        parent::__construct($message);
    }
}
