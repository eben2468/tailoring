<?php

declare(strict_types=1);

namespace Nutofe\Ai\Llm;

/**
 * Google Gemini (generateContent with function calling). The API key is read from the AI service's
 * environment only. A daily call cap protects the free-tier quota; the counter lives in var/.
 */
final class GeminiClient implements LlmClient
{
    /** @var (callable(string, array<string, mixed>): array{status: int, body: string})|null */
    private $transport;

    /** @var callable(int): void  waits the given milliseconds before a retry */
    private $pause;

    /**
     * @param  (callable(string, array<string, mixed>): array{status: int, body: string})|null  $transport  for tests
     * @param  (callable(int): void)|null  $pause  for tests
     */
    public function __construct(
        private readonly string $apiKey,
        private readonly string $model,
        private readonly int $dailyLimit,
        private readonly string $counterDir,
        ?callable $transport = null,
        ?callable $pause = null,
    ) {
        $this->transport = $transport;
        $this->pause = $pause ?? static fn (int $ms) => usleep($ms * 1000);
    }

    public function enabled(): bool
    {
        return $this->apiKey !== '';
    }

    public function name(): string
    {
        return str_starts_with($this->model, 'gemini') ? $this->model : 'gemini-'.$this->model;
    }

    public function generate(string $system, array $contents, array $tools, int $timeoutSeconds = 20): array
    {
        if (! $this->enabled()) {
            throw new LlmUnavailable('The language model is not configured.', 'not_configured');
        }
        if ($this->blockedUntil() > time()) {
            throw new LlmUnavailable('The free daily limit of '.$this->model.' is used up.', 'quota');
        }
        $this->spend();
        $body = [
            'systemInstruction' => ['parts' => [['text' => $system]]],
            'contents' => self::objects($contents),
            // Thinking tokens count towards maxOutputTokens: leave room for them and the answer.
            'generationConfig' => ['temperature' => 0.2, 'maxOutputTokens' => 2048],
        ];
        if (str_starts_with($this->model, 'gemini-3')) {
            $body['generationConfig']['thinkingConfig'] = ['thinkingLevel' => 'low']; // faster; the figures come from the tools
        }
        if ($tools !== []) {
            $body['tools'] = [['functionDeclarations' => $tools]];
        }
        $url = sprintf('https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent', rawurlencode($this->model));
        $send = $this->transport ?? fn (string $u, array $b) => $this->post($u, $b, $timeoutSeconds);
        $response = $send($url, $body);
        if ($response['status'] === 503 && $timeoutSeconds > 8) {
            // Google: demand spikes are usually brief. One retry after a short pause, then give up.
            ($this->pause)(1500);
            $response = $send($url, $body);
        }
        if ($response['status'] === 429) {
            $this->block($response['body']);
            throw new LlmUnavailable('The free limit of '.$this->model.' is used up for now (429).', 'quota');
        }
        if ($response['status'] === 503) {
            throw new LlmUnavailable('The language model is busy (503).', 'busy');
        }
        if ($response['status'] < 200 || $response['status'] >= 300) {
            $reason = mb_substr((string) (json_decode($response['body'], true)['error']['message'] ?? ''), 0, 300);
            throw new LlmUnavailable('The language model returned an error ('.$response['status'].')'.($reason === '' ? '.' : ': '.$reason));
        }
        $json = json_decode($response['body'], true);
        $parts = $json['candidates'][0]['content']['parts'] ?? null;
        if (! is_array($parts)) {
            throw new LlmUnavailable('The language model gave no answer.');
        }
        $text = null;
        $calls = [];
        foreach ($parts as $part) {
            if (isset($part['functionCall']['name'])) {
                $calls[] = ['name' => (string) $part['functionCall']['name'], 'args' => (array) ($part['functionCall']['args'] ?? [])];
            } elseif (isset($part['text'])) {
                $text = ($text ?? '').$part['text'];
            }
        }

        return ['text' => $text === null ? null : trim($text), 'calls' => $calls, 'parts' => $parts];
    }

    /**
     * @param  array<string, mixed>  $body
     * @return array{status: int, body: string}
     */
    private function post(string $url, array $body, int $timeoutSeconds): array
    {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'x-goog-api-key: '.$this->apiKey],
            CURLOPT_POSTFIELDS => json_encode($body),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => max(1, $timeoutSeconds),
            CURLOPT_CONNECTTIMEOUT => 5,
        ]);
        $raw = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($raw === false) {
            throw new LlmUnavailable('The language model could not be reached.', 'unreachable');
        }

        return ['status' => $status, 'body' => (string) $raw];
    }

    /**
     * Function-call arguments and results are JSON objects. PHP decodes an empty `{}` to `[]`, which would be
     * sent back as a list and refused (400), so empty or list-shaped values are turned into objects.
     *
     * @param  list<array{role: string, parts: list<array<string, mixed>>}>  $contents
     * @return list<array{role: string, parts: list<array<string, mixed>>}>
     */
    private static function objects(array $contents): array
    {
        foreach ($contents as &$content) {
            foreach ($content['parts'] as &$part) {
                if (isset($part['functionCall']) && ($part['functionCall']['args'] ?? []) === []) {
                    $part['functionCall']['args'] = new \stdClass;
                }
                if (isset($part['functionResponse'])) {
                    $response = $part['functionResponse']['response'] ?? [];
                    $part['functionResponse']['response'] = match (true) {
                        $response === [] => new \stdClass,
                        is_array($response) && array_is_list($response) => ['result' => $response],
                        default => $response,
                    };
                }
            }
            unset($part);
        }
        unset($content);

        return $contents;
    }

    /** Until when Google said this model's free quota is used up (unix time; 0 = not blocked). */
    public function blockedUntil(): int
    {
        $file = $this->blockFile();

        return is_readable($file) ? (int) file_get_contents($file) : 0;
    }

    /** Remembers a 429 until Google's retryDelay (a daily quota resets in hours), so later questions skip this model at once. */
    private function block(string $body): void
    {
        $seconds = 60;
        foreach ((array) (json_decode($body, true)['error']['details'] ?? []) as $detail) {
            if (is_array($detail) && preg_match('/^(\d+)(?:\.\d+)?s$/', (string) ($detail['retryDelay'] ?? ''), $m)) {
                $seconds = max(1, (int) $m[1]);
            }
        }
        @file_put_contents($this->blockFile(), (string) (time() + $seconds), LOCK_EX);
    }

    private function blockFile(): string
    {
        return rtrim($this->counterDir, '/').'/'.$this->model.'.blocked';
    }

    /** Counts today's calls; refuses past the daily cap. */
    private function spend(): void
    {
        $file = rtrim($this->counterDir, '/').'/'.$this->model.'-'.gmdate('Y-m-d').'.count';
        $count = is_readable($file) ? (int) file_get_contents($file) : 0;
        if ($count >= $this->dailyLimit) {
            throw new LlmUnavailable('Our own daily limit for '.$this->model.' is reached.', 'quota');
        }
        @file_put_contents($file, (string) ($count + 1), LOCK_EX);
    }
}
