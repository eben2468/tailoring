<?php

namespace App\Services;

use App\Models\Tool;
use App\Models\ToolCategory;
use App\Models\ToolMaintenanceLog;
use App\Support\ApiException;
use App\Support\BusinessClock;
use App\Support\RequestContext;
use App\Support\SyncSequence;
use App\Support\Uuid;
use Illuminate\Support\Facades\DB;

/**
 * Tool and maintenance rules (ARCHITECTURE §12, DATABASE_DESIGN §6.7). The app applies the same rules
 * offline (local_ops.dart), so keep the two in step:
 *  - dates are business dates (Y-m-d); a purchase or maintenance date cannot be in the future;
 *  - a manual next-maintenance date cannot be in the past; logging maintenance clears it;
 *  - logging maintenance may set the condition (condition_after) and the operational status;
 *  - a log entered by mistake is removed (tombstone, audit-logged): the dates follow automatically;
 *  - archived tools keep their history but take no new maintenance.
 */
final class ToolService
{
    private const FIELDS = [
        'category_id', 'tool_name', 'brand_model', 'serial_number', 'purchase_date', 'tool_condition', 'operational_status',
        'storage_location', 'maintenance_interval_days', 'next_maintenance_override', 'notes',
    ];

    public function __construct(
        private readonly AuditLogger $audit,
        private readonly BusinessClock $clock,
        private readonly SyncSequence $sequence,
    ) {}

