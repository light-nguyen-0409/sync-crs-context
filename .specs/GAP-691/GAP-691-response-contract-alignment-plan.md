# SPEC: GAP-691 Response Contract Alignment

> **Trạng thái**: `IMPLEMENTED — SUPERSEDED BY AMENDMENT`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex

> **Amendment hiện hành**: [GAP-691-response-format-project-alignment-plan.md](GAP-691-response-format-project-alignment-plan.md)
> thay thế response envelope custom bằng Candidate `Resource`/`Status` hiện tại
> và gom business exceptions vào Candidate `APIErrorException` dùng chung.

## 1. Tổng quan

### Mục tiêu

Căn chỉnh response của ba API Permanent intake với API contract đã duyệt trong
`.specs/GAP-691/GAP-691-implementation-plan.md` §3.2–§3.4, không thay đổi
business flow, database schema hoặc phạm vi visibility của GAP-691.

Phạm vi sửa gồm:

- Dùng một response envelope duy nhất cho cả ba endpoint: `success`, `data`,
  `message`; chỉ error response mới có thêm `errors`.
- Mọi success response đều bắt buộc có `"success": true`, không có `errors`/
  `detail`; không để config, click và submit dùng ba shape khác nhau.
- Chuẩn hóa validation/business-input errors về HTTP `422` và cùng envelope
  (`success=false`, `data=null`, `message`, `errors[]`), không phát sinh `detail`.
- Giữ trực tiếp MatchMaker sync: thành công `200`, lỗi MatchMaker `502`, không
  tạo `202 queued`, `503 sync_enqueue_failed` hoặc retry mới từ submit API.
- Đồng bộ implementation plan, OpenAPI documentation và test expectations.

### Contract interpretation cần được chốt

Implementation plan hiện có hai JSON example bị đảo nhãn tại §3.4:

- JSON `success=false` ở dòng 239–245 được hiểu là response `502`.
- JSON có `data` và `message` ở dòng 249–259 được hiểu là response `200`.

Status matrix tại dòng 265–271 và amendment direct-MatchMaker tại dòng 26–30
được giữ làm nguồn chuẩn: `401`, `404`, `422`, `409`, `502`; không có
`202/503`.

Response envelope được chuẩn hóa lại trong task này cho riêng các endpoint
GAP-691; không thay đổi `Status`/response envelope của các API hiện hữu ngoài
phạm vi task.

Đối chiếu với response format hiện tại:

- Các `Resource` hiện tại thường trả payload ở top-level và chưa có envelope chung.
- `Candidate\Status::ok` đã dùng `success=true` và `message`; `errors` là field dành cho lỗi và không cần xuất hiện ở success.
- `Candidate\Status::error` dùng `success=false` cùng `errors[]`; field `detail` đang tồn tại ở implementation cũ nhưng không được đưa vào contract mới của GAP-691.
- GAP-691 sẽ đóng gói riêng theo format thống nhất `success/data/message`, chỉ thêm `errors` khi lỗi; không thay đổi format của các API cũ ngoài phạm vi task.

| Format hiện tại | Đặc điểm | GAP-691 sau khi chuẩn hóa |
|---|---|---|
| `Status` success | Có `success=true`, `message`; có thể còn field legacy và không cần `errors` | `success=true`, `data`, `message`; không có `errors`/`detail` |
| `Status` error | Có `success=false`, `errors[]`; một số implementation còn `detail` | `success=false`, `data=null`, `message`, `errors[]`; không có `detail` |
| `Resource` payload | Payload thường ở top-level, không có envelope chung | Payload nằm trong `data` của envelope GAP-691 |

### Audit error code sau khi bỏ retry ở submit API

