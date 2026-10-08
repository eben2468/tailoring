# API Reference — Nutɔfe Core API

> Documents **implemented and tested** endpoints only. Planned endpoints are in [API_DESIGN.md](API_DESIGN.md).
> Implemented on **Laravel 13**: foundation, authentication & authorization, customers, measurements. Updated 2026-10-08.

Base URL: `http://localhost:8080/api/v1` (dev) · `https://<api-host>/api/v1` (production, HTTPS only).

---

## 1. Conventions

### Requests
- Bodies are JSON (`Content-Type: application/json`) and must be a JSON **object**. Bodies over 1 MB → `413`.
- Authenticated endpoints need `Authorization: Bearer <access_token>`.
- Unknown fields are ignored (never mass-assigned). Strings are trimmed (passwords excepted) and control characters removed; empty strings become `null`.
- Timestamps are ISO-8601 UTC (`2026-10-08T09:15:00.000Z`). Dates are `YYYY-MM-DD`. Phone numbers are E.164 (`+233241234567`).

### Success response
```json
{ "success": true, "message": "Signed in.", "data": { … }, "meta": { "pagination": { … } } }
```
`meta` only appears on paginated lists: `{"pagination": {"page": 1, "per_page": 25, "total": 42, "total_pages": 2}}`. Lists accept `?page=` and `?per_page=` (max 100).

### Error response
```json
{
  "success": false,
  "message": "Some fields are invalid.",
  "code": "VALIDATION_FAILED",
  "errors": { "email": ["The email field must be a valid email address."] },
  "request_id": "6329a511ff8a24d8"
}
```
- `code` is stable and machine-readable; `message` is safe to show to the user.
- `errors` maps field → messages (an empty object for non-validation errors).
- `request_id` is also in the `X-Request-Id` header of **every** response. Quote it when reporting problems; it links to the server log.
- Internal details are never returned (in development only, `APP_DEBUG=true` adds a `debug` object to 500 responses).

| HTTP | `code` | When |
|---|---|---|
| 400 | `MALFORMED_JSON`, `BAD_REQUEST` | Body is not a JSON object |
| 401 | `UNAUTHENTICATED` | Missing, invalid or revoked token (`WWW-Authenticate: Bearer`) |
| 401 | `TOKEN_EXPIRED` | Access token expired → call `/auth/refresh` |
| 401 | `INVALID_CREDENTIALS` | Wrong email or password (identical for unknown emails) |
| 401 | `INVALID_REFRESH_TOKEN`, `SESSION_EXPIRED`, `REFRESH_TOKEN_ROTATED` | Refresh failures (see §3) |
| 403 | `FORBIDDEN` | Signed in but lacking permission |
| 403 | `ACCOUNT_DISABLED` | Account deactivated by the admin |
| 403 | `HTTPS_REQUIRED` | Plain HTTP when `APP_REQUIRE_HTTPS=true` |
| 404 | `NOT_FOUND` | Unknown endpoint or resource |
| 405 | `METHOD_NOT_ALLOWED` | Wrong method (`Allow` header lists valid ones) |
| 409 | `SELF_MODIFICATION`, `LAST_ADMIN` | Admin safety rules |
| 413 | `PAYLOAD_TOO_LARGE` | Body over 1 MB |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | Body sent without `application/json` |
| 422 | `VALIDATION_FAILED` | Field errors in `errors` |
| 429 | `ACCOUNT_LOCKED` | 5 failed logins → locked 15 min (`Retry-After` header) |
| 429 | `RATE_LIMITED` | Too many login/refresh requests from one IP (Laravel limiter: 10/min; Nginx also limits) |
| 500 | `INTERNAL_ERROR` | Unexpected error (logged with `request_id`) |
| 503 | — | `/health` when the database is unreachable |

### Roles & permissions
| Role | Permissions |
|---|---|
| `owner` | `business` |
| `admin` | `business`, `admin.users`, `admin.audit`, `admin.system` |

Customers and workers never have accounts. Routes check permissions, not role names.

---

## 2. Health

### `GET /health` (public)
`200` → `{"status": "ok", "database": "ok", "time": "2026-10-08T01:30:37Z"}` · `503` with `"status": "degraded"` if the database is unreachable.

---

## 3. Authentication

