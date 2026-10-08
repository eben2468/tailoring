# API Design — Core REST API

> Status: **PROPOSED — awaiting approval.** Base URL: `https://<host>/api/v1`. JSON only (`Content-Type: application/json; charset=utf-8`), except file uploads (`multipart/form-data`).
>
> **Updated after the 2026-10-07 decisions:**
> - **Workers removed:** drop `/workers`, and every `worker_id` field.
> - **Offline-first:** record ids are UUID strings (generated on the device for business records), so creates are naturally idempotent and `Idempotency-Key` is only needed on non-create actions. New endpoints: `GET /sync/pull?cursor=&limit=` (changed rows plus tombstones since `sync_seq`), `POST /sync/push` (batched changes with base `version`; returns applied/conflict per record), `GET /sync/config` (configuration bundle with `config_version`).
> - **Hours, stock and maintenance dates** are read from the database views. Responses keep the same field names (`estimated_seconds`, `actual_seconds`, `remaining_seconds`, `progress_percent`, `quantity_on_hand`, `next_maintenance_date`).
> - **Inventory:** "movements" are now **transactions** (`opening`, `purchase`, `return`, `usage`, `write_off`, `adjustment`); reservation endpoints (`/job-materials/*`) are dropped; usage can reference a `job_id`.
> - **Tools:** no cost fields. **Gemini** replaces Claude behind `/ai/*` (contract unchanged).
> Endpoints below will be revised in full when the backend phase starts.

---

## 1. General Conventions

| Topic | Convention |
|---|---|
| Versioning | URL prefix `/api/v1`; breaking changes → `/v2` |
| Auth | `Authorization: Bearer <access_token>` on all routes except `/auth/login`, `/auth/refresh`, `/health` |
| Naming | plural nouns, kebab-case paths, `snake_case` JSON fields |
| IDs | integers in paths and bodies |
| Time | ISO-8601 UTC timestamps (`2026-10-07T09:15:00.000Z`); business dates as `YYYY-MM-DD` |
| Durations | integer seconds (`estimated_seconds`, `actual_seconds`, `remaining_seconds`) |
| Measurements | `value_cm` canonical + `entered_unit`; the app converts for display |
| Pagination | `?page=1&per_page=25` (max 100) → `meta.pagination {page, per_page, total, total_pages}` |
| Sorting | `?sort=due_date,-priority` (whitelisted fields only) |
| Filtering | explicit query params (`status=`, `from=`, `to=`, `q=`) |
| Partial update | `PATCH` with only changed fields + `version` for optimistic locking |
| Actions | state changes that are not plain field edits are sub-resources: `POST /jobs/{id}/status` |
| Idempotency | `Idempotency-Key: <uuid>` **required** on timer, stock movement and create-job POSTs; replay returns the original response |
| Request id | every response has `X-Request-Id`; also echoed in error bodies |
| Rate limits | `429` with `Retry-After`; login: 5/min per account + 20/min per IP; AI chat: 20/min |

## 2. Response Envelope (approved format, implemented)

Success:
```json
{ "success": true, "message": "OK", "data": { "id": "…", "job_number": "024", "status": "in_progress" } }
```
List:
```json
{ "success": true, "message": "OK", "data": [ … ], "meta": { "pagination": { "page": 1, "per_page": 25, "total": 14, "total_pages": 1 } } }
```
Error:
```json
{ "success": false, "message": "Some fields are invalid.", "code": "VALIDATION_FAILED",
  "errors": { "due_date": ["Due date cannot be before the order date."] }, "request_id": "6329a511ff8a24d8" }
```
See [API_REFERENCE.md](API_REFERENCE.md) for the implemented error codes.

