# SPEC: Lưu `journey_type_other_document` cho Permanent Candidate Intake

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-05
> **Author**: Codex

## 1. Tổng quan

Thêm cột `journey_type_other_document` vào bảng `candidates` và nhận field
cùng tên từ API `POST /api/candidate/me/permanent-intake`. Giá trị đã validate
sẽ được `PermanentCandidateIntakeService::submit()` gán vào Candidate trong
cùng transaction với các thông tin Permanent intake hiện tại.

**Yêu cầu gốc**: Bảng `candidate` thêm trường `journey_type_other_document`; lưu
giá trị nhận từ API submit qua `PermanentCandidateIntakeRequest`.

### Giả định cần review

Yêu cầu hiện tại chưa nêu field có bắt buộc khi `journey_type=others` hay không.
Plan này đề xuất field **optional** để không phá các client hiện tại:
`nullable|string|max:255`; khi không gửi, Service lưu `null`. Nếu business rule
muốn bắt buộc field khi `journey_type=others`, cần đổi sang
`required_if:journey_type,others|string|max:255` trước khi implementation.

Phạm vi hiện tại chỉ lưu dữ liệu trong GAP. Không thêm field vào response
resource hiện có và không map field mới sang MatchMaker payload nếu chưa có yêu
cầu contract tương ứng.

## 2. Database Design

### 2.1. Bảng sửa đổi

```text
Bảng: `candidates`
Migration: add_journey_type_other_document_to_candidates_table
```

| Thay đổi | Cột | Kiểu | Nullable | Default | Mô tả |
|----------|-----|------|----------|---------|-------|
| ADD | `journey_type_other_document` | `string(255)` | YES | `null` | Tên/thông tin document được gửi khi Candidate chọn journey type `others`. |

- Không tạo index hoặc foreign key vì đây là giá trị mô tả, không dùng để
  lookup/filter trong scope này.
- Existing Candidate rows phải giữ nguyên và nhận giá trị `null`.
- `down()` drop đúng cột mới.

## 3. API Contract

### 3.1. Endpoint

```text
POST /api/candidate/me/permanent-intake
```

**Auth**: Required, authenticated Candidate
**Middleware**: route middleware hiện tại của Candidate API
**Resource**: `PermanentCandidateIntakeResult`

### 3.2. Request

`PermanentCandidateIntakeController::submit()` tiếp tục truyền
`$request->validated()` vào Service; không đổi route, method signature hoặc
response success/error shape.

Field mới:

```json
{
    "journey_type": "others",
    "journey_type_other_document": "Current non-British Passport with UK work permission"
}
```

**FormRequest Validation Rules**:

```php
[
    'journey_type' => 'required|in:passport,share_code,others',
    'journey_type_other_document' => 'nullable|string|max:255',
]
```

- Field không được nhận array/object.
- Chuỗi dài hơn 255 ký tự trả validation error theo response format hiện tại.
- Field không xuất hiện trong request được chấp nhận và Service lưu `null` theo
  giả định optional ở Section 1.

### 3.3. Response

Không thay đổi response body. `journey_type_other_document` không được thêm
vào `PermanentCandidateIntakeResult` trong scope này; giá trị được xác nhận
qua database/model sau submit.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

```text
Route POST /me/permanent-intake
  → PermanentCandidateIntakeController::submit()
    → PermanentCandidateIntakeRequest::validated()
      → PermanentCandidateIntakeService::submit($candidate, $data)
        → DB transaction
          → gán journey_type_other_document cho Candidate
          → candidateRepository->save($candidate)
        → dispatch PermanentCandidateSubmittedEvent
        → MatchMaker sync hiện tại
    → PermanentCandidateIntakeResult
  → JSON Response
```

### 4.2. Business Rules

- Gán `$candidate->journey_type_other_document` từ validated input; dùng `null`
  khi field bị bỏ qua.
- Lưu field trong cùng transaction với `journey_type` và các profile fields để
  Candidate không rơi vào trạng thái lưu một phần.
- Không thay đổi quy tắc ownership, email match, file validation,
  `is_permanent`, event dispatch hoặc MatchMaker error handling.
- Không thêm logic query mới và không tạo query trong loop.

### 4.3. Side Effects

Không thêm side effect mới. Event/MatchMaker sync hiện tại tiếp tục chạy sau
transaction; field mới chỉ nằm trên Candidate trong GAP và không thay đổi event
payload hoặc MatchMaker request payload.

## 5. Data Origin & Call Chain

