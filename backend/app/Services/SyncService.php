<?php

namespace App\Services;

use App\Models\InventoryCategory;
use App\Models\JobType;
use App\Models\MeasurementGroup;
use App\Models\Setting;
use App\Models\TaskType;
use App\Models\ToolCategory;
use App\Support\Iso;
use App\Support\Uuid;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Offline sync, read side (ARCHITECTURE §21). Devices keep a local copy of the business tables and
 * pull every row whose sync_seq is above their cursor, tombstones included. sync_seq is taken from
 * counters('sync') inside each writing transaction, so commit order = sequence order and a cursor never
 * skips a row. Configuration is small and is downloaded whole when config_version changes.
 */
final class SyncService
{
    /**
     * Synced tables and how their columns are encoded. uuid: BINARY(16) → string; time: DATETIME(3) → ISO;
     * date: DATE → Y-m-d; num: DECIMAL → float; bool: TINYINT → bool.
     *
     * @var array<string, array{columns: list<string>, uuid?: list<string>, time?: list<string>, date?: list<string>, num?: list<string>, bool?: list<string>, json?: list<string>, own?: bool}>
     */
    private static array $tables = [
        'customers' => [
            'columns' => ['id', 'full_name', 'phone', 'phone_alt', 'email', 'address', 'notes', 'style_preferences', 'preferred_unit', 'archived_at', 'version', 'created_at', 'updated_at', 'deleted_at'],
            'uuid' => ['id'],
            'time' => ['archived_at', 'created_at', 'updated_at', 'deleted_at'],
        ],
        'measurement_sets' => [
            'columns' => ['id', 'customer_id', 'measured_at', 'entered_unit', 'notes', 'supersedes_set_id', 'created_by', 'created_at', 'deleted_at'],
            'uuid' => ['id', 'customer_id', 'supersedes_set_id'],
            'time' => ['measured_at', 'created_at', 'deleted_at'],
        ],
        'jobs' => [
            'columns' => [
                'id', 'job_number', 'customer_id', 'job_type_id', 'title', 'description', 'quantity', 'priority', 'status', 'order_date', 'due_date',
                'collection_date', 'measurement_set_id', 'fabric_note', 'progress_override', 'notes', 'cancel_reason', 'completed_at', 'version',
                'created_at', 'updated_at', 'deleted_at',
            ],
            'uuid' => ['id', 'customer_id', 'measurement_set_id'],
            'time' => ['completed_at', 'created_at', 'updated_at', 'deleted_at'],
            'date' => ['order_date', 'due_date', 'collection_date'],
            'num' => ['progress_override'],
        ],
        'job_tasks' => [
            'columns' => [
                'id', 'job_id', 'task_type_id', 'task_name', 'sort_order', 'status', 'estimated_seconds', 'progress_override', 'scheduled_start',
                'scheduled_end', 'completed_at', 'notes', 'version', 'updated_at', 'deleted_at',
            ],
            'uuid' => ['id', 'job_id'],
            'time' => ['scheduled_start', 'scheduled_end', 'completed_at', 'updated_at', 'deleted_at'],
            'num' => ['progress_override'],
        ],
        'job_task_checklist_items' => [
            'columns' => ['id', 'job_task_id', 'label', 'is_done', 'done_at', 'sort_order', 'version', 'created_at', 'deleted_at'],
            'uuid' => ['id', 'job_task_id'],
            'time' => ['done_at', 'created_at', 'deleted_at'],
            'bool' => ['is_done'],
        ],
        'appointments' => [
            'columns' => [
                'id', 'appointment_type', 'title', 'customer_id', 'job_id', 'job_task_id', 'starts_at', 'ends_at', 'location', 'status',
                'reminder_minutes_before', 'notes', 'version', 'created_at', 'updated_at', 'deleted_at',
            ],
            'uuid' => ['id', 'customer_id', 'job_id', 'job_task_id'],
            'time' => ['starts_at', 'ends_at', 'created_at', 'updated_at', 'deleted_at'],
        ],
        'work_logs' => [
            'columns' => ['id', 'job_task_id', 'entry_type', 'started_at', 'ended_at', 'note', 'needs_review', 'void_reason', 'created_by', 'version', 'created_at', 'deleted_at'],
            'uuid' => ['id', 'job_task_id'],
            'time' => ['started_at', 'ended_at', 'created_at', 'deleted_at'],
            'bool' => ['needs_review'],
        ],
        'inventory_items' => [
            'columns' => [
                'id', 'category_id', 'item_name', 'sku', 'description', 'unit', 'min_stock_level', 'reorder_quantity', 'unit_cost', 'supplier_name',
                'supplier_contact', 'storage_location', 'notes', 'archived_at', 'version', 'created_at', 'updated_at', 'deleted_at',
            ],
            'uuid' => ['id'],
            'time' => ['archived_at', 'created_at', 'updated_at', 'deleted_at'],
            'num' => ['min_stock_level', 'reorder_quantity', 'unit_cost'],
        ],
        'inventory_transactions' => [
            'columns' => ['id', 'item_id', 'transaction_type', 'quantity_change', 'job_id', 'unit_cost', 'reference', 'note', 'occurred_at', 'void_reason', 'created_by', 'version', 'created_at', 'deleted_at'],
            'uuid' => ['id', 'item_id', 'job_id'],
            'time' => ['occurred_at', 'created_at', 'deleted_at'],
            'num' => ['quantity_change', 'unit_cost'],
        ],
        'tools' => [
            'columns' => [
                'id', 'category_id', 'tool_name', 'brand_model', 'serial_number', 'purchase_date', 'tool_condition', 'operational_status', 'storage_location',
                'maintenance_interval_days', 'next_maintenance_override', 'notes', 'archived_at', 'version', 'created_at', 'updated_at', 'deleted_at',
            ],
            'uuid' => ['id'],
            'time' => ['archived_at', 'created_at', 'updated_at', 'deleted_at'],
            'date' => ['purchase_date', 'next_maintenance_override'],
        ],
        'tool_maintenance_logs' => [
            'columns' => ['id', 'tool_id', 'performed_on', 'maintenance_type', 'description', 'performed_by', 'condition_after', 'created_by', 'version', 'created_at', 'deleted_at'],
            'uuid' => ['id', 'tool_id'],
            'time' => ['created_at', 'deleted_at'],
            'date' => ['performed_on'],
        ],
        // AI insight cards (written by the core API from the AI service's results).
        'ai_insights' => [
            'columns' => ['id', 'insight_type', 'severity', 'title', 'body', 'payload', 'entity_type', 'entity_id', 'insight_status', 'generated_at', 'expires_at', 'updated_at'],
            'time' => ['generated_at', 'expires_at', 'updated_at'],
            'json' => ['payload'],
        ],
        // Personal: each user receives only their own notifications.
        'notifications' => [
            'columns' => ['id', 'notification_type', 'severity', 'title', 'body', 'entity_type', 'entity_id', 'route', 'read_at', 'created_at'],
            'time' => ['read_at', 'created_at'],
            'own' => true,
        ],
    ];

