<?php

declare(strict_types=1);

namespace Nutofe\Ai\Analytics;

/**
 * How well estimates match actual hours ("Labor precision"), over completed stages of completed jobs
 * that had an estimate:
 *  - error per stage = |actual − estimated| ÷ estimated;
 *  - accuracy = 100 − mean error × 100 (floored at 0); within_10 = share of stages within ±10 %;
 *  - bias = mean (actual − estimated) ÷ estimated: positive = work takes longer than planned;
 *  - per stage type, the same bias, for the stage types with at least 3 samples.
 */
final class AccuracyTracker
{
    /**
     * @param  list<array{task_type_id: int, task_type: string, estimated_seconds: int, actual_seconds: int, task_status: string}>  $stages
     * @return array{stages: int, accuracy_percent: float|null, within_10_percent: float|null, bias_percent: float|null, by_stage: list<array{task_type_id: int, name: string, stages: int, bias_percent: float}>}
     */
    public function measure(array $stages): array
    {
        $rows = array_values(array_filter($stages, fn ($s) => $s['task_status'] === 'completed' && $s['estimated_seconds'] > 0 && $s['actual_seconds'] > 0));
        if ($rows === []) {
            return ['stages' => 0, 'accuracy_percent' => null, 'within_10_percent' => null, 'bias_percent' => null, 'by_stage' => []];
        }
        $errors = [];
        $biases = [];
        $byStage = [];
        foreach ($rows as $r) {
            $bias = ($r['actual_seconds'] - $r['estimated_seconds']) / $r['estimated_seconds'];
            $errors[] = abs($bias);
            $biases[] = $bias;
            $byStage[$r['task_type_id']]['name'] = $r['task_type'];
            $byStage[$r['task_type_id']]['biases'][] = $bias;
        }
        $stageRows = [];
        foreach ($byStage as $id => $s) {
            if (count($s['biases']) >= 3) {
                $stageRows[] = ['task_type_id' => $id, 'name' => $s['name'], 'stages' => count($s['biases']), 'bias_percent' => round(Stats::mean($s['biases']) * 100, 1)];
            }
        }
        usort($stageRows, fn ($a, $b) => abs($b['bias_percent']) <=> abs($a['bias_percent']));

        return [
            'stages' => count($rows),
            'accuracy_percent' => round(max(0.0, 100 - Stats::mean($errors) * 100), 1),
            'within_10_percent' => round(count(array_filter($errors, fn ($e) => $e <= 0.10)) / count($errors) * 100, 1),
            'bias_percent' => round(Stats::mean($biases) * 100, 1),
            'by_stage' => $stageRows,
        ];
    }
}