### Token model
- `access_token` (`nat_…`): sent as a Bearer token; valid **30 minutes**.
- `refresh_token` (`nrt_…`): exchanged at `/auth/refresh`; valid **30 days**; **single use** (every refresh returns a new pair).
- Both are opaque random strings. The server stores only their SHA-256 hashes.
- Store them only in `flutter_secure_storage`, and never log them.
- If an already-used refresh token is presented more than 10 s after it was rotated, the server treats it as stolen and **signs out every token in that login family** (audit: `auth.refresh_reuse_detected`).
- Within 10 s it is treated as a client race: `REFRESH_TOKEN_ROTATED`, and the newest tokens stay valid. The app should run only one refresh at a time.

### `POST /auth/login` (public, rate-limited)
```json
{
  "email": "owner@nutofe.test",
  "password": "…",
  "device_id": "0192f0a1-2222-7000-8000-000000000001",
  "device_name": "Pixel 8",
  "platform": "android",
  "app_version": "1.0.0"
}
```
| Field | Rules |
|---|---|
| `email` | required, valid email, ≤ 190 (case-insensitive) |
| `password` | required, ≤ 128 |
| `device_id` | optional UUID generated once per app installation (it is the offline-sync identity) |
| `device_name` | optional, ≤ 120 |
| `platform` | optional, `android` \| `ios` |
| `app_version` | optional, ≤ 20 |

`200`:
```json
{
  "success": true, "message": "Signed in.",
  "data": {
    "token_type": "Bearer",
    "access_token": "nat_…", "access_token_expires_at": "2026-10-08T02:00:41.478Z",
    "refresh_token": "nrt_…", "refresh_token_expires_at": "2026-11-07T01:30:41.478Z",
    "user": { "id": 1, "full_name": "Marcus Owner", "email": "owner@nutofe.test", "phone": "+233240000001",
              "role": "owner", "permissions": ["business"] },
    "business": { "name": "Nutɔfe", "timezone": "Africa/Accra", "currency": "GHS", "currency_symbol": "GH₵",
                  "phone_region": "GH", "default_measurement_unit": "in" }
  }
}
```
Errors: `422 VALIDATION_FAILED`, `401 INVALID_CREDENTIALS`, `403 ACCOUNT_DISABLED`, `429 ACCOUNT_LOCKED` (after 5 wrong passwords; even the correct password is refused until the lock expires), `429 RATE_LIMITED`.

### `POST /auth/refresh` (public, rate-limited)
`{"refresh_token": "nrt_…"}` → `200` with the same shape as login.
Errors: `401 INVALID_REFRESH_TOKEN` (unknown, revoked, or theft detected), `401 SESSION_EXPIRED`, `401 REFRESH_TOKEN_ROTATED`.

### `POST /auth/logout` 🔒
Revokes the current session only. → `200`, `data: null`.

### `POST /auth/logout-all` 🔒
Revokes every session of the user on all devices. → `{"sessions_revoked": 2}`.

### `GET /auth/me` 🔒
→ `{"user": {...}, "business": {...}}` (same shapes as login).

### `PATCH /auth/me` 🔒
`{"full_name": "…", "phone": "+233…" | null}`. Both are optional; `role` and `email` cannot be changed here. → `{"user": {...}}`.

### `POST /auth/change-password` 🔒
`{"current_password": "…", "new_password": "…"}` → `200`. Every **other** session is signed out; the current device stays signed in.
Errors: `422` with `errors.current_password` (wrong) or `errors.new_password` (policy failure or same as current).

**Password policy** (all endpoints that set a password): 10–128 characters, not a common password, does not contain the email name, and at least 4 distinct characters. Hashed with Argon2id.

---

## 4. Admin (role `admin` only)

All of these return `401` without a token and `403 FORBIDDEN` for the owner.

### `GET /admin/users` 🔒 `admin.users`
Paginated list. Each item:
```json
{ "id": 1, "full_name": "Marcus Owner", "email": "owner@nutofe.test", "phone": "+233240000001",
  "role": "owner", "permissions": ["business"], "is_active": true, "is_locked": false,
  "last_login_at": "2026-10-08T01:30:41.478Z", "password_changed_at": "…", "created_at": "…" }
```