    /**
     * @param  array<string, mixed>  $input
     * @return array{tool: Tool, created: bool}
     */
    public function create(array $input, RequestContext $context): array
    {
        if (! empty($input['id']) && ($existing = Tool::findByUuid($input['id'])) !== null) {
            return ['tool' => $existing, 'created' => false];
        }
        $data = $this->data($input, null);

        $tool = DB::transaction(function () use ($data, $input, $context): Tool {
            $tool = new Tool($data);
            if (! empty($input['id'])) {
                $tool->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $tool->save();
            $tool->refresh();
            $this->audit->log($context, 'tool.created', 'tool', $tool->uuid(), ['tool_name' => $tool->tool_name]);

            return $tool;
        });

        return ['tool' => $tool, 'created' => true];
    }

    /** @param  array<string, mixed>  $input  changed fields + `version` */
    public function update(Tool $tool, array $input, RequestContext $context): Tool
    {
        return DB::transaction(function () use ($tool, $input, $context): Tool {
            $locked = $this->lock($tool);
            if ($locked->version !== (int) $input['version']) {
                throw ApiException::conflict('This tool was changed on another device. Reload to see the latest details.', 'CONFLICT_VERSION');
            }
            $data = $this->data($input, $locked);
            $before = $this->snapshot($locked, array_keys($data));
            $locked->fill($data)->save();
            $this->audit->log($context, 'tool.updated', 'tool', $locked->uuid(), ['before' => $before, 'after' => $this->snapshot($locked, array_keys($data))]);

            return $locked;
        });
    }

    public function setArchived(Tool $tool, bool $archived, RequestContext $context): Tool
    {
        return DB::transaction(function () use ($tool, $archived, $context): Tool {
            $locked = $this->lock($tool);
            if (($locked->archived_at !== null) === $archived) {
                return $locked; // replay
            }
            $locked->setAttribute('archived_at', $archived ? now() : null);
            $locked->save();
            $this->audit->log($context, $archived ? 'tool.archived' : 'tool.unarchived', 'tool', $locked->uuid(), ['tool_name' => $locked->tool_name]);

            return $locked;
        });
    }

    /**
     * Records maintenance done on the tool.
     *
     * @param  array<string, mixed>  $input  {id?, performed_on?, maintenance_type, description?, performed_by?, condition_after?, operational_status?}
     * @return array{log: ToolMaintenanceLog, created: bool}
     */
    public function logMaintenance(Tool $tool, array $input, RequestContext $context): array
    {
        if (! empty($input['id']) && ($existing = $this->findLog((string) $input['id'])) !== null) {
            return ['log' => $existing, 'created' => false];
        }
        $performedOn = $input['performed_on'] ?? $this->clock->todayString();
        if ($performedOn > $this->clock->todayString()) {
            throw ApiException::validation('performed_on', 'Maintenance cannot be logged for a future date.');
        }

        $log = DB::transaction(function () use ($tool, $input, $performedOn, $context): ToolMaintenanceLog {
            $locked = $this->lock($tool);
            if ($locked->archived_at !== null) {
                throw ApiException::conflict('This tool is archived. Restore it to log maintenance.', 'TOOL_ARCHIVED');
            }
            $log = new ToolMaintenanceLog([
                'tool_id' => $locked->getKey(),
                'performed_on' => $performedOn,
                'maintenance_type' => $input['maintenance_type'],
                'description' => $this->clean($input['description'] ?? null),
                'performed_by' => $this->clean($input['performed_by'] ?? null),
                'condition_after' => $input['condition_after'] ?? null,
            ]);
            if (! empty($input['id'])) {
                $log->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $log->save();

            $locked->setAttribute('next_maintenance_override', null);
            if (! empty($input['condition_after'])) {
                $locked->setAttribute('tool_condition', $input['condition_after']);
            }
            if (! empty($input['operational_status'])) {
                $locked->setAttribute('operational_status', $input['operational_status']);
            }
            $locked->save();
            $this->audit->log($context, 'tool.maintenance_logged', 'tool', $locked->uuid(), [
                'performed_on' => $performedOn, 'type' => $log->maintenance_type, 'condition_after' => $log->condition_after, 'status' => $locked->operational_status,
            ]);

            return $log;
        });

        return ['log' => $log, 'created' => true];
    }

    /** Removes a maintenance entry made by mistake; the last/next dates follow from the remaining entries. */
    public function deleteLog(ToolMaintenanceLog $log, RequestContext $context): void
    {
        if ($log->deleted_at !== null) {
            return; // replay
        }
        DB::transaction(function () use ($log, $context): void {
            /** @var Tool $tool */
            $tool = Tool::query()->whereKey($log->tool_id)->lockForUpdate()->firstOrFail();
            /** @var ToolMaintenanceLog $locked */
            $locked = ToolMaintenanceLog::query()->whereKey($log->getKey())->lockForUpdate()->firstOrFail();
            $locked->tombstone();
            $this->audit->log($context, 'tool.maintenance_deleted', 'tool', $tool->uuid(), [
                'performed_on' => $locked->performed_on->toDateString(), 'type' => $locked->maintenance_type, 'description' => $locked->description,
            ]);
        });
    }

    /** A log by id, removed ones included (for replays). */
    public function findLog(string $id): ?ToolMaintenanceLog
    {
        if (! Uuid::isValid($id)) {
            return null;
        }

        /** @var ToolMaintenanceLog|null */
        return ToolMaintenanceLog::query()->withoutGlobalScope('not_tombstoned')->whereKey(Uuid::toBytes($id))->first();
    }

    /** @param  array{category_name: string, sort_order?: int|null}  $input */
    public function createCategory(array $input, RequestContext $context): ToolCategory
    {
        return DB::transaction(function () use ($input, $context): ToolCategory {
            $name = trim($input['category_name']);
            $this->guardCategoryName($name, null);
            $category = new ToolCategory([
                'category_name' => $name,
                'sort_order' => $input['sort_order'] ?? (int) ToolCategory::query()->max('sort_order') + 10,
            ]);
            $category->save();
            $category->refresh(); // is_active comes from the column default
            $this->sequence->bumpConfigVersion();
            $this->audit->log($context, 'config.tool_category_created', 'tool_category', $category->id, ['category_name' => $name]);

            return $category;
        });
    }

    /** @param  array<string, mixed>  $input */
    public function updateCategory(ToolCategory $category, array $input, RequestContext $context): ToolCategory
    {
        return DB::transaction(function () use ($category, $input, $context): ToolCategory {
            $data = array_intersect_key($input, array_flip(['category_name', 'sort_order', 'is_active']));
            if (isset($data['category_name'])) {
                $data['category_name'] = trim($data['category_name']);
                $this->guardCategoryName($data['category_name'], $category->id);
            }
            $before = $category->only(array_keys($data));
            $category->fill($data)->save();
            $this->sequence->bumpConfigVersion();
            $this->audit->log($context, 'config.tool_category_updated', 'tool_category', $category->id, ['before' => $before, 'after' => $data]);

            return $category;
        });
    }

    /**
     * @param  array<string, mixed>  $input
     * @return array<string, mixed>
     */
    private function data(array $input, ?Tool $existing): array
    {
        $data = array_intersect_key($input, array_flip(self::FIELDS));
        foreach (['tool_name', 'brand_model', 'serial_number', 'storage_location', 'notes'] as $key) {
            if (array_key_exists($key, $data)) {
                $data[$key] = $this->clean($data[$key]);
            }
        }
        if (array_key_exists('tool_name', $data) && $data['tool_name'] === null) {
            throw ApiException::validation('tool_name', 'Give the tool a name.');
        }
        if (isset($data['category_id']) && (int) $data['category_id'] !== $existing?->category_id) {
            $category = ToolCategory::query()->find($data['category_id']);
            if ($category === null || ! $category->is_active) {
                throw ApiException::validation('category_id', 'Choose an active category.');
            }
        }
        $today = $this->clock->todayString();
        if (! empty($data['purchase_date']) && $data['purchase_date'] > $today) {
            throw ApiException::validation('purchase_date', 'The purchase date cannot be in the future.');
        }
        if (! empty($data['next_maintenance_override']) && $data['next_maintenance_override'] < $today) {
            throw ApiException::validation('next_maintenance_override', 'The next maintenance date cannot be in the past.');
        }

        return $data;
    }

    /**
     * @param  list<string>  $keys
     * @return array<string, mixed>
     */
    private function snapshot(Tool $tool, array $keys): array
    {
        $out = [];
        foreach ($keys as $key) {
            $value = $tool->getAttribute($key);
            $out[$key] = $value instanceof \DateTimeInterface ? $value->format('Y-m-d') : $value;
        }

        return $out;
    }

    private function guardCategoryName(string $name, ?int $exceptId): void
    {
        $taken = ToolCategory::query()->where('category_name', $name)->when($exceptId !== null, fn ($q) => $q->whereKeyNot($exceptId))->exists();
        if ($taken) {
            throw ApiException::validation('category_name', 'A category with this name already exists.');
        }
    }

    private function lock(Tool $tool): Tool
    {
        /** @var Tool */
        return Tool::query()->whereKey($tool->getKey())->lockForUpdate()->firstOrFail();
    }

    private function clean(mixed $value): ?string
    {
        $value = is_string($value) ? trim($value) : $value;

        return $value === null || $value === '' ? null : (string) $value;
    }
}
