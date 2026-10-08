<?php

namespace Tests\Feature;

/** Routing, response envelope, error handling and request parsing. */
final class FoundationTest extends ApiTestCase
{
    public function test_health_uses_success_envelope(): void
    {
        $this->getJson('/api/v1/health')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('message', 'Service is healthy.')
            ->assertJsonPath('data.status', 'ok')
            ->assertJsonPath('data.database', 'ok')
            ->assertHeader('Content-Type', 'application/json');
    }

    public function test_every_response_has_request_id_and_security_headers(): void
    {
        foreach (['/api/v1/health', '/api/v1/nope'] as $path) {
            $response = $this->get($path);
            $this->assertMatchesRegularExpression('/^[0-9a-f]{16}$/', (string) $response->headers->get('X-Request-Id'));
            $response->assertHeader('X-Content-Type-Options', 'nosniff');
            $this->assertStringContainsString('no-store', (string) $response->headers->get('Cache-Control'));
        }
    }

    public function test_error_request_id_matches_header(): void
    {
        $response = $this->get('/api/v1/nope');
        $this->assertSame($response->headers->get('X-Request-Id'), $response->json('request_id'));
    }

    public function test_unknown_route_is_404_even_without_accept_header(): void
    {
        $response = $this->assertApiError($this->get('/api/v1/does-not-exist'), 404, 'NOT_FOUND');
        $this->assertSame([], $response->json('errors'));
        $this->assertApiError($this->get('/'), 404, 'NOT_FOUND');
    }

    public function test_wrong_method_is_405_with_allow_header(): void
    {
        $response = $this->assertApiError($this->deleteJson('/api/v1/health'), 405, 'METHOD_NOT_ALLOWED');
        $this->assertStringContainsString('GET', (string) $response->headers->get('Allow'));
    }

    public function test_malformed_json_is_400(): void
    {
        $headers = ['CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json'];
        $this->assertApiError($this->call('POST', '/api/v1/auth/login', [], [], [], $headers, '{"email": "a@b.c",'), 400, 'MALFORMED_JSON');
        $this->assertApiError($this->call('POST', '/api/v1/auth/login', [], [], [], $headers, '["a","b"]'), 400, 'MALFORMED_JSON');
    }

    public function test_non_json_content_type_is_415(): void
    {
        $response = $this->call('POST', '/api/v1/auth/login', [], [], [], ['CONTENT_TYPE' => 'application/x-www-form-urlencoded'], 'email=a@b.c');
        $this->assertApiError($response, 415, 'UNSUPPORTED_MEDIA_TYPE');
    }

    public function test_validation_errors_use_field_map_and_never_leak_internals(): void
    {
        $response = $this->assertApiError($this->postJson('/api/v1/auth/login', ['email' => 'x@example.com']), 422, 'VALIDATION_FAILED');
        $response->assertJsonPath('message', 'Some fields are invalid.');
        $this->assertSame(['The password field is required.'], $response->json('errors.password'));
        $response->assertJsonMissingPath('debug');
    }

    public function test_control_characters_are_stripped_from_input(): void
    {
        $this->createUser('owner@test.local');
        $token = $this->login('owner@test.local')['access_token'];

        $this->patchJson('/api/v1/auth/me', ['full_name' => "Ama\x00 Mensah\x07"], $this->bearer($token))
            ->assertOk()
            ->assertJsonPath('data.user.full_name', 'Ama Mensah');
    }
}