### `GET /admin/users/{id}` 🔒 `admin.users`
One user → `404` if unknown.

### `POST /admin/users` 🔒 `admin.users`
`{"full_name": "…", "email": "…", "role": "owner"|"admin", "password": "…", "phone": "+233…"?}` → `201`.
Errors: `422` (duplicate email, invalid role, weak password).

### `PATCH /admin/users/{id}` 🔒 `admin.users`
Any of `full_name`, `phone`, `role`, `is_active`. Deactivating a user signs them out everywhere.
Errors: `409 SELF_MODIFICATION` (changing your own role or deactivating yourself), `409 LAST_ADMIN`.

### `POST /admin/users/{id}/reset-password` 🔒 `admin.users`
`{"password": "…"}` → `200`. The user is signed out everywhere. This is the recovery path for a forgotten owner password.

### `POST /admin/users/{id}/revoke-sessions` 🔒 `admin.users`
→ `{"sessions_revoked": n}`.

### `GET /admin/audit-logs` 🔒 `admin.audit`
Filters: `user_id`, `action`, `entity_type`, `entity_id`, `from`, `to` (dates), plus pagination (default 50, newest first). Item:
```json
{ "id": 12, "user_id": 2, "user_name": "System Admin", "device_id": null, "action": "admin.password_reset",
  "entity_type": "user", "entity_id": "1", "changes": {"sessions_revoked": 1},
  "ip_address": "172.18.0.1", "request_id": "…", "created_at": "…" }
```
Audited actions so far: `auth.login`, `auth.login_failed`, `auth.account_locked`, `auth.login_blocked`, `auth.logout`, `auth.logout_all`, `auth.password_changed`, `auth.refresh_reuse_detected`, `admin.user_created`, `admin.user_updated`, `admin.password_reset`, `admin.sessions_revoked`. Passwords and tokens are never written to the audit log.

---

## 5. Customers 🔒 `business` (owner and admin)

Customer ids are UUID strings. The app generates them, so a retried create can never make a duplicate.
Every customer carries a `version`. Send it back when editing; if another device changed the customer in the meantime, the server returns `409 CONFLICT_VERSION`.

### `GET /customers`
Query: `q` (name, phone or email), `status` = `active` (default) \| `archived` \| `all`, `sort` = `name` (default) \| `recent`, `page`, `per_page` (≤ 100).
`%` and `_` in `q` are treated literally. Phone search ignores spaces and a leading 0.
Each item:
```json
{ "id": "0192f0a1-…", "full_name": "Kofi Mensah", "phone": "+233241110001", "phone_alt": null,
  "email": "kofi@example.com", "address": "East Legon, Accra", "notes": null, "style_preferences": null,
  "preferred_unit": "in", "is_archived": false,
  "summary": { "active_jobs": 1, "completed_jobs": 4, "measurement_sets": 2, "last_measured_at": "2026-10-04T09:00:00.000Z" },
  "version": 3, "created_at": "…", "updated_at": "…" }
```

### `POST /customers`
`{"id"?: uuid, "full_name": "…", "phone"?, "phone_alt"?, "email"?, "address"?, "notes"?, "style_preferences"?, "preferred_unit"?: "in"|"cm", "allow_duplicate_phone"?: bool}`
- `201 Customer added.` If the same `id` already exists, it returns `200 Customer already exists.` (idempotent retry).
- Phones are normalised to E.164 using the business region. Ghana local numbers are accepted: `024 111 0001` → `+233241110001`. Anything that isn't a valid number returns `422` on `phone`.
- **Duplicate phone:** if another customer already uses the number, the server returns `409 DUPLICATE_PHONE` with `errors.phone: ["Already used by Kofi Mensah."]`. Resend with `allow_duplicate_phone: true` to save anyway.

### `GET /customers/phone-check?phone=…&except=<id>`
Customers already using a number (main or alternative), for the duplicate warning: `[{"id", "full_name", "phone", "is_archived", "created_at"}]`.

### `GET /customers/{id}` · `PATCH /customers/{id}`
PATCH takes any of the create fields plus the required `version`. It returns the updated customer, with `version` incremented. Errors: `409 CONFLICT_VERSION`, `409 DUPLICATE_PHONE`, `422`, `404` (unknown or malformed id).

