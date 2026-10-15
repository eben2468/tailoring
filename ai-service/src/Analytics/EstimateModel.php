<?php

declare(strict_types=1);

namespace Nutofe\Ai\Analytics;

/**
 * Suggested hours per stage from the workshop's own history (ARCHITECTURE §14.2):
 *  - samples = the actual hours per garment of the same stage on completed jobs of the same garment type;
 *  - with at least min_samples samples: the median × quantity, rounded to 15 minutes;
 *    confidence grows with the sample size and drops when the samples spread widely (IQR ÷ median);
 *  - otherwise the template's default hours are kept ("based on defaults", no confidence).
 */
final class EstimateModel
{
    public const METHOD = 'history-median-v1';

    /**
     * @param  list<array{job_type_id: int, task_type_id: int, quantity: int, actual_seconds: int}>  $history
     * @param  list<array{task_type_id: int, name: string, default_seconds: int}>  $tasks
     * @return list<array{task_type_id: int, name: string, suggested_seconds: int, default_seconds: int, basis: string, sample_size: int, confidence: float|null, explanation: string}>
     */
    public function suggest(int $jobTypeId, string $jobTypeName, int $quantity, array $tasks, array $history, int $minSamples): array
    {
        $quantity = max(1, $quantity);
        $out = [];
        foreach ($tasks as $task) {
            $samples = [];
            foreach ($history as $h) {
                if ($h['job_type_id'] === $jobTypeId && $h['task_type_id'] === $task['task_type_id'] && $h['actual_seconds'] > 0) {
                    $samples[] = $h['actual_seconds'] / max(1, $h['quantity']);
                }
            }
            $n = count($samples);
            if ($n < $minSamples) {
                $out[] = [
                    'task_type_id' => $task['task_type_id'], 'name' => $task['name'],
                    'suggested_seconds' => $task['default_seconds'], 'default_seconds' => $task['default_seconds'],
                    'basis' => 'defaults', 'sample_size' => $n, 'confidence' => null,
                    'explanation' => $n === 0
                        ? 'No completed '.$jobTypeName.' has hours for this stage yet: the template hours are kept.'
                        : sprintf('Only %d completed %s with hours for this stage (needs %d): the template hours are kept.', $n, $jobTypeName, $minSamples),
                ];

                continue;
            }
            $median = Stats::median($samples);
            $spread = $median > 0 ? Stats::iqr($samples) / $median : 0.0;
            $confidence = round(min(90.0, 40.0 + $n * 10.0) * (1 - min(0.5, $spread)), 1);
            $suggested = (int) (round($median * $quantity / 900) * 900);
            $out[] = [
                'task_type_id' => $task['task_type_id'], 'name' => $task['name'],
                'suggested_seconds' => max(900, $suggested), 'default_seconds' => $task['default_seconds'],
                'basis' => 'history', 'sample_size' => $n, 'confidence' => $confidence,
                'explanation' => sprintf('Median of %d completed %s: %s per garment.', $n, $jobTypeName, Stats::hours($median)),
            ];
        }

        return $out;
    }
}