```text
routes/candidate.php:104
  → PermanentCandidateIntakeController::submit()
    → PermanentCandidateIntakeRequest::validated()
      → PermanentCandidateIntakeService::submit(auth()->user(), $data)
        → $candidate->journey_type_other_document = $data[...] ?? null
        → CandidateRepository::save($candidate)
        → database.candidates.journey_type_other_document
```

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$request['journey_type_other_document']` | FormRequest | JSON body của Permanent intake request | ✅ sau khi thêm rule |
| `$data['journey_type_other_document']` | Service | `PermanentCandidateIntakeRequest::validated()` | ✅ |
| `$candidate` | Controller → Service | `auth()->user()` | ✅ |
| `journey_type_other_document` | Candidate → DB | Service assignment trong `DB::transaction()` | ✅ sau implementation |

Không giả định field đến từ `CandidateResource`, query parameter hoặc MatchMaker.

## 6. Constants & Enums

- Reuse `Candidate::JOURNEY_TYPE_OTHERS`; không thêm magic journey type string.
- Không thêm enum/constant mới nếu giữ validation `max:255` theo convention hiện
  tại của `PermanentCandidateIntakeRequest`.
- Nếu sau review muốn bắt buộc field theo journey type, dùng constant hiện có
  `Candidate::JOURNEY_TYPE_OTHERS` trong rule thay vì hardcode giá trị ở Service.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|------|-----------|-------|
| `database/migrations/2026_10_05_100000_add_journey_type_other_document_to_candidates_table.php` | — | Thêm/drop nullable string column trên `candidates`. |

Đã kiểm tra worktree và không có migration tương đương trước khi tạo file.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `app/Models/Candidate.php` | Bổ sung `@property`, `$fillable` cho `journey_type_other_document`. |
| `app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php` | Validate field mới theo contract optional/string/max 255. |
| `app/Services/PermanentCandidateIntakeService.php` | Gán field từ validated data trong transaction trước khi save Candidate. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Gửi field qua API, assert Candidate lưu đúng giá trị; thêm validation regression nếu cần. |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Bổ sung field vào service payload và assert assignment khi submit thành công. |
| `documents/Gap-API-Candidate.yaml` | Cập nhật schema `PermanentIntakeRequest` với field optional và `maxLength: 255`. |

Không sửa Repository/Contract, Controller/route, Resource response hoặc
MatchMaker payload vì không có thay đổi data-access/API-response/external
contract trong yêu cầu hiện tại.

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | `testSubmitPersistsPermanentProfileAndSynchronizesMatchMaker` | Submit `journey_type_other_document`, assert response thành công và Candidate/database lưu đúng giá trị. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Existing sync-failure/validation paths | Xác nhận field không làm thay đổi MatchMaker failure, email mismatch, file validation hoặc duplicate submit. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | New validation assertion | Chuỗi dài hơn 255 ký tự bị reject; request không có field vẫn hợp lệ theo giả định optional. |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | `testPermanentIntakeMapsSyncOutcomeAndUpdatesPermanentFlag` | Service nhận field và gán đúng vào Candidate trước repository save. |

Test gate sau implementation:

- Chạy `./vendor/bin/phpunit tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`.
- Chạy `./vendor/bin/phpunit tests/Unit/Services/PermanentCandidateIntakeServiceTest.php`.
- Review các test khác assert Candidate fillable/schema hoặc Permanent intake
  payload; cập nhật nếu bị ảnh hưởng.
- Chạy toàn bộ `./vendor/bin/phpunit`.

## 9. Implementation Phases

### Phase 1 — Persistence and Request Integration Boundary

**Input**: Existing `candidates` schema, Candidate model, Permanent intake
FormRequest và `submit()` transaction.

**File ownership**:

- `database/migrations/2026_10_05_100000_add_journey_type_other_document_to_candidates_table.php`
- `app/Models/Candidate.php`
- `app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php`
- `app/Services/PermanentCandidateIntakeService.php`

**Work**:

- Tạo nullable `string(255)` column.
- Expose field ở Candidate model.
- Validate field từ request.
- Assign field trong transaction và giữ nguyên call chain/error behavior.

**Output**: Request → validated data → Service → Candidate → database flow
compile-valid, không đổi response contract và không tạo fake success.

**Dependencies**: Không có Repository/Controller/Service binding mới.

**Acceptance criteria**:

- Migration up/down đúng cột.
- Existing rows migrate được với `null`.
- Omitted field không làm hỏng request theo optional assumption.
- Field hợp lệ được lưu cùng Candidate profile transaction.

**Test gate**: Migration/schema smoke test và existing Permanent intake feature
flow pass trước khi sang Phase 2.

### Phase 2 — Regression Coverage and Contract Documentation

**Input**: Phase 1 persistence/request integration.

**File ownership**:

- `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`
- `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php`
- `documents/Gap-API-Candidate.yaml`

**Work**:

- Bổ sung success assertion lưu field.
- Bổ sung validation boundary cho max length/omitted field.
- Cập nhật unit payload/assignment assertion.
- Cập nhật OpenAPI request schema, không thêm response field.

**Output**: Test suite bảo vệ persistence contract và API schema đồng bộ.

**Dependencies**: Phase 1 test gate đạt.

**Acceptance criteria**:

- Feature và unit tests liên quan pass.
- Không nới lỏng hoặc xóa assertion hiện có.
- OpenAPI ghi đúng field optional, string, maxLength 255.
- Full PHPUnit được chạy và mọi lỗi còn lại được phân loại rõ theo nguyên nhân.

**Test gate**: Affected suites pass, sau đó chạy `./vendor/bin/phpunit`.

## 10. Checklist trước khi Approve

- [x] Đã trace route → Controller → FormRequest → Service → Candidate → DB.
- [x] Đã xác định không cần Repository/Contract mới.
- [x] Database column, nullable/default/down migration đã nêu rõ.
- [x] Validation rule và response impact đã nêu rõ.
- [x] Test impact và full PHPUnit gate đã liệt kê.
- [x] User xác nhận và approve giả định optional (`nullable|string|max:255`).
- [x] User approve plan trước khi sửa production code.

## 11. Implementation Result

- Đã thêm migration nullable `string(255)` cho
  `candidates.journey_type_other_document`.
- Đã nối request → Service → Candidate save; request không có field vẫn hợp lệ,
  field dài hơn 255 ký tự bị reject.
- Đã cập nhật Candidate model, feature/unit tests và OpenAPI request schema.
- Affected suites pass: `8 tests, 122 assertions`.
- Full PHPUnit đã chạy: `515 tests, 2328 assertions`; còn 6 lỗi môi trường do
  Slack webhook `hooks.slack.com` không resolve được, không liên quan thay đổi
  này.