### `POST /customers/{id}/archive` · `POST /customers/{id}/unarchive`
Archived customers are hidden from the default list. Nothing is deleted.

## 6. Measurements 🔒 `business`

Lengths are stored in **centimetres** (3 decimals). Each set records the unit the tailor used, so inches round-trip exactly.
**Sets are immutable:** every recording is a new set, partial sets are allowed, and a correction is a new set with `supersedes_set_id`.
"Current" measurements are the latest value of each field across all of the customer's sets.

### `GET /measurement-fields`
Active groups with their fields, in display order. This drives the measurement form.
```json
[{ "id": 1, "code": "upper_body", "name": "Upper Body / Jacket & Shirt",
   "fields": [{ "id": 3, "code": "chest", "label": "Chest", "value_type": "length", "choice_options": null, "min_cm": 60, "max_cm": 200, "help_text": null }] }]
```
`value_type`: `length` (number), `choice` (one of `choice_options`), `text`.

### `POST /customers/{id}/measurements`
```json
{ "id": "uuid (optional, makes retries idempotent)", "entered_unit": "in", "measured_at": "2026-10-04T09:00:00Z (optional, not in the future)",
  "notes": "Erect posture …", "supersedes_set_id": null,
  "values": [ { "field_id": 3, "value": 42 }, { "field_id": 20, "value_text": "Low right" } ] }
```
→ `201 Measurements saved.` with the set. Each value is returned as `value_cm` plus `value` (in the entered unit).
Errors (nothing is saved if any value is invalid):
- `values.{i}.value`: the value is out of range (`"Chest must be between 23.62 and 78.74 in."`) or not a positive number.
- `values.{i}.value_text`: the choice isn't one of the allowed options, or the field is empty.
- `values.{i}.field_id`: the field is unknown or inactive.
- duplicate fields in one set.
- `measured_at` is in the future.
- `supersedes_set_id` belongs to another customer.

### `GET /customers/{id}/measurements`
History, newest first (paginated). Each set includes `values`, `values_count` and `recorded_by`.

### `GET /customers/{id}/measurements/current`
`{"customer_id", "preferred_unit", "last_measured_at", "values": [{"field_id", "code", "label", "group_id", "value_type", "value_cm", "value_in", "value_text", "measurement_set_id", "measured_at", "entered_unit"}]}`

### `GET /measurement-sets/{id}` · `DELETE /measurement-sets/{id}`
DELETE discards a set recorded by mistake. It is hidden from history and from current values, kept in the database for sync and audit, and logged as `measurement.discarded`. Updating a set is not possible (`405`).

## 7. Production configuration 🔒 `business`

Garment types (job types) each have a **routing template**: ordered production stages with default hours. A new job copies the template; later template edits never change existing jobs. Every change bumps `config_version`. Hours are sent as **seconds** everywhere (`default_estimated_seconds`, `estimated_seconds`, max 500 h per stage). Production starts with all template hours at 0 so the owner can enter real hours.

### `GET /job-types` (`?include_inactive=1` for settings) · `GET /job-types/{id}`
```json
{ "id": 1, "code": "three_piece_suit", "name": "3-Piece Suit", "components": "Jacket, Waistcoat & Trousers", "description": null,
  "default_quantity": 1, "sort_order": 10, "is_active": true, "estimated_seconds": 64800,
  "tasks": [{ "task_type": { "id": 1, "code": "measurement", "name": "Measurement", "kind": "work", "is_fitting": false, "color_key": "slate", "sort_order": 10, "is_active": true },
              "name": "Measurement & Pattern Drafting", "custom_name": "Measurement & Pattern Drafting", "sort_order": 1, "default_estimated_seconds": 9000 }] }
```

### `POST /job-types` · `PATCH /job-types/{id}`
`{"type_name", "components"?, "description"?, "default_quantity"?, "tasks"?: [...] (create only)}`; PATCH also takes `sort_order` and `is_active`. The `code` is generated from the name. Names are unique (`422`).

### `PUT /job-types/{id}/templates`
`{"tasks": [{"task_type_id": 2, "task_name"?: "Hand Cutting", "default_estimated_seconds"?: 10800}, …]}` replaces the routing, in the order given. `422` if a stage is unknown or inactive, if a milestone has hours, or if no work stage remains.