| HTTP | `error.code` examples |
|---|---|
| 400 | `BAD_REQUEST`, `MALFORMED_JSON` |
| 401 | `UNAUTHENTICATED`, `TOKEN_EXPIRED`, `INVALID_CREDENTIALS` |
| 403 | `FORBIDDEN`, `ACCOUNT_LOCKED` |
| 404 | `NOT_FOUND` |
| 409 | `CONFLICT_VERSION`, `TIMER_ALREADY_RUNNING`, `INVALID_STATUS_TRANSITION`, `SCHEDULE_CONFLICT`, `DUPLICATE` |
| 413 | `PAYLOAD_TOO_LARGE` |
| 422 | `VALIDATION_FAILED`, `INSUFFICIENT_STOCK` |
| 429 | `RATE_LIMITED` |
| 500 | `INTERNAL_ERROR` |
| 503 | `AI_UNAVAILABLE`, `MAINTENANCE` |

## 3. Permissions
`O` = owner, `A` = admin. All business endpoints: **O, A**. `/admin/*`: **A only**. Customers and workers never authenticate.

---

## 4. Endpoints

### 4.1 Health & Auth
| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness (public, no details) |
| POST | `/auth/login` | `{email, password, device_name}` → `{access_token, access_expires_at, refresh_token, refresh_expires_at, user}` |
| POST | `/auth/refresh` | `{refresh_token}` → new token pair (rotation) |
| POST | `/auth/logout` | Revoke current session |
| POST | `/auth/logout-all` | Revoke all sessions of the user |
| GET | `/auth/me` | Current user + permissions + key settings (timezone, units, currency, business name) |
| PATCH | `/auth/me` | Update own name/phone/avatar |
| POST | `/auth/change-password` | `{current_password, new_password}` → revokes other sessions |

### 4.2 Dashboard
| Method | Path | Purpose |
|---|---|---|
| GET | `/dashboard` | One call for the whole screen: `counts {active, pending, completed_this_period, due_today, overdue, due_this_week}`, `hours {estimated, actual, remaining}` (active jobs), `today_workload {by_stage[]}`, `today_schedule[]`, `priority_jobs[]`, `upcoming_deadlines[]`, `upcoming_appointments[]`, `inventory_alerts[]`, `maintenance_alerts[]`, `ai_insights[]` (top 1–3, may be `null` if AI down), `active_timer` |

### 4.3 Customers
| Method | Path | Purpose |
|---|---|---|
| GET | `/customers?q=&tag=&archived=&page=&sort=` | List/search |
| POST | `/customers` | Create (optionally with an initial measurement set) |
| GET | `/customers/{id}` | Profile + summary `{jobs_completed, jobs_active, customer_since, latest_measurement_set}` |
| PATCH | `/customers/{id}` | Update |
| POST | `/customers/{id}/archive` · `/unarchive` | Archive instead of delete |
| GET | `/customers/{id}/jobs?status=` | Job history ("Commissions") |
| GET | `/customers/{id}/appointments` | Appointments |
| GET | `/customers/{id}/files` · POST · DELETE `/customers/{id}/files/{fileId}` | Reference/design photos |

### 4.4 Measurements
| Method | Path | Purpose |
|---|---|---|
| GET | `/measurement-fields?attire_type_id=&include_inactive=` | Field configuration grouped by `measurement_groups` |
| POST | `/measurement-fields` · PATCH `/measurement-fields/{id}` | Configure fields (add, rename, reorder, deactivate) |
| GET/POST/PATCH | `/measurement-groups[/{id}]` | Configure groups |
| GET | `/customers/{id}/measurements` | History (sets, newest first, summary only) |
| GET | `/customers/{id}/measurements/latest` | Current set with values |
| POST | `/customers/{id}/measurements` | Record a **new** set `{taken_at, entered_unit, notes, values:[{field_id, value, value_text}], supersedes_set_id?}` — values sent in `entered_unit`, stored in cm |
| GET | `/measurement-sets/{id}` | One set with values |
| GET | `/customers/{id}/measurements/compare?from_set=&to_set=` | Field-by-field differences |

Sets are immutable: there is no PATCH/DELETE (corrections = new set with `supersedes_set_id`). [needs approval]

