# SPEC: GAP-691 — Align response format with existing Candidate API

> **Trạng thái**: `IMPLEMENTED`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex
> **Loại**: Amendment cho `GAP-691-response-contract-alignment-plan.md`

## 1. Tổng quan

### Mục tiêu

Loại bỏ response envelope custom chỉ dành cho GAP-691 và cập nhật API docs/runtime
theo convention đang dùng trong Candidate API của project. Đồng thời gom các lỗi
nghiệp vụ intake vào một `APIErrorException` dùng chung, nhận `error key` và
`message`, thay vì tạo một class exception cho từng case.

Amendment này thay đổi phần response/exception của plan đã triển khai trước đó;
không thay đổi request fields, persistence flow, ownership checks, direct
MatchMaker call hoặc quyết định không retry/queue của submit.

### Baseline đã trace trong source

- Payload data của Candidate API dùng `Resource` native và trả field ở top-level,
  không có `data` wrapper; ví dụ `MeFileController`, `MeController`.
- Operation response dùng `App\Http\Resources\Api\Candidate\Status::ok()`:
  ```json
  {
    "success": true,
    "message": "Success",
    "detail": ""
  }
  ```
- Candidate error response dùng `Status::error()`:
  ```json
  {
    "success": false,
    "message": "",
    "detail": "Human-readable error",
    "errors": [
      { "code": 1006, "message": "Human-readable error" }
    ]
  }
  ```
- FormRequest validation hiện dùng `App\Http\Requests\JsonRequest` và trả
  HTTP `400` với shape hiện hữu `{"status":400,"errors":{...}}`; không thay
  đổi global `JsonRequest` trong amendment này.

Theo baseline trên, GAP-691 sẽ không ép ba endpoint có cùng một JSON envelope
riêng. API docs sẽ mô tả đúng response type đang được runtime sử dụng.

## 2. Database Design

N/A. Không thay đổi database, migration, model relationship hoặc persistence
flow.

## 3. API Contract

### 3.1. Endpoint và middleware

Giữ nguyên ba route và Candidate auth/lock middleware hiện có:

```http
GET  /api/candidate/me/permanent-intake/config?job_id={internalJobId}
POST /api/candidate/me/permanent-intake
POST /api/candidate/me/jobs/{jobId}/work_finder_agreement/click
```

Không còn route middleware `normalizePermanentIntakeResponse`; auth và lock
response đi theo global Candidate `Handler`/`Status` như các route hiện hữu.

### 3.2. Runtime response theo convention hiện tại

#### Config success — `200`

`PermanentCandidateIntakeConfig` được trả trực tiếp:

```json
{
  "work_finder_agreement_url": "https://client.example.test/work-finder-agreement"
}
```

#### Agreement click success — `200`

`Candidate\Status::ok()` được trả trực tiếp:

```json
{
  "success": true,
  "message": "Agreement click recorded",
  "detail": ""
}
```

#### Submit success — `200`

`PermanentCandidateIntakeResult` được trả trực tiếp:

```json
{
  "candidate_id": 123,
  "job_id": 501,
  "candidate_job_id": 808,
  "submission_status": "submitted"
}
```

Success data response không thêm `success`, `message`, `errors`, `detail` hoặc
`data` wrapper nếu Resource hiện tại không emit các field đó.

#### Business/API errors

Business errors được render bởi Candidate `APIErrorException` và
`Candidate\Status::error()`:

```json
{
  "success": false,
  "message": "",
  "detail": "Candidate job was not found.",
  "errors": [
    {
      "code": 1015,
      "message": "Candidate job was not found."
    }
  ]
}
```

`detail` được giữ vì đây là field runtime của Candidate `Status`; amendment này
không đổi global Status contract.

#### FormRequest validation

Validation lỗi tiếp tục dùng base `JsonRequest` hiện tại, không tạo envelope
riêng cho GAP-691:

```json
{
  "status": 400,
  "errors": {
    "email": ["The email field is required."]
  }
}
```

### 3.3. Error mapping

