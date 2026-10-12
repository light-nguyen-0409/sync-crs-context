# SPEC: Worker Welfare Checks Pagination

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-22
> **Author**: Codex

---

## 1. Tổng quan

Bổ sung phân trang cho API lấy danh sách Worker Welfare Checks của một candidate.
Project hiện dùng convention `offset`/`limit` cho các API collection, vì vậy
feature này sẽ giữ convention đó và bổ sung tổng số bản ghi qua field `count`.

**Yêu cầu gốc**: Bổ sung phân trang cho API `worker_welfare_checks`.

---

## 2. Database Design

N/A — Không thay đổi schema hoặc migration. Truy vấn hiện tại đã có
`orderByDesc('id')`; pagination sẽ áp dụng `offset` và `limit` trên cùng query,
đồng thời thực hiện count tổng theo `candidate_id`.

---

## 3. API Contract

### 3.1. Endpoint

```text
GET /api/consultant/candidates/{id}/worker_welfare_checks
```

**Auth**: Required
**Middleware**: `auth:userApi`, `detectBranchForConsultant`, `autoLogout`
**Tags**: Consultant / Candidate / Worker Welfare Check

### 3.2. Request

**Headers**:

```text
Authorization: Bearer {token}
```

**Route Params**:

| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| `id` | integer | YES | Candidate ID |

**Query Params**:

| Param | Type | Required | Default | Mô tả |
|-------|------|----------|---------|-------|
| `offset` | integer >= 0 | NO | 0 | Số bản ghi bỏ qua |
| `limit` | integer, 1-100 | NO | 20 | Số bản ghi tối đa trả về |

**FormRequest Validation Rules**:

```php
[
    'offset' => 'nullable|integer|min:0',
    'limit' => 'nullable|integer|min:1|max:100',
]
```

Request invalid trả HTTP 400 theo cơ chế `JsonRequest` hiện có.

### 3.3. Response

Giữ field `checks` hiện tại và bổ sung `count` là tổng số Worker Welfare Checks
của candidate trước khi áp dụng `offset`/`limit`.

Mỗi item trong `checks` giữ theo contract hiện tại của
`CandidateWelfareCheck` Resource: có `consultant_user_id` và
`consultant_name`; không trả `branch_name` hoặc `welfare_image_file_id`.

**Success (200)**:

```json
{
    "checks": [
        {
            "id": 10,
            "consultant_user_id": 5,
            "consultant_name": "Consultant User",
            "candidate_id": 123,
            "checked_at": "21/09/2026 - 10:00:00",
            "facematch_score": 88.5,
            "is_passed": true,
            "welfare_image_url": "https://signed-s3-url/welfare.jpg",
            "interview_image_url": "https://signed-s3-url/interview.jpg",
            "certificate_url": "https://signed-s3-url/certificate.pdf"
        }
    ],
    "count": 25
}
```

Khi không có bản ghi, `checks` là mảng rỗng và `count` là `0`. Thứ tự vẫn là
`id` giảm dần như behavior hiện tại.

---

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

```text
1. FormRequest validate query offset/limit và áp dụng default.
2. Controller lấy candidate ID từ route và pagination data từ FormRequest.
3. Controller gọi CandidateWelfareCheckRepository contract trực tiếp vì GET này
   không có business logic ngoài data access.
4. Repository chạy count tổng và query dữ liệu đã eager-load relations,
   orderByDesc('id'), offset, limit.
5. Controller truyền collection và count vào CandidateWelfareChecks Resource.
6. Resource serialize từng CandidateWelfareCheck và trả JSON response.
```

### 4.2. Business Rules

- Không thay đổi contract hiện tại của từng Worker Welfare Check:
  `id`, `consultant_user_id`, `consultant_name`, `candidate_id`, `checked_at`,
  `facematch_score`, `is_passed`, `welfare_image_url`, `interview_image_url` và
  `certificate_url`.
- `branch_name` và `welfare_image_file_id` không thuộc response contract hiện tại.
- Không thay đổi eager-loaded relations: `consultantUser`, `interviewImageFile`,
  `welfareImageFile`, `certificateFile`.
- `count` là tổng số record theo candidate, không phải số item của trang hiện tại.
- `offset`/`limit` chỉ áp dụng cho GET list; POST tạo Worker Welfare Check giữ
  nguyên behavior.
- Repository chỉ thực hiện data access.
- GET list được phép bỏ qua Service theo pure read delegation rule trong `../../AGENTS.md`;
  Service vẫn được giữ cho POST và post-processing có business logic/orchestration.

### 4.3. Side Effects

Không có side effect mới. GET chỉ đọc database và tạo temporary URLs trong Resource
theo behavior hiện tại.

---

## 5. Data Origin & Call Chain

