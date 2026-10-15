<?php

declare(strict_types=1);

namespace Nutofe\Ai\Analytics;

use DateTimeImmutable;

/**
 * When each material runs out at its recent pace: usage per day over the last $windowDays (or since
 * its first use in that window, at least 14 days, so one big cut does not look like a daily rate);
 * days left = stock ÷ daily usage. Materials not used in the window have no forecast.
 */
final class InventoryForecaster
{
    /**
     * @param  list<array{id: string, item_name: string, unit: string, quantity_on_hand: float, min_stock_level: float, reorder_quantity: float|null, used: float, first_used_at: string|null}>  $items
     * @return list<array{item_id: string, item_name: string, unit: string, quantity_on_hand: float, min_stock_level: float, reorder_quantity: float|null, daily_usage: float, days_left: int|null, stockout_date: string|null}>
     */
    public function forecast(array $items, DateTimeImmutable $now, int $windowDays = 60): array
    {
        $out = [];
        foreach ($items as $i) {
            $days = $windowDays;
            if ($i['first_used_at'] !== null) {
                $since = (int) (new DateTimeImmutable($i['first_used_at']))->diff($now)->format('%a');
                $days = max(14, min($windowDays, $since + 1));
            }
            $rate = $i['used'] > 0 ? $i['used'] / $days : 0.0;
            $left = $rate > 0 ? (int) floor(max(0.0, $i['quantity_on_hand']) / $rate) : null;
            $out[] = [
                'item_id' => $i['id'], 'item_name' => $i['item_name'], 'unit' => $i['unit'],
                'quantity_on_hand' => $i['quantity_on_hand'], 'min_stock_level' => $i['min_stock_level'], 'reorder_quantity' => $i['reorder_quantity'],
                'daily_usage' => round($rate, 3),
                'days_left' => $left,
                'stockout_date' => $left === null ? null : $now->modify("+{$left} days")->format('Y-m-d'),
            ];
        }
        usort($out, fn ($a, $b) => [$a['days_left'] ?? PHP_INT_MAX, $a['item_name']] <=> [$b['days_left'] ?? PHP_INT_MAX, $b['item_name']]);

        return $out;
    }
}