| HTTP | Error key | Trường hợp | Cách phát sinh |
|------|-----------|------------|----------------|
| `404` | `candidateJobNotFound` | Job không tồn tại/không thuộc Candidate | Service throw Candidate `APIErrorException` |
| `404` | `permanentCvNotFound` | File không tồn tại, foreign hoặc DB type không khớp | Service throw Candidate `APIErrorException` |
| `409` | `permanentIntakeConflict` | Candidate đã submit Permanent | Service throw Candidate `APIErrorException` |
| `422` | `permanentIntakeValidation` | Email mismatch/business input cần giữ status hiện tại | Service throw Candidate `APIErrorException` |
| `502` | `permanentMatchMakerSyncFailed` | Direct MatchMaker failure sau GAP commit | Service log rồi throw Candidate `APIErrorException` |

FormRequest validation và config `job_id` malformed tiếp tục theo behavior
Candidate hiện tại (`400`/`wrongParameter` hoặc `JsonRequest` validation), không
thêm `success/data/message` envelope.

Các key/code queue/retry `202`, `503`, `queued`, `sync_enqueue_failed` tiếp tục
không thuộc submit API. `SyncPermanentCandidateToMatchMakerJob` vẫn giữ cho
legacy payloads nhưng submit mới không dispatch.

## 4. Business Logic / Service Layer

### 4.1. Luồng xử lý

```text
Route
  → Candidate auth/lock middleware hiện tại
  → Controller
    → FormRequest validation hiện tại
    → PermanentCandidateIntakeService
      → throw Candidate APIErrorException(error key, message) khi business failure
      → persist GAP
      → direct MatchMaker sync
      → log + throw Candidate APIErrorException khi sync failure
    → native Candidate Resource hoặc Candidate Status
```

### 4.2. Exception design

Tạo một exception dùng chung:

```php
new App\Exceptions\Api\Candidate\APIErrorException(
    $errorKey,
    $userMessage,
    $extraData = []
)
```

Exception kế thừa `App\Exceptions\Api\APIErrorException`, override
`getErrorResponse()` để render `App\Http\Resources\Api\Candidate\Status`,
giống pattern `Api\Compliance\APIErrorException` và
`Api\Consultant\APIErrorException`.

`PermanentCandidateIntakeService` dùng các key/message tương ứng khi throw;
Controller không còn nhiều `catch` chỉ để đổi flag thành response. Các typed
MatchMaker exceptions vẫn tồn tại cho MatchMaker/legacy Job; riêng intake
service catch chúng để log và chuyển thành Candidate API error `502`.

Xóa các exception class chỉ phục vụ branch riêng của implementation trước:

- `CandidateJobNotFoundException`
- `PermanentIntakeConflictException`
- `PermanentCandidateCvNotFoundException`
- `PermanentCandidateEmailMismatchException`

### 4.3. Side effects

Giữ nguyên:

- GAP persistence commit trước direct MatchMaker call.
- MatchMaker failure không rollback GAP data.
- Không dispatch queue, retry hoặc resync từ submit API.
- Không thêm API/global response behavior cho các domain khác.

## 5. Data Origin & Call Chain

| Response | Nguồn | Resource/handler |
|----------|-------|------------------|
| Agreement URL | `PermanentCandidateIntakeService::getConfig()` | `PermanentCandidateIntakeConfig` top-level |
| Submit IDs/status | `PermanentCandidateIntakeService::submit()` | `PermanentCandidateIntakeResult` top-level |
| Click message | Controller constant/message | Candidate `Status::ok` |
| Business error key/message | Service business branch | Candidate `APIErrorException` → `Status::error` |
| Validation errors | FormRequest validator | Base `JsonRequest::failedValidation` |

## 6. Constants & Error Keys

- Reuse existing `config('api.errors.*')` keys and status codes where applicable.
- Service khai báo constants cho các error key được dùng lặp lại; không tạo
  exception class riêng theo từng key.
- Không thêm key cho queue/retry response đã loại khỏi submit.
- Không sửa global `Status`, `Resource`, `JsonRequest` hoặc `Handler`.

## 7. Files cần sửa

### 7.1. Files tạo mới

