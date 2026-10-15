<?php

declare(strict_types=1);

namespace Nutofe\Ai\Tests;

use DateTimeZone;
use Nutofe\Ai\Analytics\WorkCalendar;
use Nutofe\Ai\Config;
use Nutofe\Ai\Data\Db;
use Nutofe\Ai\Data\Repository;

/** In-memory data for the analytics (never touches a database). */
final class FakeRepository extends Repository
{
    /** @var list<array<string, mixed>> */
    public array $jobs = [];

    /** @var list<array<string, mixed>> */
    public array $stages = [];

    /** @var list<array<string, mixed>> */
    public array $items = [];

    /** @var list<array<string, mixed>> */
    public array $predictions = [];

    public function __construct()
    {
        parent::__construct(new Db(Config::fromArray([])));
    }

    public static function calendar(): WorkCalendar
    {
        $day = ['open' => '08:00', 'close' => '16:00'];

        return new WorkCalendar(new DateTimeZone('Africa/Accra'), ['mon' => $day, 'tue' => $day, 'wed' => $day, 'thu' => $day, 'fri' => $day, 'sat' => $day, 'sun' => null], 8.0);
    }

    public function workCalendar(): WorkCalendar
    {
        return self::calendar();
    }

    public function minSamples(): int
    {
        return 3;
    }

    public function completedStages(?int $sinceDays = null): array
    {
        return $this->stages;
    }

    public function completedJobCount(): int
    {
        return 4;
    }

    public function productionJobs(): array
    {
        return $this->jobs;
    }

    public function stock(int $days = 60): array
    {
        return $this->items;
    }

    public function jobTypeNames(): array
    {
        return [1 => '3-Piece Suit'];
    }

    public function savePrediction(string $type, ?string $jobId, ?string $date, ?float $score, ?int $seconds, string $method, string $explanation, string $inputsHash): void
    {
        $this->predictions[] = compact('type', 'jobId', 'date', 'score');
    }

    /** @param  array<string, mixed>  $extra */
    public function addJob(string $number, int $remainingHours, ?string $due, string $priority = 'normal', bool $started = false, array $extra = []): string
    {
        $id = sprintf('0192f0a1-0000-7000-8000-%012d', count($this->jobs) + 1);
        $this->jobs[] = $extra + [
            'id' => $id, 'job_number' => $number, 'job_type' => '3-Piece Suit', 'priority' => $priority, 'status' => $started ? 'in_progress' : 'queued',
            'order_date' => '2026-10-01', 'due_date' => $due, 'quantity' => 1, 'estimated_seconds' => $remainingHours * 3600, 'actual_seconds' => 0,
            'remaining_seconds' => $remainingHours * 3600, 'started' => $started,
        ];

        return $id;
    }
}