### `GET /task-types` · `POST /task-types` · `PATCH /task-types/{id}`
Production stages. `kind` is `work` (has hours) or `milestone` (`ready_for_collection`, `completed`: no hours, follows the job status). `kind` is set on create and cannot change. `color_key` ∈ `slate blue teal amber indigo green rose violet`. The two system milestones cannot be deactivated.

## 8. Jobs 🔒 `business`

Jobs follow the same offline rules as customers: client-generated UUID `id` (idempotent create), `version` on edits (`409 CONFLICT_VERSION`). The server assigns `job_number` (`"024"`, shown as `#024`; never reset).
**Hours and progress are calculated, not stored** (views `v_task_hours` / `v_job_hours`, ARCHITECTURE §9.2): task progress is capped at 99 % until the task is completed, job remaining = Σ task remaining, job progress is estimate-weighted (or the completed-stage ratio when nothing is estimated), and 100 % when ready or collected. A manual `progress_override` wins until cleared.

### `GET /jobs`
Query: `filter` (chips) · `q` (job number such as `#024` or `24`, title, garment type, customer name) · `customer_id` · `priority` · `sort` = `due` \| `recent` \| `number` · `page`, `per_page`.

| filter | statuses |
|---|---|
| `open` (default, "All") | draft, queued, in_progress, on_hold, ready_for_collection |
| `active` | in_progress, on_hold |
| `pending` | draft, queued |
| `ready` | ready_for_collection |
| `due_soon` | queued/in_progress/on_hold, due today … today + `jobs.due_soon_days` (business timezone) |
| `overdue` | queued/in_progress/on_hold, due before today |
| `completed` · `cancelled` · `any` | collected · cancelled · everything (customer history) |

Default order: by due date (undated last), then urgent → normal. Each item:
```json
{ "id": "…", "job_number": "024", "title": "3-Piece Bespoke Suit", "quantity": 1, "priority": "high",
  "status": "in_progress", "status_label": "In production",
  "customer": { "id": "…", "full_name": "Kofi Mensah", "phone": "+233241110001" },
  "job_type": { "id": 1, "name": "3-Piece Suit", "components": "Jacket, Waistcoat & Trousers" },
  "order_date": "2026-09-30", "due_date": "2026-10-10", "collection_date": "2026-10-11", "completed_at": null,
  "hours": { "estimated_seconds": 64800, "actual_seconds": 37116, "remaining_seconds": 28800, "overrun_seconds": 1656,
             "task_count": 8, "completed_task_count": 4, "progress_percent": 55.56, "is_progress_manual": false,
             "has_running_timer": true, "actual_start": "…" },
  "current_task": { "id": "…", "name": "Sewing & Assembly", "status": "in_progress", "kind": "work",
                    "task_type_code": "sewing", "task_type_name": "Sewing", "color_key": "blue" },
  "step": { "index": 5, "total": 9 },
  "stages": [{ "id": "…", "name": "Measurement & Pattern Drafting", "type_name": "Measurement", "kind": "work", "status": "completed" }],
  "flags": { "is_overdue": false, "is_due_soon": true, "days_until_due": 2 },
  "allowed_transitions": ["on_hold", "ready_for_collection", "cancelled"], "version": 3, "created_at": "…", "updated_at": "…" }
```
The current task is the first in-progress stage, otherwise the first pending one (skipped stages are left out of `stages` and `step`).

### `GET /jobs/counts?customer_id=`
`{"open": 14, "active": 9, "pending": 3, "ready": 1, "due_soon": 2, "overdue": 1, "completed": 40, "cancelled": 2, "any": 57}`

### `POST /jobs`
```json
{ "id": "uuid?", "customer_id": "…", "job_type_id": 1, "status": "queued | draft", "title"?: "defaults to the garment type",
  "description"?, "quantity"?: "defaults to the garment's default", "priority"?: "normal | high | urgent",
  "order_date"?: "defaults to today (business timezone)", "due_date"?, "collection_date"?, "measurement_set_id"?,
  "fabric_note"?, "notes"?,
  "tasks"?: [{ "task_type_id": 2, "task_name"?: "…", "estimated_seconds"?: 10800 }] }
```
`tasks` replaces the template routing (e.g. the owner adjusted hours on the create screen); otherwise the template is copied. Milestone hours are ignored.
→ `201 Job queued for production.` / `Draft saved.` with the **job sheet** (below). Errors (`422`): unknown or archived customer, inactive garment type, measurements of another customer, due or collection date before the order date, unknown stages.

