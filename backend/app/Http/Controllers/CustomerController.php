<?php

namespace App\Http\Controllers;

use App\Http\Requests\Customers\CustomerIndexRequest;
use App\Http\Requests\Customers\CustomerRequest;
use App\Http\Resources\CustomerResource;
use App\Models\Customer;
use App\Services\CustomerService;
use App\Support\ApiResponse;
use App\Support\Iso;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** /api/v1/customers — owner and admin (can:business). */
final class CustomerController extends Controller
{
    public function __construct(private readonly CustomerService $customers) {}

    public function index(CustomerIndexRequest $request): JsonResponse
    {
        $filters = $request->filters();
        $status = $filters['status'] ?? 'active';

        $query = Customer::query()
            ->withSummary()
            ->search($filters['q'] ?? null)
            ->when($status === 'active', fn ($q) => $q->whereNull('archived_at'))
            ->when($status === 'archived', fn ($q) => $q->whereNotNull('archived_at'));

        ($filters['sort'] ?? 'name') === 'recent'
            ? $query->orderByDesc('updated_at')
            : $query->orderBy('full_name');

        return ApiResponse::paginated($query->paginate($request->perPage()), CustomerResource::class);
    }

    public function show(Customer $customer): JsonResponse
    {
        return ApiResponse::success(CustomerResource::make($this->withSummary($customer)));
    }

    public function store(CustomerRequest $request): JsonResponse
    {
        $result = $this->customers->create($request->validated(), $this->context($request));
        $resource = CustomerResource::make($this->withSummary($result['customer']));

        return $result['created']
            ? ApiResponse::created($resource, 'Customer added.')
            : ApiResponse::success($resource, 'Customer already exists.');
    }

    public function update(CustomerRequest $request, Customer $customer): JsonResponse
    {
        $customer = $this->customers->update($customer, $request->validated(), $this->context($request));

        return ApiResponse::success(CustomerResource::make($this->withSummary($customer)), 'Customer updated.');
    }

    public function archive(Request $request, Customer $customer): JsonResponse
    {
        $customer = $this->customers->setArchived($customer, true, $this->context($request));

        return ApiResponse::success(CustomerResource::make($this->withSummary($customer)), 'Customer archived.');
    }

    public function unarchive(Request $request, Customer $customer): JsonResponse
    {
        $customer = $this->customers->setArchived($customer, false, $this->context($request));

        return ApiResponse::success(CustomerResource::make($this->withSummary($customer)), 'Customer restored.');
    }

    /** GET /customers/phone-check?phone=…&except= — customers already using a number (duplicate warning). */
    public function phoneCheck(Request $request): JsonResponse
    {
        $request->validate(['phone' => ['required', 'string', 'max:30'], 'except' => ['nullable', 'uuid']]);
        $except = $request->filled('except') ? Customer::findByUuid((string) $request->input('except')) : null;
        $matches = $this->customers->findByPhone((string) $request->input('phone'), $except);

        return ApiResponse::success($matches->map(fn (Customer $c) => [
            'id' => $c->uuid(),
            'full_name' => $c->full_name,
            'phone' => $c->phone,
            'is_archived' => $c->archived_at !== null,
            'created_at' => Iso::format($c->created_at),
        ])->values());
    }

    private function withSummary(Customer $customer): Customer
    {
        return Customer::query()->withSummary()->whereKey($customer->getKey())->firstOrFail();
    }
}