### 4.5 Catalog & configuration
| Method | Path | Purpose |
|---|---|---|
| GET/POST/PATCH | `/attire-types[/{id}]` | Garment types |
| GET/PUT | `/attire-types/{id}/stages` | Template routing: ordered stages, default hours, checklist |
| GET/POST/PATCH | `/production-stages[/{id}]` | Stage catalog |
| GET/POST/PATCH | `/workers[/{id}]` | Worker records (no accounts) — *only if approved* |
| GET/PATCH | `/settings` | Business profile, timezone, currency, units, working hours, capacity, thresholds |

### 4.6 Jobs
| Method | Path | Purpose |
|---|---|---|
| GET | `/jobs?status=&priority=&q=&customer_id=&due_from=&due_to=&overdue=&page=&sort=` | List; each item includes customer summary, current stage, `step {index,total}`, hours, progress |
| GET | `/jobs/counts` | Filter-chip counts (All/Active/Pending/Due soon/Overdue) |
| POST | `/jobs` | Create `{customer_id, attire_type_id, title, description, quantity, priority, order_date, due_date, collection_date, measurement_set_id, fabric_description, notes, status: draft|queued, tasks?:[…], fittings?:[{starts_at, ends_at, title}], materials?:[{item_id, quantity}]}` — tasks default from the attire template; fittings create appointments |
| GET | `/jobs/{id}` | Full detail: job, customer, tasks (with checklist), hours, timeline, materials, files, linked appointments, measurement snapshot summary, `active_timer` |
| PATCH | `/jobs/{id}` | Edit fields (with `version`) |
| POST | `/jobs/{id}/status` | `{status, reason?}` — validated transitions |
| POST | `/jobs/{id}/progress-override` | `{progress_percent | null}` |
| DELETE | `/jobs/{id}` | Drafts only; otherwise use status `cancelled` |
| GET/POST/DELETE | `/jobs/{id}/files[/{fileId}]` | Reference photos |
| GET | `/jobs/{id}/time-entries` | All labour on the job |

### 4.7 Tasks
| Method | Path | Purpose |
|---|---|---|
| POST | `/jobs/{id}/tasks` | Add a task |
| PUT | `/jobs/{id}/tasks/order` | Reorder `{task_ids:[…]}` |
| PATCH | `/tasks/{id}` | Edit name, estimate, schedule, notes, worker, `version` |
| POST | `/tasks/{id}/status` | `{status: in_progress|paused|completed|skipped|pending}` |
| POST | `/tasks/{id}/progress-override` | `{progress_percent | null}` |
| DELETE | `/tasks/{id}` | Only if no time entries |
| POST | `/tasks/{id}/checklist` · PATCH/DELETE `/checklist-items/{id}` | Subtasks |

### 4.8 Timer & time entries
| Method | Path | Purpose |
|---|---|---|
| GET | `/timers/active` | Running entries (with server `now` for offset) |
| POST | `/tasks/{id}/timer/start` | `{worker_id?, note?}` → running entry (409 `TIMER_ALREADY_RUNNING`) |
| POST | `/tasks/{id}/timer/stop` | `{note?, complete_task: bool}` → closed entry + updated task/job hours ("Pause" = stop; "Log & Finish" = stop + complete) |
| POST | `/timers/switch` | `{from_task_id, to_task_id}` atomic stop/start |
| GET | `/tasks/{id}/time-entries` | Entries for a task |
| POST | `/tasks/{id}/time-entries` | Manual entry `{started_at, ended_at}` or adjustment `{source:'adjustment', duration_seconds, reason}` ("+15m Adjust") |
| PATCH | `/time-entries/{id}` | Correct times/note (closed entries; audit-logged) |
| POST | `/time-entries/{id}/void` | `{reason}` — never hard-deleted |

Every timer/time-entry mutation returns the recalculated `task` and `job` hour blocks so the UI updates without refetching.

