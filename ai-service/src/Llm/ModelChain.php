<?php

declare(strict_types=1);

namespace Nutofe\Ai\Llm;

/**
 * Several models in order of preference (GEMINI_MODEL, then GEMINI_FALLBACK_MODELS). Free tiers have small
 * per-model daily quotas, so when one is used up or busy the next one answers. A question stays with the
 * model that started it: once the conversation holds that model's function calls (with its thought
 * signatures), they are only sent back to the same model.
 */
final class ModelChain implements LlmClient
{
    private ?LlmClient $current = null;

    /** @param  list<LlmClient>  $models */
    public function __construct(private readonly array $models) {}

    public function enabled(): bool
    {
        foreach ($this->models as $m) {
            if ($m->enabled()) {
                return true;
            }
        }

        return false;
    }

    /** The model that answered last, else the first one. */
    public function name(): string
    {
        return ($this->current ?? $this->models[0] ?? null)?->name() ?? 'none';
    }

    public function generate(string $system, array $contents, array $tools, int $timeoutSeconds = 20): array
    {
        if ($this->current !== null && self::midQuestion($contents)) {
            return $this->current->generate($system, $contents, $tools, $timeoutSeconds);
        }
        $last = new LlmUnavailable('No language model is configured.', 'not_configured');
        foreach ($this->models as $model) {
            if (! $model->enabled()) {
                continue;
            }
            try {
                $reply = $model->generate($system, $contents, $tools, $timeoutSeconds);
                $this->current = $model;

                return $reply;
            } catch (LlmUnavailable $e) {
                $last = $e;
                if (! in_array($e->reason, ['quota', 'busy'], true)) {
                    throw $e; // a bad request or the network fails the same way on every model
                }
            }
        }

        throw $last;
    }

    /** True once the model has asked for a tool in this question. */
    private static function midQuestion(array $contents): bool
    {
        foreach ($contents as $c) {
            foreach ($c['parts'] ?? [] as $p) {
                if (isset($p['functionCall'])) {
                    return true;
                }
            }
        }

        return false;
    }
}
