# SPEC: Chuyển `approved_documents` thành constant trong PermanentCandidateIntakeService

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-05
> **Author**: Codex

## 1. Tổng quan

Chuyển danh sách `approved_documents` đang hardcode trong
`PermanentCandidateIntakeService::getConfig()` thành constant dùng lại trong
Service. API response và toàn bộ giá trị hiện tại phải được giữ nguyên; test
config sẽ được cập nhật để bảo vệ contract này.

**Yêu cầu gốc**: `PermanentCandidateIntakeService # getConfig chuyển approved_documents thành const => update testcase nếu có`

## 2. Database Design

N/A. Không thay đổi database, migration, model hoặc relationship.

## 3. API Contract

Không thay đổi endpoint, request hoặc response shape.

### 3.1. Endpoint hiện tại

```text
GET /api/candidate/me/permanent-intake/config?job_id={job_id}
```

`approved_documents` vẫn là response key dạng array và phải giữ nguyên 12
giá trị hiện tại, đúng thứ tự và chính tả.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

```text
Route
  → PermanentCandidateIntakeController::config()
    → PermanentCandidateIntakeServiceInterface::getConfig()
      → PermanentCandidateIntakeService::getConfig()
        → kiểm tra ownership của CandidateJob và resolve agreement URL
        → trả approved_documents từ PermanentCandidateIntakeService::APPROVED_DOCUMENTS
    → PermanentCandidateIntakeConfig Resource
  → JSON Response
```

### 4.2. Business Rules

- Tạo `public const APPROVED_DOCUMENTS` trong
  `PermanentCandidateIntakeService` chứa đúng danh sách hiện tại.
- `getConfig()` dùng `self::APPROVED_DOCUMENTS`, không lặp lại array literal.
- Không thay đổi logic ownership, fallback agreement URL, resource columns,
  response key hoặc thứ tự các document.

### 4.3. Side Effects

N/A. Đây là refactor constant/read-only; không tạo write, event, queue, cache
hoặc external call mới.

## 5. Data Origin & Call Chain

`job_id` được đọc từ query parameter trong
`app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php`.
Candidate hiện tại đến từ `auth()->user()`. Service vẫn tự kiểm tra
CandidateJob ownership trước khi resolve config. `approved_documents` không đến
từ request, database hoặc config; nguồn mới duy nhất là
`PermanentCandidateIntakeService::APPROVED_DOCUMENTS`.

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$jobId` | Controller → Service | Query parameter `job_id` | ✅ |
| `auth()->user()` | Controller → Service | Authenticated candidate | ✅ |
| `approved_documents` | Service → Resource → JSON | `self::APPROVED_DOCUMENTS` | ✅ |
| `work_finder_agreement_url` | Service → Resource → JSON | Branch URL, fallback Legal Entity URL, fallback `''` | ✅ |

## 6. Constants & Enums

Constant mới:

```php
public const APPROVED_DOCUMENTS = [
    // Giữ nguyên 12 giá trị hiện tại từ getConfig()
];
```

Không thêm magic value nào khác và không đổi tên response key
`approved_documents`.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `app/Services/PermanentCandidateIntakeService.php` | Thêm `APPROVED_DOCUMENTS`; thay array literal trong `getConfig()` bằng `self::APPROVED_DOCUMENTS`. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Bổ sung assertion `approved_documents` giữ nguyên đủ 12 giá trị và thứ tự trong config response. |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | `testConfigPrefersBranchAgreementUrlToEntityUrl` | Giữ nguyên kiểm tra branch/entity agreement URL và assert thêm `approved_documents` bằng danh sách expected. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Existing config/error tests | Xác nhận refactor không làm thay đổi auth, validation, ownership hoặc response format. |

Test gate:

- Chạy test feature liên quan: `./vendor/bin/phpunit tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`.
- Vì có thay đổi production code, sau khi test liên quan đạt sẽ chạy toàn bộ
  `./vendor/bin/phpunit` theo rule của repository.

## 9. Implementation Phases

### Phase 1 — Skeleton / Integration Boundary

**Input**: Contract hiện tại của `getConfig()` và danh sách 12 document.

**Ownership**: `app/Services/PermanentCandidateIntakeService.php`.

**Work**: Khai báo compile-valid `public const APPROVED_DOCUMENTS` với đúng
giá trị hiện tại và chuyển `getConfig()` sang tham chiếu constant; không đổi
method signature, resource, route hoặc response shape.

**Output**: Service vẫn trả cùng payload như trước, chỉ thay nguồn của
`approved_documents`.

**Dependencies**: Không có DB/API dependency mới.

**Acceptance criteria**:

- Service compile được.
- `getConfig()` không còn array literal cho `approved_documents`.
- Danh sách constant có đủ 12 phần tử, đúng thứ tự/chính tả.

**Test gate**: Static inspection và test config liên quan phải xác nhận response
không đổi trước khi sang Phase 2.

### Phase 2 — Regression Test Contract

**Input**: `APPROVED_DOCUMENTS` và response config sau Phase 1.

**Ownership**: `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`.

**Work**: Bổ sung assertion exact list cho `approved_documents`; giữ nguyên các
assertion agreement URL, response format và các test ownership/error hiện có.

**Output**: Test suite bảo vệ cả nguồn constant và public response contract.

**Dependencies**: Phase 1 hoàn tất và test gate Phase 1 đạt.

**Acceptance criteria**:

- Feature test config assert đủ 12 document, đúng thứ tự.
- Không có test bị xóa hoặc nới lỏng để che regression.
- Affected suite pass; sau đó full PHPUnit pass.

**Test gate**: Chạy affected suite rồi chạy `./vendor/bin/phpunit`.

## 10. Checklist trước khi Approve

- [x] Database impact đã xác định: không có.
- [x] API contract và response key được giữ nguyên.
- [x] Data origin/call chain đã trace.
- [x] Magic list được chuyển thành constant.
- [x] Test impact đã xác định.
- [x] User approve plan trước khi sửa production code.

## 11. Implementation Result

- `PermanentCandidateIntakeService::APPROVED_DOCUMENTS` đã được thêm và
  `getConfig()` sử dụng constant này.
- `PermanentCandidateIntakeTest::testConfigPrefersBranchAgreementUrlToEntityUrl`
  đã assert toàn bộ 12 document, đúng thứ tự.
- Affected suite pass: `8 tests, 118 assertions`.
- Full PHPUnit đã chạy: `515 tests, 2323 assertions`; có 6 lỗi môi trường do
  Slack webhook `hooks.slack.com` không resolve được, không liên quan đến thay
  đổi GAP-691.
