<?php

declare(strict_types=1);

namespace Nutofe\Ai\Data;

use Nutofe\Ai\Config;
use PDO;

/** PDO connection with a read-only account. Prepared statements only; times in UTC. */
final class Db
{
    private ?PDO $pdo = null;

    public function __construct(private readonly Config $config) {}

    public function pdo(): PDO
    {
        return $this->pdo ??= new PDO(
            sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $this->config->get('DB_HOST', 'mysql'), $this->config->int('DB_PORT', 3306), $this->config->get('DB_DATABASE', 'nutofe')),
            $this->config->get('DB_USERNAME', 'nutofe_ai'),
            $this->config->get('DB_PASSWORD'),
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
                PDO::MYSQL_ATTR_INIT_COMMAND => "SET time_zone = '+00:00'",
            ],
        );
    }

    /**
     * @param  list<mixed>  $params
     * @return list<array<string, mixed>>
     */
    public function select(string $sql, array $params = []): array
    {
        $stmt = $this->pdo()->prepare($sql);
        $stmt->execute($params);

        return $stmt->fetchAll();
    }

    /** @param  list<mixed>  $params */
    public function execute(string $sql, array $params = []): void
    {
        $this->pdo()->prepare($sql)->execute($params);
    }
}
