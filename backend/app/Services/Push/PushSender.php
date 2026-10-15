<?php

namespace App\Services\Push;

/** Sends one push message to one device token. */
interface PushSender
{
    /** False when push is not configured (no credentials): notifications are then only in-app. */
    public function enabled(): bool;

    /**
     * @param  array<string, string>  $data
     * @return string  'sent' | 'invalid_token' (the device must forget it) | 'retry' (temporary failure)
     */
    public function send(string $token, string $title, ?string $body, array $data): string;
}
