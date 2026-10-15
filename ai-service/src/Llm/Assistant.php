<?php

declare(strict_types=1);

namespace Nutofe\Ai\Llm;

use Nutofe\Ai\Analytics\Analysis;
use Nutofe\Ai\Analytics\CompletionForecaster;
use Nutofe\Ai\Analytics\Stats;

/**
 * The grounded assistant (ARCHITECTURE §14.2). The model may only answer by calling the tools below,
 * which are backed by the analytics (never SQL). Tool results contain job numbers, garment types,
 * hours and dates: **no customer names, phones or other personal data** are ever sent to the model.
 *
 * Without a language model (no key, quota used up, provider down) the common questions are answered
 * directly from the same tools, and anything else gets a list of what can be asked.
 */
final class Assistant
{
    private const MAX_TOOL_ROUNDS = 3;

    /** All model calls for one question, so the figures-only answer still arrives within the core API's 45 s. */
    private const TIME_LIMIT_SECONDS = 30;

    private const SYSTEM = <<<'TXT'
        You are the Nutɔfe assistant, built into Nutɔfe, the production app of a bespoke men's tailoring workshop
        in Ghana (one owner). You run on Google Gemini. Be warm, clear and practical.

        What you can do:
        1. The workshop's own figures (jobs, deadlines, hours, workload, stock, estimate accuracy): use ONLY the
           figures below and the results of the tools you call. Never invent jobs, numbers or dates. If the figures
           do not cover a question, say so and suggest what the owner can check in the app.
        2. How to use Nutɔfe: explain from the app guide below.
        3. General tailoring and workshop know-how (techniques, fabrics and their care, fittings, planning a busy
           week, keeping tools in order): answer from general knowledge and say it is general advice, not from
           their figures.
        4. Greetings and questions about yourself: reply briefly and say what you can help with.

        Rules: refer to jobs by number, like #024. You never see customer names, phones or notes; do not ask for
        them. Prices, payments and money are out of scope for this app: say so politely. Durations in the figures
        are seconds: write hours like "6.5 h". Dates are YYYY-MM-DD: write them like "Thu 15 Oct". Keep answers
        short: at most about 6 sentences or a short list, with no headings.

        App guide (Nutɔfe):
        - Dashboard: today at a glance: active, due-today, overdue and this-week jobs; today's workload per stage;
          the top AI insight; the production schedule (running timer, planned stages, appointments, up next);
          priority jobs; stock and tool alerts.
        - Jobs: add a job for a customer from a garment template; it gets production stages (cutting, sewing,
          fitting…) with estimated hours. On the job sheet: start the timer on a stage, mark stages complete, add
          subtasks, record materials used, change the status (queued, in progress, on hold, ready for collection,
          collected). "Suggest hours" on a new job estimates hours from finished jobs.
        - Work timer: start, pause, switch stage or finish; time logged becomes the job's actual hours.
        - Calendar: week, day and month views of fittings, collections, consultations, due dates, planned stages
          and tool service dates; add appointments there.
        - Customers: profiles, contact buttons, measurement records with history and comparison, and their jobs.
        - More: Inventory (materials, stock levels, restock, usage per job), Tools & Equipment (maintenance log and
          next service), Reports (jobs, hours, workload, customers, inventory, tools), Notifications, this AI
          Assistant, Sync status, and settings such as garment templates and categories.
        - Works without a connection: changes are saved on the phone and sync when the server is reachable.
        - Notifications: low stock, jobs due or overdue, tool service, appointment reminders, timers left running.
        TXT;

    /** Short guide to the app, for "help" questions without the language model. */
    private const APP_GUIDE = <<<'TXT'
        Nutɔfe in short:
        • Dashboard: today's jobs, workload, production schedule, priority jobs and stock / tool alerts.
        • Jobs: add a job from a garment template; time each stage with the timer, mark stages done, and move the job on to ready and collected.
        • Calendar: fittings, collections, due dates and planned stages.
        • Customers: profiles and measurements with history.
        • More: inventory, tools & maintenance, reports, notifications and this assistant.
        It works without a connection and syncs when the server is reachable.
        TXT;

    public function __construct(private readonly Analysis $analysis, private readonly LlmClient $llm) {}

