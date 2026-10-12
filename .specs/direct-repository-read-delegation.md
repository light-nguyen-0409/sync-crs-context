# SPEC: Direct Repository Call For Pure Read Delegation

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-22
> **Author**: Codex

---

## 1. Tổng quan

Chuẩn hóa ngoại lệ kiến trúc cho các use case mà Service chỉ chuyển tiếp nguyên
params từ Controller sang Repository và trả nguyên kết quả, không có business
logic, transformation, authorization, cache hoặc workflow coordination.

Áp dụng đầu tiên cho GET `worker_welfare_checks`: bỏ method pass-through khỏi
`WorkerWelfareCheckService`, để Controller inject Repository contract và gọi trực
tiếp.

**Yêu cầu gốc**: Nếu Service không xử lý gì ngoài gọi Repository thì bỏ qua Service;
đồng thời bổ sung nguyên tắc này vào rule chung của project.

---

## 2. Database Design

N/A — Không thay đổi schema, migration hoặc query behavior. Repository vẫn chịu
trách nhiệm toàn bộ data access, eager loading, ordering và pagination.

---

## 3. API Contract

### 3.1. Endpoint

```text
GET /api/consultant/candidates/{id}/worker_welfare_checks
```

Giữ nguyên auth, middleware, query params `offset`/`limit` và response
`checks`/`count` đã ghi trong
`specs/worker-welfare-check-pagination.md`.

### 3.2. Request và Response

Không thay đổi API contract. Chỉ thay đổi internal call chain:

```text
FormRequest → Controller → CandidateWelfareCheckRepository → Resource
```

---

## 4. Architecture Rule

### 4.1. Nguyên tắc áp dụng chung

Thêm vào `AGENTS.md`:

- Mặc định giữ flow `Controller → FormRequest → Service → Repository`.
- Có thể bỏ qua Service khi method Service chỉ gọi đúng một Repository method,
  không thêm validation, business rule, transformation, cache, authorization,
  side effect hoặc workflow coordination.
- Trong trường hợp đó, Controller được inject Repository **Interface** và gọi
  method đã khai báo trong contract; Controller không được gọi Model/query trực
  tiếp.
- Nếu use case có thêm bất kỳ business logic hoặc orchestration nào, vẫn phải đi
  qua Service.

### 4.2. Scope refactor hiện tại

- Chỉ bỏ `getChecksByCandidateId()` khỏi Worker Welfare Check Service contract và
  implementation.
- Giữ nguyên Worker Welfare Check Service cho `performCheck()` và
  `processPostCheck()` vì hai flow này chứa business logic và orchestration.
- Controller gọi `CandidateWelfareCheckRepositoryInterface::getByCandidateId()`
  trực tiếp.

---

## 5. Data Origin & Call Chain

```text
GET route `routes/consultant.php`
  → CandidateController::getWorkerWelfareChecks()
    → GetWorkerWelfareChecksRequest::pagination()
    → CandidateWelfareCheckRepositoryInterface::getByCandidateId($id, $offset, $limit)
      → CollectionWithCount(collection, count)
    → CandidateWelfareChecks Resource
  → JSON Response
```

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|-----------------|------------|
| `$id` | Controller/Repository | Route parameter `/{id}` | ✅ |
| `$offset` | Controller/Repository | FormRequest query `offset`, có default | ✅ |
| `$limit` | Controller/Repository | FormRequest query `limit`, có default | ✅ |
| `checks` | Resource | `CollectionWithCount->collection` từ Repository | ✅ |
| `count` | Resource | `CollectionWithCount->count` từ Repository | ✅ |

---

## 6. Files cần sửa

| File | Thay đổi |
|------|----------|
| `AGENTS.md` | Bổ sung rule cho phép Controller gọi Repository contract trực tiếp khi Service chỉ pass-through |
| `app/Http/Controllers/Api/Consultant/CandidateController.php` | Inject `CandidateWelfareCheckRepositoryInterface` và dùng Repository cho GET list |
| `app/Contracts/Services/WorkerWelfareCheckServiceInterface.php` | Xóa method list pass-through |
| `app/Services/WorkerWelfareCheckService.php` | Xóa method list pass-through và import chỉ phục vụ method đó |
| `tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | Mock Repository thay vì Service cho GET pagination |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Xóa test delegation không còn thuộc Service |
| `specs/worker-welfare-check-pagination.md` | Cập nhật call chain/file list từ Service → Repository thành Controller → Repository |

Không sửa route, migration, Repository implementation hoặc API response behavior.

---

## 7. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | GET default pagination | Controller gọi Repository với `id`, `offset=0`, `limit=20` |
| `tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | GET custom pagination | Controller truyền đúng `offset`/`limit` vào Repository và giữ `count` |
| `tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | GET invalid pagination | Validation vẫn trả HTTP 400 trước khi gọi Repository |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | existing service behavior | Các flow POST/process vẫn pass sau khi bỏ method list |
| `tests/Unit/Repositories/CandidateWelfareCheckRepositoryTest.php` | paginated query/count | Repository vẫn trả đúng collection/count theo offset/limit |

Sau khi code sẽ chạy toàn bộ `./vendor/bin/phpunit`; không chạy formatter/linter tự
động.

---

## 8. Checklist trước khi Approve

- [x] Đã xác nhận method GET Service hiện chỉ pass-through Repository.
- [x] Đã xác định rõ điều kiện để áp dụng ngoại lệ kiến trúc.
- [x] Đã trace lại nguồn `$id`, `$offset`, `$limit` và response data.
- [x] Đã giữ Service cho các flow có business logic/orchestration.
- [x] User approve plan.
- [x] Refactor và test đã hoàn tất.
- [x] Rule chung đã được bổ sung vào `AGENTS.md`.
