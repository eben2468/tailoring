<?php

namespace App\Services\Push;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * Firebase Cloud Messaging, HTTP v1 API. Credentials: a Google service-account JSON file whose path is
 * in FCM_CREDENTIALS (outside the repository; never in git). The OAuth access token is obtained with a
 * signed JWT (RS256, PHP openssl) and cached for 50 minutes. Without credentials, enabled() is false.
 */
final class FcmPushSender implements PushSender
{
    /** @var array{project_id: string, client_email: string, private_key: string}|null */
    private ?array $credentials = null;

    public function __construct(private readonly ?string $credentialsPath) {}

    public function enabled(): bool
    {
        return $this->credentials() !== null;
    }

    public function send(string $token, string $title, ?string $body, array $data): string
    {
        $c = $this->credentials() ?? throw new RuntimeException('FCM is not configured.');
        $response = Http::withToken($this->accessToken($c))
            ->timeout(10)
            ->post("https://fcm.googleapis.com/v1/projects/{$c['project_id']}/messages:send", ['message' => [
                'token' => $token,
                'notification' => array_filter(['title' => $title, 'body' => $body]),
                'data' => $data,
                'android' => ['priority' => 'high'],
            ]]);
        if ($response->successful()) {
            return 'sent';
        }
        $status = $response->json('error.status');
        if ($response->status() === 404 || $status === 'UNREGISTERED' || $status === 'INVALID_ARGUMENT') {
            return 'invalid_token';
        }
        Log::warning('FCM push failed', ['status' => $response->status(), 'error' => $status]);

        return 'retry';
    }

    /** @param  array{project_id: string, client_email: string, private_key: string}  $c */
    private function accessToken(array $c): string
    {
        return Cache::remember('fcm_access_token', now()->addMinutes(50), function () use ($c): string {
            $now = time();
            $segment = fn (array $part) => rtrim(strtr(base64_encode((string) json_encode($part)), '+/', '-_'), '=');
            $unsigned = $segment(['alg' => 'RS256', 'typ' => 'JWT']).'.'.$segment([
                'iss' => $c['client_email'],
                'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
                'aud' => 'https://oauth2.googleapis.com/token',
                'iat' => $now,
                'exp' => $now + 3600,
            ]);
            if (! openssl_sign($unsigned, $signature, $c['private_key'], OPENSSL_ALGO_SHA256)) {
                throw new RuntimeException('Could not sign the FCM token request.');
            }
            $jwt = $unsigned.'.'.rtrim(strtr(base64_encode($signature), '+/', '-_'), '=');
            $response = Http::asForm()->timeout(10)->post('https://oauth2.googleapis.com/token', [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $jwt,
            ])->throw();

            return (string) $response->json('access_token');
        });
    }

    /** @return array{project_id: string, client_email: string, private_key: string}|null */
    private function credentials(): ?array
    {
        if ($this->credentials !== null) {
            return $this->credentials;
        }
        if ($this->credentialsPath === null || $this->credentialsPath === '' || ! is_readable($this->credentialsPath)) {
            return null;
        }
        $json = json_decode((string) file_get_contents($this->credentialsPath), true);
        if (! is_array($json) || empty($json['project_id']) || empty($json['client_email']) || empty($json['private_key'])) {
            Log::error('FCM credentials file is not a service-account key.', ['path' => $this->credentialsPath]);

            return null;
        }

        return $this->credentials = ['project_id' => (string) $json['project_id'], 'client_email' => (string) $json['client_email'], 'private_key' => (string) $json['private_key']];
    }
}