### `GET /jobs/{id}` (job sheet)
The list item plus `description`, `fabric_note`, `notes`, `cancel_reason`, `progress_override`, `measurement_set {id, measured_at}` and `tasks`:
```json
{ "id": "…", "task_type": { … }, "name": "Sewing & Assembly", "sort_order": 5, "status": "in_progress",
  "estimated_seconds": 21600, "actual_seconds": 18000, "remaining_seconds": 3600, "overrun_seconds": 0,
  "progress_percent": 83.33, "is_progress_manual": false, "is_running": true, "log_count": 2,
  "actual_start": "…", "actual_end": "…", "scheduled_start": "…", "scheduled_end": "…", "completed_at": null, "notes": null,
  "checklist": [{ "id": "…", "label": "Set sleeves & shoulder pads", "is_done": false, "done_at": null, "sort_order": 3, "version": 1 }],
  "version": 4, "updated_at": "…" }
```

### `PATCH /jobs/{id}`
Any of `title`, `description`, `quantity`, `priority`, `order_date`, `due_date`, `collection_date`, `measurement_set_id`, `fabric_note`, `notes` plus the required `version`. The customer, garment type and status cannot be changed here (`422`). Collected and cancelled jobs are read-only (`409 JOB_CLOSED`).

### `POST /jobs/{id}/status`
`{"status", "reason"?, "force"?, "version"?}`
```
draft ──► queued ──► in_progress ◄──► on_hold
                         │   ▲
                         ▼   │  (back to production for rework)
               ready_for_collection ──► completed (collected)
any state except completed ──► cancelled          completed and cancelled are final
```
- Not allowed → `409 INVALID_STATUS_TRANSITION`. Cancelling needs a `reason` (`422`).
- `ready_for_collection` with unfinished work stages → `409 TASKS_INCOMPLETE` ("2 stages are not finished yet: Pressing and Quality Check."). Resend with `force: true` to confirm.
- On hold, ready, collected or cancelled while a work timer runs → `409 TIMER_RUNNING`.
- Milestone stages follow: *Ready for Collection* is completed when the job is ready, *Completed* when it is collected; both reopen when the job goes back to production. `completed_at` is set on collection.

### `POST /jobs/{id}/progress-override`
`{"progress_percent": 0–100 | null}`; `null` returns to the calculated value.

### `DELETE /jobs/{id}`
Drafts only (`409 JOB_NOT_DRAFT` otherwise: cancel instead). The job and its stages become tombstones.

## 9. Production stages (tasks) and subtasks 🔒 `business`

Every call below returns the whole **job sheet** with recalculated hours, progress and current stage. Collected and cancelled jobs are read-only (`409 JOB_CLOSED`).

| Call | Body | Notes |
|---|---|---|
| `POST /jobs/{id}/tasks` | `{"id"?, "task_type_id", "task_name"?, "estimated_seconds"?, "notes"?}` | Work stages are inserted before the trailing milestones. `201`. |
| `PUT /jobs/{id}/tasks/order` | `{"task_ids": [...]}` | Every stage of the job exactly once (`422` otherwise). |
| `PATCH /tasks/{id}` | `task_name`, `estimated_seconds`, `notes`, `scheduled_start`, `scheduled_end` (ISO-8601) + required `version` | Milestones cannot have hours; the planned end must be after the start. |
| `POST /tasks/{id}/status` | `{"status": "pending \| in_progress \| completed \| skipped", "version"?}` | Needs the job in production (`409 JOB_NOT_IN_PRODUCTION` for drafts or ready jobs). Starting or completing a stage moves a queued or held job to `in_progress`. Milestones follow the job status (`422`). Completing or skipping a stage with a running timer → `409 TIMER_RUNNING`. |
| `POST /tasks/{id}/progress-override` | `{"progress_percent": 0–100 \| null}` | Work stages only. |
| `DELETE /tasks/{id}` | | Only stages without logged hours (`409 TASK_HAS_WORK`: skip it instead). |
| `POST /tasks/{id}/checklist` | `{"id"?, "label"}` | Subtask, `201`. |
| `PATCH /checklist-items/{id}` | `{"label"?, "is_done"?, "version"?}` | `done_at` is set when ticked. |
| `DELETE /checklist-items/{id}` | | Tombstone. |