| Nhóm | Mã/nhánh | Quyết định |
|---|---|---|
| Vẫn dùng | `permanentIntakeConflict` (`1014`, `409`) | Giữ cho duplicate submit |
| Vẫn dùng | `candidateJobNotFound` (`1015`, `404`) | Giữ cho job không thuộc Candidate/không tồn tại |
| Vẫn dùng | `permanentCvNotFound` (`1016`, `404`) | Giữ cho CV không tồn tại/không hợp lệ theo flow hiện tại |
| Vẫn dùng | `permanentMatchMakerSyncFailed` (`1017`, `502`) | Giữ cho direct MatchMaker failure sau khi GAP đã commit |
| Không còn dùng trong submit API | `202`, `503`, `queued`, `sync_enqueue_failed` và các mã chỉ mô tả enqueue/retry exhaustion | Loại khỏi controller, OpenAPI, contract và submit tests |
| Ngoài phạm vi submit API | Retry/final-failure branch của `SyncPermanentCandidateToMatchMakerJob` | Giữ cho legacy payloads theo implementation plan; không dispatch từ submit mới |

Rà soát source hiện tại không tìm thấy config key `sync_enqueue_failed`; staged
snapshot, OpenAPI và test fixtures đã được kiểm tra để loại mọi reference còn sót.

## 2. Database Design

Không thay đổi database, migration, model relationship hoặc persistence flow.

## 3. API Contract

### 3.1. Endpoint

Các endpoint giữ nguyên route và middleware:

```http
GET  /api/candidate/me/permanent-intake/config?job_id={internalJobId}
POST /api/candidate/me/jobs/{jobId}/work_finder_agreement/click
POST /api/candidate/me/permanent-intake
```

**Auth**: `auth:candidateApi` và `checkCandidateLockEdit` theo route hiện tại.

### 3.2. Response envelope chung

Tất cả response của ba endpoint GAP-691 phải có cùng các field bắt buộc
top-level và cùng kiểu dữ liệu; `errors` chỉ dành cho error response:

**Success** (không có `errors` và `detail`):

```json
{
  "success": true,
  "data": {},
  "message": "Success"
}
```

**Error** (có `errors`, không có `detail`):

```json
{
  "success": false,
  "data": null,
  "message": "Request failed",
  "errors": [
    {
      "code": 1019,
      "message": "Human-readable error message"
    }
  ]
}
```

`success`, `data`, `message` luôn tồn tại. `errors` chỉ xuất hiện khi
`success=false`; success response không xuất hiện `errors` hoặc `detail`.

#### GET config — `200`

```json
{
  "success": true,
  "data": {
    "work_finder_agreement_url": "https://client.example.test/work-finder-agreement"
  },
  "message": "Permanent intake configuration retrieved successfully"
}
```

Nếu không resolve được URL, giá trị vẫn là chuỗi rỗng `""`.

#### POST Agreement click — `200`

```json
{
  "success": true,
  "data": null,
  "message": "Agreement click recorded"
}
```

#### POST Permanent intake — `200`

```json
{
  "success": true,
  "data": {
    "candidate_id": 123,
    "job_id": 501,
    "candidate_job_id": 808,
    "submission_status": "submitted"
  },
  "message": "Candidate information submitted successfully"
}
```

Response không expose trạng thái queue/sync nội bộ ngoài HTTP status.

### 3.3. Error responses

Các endpoint dùng cùng error envelope ở §3.2; chỉ khác HTTP status và error
configuration/message:

| HTTP | Trường hợp | Quy tắc |
|------|------------|---------|
| `401` | Candidate token thiếu, hết hạn hoặc không hợp lệ | Response được normalize về envelope GAP-691 sau middleware |
| `404` | Job không tồn tại/không thuộc Candidate hoặc submitted file không thuộc Candidate | Không tiết lộ ownership của Candidate khác |
| `422` | Required/enum/format sai, Agreement false, email không khớp, hoặc `files[]` sai shape/thiếu CV/duplicate type | FormRequest và email mismatch phải dùng cùng error format |
| `409` | Candidate đã submit Permanent | Không persistence hoặc MatchMaker attempt lần hai |
| `502` | MatchMaker transient/non-retryable failure sau khi GAP commit | Log/alert; không enqueue, retry hoặc resync |