| File | Mô tả |
|------|-------|
| `app/Exceptions/Api/Candidate/APIErrorException.php` | Candidate-domain API exception dùng chung, nhận key/message và render Candidate Status |

### 7.2. Files sửa/xóa

| File | Thay đổi |
|------|----------|
| `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php` | Bỏ custom response/catch branch; trả native Config/Result/Status; giữ xử lý input cần thiết |
| `app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php` | Bỏ custom `failedValidation` envelope; dùng validation behavior hiện tại |
| `app/Services/PermanentCandidateIntakeService.php` | Dùng một Candidate API exception với key/message; MM failure chuyển thành API error sau khi log |
| `app/Http/Kernel.php` | Bỏ alias/priority của normalizer, giữ thay đổi unrelated hiện có |
| `routes/candidate.php` | Bỏ `normalizePermanentIntakeResponse` khỏi ba route |
| `config/api.php` | Giữ các key còn dùng; loại validation key nếu không còn branch sử dụng sau audit |
| `documents/Gap-API-Candidate.yaml` | Dùng native Config/Result/Status schemas; bỏ custom envelope schemas cho GAP-691 |
| `.specs/GAP-691/GAP-691-implementation-plan.md` | Cập nhật response examples/contract theo Candidate convention |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật SPEC-039 và source map theo runtime response/exception mới |
| `.business-spec/backend-api-route-inventory.md` | Bỏ normalizer khỏi middleware inventory |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Assert native Resource/Status/validation shapes và exception-driven mapping |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Assert một Candidate API exception với từng key; MM failure không dùng nhiều domain exception |
| `app/Http/Resources/Api/Candidate/PermanentCandidateIntakeResponse.php` | Xóa custom response resource |
| `app/Http/Middleware/NormalizePermanentIntakeResponse.php` | Xóa route-scoped normalizer |
| `app/Exceptions/Services/CandidateJobNotFoundException.php` | Xóa exception riêng không còn dùng |
| `app/Exceptions/Services/PermanentIntakeConflictException.php` | Xóa exception riêng không còn dùng |
| `app/Exceptions/Services/PermanentCandidateCvNotFoundException.php` | Xóa exception riêng không còn dùng |
| `app/Exceptions/Services/PermanentCandidateEmailMismatchException.php` | Xóa exception riêng không còn dùng |

Không sửa repository, migration, MatchMaker payload/mapping hoặc legacy Job
ngoài phần test/contract cần thiết.

## 8. Test Cases

- Config success trả `PermanentCandidateIntakeConfig` top-level.
- Submit success trả `PermanentCandidateIntakeResult` top-level.
- Click success trả Candidate `Status::ok`.
- Auth/lock errors đi qua global Candidate response.
- FormRequest validation trả base `JsonRequest` shape và HTTP hiện tại.
- Job/file/conflict/email/MM branches throw cùng một Candidate API exception với
  đúng key/message/status.
- Submit MatchMaker failure vẫn không dispatch queue/retry.
- Legacy Job/MatchMaker tests tiếp tục pass.
- Chạy toàn bộ affected suites và full `./vendor/bin/phpunit` với logging channel
  phù hợp workspace.

## 9. Approval gate

- [x] User xác nhận “format project hiện tại” được hiểu là Candidate Resource +
      Candidate Status như phần 3, bao gồm `detail` ở error và không có
      `data` wrapper.
- [x] User xác nhận FormRequest validation giữ shape `status/errors` và HTTP
      `400` hiện tại, thay vì ép thành Candidate Status `422`.
- [x] User duyệt dùng một `App\Exceptions\Api\Candidate\APIErrorException`
      nhận `error key/message`.
- [x] User duyệt xóa bốn service exception class riêng và route normalizer.
- [x] Sau approval mới sửa code/docs/tests.

## 10. Verification evidence

- Feature GAP-691: `7 tests, 107 assertions`.
- Service/legacy MatchMaker suites: `2 + 5 + 1 tests`, all passing.
- Full PHPUnit with `LOG_CHANNEL=single`: `511 tests, 2,293 assertions`.
- OpenAPI YAML parsed successfully.
