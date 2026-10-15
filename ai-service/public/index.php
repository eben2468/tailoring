<?php

declare(strict_types=1);

// Nutɔfe AI service entry point. Internal only: reached by the core API on the private network.

use Nutofe\Ai\Config;
use Nutofe\Ai\Data\Db;
use Nutofe\Ai\Data\Repository;
use Nutofe\Ai\Http\Kernel;
use Nutofe\Ai\Llm\GeminiClient;
use Nutofe\Ai\Llm\ModelChain;

require __DIR__.'/../vendor/autoload.php';

$root = dirname(__DIR__);
$config = Config::load($root);
// The main model, then lighter ones with their own free quotas (GEMINI_FALLBACK_MODELS, comma-separated).
$models = array_values(array_unique(array_filter(array_map('trim', [
    $config->get('GEMINI_MODEL', 'gemini-3.5-flash'),
    ...explode(',', $config->get('GEMINI_FALLBACK_MODELS', 'gemini-3.1-flash-lite,gemini-flash-lite-latest')),
]))));
$kernel = new Kernel(
    $config->get('AI_SERVICE_SECRET'),
    new Repository(new Db($config)),
    new ModelChain(array_map(fn (string $m) => new GeminiClient($config->get('GEMINI_API_KEY'), $m, $config->int('GEMINI_DAILY_LIMIT', 200), $root.'/var'), $models)),
);

$path = parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH) ?: '/';
$result = $kernel->handle(
    strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET')),
    $path,
    (string) file_get_contents('php://input'),
    $_SERVER['HTTP_X_NUTOFE_TIME'] ?? null,
    $_SERVER['HTTP_X_NUTOFE_SIGNATURE'] ?? null,
    time(),
);

http_response_code($result['status']);
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
echo json_encode($result['body'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION);