Đối với `GET config`, `job_id` malformed/missing sẽ được chuẩn hóa về `422`;
job hợp lệ nhưng không thuộc Candidate vẫn là `404`.

Không khai báo hoặc sinh response `202`/`503` từ submit flow.

### 3.4. Request validation rules

Giữ các field/rules hiện có trong `PermanentCandidateIntakeRequest`, bao gồm:

- `job_id` là internal `jobs.id`, required integer.
- Email phải match Candidate từ JWT.
- `work_finder_agreement_accepted` phải là `true`.
- `files[]` phải có đúng một CV và tối đa một Other; `file_id` ownership/type
  được xác minh ở Service.
- `journey_type` giữ enum `passport`, `share_code`, `others`.

Chỉ thay đổi HTTP status và error envelope của validation; không thay đổi dữ liệu
được validate.

## 4. Business Logic / Implementation Design

### 4.1. Luồng xử lý

```text
Route
  → PermanentCandidateIntakeController
    → PermanentCandidateIntakeRequest::validated()
    → PermanentCandidateIntakeService
      → persist GAP data
      → direct MatchMaker sync
    → PermanentCandidateIntakeResponse envelope
```

### 4.2. Thay đổi dự kiến

1. `PermanentCandidateIntakeService::submit()` chỉ trả success payload với các
   key `candidate_id`, `job_id`, `candidate_job_id`, `submission_status`; không
   trả các flag `conflict`, `not_found`, `email_mismatch`, `sync_failed` hoặc
   `http_status` để Controller tự chọn lỗi.
2. Service throw custom exception ngay tại business failure; Controller chỉ catch
   exception và map sang HTTP/common response:

   | Exception | Điểm throw | API mapping |
   |---|---|---|
   | `CandidateJobNotFoundException` | `getOwnedCandidateJob()` | `404` / `candidateJobNotFound` |
   | `PermanentIntakeConflictException` | Candidate đã `is_permanent` | `409` / `permanentIntakeConflict` |
   | `PermanentCandidateCvNotFoundException` | File không tồn tại, không thuộc Candidate, sai type hoặc thiếu CV | `404` / `permanentCvNotFound` |
   | `PermanentCandidateEmailMismatchException` | Email request khác email Candidate từ token | `422` / validation error code riêng của GAP-691 |
   | `MatchMakerTransientException` hoặc `MatchMakerNonRetryableException` | Direct MatchMaker call sau GAP commit | Log rồi rethrow; Controller map `502` / `permanentMatchMakerSyncFailed` |

   FormRequest validation vẫn xử lý ở FormRequest và trả `422`; không biến lỗi
   validation thành các flag trong Service.
3. Tạo `PermanentCandidateIntakeResponse` làm Resource envelope dùng chung cho
   config, click, submit success và các lỗi do controller/FormRequest tạo ra.
   Resource luôn emit `success`, `data`, `message`; chỉ emit `errors` khi lỗi.
4. `PermanentCandidateIntakeConfig` và `PermanentCandidateIntakeResult`
   chỉ làm payload resources nằm trong `data`; không tự wrap riêng và không
   sửa behavior/wrapping của các Resource khác.
5. `PermanentCandidateIntakeRequest` override failed-validation cục bộ để trả
   HTTP `422` qua common response envelope; không sửa global `JsonRequest`.
6. Controller bỏ toàn bộ `if` đọc result flags; chỉ map các custom exception về
   `404`, `409`, `422`, `502` và bỏ hoàn toàn branch queue nếu còn trong staged
   snapshot.
7. Thêm error config key/domain code cho validation `422` nếu cần; không giữ
   error key queue failure không còn được sử dụng. Reuse/mapping của
   `wrongParameter` phải được quyết định lại vì config hiện tại của mã này là
   HTTP `400`, trong khi GAP-691 yêu cầu validation/business-input là `422`.