### 4.9 Calendar & appointments
| Method | Path | Purpose |
|---|---|---|
| GET | `/calendar?from=&to=&types=appointment,task,deadline,collection,maintenance` | Aggregated `CalendarItem[] {type, id, title, subtitle, starts_at, ends_at, all_day, status, color_key, job_id, customer_id, route}` |
| GET | `/calendar/summary?from=&to=` | Per-day counts + planned hours vs capacity (month view, week strip dots, "bench load") |
| GET/POST | `/appointments` | List (`from,to,customer_id,job_id,type`) / create (409 `SCHEDULE_CONFLICT` unless `allow_overlap`) |
| GET/PATCH/DELETE | `/appointments/{id}` | |
| POST | `/appointments/{id}/status` | confirm, complete, cancel, no_show |

### 4.10 Inventory
| Method | Path | Purpose |
|---|---|---|
| GET | `/inventory/summary` | Tiles: total items, low stock, depleted, alerts list |
| GET | `/inventory/items?category_id=&q=&stock=low|out|ok&page=&sort=` | List |
| POST · GET · PATCH | `/inventory/items[/{id}]` | Create / detail (incl. recent movements, reservations) / edit |
| POST | `/inventory/items/{id}/archive` | |
| GET | `/inventory/items/{id}/movements` | Ledger |
| POST | `/inventory/items/{id}/movements` | `{type: receive|adjust_in|adjust_out|write_off|return, quantity, unit_cost?, reference?, note}` |
| GET/POST/PATCH | `/inventory/categories[/{id}]` · `/suppliers[/{id}]` | Config |
| GET | `/jobs/{id}/materials` | Materials allocated to a job |
| POST | `/jobs/{id}/materials` | Reserve `{item_id, quantity}` (422 `INSUFFICIENT_STOCK`) |
| POST | `/job-materials/{id}/consume` · `/release` | Consume or release reservation |

### 4.11 Tools & equipment
| Method | Path | Purpose |
|---|---|---|
| GET | `/tools/summary` | Total, operational, due for service, imminent actions |
| GET | `/tools?category_id=&status=&due=soon|overdue&q=` | List |
| POST · GET · PATCH | `/tools[/{id}]` | Create / detail (with logs) / edit |
| POST | `/tools/{id}/archive` | |
| GET · POST | `/tools/{id}/maintenance` | Logs / record maintenance (recomputes next date) |
| GET/POST/PATCH | `/tool-categories[/{id}]` | Config |

### 4.12 Reports
All accept `from`, `to` (dates), optional `group_by=day|week|month`, `attire_type_id`, `stage_id`; return chart-ready series + totals. `format=csv` export is a later option.

| Path | Content |
|---|---|
| `/reports/jobs` | Completed, active, overdue, cancelled counts; by attire type |
| `/reports/hours` | Estimated vs actual by job, attire type, stage, period; overrun % |
| `/reports/production-performance` | Throughput, average lead time, on-time completion rate, average hours per garment |
| `/reports/customers` | New vs returning, top customers by jobs, active customers |
| `/reports/inventory` | Stock status, low/out items, consumption by item/category |
| `/reports/tool-maintenance` | Due/overdue, maintenance history, cost (if recorded) |
| `/reports/workload` | Planned vs capacity per day/week; per worker if enabled |
| `/reports/completion-trends` | Completions over time, average days late/early |

### 4.13 Notifications & devices
| Method | Path | Purpose |
|---|---|---|
| GET | `/notifications?unread=&page=` | List |
| GET | `/notifications/unread-count` | Bell badge |
| POST | `/notifications/{id}/read` · `/notifications/read-all` | Mark read |
| GET · PUT | `/notification-preferences` | Per-type in-app/push toggles, quiet hours |
| POST | `/devices` | Register/refresh FCM token `{platform, fcm_token}` |
| DELETE | `/devices/{fcm_token}` | Unregister (logout) |

### 4.14 Files
| Method | Path | Purpose |
|---|---|---|
| POST | `/files` | Upload image (multipart, ≤ 10 MB, jpg/png/webp/heic) → `{id, url, thumb_url}` |
| GET | `/files/{id}` · `/files/{id}/thumb` | Authorised download (short-lived signed URL or bearer) |

