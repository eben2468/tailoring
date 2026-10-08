<?php

namespace Database\Factories;

use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Hash;

/**
 * Test accounts. Default password: Correct-Horse-42
 *
 * @extends Factory<User>
 */
class UserFactory extends Factory
{
    public const PASSWORD = 'Correct-Horse-42';

    private static ?string $hash = null;

    public function definition(): array
    {
        return [
            'full_name' => fake()->name(),
            'email' => fake()->unique()->safeEmail(),
            'phone' => null,
            'role' => 'owner',
            'is_active' => true,
            'password_hash' => self::$hash ??= Hash::make(self::PASSWORD),
            'password_changed_at' => now(),
        ];
    }

    public function admin(): static
    {
        return $this->state(['role' => 'admin']);
    }

    public function inactive(): static
    {
        return $this->state(['is_active' => false]);
    }

    public function withPassword(string $password): static
    {
        return $this->state(['password_hash' => Hash::make($password)]);
    }
}