8. Thêm route middleware riêng cho ba endpoint GAP-691 để normalize cả
   authentication/lock response về common envelope; middleware chỉ đổi shape,
   loại bỏ `detail`, không đổi authentication decision hoặc HTTP status. Không
   sửa global Handler hoặc `CheckCandidateLockEdit`.
9. Không dispatch `SyncPermanentCandidateToMatchMakerJob` từ submit; Job cũ chỉ
   được giữ cho payload legacy như implementation plan đã quy định.
10. Cập nhật tài liệu để hai JSON example trong implementation plan không còn bị
   đảo và OpenAPI phản ánh đúng common envelope/field/status.

### 4.3. Side effects

Không thêm side effect mới. Giữ nguyên:

- GAP persistence commit trước MatchMaker call.
- MatchMaker success cập nhật people number/status `PERM`.
- MatchMaker failure log/alert và trả `502`.
- Không retry/enqueue/resync trong submit API.

## 5. Data Origin & Call Chain

| Response field | Nguồn | Xác minh |
|----------------|-------|----------|
| `work_finder_agreement_url` | `PermanentCandidateIntakeService::getConfig()` resolve branch → legal entity | Đã trace |
| `candidate_id` | `auth()->user()->id` truyền vào Service | Đã trace |
| `job_id` | `PermanentCandidateIntakeRequest::validated()['job_id']` | Đã trace |
| `candidate_job_id` | `getOwnedCandidateJob()` result | Đã trace |
| `submission_status` | Service constant `SUBMISSION_STATUS_SUBMITTED` | Đã trace |
| validation errors | `PermanentCandidateIntakeRequest` Validator | Đã kiểm thử |
| MM failure mapping | `MatchMakerTransientException`/`MatchMakerNonRetryableException` mapping | Đã trace |

Không lấy `candidate_id`, `job_id` hoặc ownership từ client ngoài các input đã
được xác thực theo contract.

## 6. Constants & Enums

- Giữ `PermanentCandidateIntakeService::SUBMISSION_STATUS_SUBMITTED`.
- Khai báo constants cho các success messages và common response defaults trong
  `PermanentCandidateIntakeResponse`; không hardcode message lặp lại trong
  Controller.
- Error code/status validation phải nằm trong `config/api.php`, không hardcode
  HTTP `422` hoặc numeric code ở nhiều nơi.
- Không thêm constant cho `202`, `503` hoặc `queued` vì các nhánh này bị loại khỏi
  submit contract.

## 7. Files cần sửa

| File | Thay đổi |
|------|----------|
| `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php` | Bỏ result-flag `if`; catch custom exceptions và map response theo contract; config invalid `job_id` thành `422`; loại queue branch |
| `app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php` | Domain-local failed-validation response `422` through the common `success/data/message/errors` envelope |
| `app/Exceptions/Services/PermanentIntakeConflictException.php` | Custom exception cho duplicate Permanent submit |
| `app/Exceptions/Services/PermanentCandidateCvNotFoundException.php` | Custom exception cho CV/file ownership/type failure trong submit |
| `app/Exceptions/Services/PermanentCandidateEmailMismatchException.php` | Custom exception cho email không khớp Candidate token |
| `app/Http/Middleware/NormalizePermanentIntakeResponse.php` | Route-scoped normalizer cho auth/lock/legacy response về common envelope |
| `app/Http/Kernel.php` | Register route middleware alias cho GAP-691 response normalizer |
| `routes/candidate.php` | Áp dụng normalizer cùng ba endpoint, trước auth middleware trong route chain |
| `app/Http/Resources/Api/Candidate/PermanentCandidateIntakeResponse.php` | Common GAP-691 response envelope; luôn có `success`, `data`, `message`, chỉ có `errors` khi lỗi |
| `app/Http/Resources/Api/Candidate/PermanentCandidateIntakeConfig.php` | Chỉ giữ config payload trong `data` |
| `app/Http/Resources/Api/Candidate/PermanentCandidateIntakeResult.php` | Chỉ giữ submit payload trong `data` |
| `app/Services/PermanentCandidateIntakeService.php` | Chỉ trả normalized success result; throw custom exceptions cho business failure; log rồi rethrow direct MM exception |
| `config/api.php` | Error config cho validation `422`; loại stale queue error key nếu còn effective |
| `documents/Gap-API-Candidate.yaml` | Cập nhật response schemas, `422`, success/error examples; không khai báo `202/503` |
| `.specs/GAP-691/GAP-691-implementation-plan.md` | Sửa hai JSON example bị đảo và ghi rõ response contract đã chuẩn hóa |
| `.business-spec/backend-business-flow-spec.md` | Bổ sung exact response envelope/status trong SPEC-039 nếu cần để living spec khớp runtime |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Assert exact config/success envelope, `422`, error envelope, duplicate/404/502 và no queue |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Assert normalized success result, custom business exceptions và direct MM exception rethrow |