## 10. Work timer and work logs 🔒 `business`

The labour ledger (`work_logs`) is the only source of actual hours. **Times come from the server clock.** Each user has at most one running timer (also enforced by a unique key). Pause closes the session; resume starts a new one. Entries are never deleted: they are voided with a reason and stop counting.

Timer calls return:
```json
{ "timer": { "id": "…", "task_id": "…", "entry_type": "timer", "started_at": "…", "ended_at": null, "duration_seconds": 5025,
             "is_running": true, "note": null, "needs_review": false, "is_voided": false, "void_reason": null, "version": 1,
             "task": { "id": "…", "name": "Sewing & Assembly", "type_name": "Sewing", "job_id": "…", "job_number": "024",
                       "job_title": "3-Piece Bespoke Suit", "customer_name": "Kofi Mensah" } },
  "stopped": null, "job": { "…job sheet (§8)…" }, "server_time": "2026-10-08T09:15:00.000Z" }
```
`duration_seconds` of a running timer is the elapsed time at `server_time`; the app adds the time since then, using its offset from `server_time`. Task and job `actual_seconds` count closed sessions only.

| Call | Body | Result / errors |
|---|---|---|
| `GET /timers/active` | | The signed-in user's running timer, or `timer: null` (restores the timer after an app restart). |
| `POST /tasks/{id}/timer/start` | `{"id"?: uuid, "note"?}` | Starts the stage (`pending` → `in_progress`) and moves a queued/held job to `in_progress`. Same stage already running or same `id` → returns it. `409 TIMER_ALREADY_RUNNING` (another stage), `409 TASK_CLOSED` (completed/skipped: reopen first), `409 JOB_NOT_IN_PRODUCTION` (draft, ready, collected, cancelled), `422` milestone. |
| `POST /timers/stop` | `{"note"?, "complete_task"?: bool}` | "Pause Work" / "Log & Finish" (stop + complete the stage, one transaction). `stopped` holds the closed session. `409 NO_TIMER_RUNNING`. Sessions over `timer.review_threshold_hours` (12) get `needs_review: true`. |
| `POST /timers/switch` | `{"task_id", "id"?, "note"?}` | Stops the running session (with `note`) and starts the new stage atomically. Starts directly when nothing runs. |
| `GET /tasks/{id}/work-logs` | | Every entry of the stage, newest first, **voided ones included** (`is_voided`, `void_reason`, `recorded_by`). |
| `POST /tasks/{id}/work-logs` | `{"id"?, "started_at", "ended_at", "note"?}` or `{"id"?, "duration_seconds", "note"?}` | Manual entry, or adjustment ("+15m Adjust"). An adjustment ends where the running timer started (or now), so it never overlaps the live session; its default note is "Adjustment +15m". `422`: end not after start, in the future, longer than 24 h, milestone. Allowed while the job is ready for collection. → `201 {entry, job}` |
| `PATCH /work-logs/{id}` | `{"version", "started_at"?, "ended_at"?, "note"?}` | Correct an entry (audit-logged with before/after). Times of a running timer cannot change (`409 TIMER_RUNNING`). → `{entry, job}` |
| `POST /work-logs/{id}/void` | `{"reason"}` | Voids (also discards a running session). → `{entry, job}` |

## 11. CLI (server only)
```bash
php artisan migrate --force                     # apply new migrations (each runs its SQL file from /database/migrations)
php artisan db:seed --force                     # reference data (idempotent, every environment)
php artisan db:seed --class=DemoSeeder          # demo data — refused in production
composer reset-dev                              # dev only: migrate:fresh --drop-views + reference + demo
php artisan user:create --email=owner@example.com --name="Owner Name" --role=owner [--phone=+233…]
php artisan user:reset-password --email=owner@example.com
# non-interactive: echo "$PASSWORD" | php artisan user:create ... -n
```
The first production accounts (admin and owner) are created with `user:create`. No account is ever seeded in production.
