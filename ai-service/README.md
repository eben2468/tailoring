# Nutɔfe AI service

Internal service for production analytics and the assistant (ARCHITECTURE §14). Only the core API calls it; the app never does. Plain PHP 8.3, no framework.

```
public/index.php      entry point (HTTP, HMAC-checked)
src/Data/             read-only queries (no personal data is ever read)
src/Analytics/        EstimateModel, CompletionForecaster, AccuracyTracker, WorkloadAnalyzer, InventoryForecaster
src/Insights/         InsightGenerator: figures → insight cards with evidence and a suggested action
src/Llm/              LlmClient, GeminiClient (function calling, daily cap), Assistant (grounded chat + figures-only fallback)
src/Http/Kernel.php   routes: /health, /overview, /jobs/{id}/forecast, /estimate, /insights, /chat
tests/                PHPUnit (analytics, assistant, signing); no database needed
```

## Run (development)
The `ai` container in `infra/docker-compose.yml` serves it on the internal network at `http://ai:8090` (no published port).

```bash
cp ai-service/.env.example ai-service/.env       # then set AI_SERVICE_SECRET (same value as backend/.env)
docker run --rm -v "$PWD/ai-service:/app" nutofe-php sh -c "cd /app && composer install"
docker compose -f infra/docker-compose.yml up -d ai
docker exec -w /var/www/backend nutofe-php php artisan ai:refresh      # insight cards, through the core API
docker run --rm -v "$PWD/ai-service:/app" nutofe-php sh -c "cd /app && vendor/bin/phpunit"
```

## Configuration (`ai-service/.env`, never committed)
| Key | |
|---|---|
| `DB_*` | Account `nutofe_ai`: SELECT on the business tables and views, INSERT on `ai_predictions` only (`infra/mysql/init/02-ai-user.sql`). |
| `AI_SERVICE_SECRET` | Shared with the core API (`backend/.env`). Without it every request is refused. |
| `GEMINI_API_KEY`, `GEMINI_MODEL`, `GEMINI_FALLBACK_MODELS` | The language models for the chat, in order (default `gemini-3.5-flash`, then `gemini-3.1-flash-lite,gemini-flash-lite-latest`). Free tiers have small per-model daily quotas (gemini-3.5-flash: 20 requests a day); on a 429 the model is skipped until Google's reset time (`var/<model>.blocked`) and the next one answers. Google retires older models for new keys: check the model list if calls fail with 404. The current figures (job numbers, garment types, hours, dates) travel with each question, so most answers take one request. Empty key = the chat answers from the figures only. Each question gets at most 30 s of model calls; a busy model (503) is retried once after 1.5 s; on quota (429), any other error or the time limit, the chat answers from the figures and the reason is logged (never the conversation). |
| `GEMINI_DAILY_LIMIT` | Maximum Gemini calls per day (free-tier protection; counter in `var/`). |

## Privacy
Gemini only ever receives the conversation text and tool results made of job numbers, garment types, hours and dates. Customer names, phones, addresses, notes and job titles are never read by this service. Google's terms for unpaid Gemini API use allow submitted content to be used to improve their products: check the current terms before go-live (ARCHITECTURE §14.2).

## Production
Run `public/index.php` behind PHP-FPM on the private network (not the built-in server). Use a strong `nutofe_ai` password and secret from the server's secrets store.
