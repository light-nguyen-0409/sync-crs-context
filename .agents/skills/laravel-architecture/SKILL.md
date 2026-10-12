---
name: laravel-architecture
description: >-
  Quy tắc kiến trúc Laravel cho project gap-web-backend.
  Sử dụng skill này khi cần tạo file mới (Controller, Service, Repository, Model, Migration, FormRequest)
  hoặc khi cần kiểm tra code có tuân thủ kiến trúc phân lớp không.
  Chứa template chuẩn và quy tắc đặt tên cho từng layer.
---

# Laravel Architecture Guide — gap-web-backend

## Kiến trúc phân lớp (STRICT)

```
Route -> Controller -> FormRequest (validation) -> Service (logic) -> Repository (data access)
```

---

## 1. Cấu trúc thư mục & Namespace

| Layer | Directory | Namespace | Contract |
|---|---|---|---|
| Controller | `app/Http/Controllers/` | `App\Http\Controllers` | — |
| FormRequest | `app/Http/Requests/` | `App\Http\Requests` | — |
| Resource | `app/Http/Resources/` | `App\Http\Resources` | — |
| Service | `app/Services/` | `App\Services` | `App\Contracts\Services` |
| Repository | `app/Repositories/` | `App\Repositories` | `App\Contracts\Repositories` |
| Model | `app/Models/` | `App\Models` | — |
| DTO | `app/Dto/` | `App\Dto` | — |
| Exception | `app/Exceptions/` | `App\Exceptions` | — |
| Event | `app/Events/` | `App\Events` | — |
| External | `app/Externals/` | `App\Externals` | `App\Contracts\Externals` |

---

## 2. Trách nhiệm từng Layer

### Controller
- Nhận request, gọi FormRequest validate, gọi Service, return response.
- **KHÔNG** chứa logic nghiệp vụ.
- **KHÔNG** gọi trực tiếp Repository hoặc Model query.

### FormRequest
- Validate input data bằng `rules()` method.
- Có thể thêm `authorize()` để check quyền.

### Service
- Chứa **100%** business logic.
- Inject Repository/External qua constructor (DI).
- Quản lý cache, data transformation, workflow, gọi external services.
- Wrap write operations trong `DB::transaction` khi cần atomicity.

### Repository
- **CHỈ** chứa database queries (SELECT, INSERT, UPDATE, DELETE).
- **KHÔNG** chứa business logic, `config()`, cache, hay conditional branching.
- Implement Contract interface.
- **Return Type Hint cho Single Record Query**: Các function trả về 1 bản ghi (`find`, `first`, `firstByFilter`, `getLatestBy...`) **PHẢI** type hint là `?\Illuminate\Database\Eloquent\Model` (hoặc `?Model`), **KHÔNG** dùng custom Model cụ thể (như `?CandidateWelfareCheck`).

### Model
- Định nghĩa `$table`, `$fillable`, `$casts`, relationships.
- Khai báo `public const` cho statuses, types, fixed identifiers.
- **KHÔNG** chứa complex business logic trong accessors/mutators.

---

## 3. Quy tắc đặt tên

| Thành phần | Convention | Ví dụ |
|---|---|---|
| Migration | `yyyy_mm_dd_HHmmss_action_description_table` | `2024_01_15_100000_create_orders_table`, `2024_01_15_100000_add_status_to_orders_table` |
| Model | Singular PascalCase | `Order`, `UserProfile` |
| Controller | PascalCase + `Controller` (trong domain folder) | `Candidate/OrderController` |
| Service | PascalCase + `Service` | `OrderService` |
| Repository | PascalCase + `Repository` | `OrderRepository` |
| FormRequest | Descriptive + `Request` (trong domain folder) | `Candidate/StoreOrderRequest` |
| Service Interface | PascalCase + `ServiceInterface` (extends `BaseServiceInterface`) | `OrderServiceInterface` |
| Repository Interface | PascalCase + `RepositoryInterface` (extends `SingleKeyModelRepositoryInterface`) | `OrderRepositoryInterface` |
| DTO | PascalCase + descriptive (readonly properties) | `OrderResult`, `CollectionWithCount` |
| Resource | Singular/Plural PascalCase (trong `Api/{Domain}/`) (extends `Resource`, dùng `$columns`) | `Api/Candidate/Order`, `Api/Admin/Orders` |
| Event | Past tense PascalCase | `OrderCreated`, `PaymentProcessed` |
| Exception | Domain-scoped `APIErrorException` | `App\Exceptions\Api\Candidate\APIErrorException` |

---

## 4. Database Rules

- **Index**: Luôn đánh index cho cột dùng trong WHERE, JOIN, ORDER BY.
- **Foreign Keys**: Luôn tạo foreign key constraints trong migration.
- **Soft Deletes**: Sử dụng `SoftDeletes` trait khi cần giữ lại data đã xóa.
- **Timestamps**: Mặc định có `created_at`, `updated_at`.
- **No raw SQL**: Ưu tiên Eloquent/Query Builder. Chỉ dùng raw SQL khi query quá phức tạp.
