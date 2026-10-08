<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

/**
 * An app installation. Its UUID (generated on the device, stored as BINARY(16)) is the offline-sync identity.
 *
 * @property string $id
 * @property int $user_id
 */
class UserDevice extends Model
{
    use UsesMillisecondTimestamps;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected $hidden = ['fcm_token'];

    /** Registers the installation for this user (re-assigns it if another user signs in on the same phone). */
    public static function register(string $deviceId, int $userId, ?string $name, string $platform, ?string $appVersion): void
    {
        $now = now()->format('Y-m-d H:i:s.v');
        DB::table('user_devices')->upsert(
            [[
                'id' => $deviceId, 'user_id' => $userId, 'device_name' => $name, 'platform' => $platform,
                'app_version' => $appVersion, 'last_seen_at' => $now, 'revoked_at' => null,
            ]],
            ['id'],
            ['user_id', 'device_name', 'platform', 'app_version', 'last_seen_at', 'revoked_at'],
        );
    }
}