    /** @return list<array{name: string, description: string, parameters?: array<string, mixed>}> */
    public static function tools(): array
    {
        return [
            ['name' => 'work_queue', 'description' => 'Jobs in production in the order they should be worked on, with remaining hours, forecast finish date, due date and delay risk.'],
            ['name' => 'delay_risks', 'description' => 'Jobs forecast to finish late or close to their due date, with reasons.'],
            ['name' => 'job', 'description' => 'Forecast and status of one job by its number.', 'parameters' => ['type' => 'object', 'properties' => ['job_number' => ['type' => 'string', 'description' => 'The job number, e.g. 024']], 'required' => ['job_number']]],
            ['name' => 'workload', 'description' => 'Bench capacity against the work due in the coming week, and how much room is left.'],
            ['name' => 'stock_forecast', 'description' => 'Materials that will run out soon at their recent usage, with days left.'],
            ['name' => 'estimate_accuracy', 'description' => 'How accurate the hour estimates have been, overall and per stage.'],
        ];
    }

    /** @return array<string, mixed> */
    public function callTool(string $name, array $args): array
    {
        return match ($name) {
            'work_queue' => ['jobs' => array_map(fn ($f) => $this->jobRow($f), array_slice($this->analysis->forecast(), 0, 10))],
            'delay_risks' => ['jobs' => array_values(array_map(fn ($f) => $this->jobRow($f), array_filter($this->analysis->forecast(), fn ($f) => in_array($f['risk'], ['high', 'medium'], true))))],
            'job' => $this->job((string) ($args['job_number'] ?? '')),
            'workload' => $this->analysis->workload(),
            'stock_forecast' => ['materials' => array_values(array_filter($this->analysis->stock(), fn ($s) => $s['days_left'] !== null && $s['days_left'] <= 30))],
            'estimate_accuracy' => $this->analysis->accuracy(),
            default => ['error' => 'Unknown tool'],
        };
    }

    /**
     * @param  list<array{role: string, text: string}>  $messages  the conversation, last one from the user
     * @return array{answer: string, source: string, job_numbers: list<string>}
     */
    public function answer(array $messages): array
    {
        $question = trim((string) (end($messages)['text'] ?? ''));
        $reason = 'not_configured';
        if ($this->llm->enabled()) {
            try {
                return $this->withModel($messages);
            } catch (LlmUnavailable $e) {
                $reason = $e->reason;
                error_log('Language model unavailable, answering from the figures: '.$e->getMessage()); // no conversation text logged
            }
        }

        return $this->withoutModel($question, $reason);
    }

    /** One line saying why the full assistant cannot answer, for questions the figures alone cannot. */
    private static function unavailableNote(string $reason): string
    {
        return match ($reason) {
            'quota' => "The full assistant (Google Gemini) has used up its free allowance for today, so I can only answer from your figures until it resets.",
            'not_configured' => 'The full assistant (Google Gemini) is not switched on, so I can only answer from your figures.',
            default => "The full assistant (Google Gemini) can't be reached right now, so I can only answer from your figures. Try again in a minute.",
        };
    }

    /**
     * @param  list<array{role: string, text: string}>  $messages
     * @return array{answer: string, source: string, job_numbers: list<string>}
     */
    private function withModel(array $messages): array
    {
        $contents = [];
        foreach (array_slice($messages, -8) as $m) {
            $contents[] = ['role' => $m['role'] === 'assistant' ? 'model' : 'user', 'parts' => [['text' => mb_substr($m['text'], 0, 1000)]]];
        }
        $jobNumbers = [];
        $system = self::SYSTEM."\n\n".$this->snapshot();
        $deadline = microtime(true) + self::TIME_LIMIT_SECONDS;
        for ($round = 0; $round <= self::MAX_TOOL_ROUNDS; $round++) {
            $left = (int) floor($deadline - microtime(true));
            if ($left < 3) {
                throw new LlmUnavailable('The language model took too long.', 'timeout');
            }
            $reply = $this->llm->generate($system, $contents, self::tools(), min(20, $left));
            if ($reply['calls'] === []) {
                $text = $reply['text'] ?? '';
                preg_match_all('/#(\d{2,})/', $text, $m);

                return ['answer' => $text !== '' ? $text : "I don't have data for that.", 'source' => $this->llm->name(), 'job_numbers' => array_values(array_unique($m[1]))];
            }
            $contents[] = ['role' => 'model', 'parts' => $reply['parts']];
            $responses = [];
            foreach ($reply['calls'] as $call) {
                $result = $this->callTool($call['name'], $call['args']);
                array_push($jobNumbers, ...$this->numbersIn($result));
                $responses[] = ['functionResponse' => ['name' => $call['name'], 'response' => $result]];
            }
            $contents[] = ['role' => 'user', 'parts' => $responses];
        }

        throw new LlmUnavailable('The language model did not finish its answer.', 'timeout');
    }