### 4.15 AI (proxied to the AI service)
| Method | Path | Purpose |
|---|---|---|
| GET | `/ai/insights?status=&type=&entity_type=&entity_id=` | Insight cards (dashboard, AI screen, job detail) |
| POST | `/ai/insights/{id}/dismiss` | |
| POST | `/ai/insights/{id}/apply` | Returns the **proposed change**; with `{confirm:true}` the core API applies it and audit-logs it |
| POST | `/ai/estimate` | `{attire_type_id, customer_id?, quantity, tasks?[]}` → per-task suggested hours, confidence, sample size, explanation ("Apply AI Estimate") |
| GET | `/jobs/{id}/ai/forecast` | Predicted finish, buffer, delay risk + reasons ("Atelier AI Production Analysis") |
| GET | `/ai/workload?from=&to=` | Capacity & workload analysis |
| GET | `/ai/accuracy` | Estimate accuracy metrics ("Labor precision") |
| POST | `/ai/chat` | `{conversation_id?, message}` → grounded answer + referenced entities |
| GET | `/ai/conversations` · `/ai/conversations/{id}` | History |

If the AI service is unreachable: `503 AI_UNAVAILABLE`; the dashboard returns `ai_insights: null` rather than failing.

### 4.16 Admin (admin role only)
| Method | Path | Purpose |
|---|---|---|
| GET/POST/PATCH | `/admin/users[/{id}]` | Manage owner/admin accounts (activate/deactivate) |
| POST | `/admin/users/{id}/reset-password` | Set temporary password; revokes sessions |
| POST | `/admin/users/{id}/revoke-sessions` | |
| GET | `/admin/audit-logs?user_id=&entity_type=&entity_id=&from=&to=` | Audit trail |
| GET | `/admin/system/health` | DB, disk, scheduler heartbeat, last backup, AI service, FCM status, versions |
| GET | `/admin/system/scheduler` | Scheduled task runs |
| GET | `/admin/ai/usage?from=&to=` | Tokens, cost estimate, errors |
| POST | `/admin/maintenance/recalculate-hours` | Trigger cache rebuild (also via CLI) |

---

## 5. Internal AI Service API (not reachable from the internet)
Called only by the core API, authenticated with HMAC-SHA256 (`X-Signature`, `X-Timestamp`, 5-minute window), bound to localhost/private network.
`POST /internal/estimate` · `GET /internal/jobs/{id}/forecast` · `GET /internal/workload` · `GET /internal/accuracy` · `POST /internal/chat` · `POST /internal/insights/refresh` · `GET /internal/health`.

## 6. Screen → Endpoint Map
| Screen | Calls |
|---|---|
| Dashboard | `GET /dashboard`, `GET /notifications/unread-count` |
| Jobs list | `GET /jobs`, `GET /jobs/counts`, `POST /tasks/{id}/timer/start` |
| Job details | `GET /jobs/{id}`, `GET /jobs/{id}/ai/forecast`, `POST /tasks/{id}/status`, checklist endpoints |
| Create job | `GET /customers?q=`, `GET /attire-types/{id}/stages`, `POST /ai/estimate`, `GET /inventory/items?category_id=fabric`, `POST /jobs` |
| Work timer | `GET /timers/active`, `POST …/timer/stop`, `POST /timers/switch`, `POST /tasks/{id}/time-entries`, `GET /calendar?from=now` |
| Calendar | `GET /calendar`, `GET /calendar/summary`, appointments CRUD |
| Customer profile | `GET /customers/{id}`, `GET /customers/{id}/measurements/latest`, `GET /measurement-fields`, `GET /customers/{id}/jobs` |
| Inventory | `GET /inventory/summary`, `GET /inventory/items`, movements, job materials |
| Tools | `GET /tools/summary`, `GET /tools`, maintenance endpoints |
| AI assistant | `GET /ai/insights`, `GET /ai/accuracy`, `GET /ai/workload`, `POST /ai/chat` |
