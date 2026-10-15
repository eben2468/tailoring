<?php

namespace App\Services\Ai;

use App\Models\Setting;
use App\Support\ApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

/**
 * The only way to the AI service (ai-service/, internal network). Requests are signed with the shared
 * secret: X-Nutofe-Time + X-Nutofe-Signature = HMAC-SHA256("{time}\n{METHOD}\n{path}\n{body}").
 * Any failure becomes 503 AI_UNAVAILABLE, so the rest of the app is never affected.
 */
class AiClient
{
    /** @return array<string, mixed> */
    public function get(string $path, int $timeout = 15): array
    {
        return $this->send('GET', $path, null, $timeout);
    }

    /**
     * @param  array<string, mixed>  $body
     * @return array<string, mixed>
     */
    public function post(string $path, array $body = [], int $timeout = 30): array
    {
        return $this->send('POST', $path, $body, $timeout);
    }

    public function configured(): bool
    {
        return (string) config('nutofe.ai.service_url') !== '' && (string) config('nutofe.ai.secret') !== '';
    }

    /**
     * @param  array<string, mixed>|null  $body
     * @return array<string, mixed>
     */
    private function send(string $method, string $path, ?array $body, int $timeout): array
    {
        if (! $this->configured()) {
            throw $this->unavailable('The AI assistant is not set up on this server.');
        }
        if ((Setting::getMany(['ai.enabled'])['ai.enabled'] ?? true) === false) {
            throw $this->unavailable('The AI assistant is switched off in the settings.');
        }
        $json = $body === null ? '' : (string) json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $time = (string) time();
        $signature = hash_hmac('sha256', $time."\n".$method."\n".$path."\n".$json, (string) config('nutofe.ai.secret'));
        try {
            $request = Http::withHeaders(['X-Nutofe-Time' => $time, 'X-Nutofe-Signature' => $signature, 'Content-Type' => 'application/json'])
                ->timeout($timeout)->connectTimeout(3)->withBody($json, 'application/json');
            $response = $method === 'GET'
                ? $request->get(rtrim((string) config('nutofe.ai.service_url'), '/').$path)
                : $request->post(rtrim((string) config('nutofe.ai.service_url'), '/').$path);
        } catch (ConnectionException) {
            throw $this->unavailable('The AI assistant cannot be reached right now. Everything else keeps working.');
        }
        if ($response->status() === 404) {
            throw ApiException::notFound();
        }
        if (! $response->successful() || ! is_array($response->json())) {
            report(new \RuntimeException("AI service {$method} {$path} answered {$response->status()}"));

            throw $this->unavailable('The AI assistant is unavailable right now. Everything else keeps working.');
        }

        return $response->json();
    }

    private function unavailable(string $message): ApiException
    {
        return new ApiException(503, 'AI_UNAVAILABLE', $message);
    }
}
