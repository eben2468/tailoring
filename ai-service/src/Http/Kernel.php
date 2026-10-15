<?php

declare(strict_types=1);

namespace Nutofe\Ai\Http;

use Nutofe\Ai\Analytics\Analysis;
use Nutofe\Ai\Analytics\CompletionForecaster;
use Nutofe\Ai\Data\Repository;
use Nutofe\Ai\Insights\InsightGenerator;
use Nutofe\Ai\Llm\Assistant;
use Nutofe\Ai\Llm\LlmClient;
use Throwable;

/**
 * The internal API, called only by the core API (never by the app). Every request must be signed:
 *   X-Nutofe-Time: unix seconds (±300 s)
 *   X-Nutofe-Signature: hex HMAC-SHA256(secret, "{time}\n{METHOD}\n{path}\n{body}")
 * Without a configured secret every request is refused.
 *
 *   GET  /health                  status and whether the language model is configured
 *   GET  /overview                accuracy, coming week, forecast risks, stock forecast
 *   GET  /jobs/{uuid}/forecast    one job's predicted finish and delay risk
 *   POST /estimate                {job_type_id, quantity, tasks:[{task_type_id, name, default_seconds}]}
 *   POST /insights                insight cards for the current data (the core API stores them)
 *   POST /chat                    {messages:[{role: user|assistant, text}]} → grounded answer
 */
final class Kernel
{
    public function __construct(
        private readonly string $secret,
        private readonly Repository $repo,
        private readonly LlmClient $llm,
        private readonly ?Analysis $analysis = null,
    ) {}

    /** @return array{status: int, body: array<string, mixed>} */
    public function handle(string $method, string $path, string $body, ?string $time, ?string $signature, int $now): array
    {
        if (! $this->verify($method, $path, $body, $time, $signature, $now)) {
            return ['status' => 401, 'body' => ['error' => 'unauthorized']];
        }
        try {
            $input = $body === '' ? [] : (array) json_decode($body, true, 32, JSON_THROW_ON_ERROR);
            $analysis = $this->analysis ?? new Analysis($this->repo);

            return ['status' => 200, 'body' => match (true) {
                $method === 'GET' && $path === '/health' => ['ok' => true, 'llm' => ['enabled' => $this->llm->enabled(), 'name' => $this->llm->name()]],
                $method === 'GET' && $path === '/overview' => $this->overview($analysis),
                $method === 'GET' && (bool) preg_match('#^/jobs/([0-9a-f-]{36})/forecast$#', $path, $m) => ['forecast' => $analysis->jobForecast($m[1])],
                $method === 'POST' && $path === '/estimate' => ['tasks' => $analysis->estimate((int) ($input['job_type_id'] ?? 0), (int) ($input['quantity'] ?? 1), $this->tasks($input['tasks'] ?? []))],
                $method === 'POST' && $path === '/insights' => $this->insights($analysis),
                $method === 'POST' && $path === '/chat' => (new Assistant($analysis, $this->llm))->answer($this->messages($input['messages'] ?? [])),
                default => throw new NotFound(),
            }];
        } catch (NotFound) {
            return ['status' => 404, 'body' => ['error' => 'not_found']];
        } catch (\JsonException) {
            return ['status' => 422, 'body' => ['error' => 'invalid_json']];
        } catch (Throwable $e) {
            error_log('[nutofe-ai] '.$e::class.': '.$e->getMessage());

            return ['status' => 500, 'body' => ['error' => 'internal_error']];
        }
    }

    public static function sign(string $secret, string $time, string $method, string $path, string $body): string
    {
        return hash_hmac('sha256', $time."\n".strtoupper($method)."\n".$path."\n".$body, $secret);
    }

    private function verify(string $method, string $path, string $body, ?string $time, ?string $signature, int $now): bool
    {
        if ($this->secret === '' || $time === null || $signature === null || ! ctype_digit($time) || abs($now - (int) $time) > 300) {
            return false;
        }

        return hash_equals(self::sign($this->secret, $time, $method, $path, $body), $signature);
    }

    /** @return array<string, mixed> */
    private function overview(Analysis $analysis): array
    {
        $forecast = $analysis->forecast();

        return [
            'completed_jobs' => $analysis->completedJobs(),
            'accuracy' => $analysis->accuracy(),
            'workload' => $analysis->workload(),
            'risks' => array_values(array_filter($forecast, fn ($f) => in_array($f['risk'], ['high', 'medium'], true))),
            'queue' => array_slice($forecast, 0, 5),
            'stock' => array_values(array_filter($analysis->stock(), fn ($s) => $s['days_left'] !== null && $s['days_left'] <= 30)),
            'llm' => ['enabled' => $this->llm->enabled(), 'name' => $this->llm->name()],
        ];
    }

    /** @return array<string, mixed> */
    private function insights(Analysis $analysis): array
    {
        $cards = (new InsightGenerator)->generate($analysis->forecast(), $analysis->jobs(), $analysis->workload(), $analysis->accuracy(), $analysis->stock());
        foreach ($analysis->forecast() as $f) {
            if ($f['finish_date'] === null) {
                continue;
            }
            // Kept for measuring forecast accuracy later (joined to jobs.completed_at).
            $hash = hash('sha256', $f['job_id'].'|'.$f['finish_date'].'|'.$f['remaining_seconds']);
            $this->repo->savePrediction('completion_date', $f['job_id'], $f['finish_date'], null, null, CompletionForecaster::METHOD, implode('; ', $f['reasons']), $hash);
            if ($f['risk_score'] !== null) {
                $this->repo->savePrediction('delay_risk', $f['job_id'], null, (float) $f['risk_score'], null, CompletionForecaster::METHOD, $f['risk'], $hash);
            }
        }

        return ['insights' => $cards, 'method' => InsightGenerator::METHOD];
    }

    /**
     * @param  mixed  $tasks
     * @return list<array{task_type_id: int, name: string, default_seconds: int}>
     */
    private function tasks(mixed $tasks): array
    {
        return array_values(array_map(fn ($t) => [
            'task_type_id' => (int) ($t['task_type_id'] ?? 0), 'name' => mb_substr((string) ($t['name'] ?? ''), 0, 120), 'default_seconds' => max(0, (int) ($t['default_seconds'] ?? 0)),
        ], array_filter(is_array($tasks) ? $tasks : [], 'is_array')));
    }

    /**
     * @param  mixed  $messages
     * @return list<array{role: string, text: string}>
     */
    private function messages(mixed $messages): array
    {
        $out = [];
        foreach (is_array($messages) ? array_slice($messages, -8) : [] as $m) {
            if (is_array($m) && isset($m['text'])) {
                $out[] = ['role' => ($m['role'] ?? 'user') === 'assistant' ? 'assistant' : 'user', 'text' => mb_substr((string) $m['text'], 0, 1000)];
            }
        }

        return $out === [] ? [['role' => 'user', 'text' => '']] : $out;
    }
}
