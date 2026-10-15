<?php

declare(strict_types=1);

namespace Nutofe\Ai;

/** Settings from the environment (.env in development; real environment variables in production). */
final class Config
{
    /** @param  array<string, string>  $values */
    private function __construct(private readonly array $values) {}

    public static function load(string $root): self
    {
        $values = [];
        $file = $root.'/.env';
        if (is_readable($file)) {
            foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
                $line = trim($line);
                if ($line === '' || str_starts_with($line, '#') || ! str_contains($line, '=')) {
                    continue;
                }
                [$key, $value] = explode('=', $line, 2);
                $values[trim($key)] = trim(trim($value), '"\'');
            }
        }
        foreach ($values as $key => $_) {
            $env = getenv($key);
            if ($env !== false) {
                $values[$key] = $env; // real environment wins
            }
        }

        return new self($values);
    }

    /** @param  array<string, string>  $values */
    public static function fromArray(array $values): self
    {
        return new self($values);
    }

    public function get(string $key, string $default = ''): string
    {
        $env = getenv($key);

        return $this->values[$key] ?? ($env === false ? $default : $env);
    }

    public function int(string $key, int $default): int
    {
        $v = $this->get($key);

        return $v === '' ? $default : (int) $v;
    }
}