    /**
     * The workshop's current figures, sent with every question so most answers need one model call (free
     * quotas count calls). Job numbers, garment types, hours and dates only: no personal data.
     */
    private function snapshot(): string
    {
        $figures = [];
        foreach (['work_queue', 'delay_risks', 'workload', 'stock_forecast', 'estimate_accuracy'] as $tool) {
            $figures[$tool] = $this->callTool($tool, []);
        }
        $today = $this->analysis->calendar()->today($this->analysis->now);

        return 'Today is '.$today->format('l j F Y').". Current workshop figures (JSON; use the `job` tool for one job's details):\n"
            .json_encode($figures, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    /** @return array{answer: string, source: string, job_numbers: list<string>} */
    private function withoutModel(string $question, string $reason = 'not_configured'): array
    {
        $q = mb_strtolower($question);
        $has = fn (string ...$words): bool => array_filter($words, fn (string $w) => str_contains($q, $w)) !== [];
        $intent = match (true) {
            (bool) preg_match('/#?(\d{3,})/', $q) && $has('job') || (bool) preg_match('/#(\d{2,})/', $q) => 'job',
            $has('late', 'risk', 'overdue', 'behind') => 'risks',
            $has('stock', 'material', 'fabric', 'run out') => 'stock',
            $has('capacity', 'workload', 'room', 'accept', 'overtime', 'this week', 'commission') => 'workload',
            $has('accura', 'estimate') => 'accuracy',
            $has('today', 'next', 'work on', 'priority', 'first') => 'queue',
            $has('which model', 'what model', 'who are you', 'what are you', 'are you an ai', 'gemini') => 'identity',
            $has('how do i', 'how to', 'how does', 'help', 'understand', 'system', 'the app', 'nutɔfe', 'nutofe', 'what can you', 'explain') => 'app',
            str_word_count($q) <= 4 && (bool) preg_match('/\b(hello|hi|hey|good (morning|afternoon|evening)|thanks|thank you)\b/', $q) => 'greeting',
            default => 'other',
        };
        $examples = 'Ask me, for example: what should I work on today, which jobs may finish late, can I take another commission this week, which materials run out soon, or "How is #024 doing?".';
        $plain = fn (string $text): array => ['answer' => $text, 'source' => 'analytics', 'job_numbers' => []];

        return match ($intent) {
            'queue' => $this->queueAnswer(),
            'risks' => $this->risksAnswer(),
            'stock' => $this->stockAnswer(),
            'workload' => $this->workloadAnswer(),
            'accuracy' => $this->accuracyAnswer(),
            'job' => $this->jobAnswer($q),
            'greeting' => $plain("Hello! I'm the Nutɔfe assistant. ".self::unavailableNote($reason)."\n\n".$examples),
            'identity' => $plain("I'm the Nutɔfe assistant. With Google Gemini I answer free questions about your workshop, how to use the app and tailoring in general. ".self::unavailableNote($reason)),
            'app' => $plain(self::APP_GUIDE."\n\n".$examples),
            default => $plain(self::unavailableNote($reason)."\n\n".$examples),
        };
    }

    /** @return array{answer: string, source: string, job_numbers: list<string>} */
    private function queueAnswer(): array
    {
        $queue = array_slice($this->analysis->forecast(), 0, 3);
        if ($queue === []) {
            return ['answer' => 'There is no job in production right now.', 'source' => 'analytics', 'job_numbers' => []];
        }
        $lines = array_map(fn ($f) => sprintf('#%s %s: %s left%s', $f['job_number'] ?? 'new', $f['job_type'], Stats::hours($f['remaining_seconds']),
            $f['due_date'] === null ? '' : ', due '.CompletionForecaster::label($f['due_date']).($f['risk'] === 'high' ? ' (at risk)' : '')), $queue);

        return ['answer' => "Work in this order:\n• ".implode("\n• ", $lines), 'source' => 'analytics', 'job_numbers' => $this->numbersIn(['jobs' => $queue])];
    }

    /** @return array{answer: string, source: string, job_numbers: list<string>} */
    private function risksAnswer(): array
    {
        $risks = array_values(array_filter($this->analysis->forecast(), fn ($f) => in_array($f['risk'], ['high', 'medium'], true)));
        if ($risks === []) {
            return ['answer' => 'No job is at risk: at the current capacity every job in production finishes before its due date.', 'source' => 'analytics', 'job_numbers' => []];
        }
        $lines = array_map(fn ($f) => sprintf('#%s %s finishes %s, due %s%s', $f['job_number'] ?? 'new', $f['job_type'],
            CompletionForecaster::label((string) $f['finish_date']), CompletionForecaster::label((string) $f['due_date']),
            $f['risk'] === 'high' ? sprintf(' (%d day%s late)', $f['days_late'], $f['days_late'] === 1 ? '' : 's') : ' (no time to spare)'), $risks);

        return ['answer' => "At risk:\n• ".implode("\n• ", $lines), 'source' => 'analytics', 'job_numbers' => $this->numbersIn(['jobs' => $risks])];
    }

    /** @return array{answer: string, source: string, job_numbers: list<string>} */
    private function stockAnswer(): array
    {
        $soon = array_values(array_filter($this->analysis->stock(), fn ($s) => $s['days_left'] !== null && $s['days_left'] <= 30));
        if ($soon === []) {
            return ['answer' => 'No material runs out in the next 30 days at its recent pace.', 'source' => 'analytics', 'job_numbers' => []];
        }
        $lines = array_map(fn ($s) => sprintf('%s: about %d day%s left', $s['item_name'], $s['days_left'], $s['days_left'] === 1 ? '' : 's'), array_slice($soon, 0, 5));

        return ['answer' => "Running out soonest:\n• ".implode("\n• ", $lines), 'source' => 'analytics', 'job_numbers' => []];
    }

    /** @return array{answer: string, source: string, job_numbers: list<string>} */
    private function workloadAnswer(): array
    {
        $w = $this->analysis->workload();
        $text = sprintf('Until %s the bench has %s; jobs due by then need %s', CompletionForecaster::label($w['to']), Stats::hours($w['capacity_seconds']), Stats::hours($w['demand_seconds']));
        $text .= match ($w['state']) {
            'overbooked' => '. That is more than the time available: move a due date or plan extra hours.',
            'full' => ', which fills the week.',
            'closed' => '.',
            default => sprintf(', leaving room for about %s more.', Stats::hours($w['free_seconds'])),
        };

        return ['answer' => $text, 'source' => 'analytics', 'job_numbers' => []];
    }

    /** @return array{answer: string, source: string, job_numbers: list<string>} */
    private function accuracyAnswer(): array
    {
        $a = $this->analysis->accuracy();
        if ($a['stages'] === 0) {
            return ['answer' => 'There are no completed stages with estimates yet, so accuracy cannot be measured.', 'source' => 'analytics', 'job_numbers' => []];
        }
        $text = sprintf('Estimates are %s%% accurate over %d completed stages; %s%% finished within ±10%%.', $a['accuracy_percent'], $a['stages'], $a['within_10_percent']);
        if ($a['by_stage'] !== []) {
            $s = $a['by_stage'][0];
            $text .= sprintf(' %s runs %s%% %s than estimated.', $s['name'], abs($s['bias_percent']), $s['bias_percent'] > 0 ? 'longer' : 'shorter');
        }

        return ['answer' => $text, 'source' => 'analytics', 'job_numbers' => []];
    }

    /** @return array{answer: string, source: string, job_numbers: list<string>} */
    private function jobAnswer(string $q): array
    {
        preg_match('/#?(\d{2,})/', $q, $m);
        $r = $this->job($m[1] ?? '');
        if (isset($r['error'])) {
            return ['answer' => (string) $r['error'], 'source' => 'analytics', 'job_numbers' => []];
        }

        return ['answer' => sprintf('#%s %s: %s left, position %d in the queue. %s', $r['job_number'], $r['job_type'], Stats::hours($r['remaining_seconds']), $r['position'], implode('; ', $r['reasons']).'.'),
            'source' => 'analytics', 'job_numbers' => [(string) $r['job_number']]];
    }

    /** @return array<string, mixed> */
    private function job(string $number): array
    {
        $number = ltrim(trim($number), '#');
        foreach ($this->analysis->forecast() as $f) {
            if ($f['job_number'] !== null && (ltrim($f['job_number'], '0') === ltrim($number, '0') || $f['job_number'] === $number)) {
                return $this->jobRow($f);
            }
        }

        return ['error' => "Job #{$number} is not in production (it may be finished, on hold or not exist)."];
    }

    /**
     * @param  array<string, mixed>  $f
     * @return array<string, mixed>
     */
    private function jobRow(array $f): array
    {
        return array_intersect_key($f, array_flip(['job_number', 'job_type', 'position', 'remaining_seconds', 'finish_date', 'due_date', 'days_late', 'risk', 'reasons']));
    }

    /**
     * @param  array<string, mixed>  $result
     * @return list<string>
     */
    private function numbersIn(array $result): array
    {
        $out = [];
        array_walk_recursive($result, function ($v, $k) use (&$out): void {
            if ($k === 'job_number' && $v !== null) {
                $out[] = (string) $v;
            }
        });

        return array_values(array_unique($out));
    }
}