    /**
     * Rows changed after $cursor, oldest first, at most $limit in total. Personal tables are limited to $userId.
     *
     * @return array{cursor: int, has_more: bool, changes: array<string, list<array<string, mixed>>>}
     */
    public function pull(int $cursor, int $limit, int $userId): array
    {
        $rows = collect();
        $truncated = false;
        foreach (self::$tables as $table => $spec) {
            $batch = DB::table($table)
                ->when($spec['own'] ?? false, fn ($q) => $q->where('user_id', $userId))
                ->where('sync_seq', '>', $cursor)
                ->orderBy('sync_seq')
                ->limit($limit + 1)
                ->get([...$spec['columns'], 'sync_seq']);
            $truncated = $truncated || $batch->count() > $limit;
            $rows = $rows->concat($batch->take($limit)->map(fn (object $row) => ['table' => $table, 'row' => $row]));
        }

        // Take the oldest $limit rows over all tables: every row up to the new cursor is then included,
        // because each table was read past that point (or to its end).
        $sorted = $rows->sortBy(fn (array $r) => $r['row']->sync_seq)->values();
        $page = $sorted->take($limit);
        $hasMore = $truncated || $sorted->count() > $limit;
        $newCursor = $page->isEmpty() ? $cursor : (int) $page->last()['row']->sync_seq;

        $changes = array_fill_keys(array_keys(self::$tables), []);
        $names = $this->userNames($page);
        foreach ($page as $item) {
            $changes[$item['table']][] = $this->encode($item['table'], $item['row'], $names);
        }
        $this->attachMeasurementValues($changes['measurement_sets']);

        return ['cursor' => $newCursor, 'has_more' => $hasMore, 'changes' => $changes];
    }

    public function configVersion(): int
    {
        return (int) DB::table('counters')->where('counter_key', 'config_version')->value('counter_value');
    }

