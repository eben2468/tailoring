<?php

namespace Tests\Unit;

use App\Support\HoursCalculator;
use App\Support\JobStatusMachine;
use PHPUnit\Framework\TestCase;

final class HoursCalculatorTest extends TestCase
{
    /** @return array{status: string, estimated_seconds: int, actual_seconds: int, progress_override: float|null} */
    private function task(string $status, int $estimatedHours, float $actualHours, ?float $override = null): array
    {
        return ['status' => $status, 'estimated_seconds' => $estimatedHours * 3600, 'actual_seconds' => (int) ($actualHours * 3600), 'progress_override' => $override];
    }

    public function test_architecture_example(): void
    {
        $result = HoursCalculator::task($this->task('in_progress', 12, 7));
        $this->assertSame(5 * 3600, $result['remaining_seconds']);
        $this->assertSame(58.33, $result['progress_percent']);
    }

    public function test_edge_cases(): void
    {
        $this->assertSame(99.0, HoursCalculator::task($this->task('in_progress', 2, 5))['progress_percent']);
        $this->assertSame(100.0, HoursCalculator::task($this->task('completed', 2, 1))['progress_percent']);
        $this->assertSame(0, HoursCalculator::task($this->task('completed', 2, 1))['remaining_seconds']);
        $this->assertSame(0.0, HoursCalculator::task($this->task('pending', 0, 3))['progress_percent']); // no division by zero
        $this->assertSame(100.0, HoursCalculator::task($this->task('completed', 2, 1, 30))['progress_percent']);
        $this->assertFalse(HoursCalculator::task($this->task('completed', 2, 1, 30))['is_progress_manual']);

        $this->assertSame(0.0, HoursCalculator::job('queued', null, [])['progress_percent']);
        $this->assertSame(50.0, HoursCalculator::job('in_progress', null, [$this->task('completed', 0, 0), $this->task('pending', 0, 0)])['progress_percent']);
        $this->assertSame(100.0, HoursCalculator::job('ready_for_collection', null, [$this->task('pending', 4, 0)])['progress_percent']);
        $this->assertSame(10.0, HoursCalculator::job('completed', 10.0, [])['progress_percent']);
    }

    public function test_status_machine(): void
    {
        $this->assertTrue(JobStatusMachine::canMove('ready_for_collection', 'in_progress'));
        $this->assertFalse(JobStatusMachine::canMove('completed', 'cancelled'));
        $this->assertFalse(JobStatusMachine::canMove('draft', 'in_progress'));
        $this->assertSame([], JobStatusMachine::allowed('cancelled'));
    }
}
