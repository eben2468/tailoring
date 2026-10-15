<?php

namespace Tests\Unit;

use App\Auth\PasswordPolicy;
use App\Auth\Permissions;
use App\Auth\TokenService;
use App\Support\ApiException;
use App\Support\SqlFile;
use App\Support\Uuid;
use PHPUnit\Framework\TestCase;

final class SupportTest extends TestCase
{
    public function test_sql_splitter_respects_quotes_and_comments(): void
    {
        $sql = <<<'SQL'
            -- comment with ; semicolon
            INSERT INTO t VALUES ('a;b', 'it''s', "x;y"); /* block ; comment */
            SET @v := 'back\\slash;';
            SELECT `weird;name` FROM t # trailing ; comment
            ;
            SQL;

        $statements = SqlFile::split($sql);

        $this->assertCount(3, $statements);
        $this->assertStringContainsString("'a;b', 'it''s', \"x;y\"", $statements[0]);
        $this->assertStringContainsString("'back\\\\slash;'", $statements[1]);
        $this->assertStringStartsWith('SELECT `weird;name`', $statements[2]);
    }

    public function test_uuid_round_trip_and_v7(): void
    {
        $bytes = Uuid::v7Bytes();
        $this->assertSame(16, strlen($bytes));
        $string = Uuid::toString($bytes);
        $this->assertMatchesRegularExpression('/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/', $string);
        $this->assertSame($bytes, Uuid::toBytes(strtoupper($string)));

        $this->expectException(ApiException::class);
        Uuid::toBytes('not-a-uuid');
    }

    public function test_permissions(): void
    {
        $this->assertSame([Permissions::BUSINESS, Permissions::RECEIVE_ALERTS], Permissions::forRole('owner'));
        $this->assertNotContains(Permissions::RECEIVE_ALERTS, Permissions::forRole('admin'), 'the developer account gets no business alerts');
        $this->assertContains(Permissions::ADMIN_USERS, Permissions::forRole('admin'));
        $this->assertSame([], Permissions::forRole('customer'), 'unknown roles get nothing');
    }

    public function test_tokens_are_random_prefixed_and_hashed(): void
    {
        $service = new TokenService;
        $a = $service->newAccessToken();
        $this->assertStringStartsWith('nat_', $a);
        $this->assertStringStartsWith('nrt_', $service->newRefreshToken());
        $this->assertNotSame($a, $service->newAccessToken());
        $this->assertSame(47, strlen($a)); // prefix + 43 base64url chars (256 bits)
        $this->assertSame(32, strlen($service->hash($a)));
    }

    public function test_password_policy(): void
    {
        $policy = new PasswordPolicy;
        $this->assertSame([], $policy->problems('Correct-Horse-42', 'owner@nutofe.test'));

        foreach (['short', 'password123', 'aaaaaaaaaaaa', 'kwame-mensah-99'] as $bad) {
            $this->assertNotEmpty($policy->problems($bad, 'kwame-mensah@example.com'), "accepted weak password {$bad}");
        }
    }
}