    /**
     * Everything the app needs to work offline that is not a synced business row.
     *
     * @return array<string, mixed>
     */
    public function config(): array
    {
        $settings = Setting::getMany([
            'business.name', 'business.timezone', 'business.currency', 'business.currency_symbol', 'business.phone_region',
            'measurements.default_unit', 'jobs.due_soon_days', 'jobs.number_format', 'timer.review_threshold_hours',
            'schedule.working_hours', 'schedule.capacity_hours_per_day', 'tools.maintenance_due_soon_days',
        ]);

        return [
            'config_version' => $this->configVersion(),
            'settings' => (object) $settings,
            'task_types' => TaskType::query()->orderBy('sort_order')->get()->map(fn (TaskType $t) => $t->toApi())->values(),
            'job_types' => JobType::query()->with('templates.taskType')->orderBy('sort_order')->orderBy('type_name')->get()->map(fn (JobType $t) => [
                'id' => $t->id,
                'code' => $t->code,
                'name' => $t->type_name,
                'components' => $t->components,
                'description' => $t->description,
                'default_quantity' => $t->default_quantity,
                'sort_order' => $t->sort_order,
                'is_active' => $t->is_active,
                'tasks' => $t->templates->map(fn ($tpl) => [
                    'task_type' => $tpl->taskType->toApi(),
                    'name' => $tpl->displayName(),
                    'custom_name' => $tpl->task_name,
                    'sort_order' => $tpl->sort_order,
                    'default_estimated_seconds' => $tpl->default_estimated_seconds,
                ])->values(),
            ])->values(),
            'inventory_categories' => InventoryCategory::query()->orderBy('sort_order')->orderBy('category_name')->get()->map(fn (InventoryCategory $c) => $c->toApi())->values(),
            'tool_categories' => ToolCategory::query()->orderBy('sort_order')->orderBy('category_name')->get()->map(fn (ToolCategory $c) => $c->toApi())->values(),
            'measurement_groups' => MeasurementGroup::query()->with(['fields' => fn ($q) => $q->orderBy('sort_order')])->orderBy('sort_order')->get()->map(fn (MeasurementGroup $g) => [
                'id' => $g->id,
                'code' => $g->code,
                'name' => $g->group_name,
                'is_active' => $g->is_active,
                'fields' => $g->fields->map(fn ($f) => [
                    'id' => $f->id,
                    'code' => $f->code,
                    'label' => $f->label,
                    'value_type' => $f->value_type,
                    'choice_options' => $f->choice_options,
                    'min_cm' => $f->min_cm === null ? null : (float) $f->min_cm,
                    'max_cm' => $f->max_cm === null ? null : (float) $f->max_cm,
                    'help_text' => $f->help_text,
                    'is_active' => $f->is_active,
                ])->values(),
            ])->values(),
        ];
    }

    /**
     * @param  array<int, string>  $names  user id → full name
     * @return array<string, mixed>
     */
    private function encode(string $table, object $row, array $names): array
    {
        $spec = self::$tables[$table];
        $out = [];
        foreach ($spec['columns'] as $column) {
            $value = $row->{$column};
            $out[$column] = match (true) {
                $value === null => null,
                in_array($column, $spec['uuid'] ?? [], true) => Uuid::toString($value),
                in_array($column, $spec['time'] ?? [], true) => Iso::format(Carbon::parse($value, 'UTC')),
                in_array($column, $spec['date'] ?? [], true) => substr((string) $value, 0, 10),
                in_array($column, $spec['num'] ?? [], true) => (float) $value,
                in_array($column, $spec['bool'] ?? [], true) => (bool) $value,
                in_array($column, $spec['json'] ?? [], true) => json_decode((string) $value, true),
                in_array($column, ['id', 'version', 'quantity', 'job_type_id', 'task_type_id', 'sort_order', 'estimated_seconds', 'created_by', 'reminder_minutes_before', 'category_id', 'maintenance_interval_days'], true) => (int) $value,
                default => $value,
            };
        }
        if (array_key_exists('created_by', $out)) {
            $out['recorded_by'] = $names[$out['created_by']] ?? null;
        }
        $out['sync_seq'] = (int) $row->sync_seq;

        return $out;
    }

    /**
     * @param  Collection<int, array{table: string, row: object}>  $page
     * @return array<int, string>
     */
    private function userNames(Collection $page): array
    {
        $ids = $page->map(fn (array $r) => $r['row']->created_by ?? null)->filter()->unique()->values();

        return $ids->isEmpty() ? [] : DB::table('users')->whereIn('id', $ids)->pluck('full_name', 'id')->all();
    }

    /**
     * Measurement sets are immutable, so their values travel with the set.
     *
     * @param  list<array<string, mixed>>  $sets
     */
    private function attachMeasurementValues(array &$sets): void
    {
        if ($sets === []) {
            return;
        }
        $rows = DB::table('measurement_values')
            ->whereIn('measurement_set_id', array_map(fn (array $s) => Uuid::toBytes($s['id']), $sets))
            ->get(['measurement_set_id', 'field_id', 'value_cm', 'value_text']);
        /** @var array<string, list<array{field_id: int, value_cm: float|null, value_text: string|null}>> $bySet */
        $bySet = [];
        foreach ($rows as $v) {
            $bySet[Uuid::toString($v->measurement_set_id)][] = [
                'field_id' => (int) $v->field_id,
                'value_cm' => $v->value_cm === null ? null : (float) $v->value_cm,
                'value_text' => $v->value_text,
            ];
        }
        foreach ($sets as &$set) {
            $set['values'] = $bySet[$set['id']] ?? [];
        }
    }
}
