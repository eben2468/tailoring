<?php

declare(strict_types=1);

namespace Nutofe\Ai\Analytics;

use DateTimeImmutable;
use DateTimeZone;
use Nutofe\Ai\Data\Repository;

/** All analytics over the current data, each computed once per request. */
final class Analysis
{
    private ?WorkCalendar $calendar = null;

    /** @var list<array<string, mixed>>|null */
    private ?array $jobs = null;

    /** @var list<array<string, mixed>>|null */
    private ?array $forecast = null;

    public readonly DateTimeImmutable $now;

    public function __construct(private readonly Repository $repo, ?DateTimeImmutable $now = null)
    {
        $this->now = $now ?? new DateTimeImmutable('now', new DateTimeZone('UTC'));
    }

    public function calendar(): WorkCalendar
    {
        return $this->calendar ??= $this->repo->workCalendar();
    }

    /** @return list<array<string, mixed>> */
    public function jobs(): array
    {
        return $this->jobs ??= $this->repo->productionJobs();
    }

    /** @return list<array<string, mixed>> */
    public function forecast(): array
    {
        /** @phpstan-ignore-next-line */
        return $this->forecast ??= (new CompletionForecaster)->forecast($this->jobs(), $this->calendar(), $this->now);
    }

    /** @return array<string, mixed>|null */
    public function jobForecast(string $jobId): ?array
    {
        foreach ($this->forecast() as $f) {
            if ($f['job_id'] === $jobId) {
                return $f;
            }
        }

        return null;
    }

    /** @return array<string, mixed> */
    public function workload(): array
    {
        /** @phpstan-ignore-next-line */
        return (new WorkloadAnalyzer)->week($this->jobs(), $this->calendar(), $this->now);
    }

    /** @return array<string, mixed> */
    public function accuracy(): array
    {
        return (new AccuracyTracker)->measure($this->repo->completedStages(180));
    }

    /** @return list<array<string, mixed>> */
    public function stock(): array
    {
        return (new InventoryForecaster)->forecast($this->repo->stock(), $this->now);
    }

    /**
     * @param  list<array{task_type_id: int, name: string, default_seconds: int}>  $tasks
     * @return list<array<string, mixed>>
     */
    public function estimate(int $jobTypeId, int $quantity, array $tasks): array
    {
        $names = $this->repo->jobTypeNames();

        return (new EstimateModel)->suggest($jobTypeId, $names[$jobTypeId] ?? 'garment', $quantity, $tasks, $this->repo->completedStages(), $this->repo->minSamples());
    }

    public function completedJobs(): int
    {
        return $this->repo->completedJobCount();
    }
}
