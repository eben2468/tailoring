<?php

declare(strict_types=1);

namespace Nutofe\Ai\Llm;

/**
 * Provider-agnostic language model with function calling (ARCHITECTURE §14.1). One turn: the model
 * either answers in text or asks to call one or more of the declared tools.
 */
interface LlmClient
{
    public function enabled(): bool;

    public function name(): string;

    /**
     * @param  string  $system  instructions
     * @param  list<array{role: string, parts: list<array<string, mixed>>}>  $contents  conversation so far (Gemini shape)
     * @param  list<array{name: string, description: string, parameters?: array<string, mixed>}>  $tools
     * @param  int  $timeoutSeconds  how long this one call may take
     * @return array{text: string|null, calls: list<array{name: string, args: array<string, mixed>}>, parts: list<array<string, mixed>>}
     *
     * @throws LlmUnavailable
     */
    public function generate(string $system, array $contents, array $tools, int $timeoutSeconds = 20): array;
}