```text
GET route `routes/consultant.php`
  → CandidateController::getWorkerWelfareChecks()
  → GetWorkerWelfareChecksRequest::validated()/pagination data
    → CandidateWelfareCheckRepository::getByCandidateId($id, $offset, $limit)
      → CollectionWithCount(collection, count)
    → CandidateWelfareChecks Resource
  → JSON Response
```

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|-----------------|------------|
| `$id` | Controller/Repository | Route parameter `/{id}` | ✅ |
| `$offset` | Controller/Repository | Query `offset`, default từ FormRequest | ✅ |
| `$limit` | Controller/Repository | Query `limit`, default từ FormRequest | ✅ |
| `checks` | Resource | `CollectionWithCount->collection` từ repository | ✅ |
| `count` | Resource | `CollectionWithCount->count` từ repository count query | ✅ |
| Check relations | `CandidateWelfareCheck` Resource | Repository eager loading | ✅ |

---

## 6. Constants & Enums

Khai báo trong `GetWorkerWelfareChecksRequest` và dùng lại khi lấy default/validate
pagination:

```php
public const DEFAULT_OFFSET = 0;
public const MIN_LIMIT = 1;
public const DEFAULT_LIMIT = 20;
public const MAX_LIMIT = 100;
```

Không hardcode các giá trị default/max trong Controller, Service hoặc Repository.

---

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|------|-----------|-------|
| `../../app/Http/Requests/Api/Consultant/GetWorkerWelfareChecksRequest.php` | `App\Http\Requests\Api\Consultant` | Validate và normalize `offset`/`limit` cho GET endpoint |

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `../../app/Http/Controllers/Api/Consultant/CandidateController.php` | Nhận FormRequest mới, truyền pagination params vào Repository và trả `count` |
| `../../app/Contracts/Repositories/CandidateWelfareCheckRepositoryInterface.php` | Cập nhật contract repository nhận offset/limit và trả `CollectionWithCount` |
| `../../app/Repositories/CandidateWelfareCheckRepository.php` | Count tổng và lấy collection theo offset/limit, giữ eager loading/order hiện tại |
| `../../app/Http/Resources/Api/Consultant/CandidateWelfareCheck.php` | Giữ response item theo contract hiện tại, bao gồm temporary URLs và fallback khi relation/file chưa có |
| `../../app/Http/Resources/Api/Consultant/CandidateWelfareChecks.php` | Serialize thêm field `count` |
| `../../tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | Test GET default/custom pagination và validation query |
| `tests/Unit/Repositories/CandidateWelfareCheckRepositoryTest.php` | Bổ sung test repository trả đúng collection/count theo offset/limit nếu fixture hiện có hỗ trợ |
| `tests/Unit/Http/Resources/CandidateWelfareCheckResourceTest.php` | Cập nhật assertion theo Resource hiện tại; không assert `branch_name`/`welfare_image_file_id`, xác nhận consultant fields và các URL |

Không cần sửa route và không cần migration.

---

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `../../tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | GET default pagination | Không truyền query: service nhận `offset=0`, `limit=20`, response có `checks` và `count` |
| `../../tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | GET custom pagination | Truyền `offset`/`limit`: service nhận đúng giá trị và response trả count tổng |
| `../../tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | GET invalid pagination | `offset < 0`, `limit < 1`, `limit > 100`, hoặc giá trị không phải integer trả 400 |
| `../../tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | GET empty result | Response trả `checks: []` và `count: 0` |
| `tests/Unit/Repositories/CandidateWelfareCheckRepositoryTest.php` | paginated query/count | Query áp dụng đúng candidate filter, order, offset/limit và count tổng |
| `tests/Unit/Http/Resources/CandidateWelfareCheckResourceTest.php` | collection resource count | Resource giữ `checks` và serialize `count` |
| `tests/Unit/Http/Resources/CandidateWelfareCheckResourceTest.php` | current item contract | Resource trả `consultant_user_id`, `consultant_name`, các field welfare hiện tại và không yêu cầu `branch_name`/`welfare_image_file_id` |
| `tests/Unit/Http/Resources/CandidateWelfareCheckResourceTest.php` | certificate pending | Khi `certificateFile` chưa có nhưng image relations có, `certificate_url` là chuỗi rỗng và không throw lỗi |

Sau khi code sẽ chạy các test suite bị ảnh hưởng và toàn bộ
`./vendor/bin/phpunit`; không chạy formatter/linter tự động.

---

## 9. Checklist trước khi Approve

- [x] Đã kiểm tra route, middleware và endpoint hiện tại.
- [x] Đã kiểm tra convention phân trang hiện có: `offset`/`limit` + `count`.
- [x] Database design xác nhận không cần migration.
- [x] API contract gồm query params, validation và response shape.
- [x] Call chain và nguồn dữ liệu đã trace.
- [x] Default/max pagination được quy hoạch bằng constants.
- [x] File list và test impact đã liệt kê.
- [x] User approve plan.
- [x] Code và test đã triển khai theo contract.
- [x] Toàn bộ PHPUnit pass.
