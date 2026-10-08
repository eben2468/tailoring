<?php

namespace App\Services;

use App\Models\Customer;
use App\Models\Setting;
use App\Support\ApiException;
use App\Support\Phone;
use App\Support\RequestContext;
use App\Support\Uuid;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

/** Customer rules: phone normalisation, duplicate-phone warning, optimistic locking, archive. */
final class CustomerService
{
    public function __construct(private readonly AuditLogger $audit) {}

    /**
     * Creates a customer. A client-supplied id makes the call idempotent (offline retries): if that
     * id already exists the existing customer is returned and $created is false.
     *
     * @param  array<string, mixed>  $input
     * @return array{customer: Customer, created: bool}
     */
    public function create(array $input, RequestContext $context): array
    {
        if (isset($input['id']) && ($existing = Customer::findByUuid($input['id'])) !== null) {
            return ['customer' => $existing, 'created' => false];
        }

        $data = $this->normalize($input);
        $this->guardDuplicatePhone($data, null, (bool) ($input['allow_duplicate_phone'] ?? false));

        $customer = DB::transaction(function () use ($data, $input, $context): Customer {
            $customer = new Customer($data);
            if (isset($input['id'])) {
                $customer->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $customer->save();
            $this->audit->log($context, 'customer.created', 'customer', $customer->uuid(), ['full_name' => $customer->full_name]);

            return $customer;
        });

        return ['customer' => $customer, 'created' => true];
    }

    /** @param  array<string, mixed>  $input  includes the `version` the client edited */
    public function update(Customer $customer, array $input, RequestContext $context): Customer
    {
        $data = $this->normalize($input);
        $this->guardDuplicatePhone($data, $customer, (bool) ($input['allow_duplicate_phone'] ?? false));

        return DB::transaction(function () use ($customer, $data, $input, $context): Customer {
            /** @var Customer $locked */
            $locked = Customer::query()->whereKey($customer->getKey())->lockForUpdate()->firstOrFail();
            $this->guardVersion($locked, (int) $input['version']);

            $before = $locked->only(array_keys($data));
            $locked->fill($data)->save();
            $this->audit->log($context, 'customer.updated', 'customer', $locked->uuid(), ['before' => $before, 'after' => $data]);

            return $locked;
        });
    }

    public function setArchived(Customer $customer, bool $archived, RequestContext $context): Customer
    {
        return DB::transaction(function () use ($customer, $archived, $context): Customer {
            $customer->setAttribute('archived_at', $archived ? now() : null);
            $customer->save();
            $this->audit->log($context, $archived ? 'customer.archived' : 'customer.unarchived', 'customer', $customer->uuid());

            return $customer;
        });
    }

    /**
     * Customers already using this phone (as main or alternative number).
     *
     * @return Collection<int, Customer>
     */
    public function findByPhone(?string $phone, ?Customer $except = null): Collection
    {
        $phone = Phone::normalize($phone, $this->region());
        if (! Phone::isValid($phone)) {
            return new Collection;
        }

        return Customer::query()
            ->where(fn ($q) => $q->where('phone', $phone)->orWhere('phone_alt', $phone))
            ->when($except !== null, fn ($q) => $q->whereKeyNot($except->getKey()))
            ->orderBy('full_name')
            ->limit(5)
            ->get();
    }

    /**
     * @param  array<string, mixed>  $input
     * @return array<string, mixed> only customer columns, phones in E.164
     */
    private function normalize(array $input): array
    {
        $data = array_intersect_key($input, array_flip((new Customer)->getFillable()));
        foreach (['phone', 'phone_alt'] as $field) {
            if (array_key_exists($field, $data)) {
                $data[$field] = Phone::normalize($data[$field], $this->region());
                if ($data[$field] !== null && ! Phone::isValid($data[$field])) {
                    throw ApiException::validation($field, 'Enter a valid phone number, e.g. 024 123 4567 or +233 24 123 4567.');
                }
            }
        }
        if (isset($data['email'])) {
            $data['email'] = mb_strtolower($data['email']);
        }

        return $data;
    }

    /** @param  array<string, mixed>  $data */
    private function guardDuplicatePhone(array $data, ?Customer $except, bool $allowed): void
    {
        if ($allowed || empty($data['phone'])) {
            return;
        }
        $matches = $this->findByPhone($data['phone'], $except);
        if ($matches->isNotEmpty()) {
            $names = $matches->pluck('full_name')->join(', ', ' and ');
            throw new ApiException(409, 'DUPLICATE_PHONE', "This phone number is already used by {$names}.", [
                'phone' => ["Already used by {$names}."],
            ]);
        }
    }

    private function guardVersion(Customer $customer, int $version): void
    {
        if ($customer->version !== $version) {
            throw ApiException::conflict('This customer was changed on another device. Reload to see the latest details.', 'CONFLICT_VERSION');
        }
    }

    private function region(): string
    {
        return (string) (Setting::getMany(['business.phone_region'])['business.phone_region'] ?? 'GH');
    }
}