Không sửa `app/Http/Requests/JsonRequest.php`, `app/Http/Resources/Resource.php`
hoặc `app/Http/Resources/Api/Candidate/Status.php`; common envelope chỉ áp dụng
cho ba endpoint GAP-691.

## 8. Test Cases

| Test area | Acceptance case |
|-----------|-----------------|
| Common envelope | Mọi success có `success=true`, `data`, `message` và không có `errors`/`detail`; mọi error có `success=false`, `data`, `message`, `errors` |
| Config success | Response có `success=true`, `data.work_finder_agreement_url`; branch > entity; fallback `""` |
| Config validation | Missing/malformed `job_id` trả `422`; foreign job trả `404`; cùng error envelope |
| Auth/lock guard | Missing/expired token và locked candidate giữ HTTP status hiện tại nhưng response dùng common envelope |
| Agreement click | `200`, `success=true`, `data=null`, message đúng, repeated click idempotent |
| Submit success | `200`, `success=true`, `data.candidate_id`, `data.job_id`, `data.candidate_job_id`, `data.submission_status=submitted`, `message` đúng contract |
| Submit validation | Missing required, invalid enum, Agreement false, email mismatch, hoặc `files[]` sai shape/thiếu CV/duplicate type trả `422` và cùng `errors[]` shape; file DB thiếu/foreign/type mismatch trả `404` |
| Exception flow | Service không trả `conflict/not_found/email_mismatch/sync_failed`; từng business failure throw đúng custom exception và Controller map đúng status/code |
| Submit ownership | Foreign job/file trả `404` và cùng error envelope |
| Duplicate | Submit lần hai trả `409`, không persistence/MatchMaker attempt mới, cùng error envelope |
| MatchMaker failure | Transient/non-retryable trả `502` sau GAP commit, không queue/resync, cùng error envelope |
| Legacy queue | Existing Job tests vẫn pass; submit API không dispatch Job |
| Regression | Chạy toàn bộ affected suites và `./vendor/bin/phpunit` theo workspace rules |

## 9. Checklist trước khi Approve

- [x] User xác nhận hai JSON example trong implementation plan được đảo lại như
      phần “Contract interpretation”.
- [x] User duyệt common envelope gồm `success`, `data`, `message`; `errors` chỉ
      xuất hiện khi lỗi; success bắt buộc `success=true` và không có `detail`.
- [x] User duyệt success data có các field
      `candidate_id/job_id/candidate_job_id/submission_status`.
- [x] User duyệt validation status `422` thay cho `400`.
- [x] User duyệt Service throw custom exception cho business failure; Controller
      không còn dùng result flags để chọn error response.
- [x] User duyệt không sửa global `Status`/Resource; common envelope chỉ áp dụng
      cho ba endpoint GAP-691.
- [x] Không còn staged/worktree split giữa direct `502` và queue `202/503`.
- [x] OpenAPI, implementation plan, business spec và tests cùng một contract.
- [x] Không thay đổi database hoặc global response/validation behavior ngoài
      GAP-691.
- [x] Sau approval mới bắt đầu code và chạy migration/test commands cần thiết.
