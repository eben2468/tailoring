<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

/**
 * Executes our authoritative SQL files (database/migrations/*.sql, database/seeds/**.sql)
 * statement by statement, so an error in any statement fails loudly with its file name.
 * Only ever used on trusted files from the repository — never on user input.
 */
final class SqlFile
{
    /** Absolute path of a file under the SQL root, e.g. path('migrations/0001_system.sql'). */
    public static function path(string $relative): string
    {
        return rtrim((string) config('nutofe.sql_path'), '/').'/'.ltrim($relative, '/');
    }

    public static function run(string $file): void
    {
        $sql = @file_get_contents($file);
        if ($sql === false) {
            throw new RuntimeException("Cannot read SQL file {$file}. Check NUTOFE_SQL_PATH.");
        }

        foreach (self::split($sql) as $statement) {
            try {
                DB::unprepared($statement);
            } catch (Throwable $e) {
                throw new RuntimeException(sprintf("%s failed: %s\nStatement: %s", basename($file), $e->getMessage(), mb_substr($statement, 0, 300)), 0, $e);
            }
        }
    }

    /** @return list<string> files in a folder under the SQL root, in name order */
    public static function filesIn(string $relativeDir): array
    {
        $files = glob(self::path($relativeDir).'/*.sql') ?: [];
        sort($files, SORT_STRING);

        return $files;
    }

    /**
     * Splits SQL into statements, respecting quotes, backticks, escapes and comments.
     * No DELIMITER support (the schema uses no stored routines).
     *
     * @return list<string>
     */
    public static function split(string $sql): array
    {
        $statements = [];
        $current = '';
        $length = strlen($sql);
        $quote = null;

        for ($i = 0; $i < $length; $i++) {
            $char = $sql[$i];
            $next = $i + 1 < $length ? $sql[$i + 1] : '';

            if ($quote !== null) {
                $current .= $char;
                if ($char === '\\' && $quote !== '`') {
                    $current .= $next;
                    $i++;
                } elseif ($char === $quote) {
                    if ($next === $quote) {
                        $current .= $next;
                        $i++;
                    } else {
                        $quote = null;
                    }
                }

                continue;
            }

            if (($char === '-' && $next === '-' && in_array(substr($sql, $i + 2, 1), ['', ' ', "\t", "\n", "\r"], true)) || $char === '#') {
                $end = strpos($sql, "\n", $i);
                $i = $end === false ? $length : $end;
                $current .= "\n";

                continue;
            }
            if ($char === '/' && $next === '*') {
                $end = strpos($sql, '*/', $i + 2);
                $i = $end === false ? $length : $end + 1;

                continue;
            }
            if ($char === "'" || $char === '"' || $char === '`') {
                $quote = $char;
                $current .= $char;

                continue;
            }
            if ($char === ';') {
                if (trim($current) !== '') {
                    $statements[] = trim($current);
                }
                $current = '';

                continue;
            }
            $current .= $char;
        }

        if (trim($current) !== '') {
            $statements[] = trim($current);
        }

        return $statements;
    }
}
