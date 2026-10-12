# SPEC: GAP-691 — Kế hoạch triển khai tiếp nhận Candidate Permanent

> **Trạng thái**: `PHASES 1–5 IMPLEMENTED; SOURCE/TEST ACCEPTANCE COMPLETE; PRODUCTION ALERT DELIVERY UNVERIFIED`
> **Ngày tạo**: 2026-09-28; cập nhật 2026-09-30
> **Author**: Codex

---

## 1. Tổng quan

Triển khai luồng Permanent trên Candidate đã đăng ký bằng flow hiện tại, giữ `job_ref`/`candidate_job`, thu thập các trường đã chốt (bao gồm `journey_type` bắt buộc), ghi Work Finder Agreement click, lưu GAP trước rồi gọi MatchMaker trực tiếp theo timeout mặc định của HTTP client với trạng thái `PERM`. Khi MatchMaker lỗi, flow không dispatch queue hoặc resync mà trả kết quả lỗi ngay. Permanent chỉ bị loại khỏi các Candidate list/filter đã chốt; lookup theo ID và các luồng khác không lọc chỉ bởi `is_permanent`. Permanent không được dùng các chức năng/rule dành cho `LIVE`.

**Yêu cầu gốc**: `.specs/GAP-691/GAP-691-permanent-candidate-intake.md` — tài liệu yêu cầu đã duyệt. Các câu hỏi/điều kiện đang ở mục 10 của tài liệu đó được giữ lại để xử lý sau; plan này không tự chốt các giá trị còn hoãn.

### Implementation audit status (2026-09-29)

- Phase 1: implementation/schema, repository, branch URL/seeder changes present; full PHPUnit passes. Production migration/seeder state remains UNVERIFIED.
- Phase 2: direct Permanent MatchMaker mapping and the legacy transient fallback job are implemented. The current intake path no longer dispatches that job; terminal job failure logs at critical and direct MatchMaker failures log at error. `config/logging.php` default stack contains Slack and default Slack threshold is error; effective config was verified as `slack_level=error`, `stack_channels=single,slack`. Actual environment override, webhook/delivery and workers are UNVERIFIED.
- Phase 3: candidate config/click/submit and CV upload paths are implemented and covered by existing tests.
- Phase 4 (scope amended): Candidate list/filter visibility rules are implemented; ID lookups and non-filter flows are not excluded by `is_permanent`. Dedicated staff-only lookup APIs have been removed; no global scope was added.
- Phase 5: source/test review and canonical business-spec updates completed. After the response-format amendment, full suite passes: `511 tests, 2,293 assertions`. No runtime code follow-up is required for the direct 4xx alert source path; production delivery remains UNVERIFIED.
- Intake files amendment: submit accepts `files[]` with CV required and Other optional independent of `journey_type`; ownership and persisted type are checked in one batch read. Only CV ID is sent to MatchMaker. Feature/unit tests and OpenAPI documentation were updated.
- Route inventory count checked with `LOG_CHANNEL=single DB_CONNECTION=sqlite DB_DATABASE=:memory: php artisan route:list --json`: 245 API route entries; production route/deployment state is UNVERIFIED.
- Existing unrelated/user working-tree changes were retained; their original baseline cannot be proven from the current modified working tree.

### Current behavior amendment (2026-09-30)

- Sau khi Permanent persistence commit, transient/non-retryable MatchMaker failure đều được service log rồi throw lại custom exception để Controller trả HTTP `502` ngay; không dispatch `SyncPermanentCandidateToMatchMakerJob`.
- Không thêm endpoint resync/manual retry. `candidate_id` + `job_id` không phải input của API mới vì không có API mới.
- Giữ class Job và logic xử lý payload đã tồn tại để tránh phá dữ liệu queue cũ; thay đổi này không chứng minh queue worker/alert delivery trên deployment.

### 1.1 Quyết định đã chốt, không mở lại trong implementation

- Giữ `POST /api/candidate/auth/signup`, Candidate token hiện tại và `job_ref`. Sau signup, gọi `POST /api/candidate/me/jobs` trước khi mở form để tạo `candidate_job`; API này nhận external IDs từ invitation và trả internal `jobs.id`.
- `RT=P` chọn form Permanent. Chỉ lưu `journey_type`, không chạy xác minh RTW.
- Required fields: Title, First name, Last name, Email, Phone number, Date of birth, Address, Contact date, Contact time, primary transport, travel distance, recruitment source, Work Finder Agreement, CV Upload; `journey_type` cũng bắt buộc.
- URL entity là fallback bắt buộc, lưu ở `legal_entities` và nạp bằng CSV update-only. Thêm URL override tùy chọn vào `branches`, cho phép sửa qua Branch CRUD; backend resolve branch URL trước, entity URL sau. Không có mức URL brand.
- FE chịu trách nhiệm bắt buộc click Agreement trước khi tiếp tục; backend ghi nhận lần click đầu tiên theo Candidate/job bằng thời gian/IP. Checkbox Agreement vẫn bắt buộc `true` tại submit nhưng không lưu boolean hoặc thời điểm đồng ý.
- Upload CV bằng API/file type `cv` hiện tại; optional supporting file dùng file type `other`. API submit nhận `files[]` gồm `{file_id,type}`; không thêm file type hoặc cột file reference riêng.
- GAP lưu Candidate và commit trước; sau đó gọi tích hợp Candidate–MatchMaker hiện tại trực tiếp theo timeout mặc định của HTTP client. Mọi lỗi MatchMaker đều được ghi nhận/báo lỗi và trả kết quả ngay; không queue retry hoặc resync. Gửi toàn bộ dữ liệu form, gồm `journey_type`; status đích `PERM`. Không yêu cầu idempotency/upsert riêng ở MM trong đợt này.
- Permanent bị loại khỏi Candidate list/search, Escalated Issue candidate list, Appointment list và SMS eligible-recipient filter. Các ID lookups, aggregate/count, report, export và campaign đã tạo không lọc chỉ vì cờ này. Không mở bất kỳ chức năng nào theo quy tắc `LIVE`.

### 1.2 Ranh giới và điểm cần giữ nguyên

- Không tạo Candidate tạm, `intake_token`, API verify RTW, PDF Agreement, hoặc contract/contact-log input riêng từ FE.
- Không gọi nguyên trạng `MatchMakerService::sendCandidateToMatchMaker()`: method này yêu cầu readiness/interview/RTW, gửi RTW documents và chuyển local status thành `LIVE`.
- Không đặt filter ẩn Permanent thành global Eloquent scope; background sync và Candidate self-service phải tiếp tục truy cập dữ liệu.
- Không dùng lại nguyên `LegalEntitySeeder`: `CSVSeeder` mặc định xóa dữ liệu bảng; seeder email-template chỉ insert ID mới, không update entity hiện hữu.
- Dữ liệu URL entity sẽ được cung cấp đầy đủ; nếu resolver không tìm được URL thì config trả `work_finder_agreement_url: ""`, không trả `null` hoặc lỗi cấu hình. Enum Sourceflow và giới hạn CV chính thức vẫn deferred theo tài liệu GAP-691.
- Không giữ transaction khi gọi MM. Direct success cập nhật MM identity/status sau phản hồi; lỗi sync được trả ngay sau commit. Job class cũ vẫn tồn tại để xử lý payload đã có, nhưng không phải fallback mới của submit.

## 2. Database Design

### 2.1 Không tạo bảng mới

Không tạo bảng intake hoặc bảng click riêng. Submission dùng Candidate, CandidateJob, answers, address và files hiện có; MM failure được ghi log/cảnh báo vận hành, không có `permanent_sync_status` trong GAP.

### 2.2 Bảng sửa đổi

| Bảng | Thay đổi | Ghi chú |
|------|----------|---------|
| `candidates` | Thêm `is_permanent` boolean, default `false` | Dấu phân loại GAP độc lập với `match_maker_status`; bật ngay cùng lúc form được lưu thành công |
| `legal_entities` | Thêm `work_finder_agreement_url` text/string nullable trong giai đoạn migration | Deploy migration trước; seeder cập nhật URL theo entity ID; không clear/reload bảng |
| `branches` | Thêm `work_finder_agreement_url` text/string nullable | URL override theo branch; Branch CRUD create/update/get/list quản lý field này; để trống thì dùng URL entity |
| `candidate_timings` | Thêm `work_finder_agreement_link_clicked_at` datetime nullable và `work_finder_agreement_link_clicked_ip` string(45) nullable | Dùng row unique theo Candidate/job; chỉ ghi lần click đầu, không ghi đè sự kiện KID/ToE/medical |
| `match_maker_candidates` mapping | Bổ sung mapping `PERM` rõ ràng; khai báo local constant `Candidate::MM_STATUS_PERM` | Không coi `PERM` tương đương `LIVE`; field này vẫn phản ánh trạng thái MM thật |

### 2.3 Dữ liệu form được lưu ở đâu

| API field | Nguồn lưu hiện tại/đề xuất |
|------------|---------------------------|
| `title`, `first_name`, `last_name`, `email`, `phone_number`, `date_of_birth`, `journey_type`, `contact_dates`, `contact_times` | Cột hiện có ở `candidates` (giữ `middle_name` hiện có nếu có; form không yêu cầu nhập mới) |
| `address.*` | `candidate_addresses` qua Permanent-specific write path; giữ nguyên mapping/field hiện có nhưng không gọi nguyên legacy updater có read/duplicate side effects |
| `transportation_method`, `transportation_distance`, `recruitment_source` | `answers` theo Question category/option hiện có; dùng mapping hiện tại qua Permanent-specific write path, không tạo cột trùng hoặc chạy duplicate issue checks |
| `files[].file_id/type` | Binary/storage + row `files` hiện hữu; CV bắt buộc, Other tùy chọn độc lập `journey_type`; submit xác thực owner và DB type theo batch lookup. Chỉ CV ID dùng khi gọi MM; file Other đã được upload/lưu ở GAP, không gửi MM |
| checkbox `work_finder_agreement_accepted` | Chỉ validate bắt buộc `true` khi submit; không lưu boolean hoặc thời điểm đồng ý vào DB ở giai đoạn này |
| submission marker | `candidates.is_permanent`; dùng để ẩn CRS và chặn submit/dispatch trùng ở GAP |
| MM sync attempt/failure | Direct call; mọi lỗi được trả sau commit và ghi log/ops alert; không lưu state riêng trên Candidate/CandidateJob |
| Agreement click time/IP | `candidate_timings.work_finder_agreement_link_clicked_at` / `work_finder_agreement_link_clicked_ip` |
| Branch Agreement URL | `branches.work_finder_agreement_url`, tùy chọn; override entity URL |
| Entity Agreement URL | `legal_entities.work_finder_agreement_url`, fallback bắt buộc |

## 3. API Contract

Các endpoint mới nằm dưới Candidate auth hiện tại. Config dùng query `job_id` là internal `jobs.id` lấy từ response `POST /api/candidate/me/jobs`; click route vẫn dùng `{jobId}` trên path. Submit dùng candidate-scoped route `/api/candidate/me/permanent-intake` và nhận `job_id` cùng internal `jobs.id` trong body. Backend resolve Candidate từ JWT và xác minh `candidate_job → job → branch → legal_entity`; Agreement URL ưu tiên branch rồi fallback entity. Không nhận `candidate_id`, `candidate_job_id`, `branch_id`, `legal_entity_id`, URL, click time hoặc IP tùy ý từ form body.

### 3.1 API hiện hữu được giữ nguyên hoặc siết validation

#### Đăng ký và gắn job — không đổi contract

```http
POST /api/candidate/auth/signup
POST /api/candidate/me/jobs
```

Signup vẫn tạo Candidate/token theo flow hiện tại. Trước khi mở form, `POST /me/jobs` nhận `external_id` (external job ID từ invitation), `branch_id` (external branch ID), `title`, `job_ref` và tracking fields; API map/tạo Job nội bộ, tạo `candidate_job`, rồi trả `201` với `data.id` (internal `jobs.id`), `data.branch` và `job_ref`. FE dùng `data.id` cho config/click routes và trường `job_id` của submit; không gửi lại external invitation ID ở các vị trí này.

#### Upload Candidate files — endpoint hiện hữu

```http
POST /api/candidate/me/files/cv
POST /api/candidate/me/files/other (optional)
Authorization: Bearer {candidate_token}
Content-Type: multipart/form-data
```

| Input | Validation đề xuất |
|-------|--------------------|
| `file` | required; CV MIME/extension allowlist PDF/DOC/DOCX; ClamAV; ownership lấy từ token; giới hạn dung lượng theo đề xuất hiện tại 10 MiB, còn quyết định cuối nằm ở mục 10 deferred |

Response `201`, resource `File` hiện có (`data.id`, `data.type`, `data.original_file_name`, URL/status hiện tại). FE đưa `data.id` cùng `data.type` vào `files[]` khi submit. Candidate-level CV/Other không cần `Gap-Job-ID`; không thay đổi upload behavior các file type khác. CV-specific PDF/DOC/DOCX, MIME và giới hạn 10 MiB chỉ áp dụng cho type `cv`.

File hỗ trợ tùy chọn được upload qua `POST /api/candidate/me/files/other` trước submit; file record/storage gắn với Candidate từ token giống CV. FE đưa ID/type vào cùng `files[]`; Other không có `Gap-Job-ID` và chưa được upload sang MatchMaker.

Mock response:

```json
{
  "data": {
    "id": 9821,
    "type": "cv",
    "url": "https://files.example.test/cv/9821",
    "converted_file_url": "",
    "status": "uploaded",
    "original_file_name": "candidate-cv.pdf",
    "uploaded_at": 1790592000,
    "toe_signed_ip": ""
  }
}
```

### 3.2 Lấy cấu hình Agreement cho form

```http
GET /api/candidate/me/permanent-intake/config?job_id=501
Authorization: Bearer {candidate_token}
Accept: application/json
```

**Auth/middleware**: `auth:candidateApi`; query `job_id` phải là internal `jobs.id` có `candidate_job` thuộc Candidate trong token. GET không yêu cầu `Gap-Job-ID`. Backend trả URL đã resolve theo thứ tự branch → entity.

**Response convention** cho ba endpoint dùng đúng Candidate API hiện tại:

- Config và submit trả native `Resource` top-level; không có `data` wrapper.
- Click và business errors dùng Candidate `Status`: success có `success`,
  `message`, `detail` rỗng; error có `success`, `message` rỗng, `detail` và
  `errors[]`.
- FormRequest validation giữ response legacy của `JsonRequest` gồm HTTP `400`,
  `status` và object `errors`; không tạo envelope custom cho GAP-691.

**Response 200** — trả `PermanentCandidateIntakeConfig` top-level, chỉ có trường
URL Agreement đã resolve; không trả ID, URL theo từng cấp, danh sách trường
bắt buộc/enum hoặc trạng thái submit. Giá trị là URL branch nếu có, nếu không
thì URL entity; nếu không resolve được thì trả chuỗi rỗng `""`.

```json
{
  "work_finder_agreement_url": "https://client.example.test/work-finder-agreement/entity-3"
}
```

Candidate profile prefill lấy từ API hiện tại `GET /api/candidate/me`; required fields/enums thuộc API contract của form, không trả trong endpoint config này.

### 3.3 Ghi nhận click Work Finder Agreement

```http
POST /api/candidate/me/jobs/{jobId}/work_finder_agreement/click
Authorization: Bearer {candidate_token}
Content-Type: application/json
```

Body rỗng `{}`. FE gọi endpoint này từ nút/link Agreement trên form; chỉ khi API thành công mới mở URL public. Backend xác thực Candidate/job và ghi thời gian/IP của lần click đầu vào row `candidate_timings` tương ứng. Các lần gọi tiếp theo không ghi đè thời gian/IP đầu tiên. Không nhận URL/time/IP từ body. Bắt buộc click trước khi FE tiếp tục là rule FE; backend không tự mở URL và click không được xem là dữ liệu checkbox consent.

**Response 200** theo `Candidate\Status::ok()` hiện có (idempotent nếu đã ghi
nhận click trước đó):

```json
{
  "success": true,
  "message": "Agreement click recorded",
  "detail": ""
}
```

### 3.4 Submit Candidate Permanent intake

```http
POST /api/candidate/me/permanent-intake
Authorization: Bearer {candidate_token}
Content-Type: application/json
Accept: application/json
```

**Request body** (FE mock contract):

```json
{
  "job_id": 501,
  "title": "Ms",
  "first_name": "Alex",
  "middle_name": "",
  "last_name": "Taylor",
  "email": "alex.taylor@example.test",
  "phone_number": "+447700900123",
  "phone_number_country_code": "+44",
  "date_of_birth": "1990-01-02",
  "address": {
    "building": "10",
    "street": "High Street",
    "town_city": "London",
    "county": "Greater London",
    "postcode": "SW1A 1AA"
  },
  "contact_dates": ["monday", "tuesday"],
  "contact_times": ["morning", "afternoon"],
  "transportation_method": "car",
  "transportation_distance": "10_miles",
  "recruitment_source": "website",
  "journey_type": "passport",
  "work_finder_agreement_accepted": true,
  "files": [
    { "file_id": 9821, "type": "cv" },
    { "file_id": 9822, "type": "other" }
  ]
}
```

`transportation_method`, `transportation_distance` và `recruitment_source` phải là value/key đang dùng trong các Question/Answer hiện có; label cuối do Sourceflow/client cung cấp và là điều kiện deferred. `phone_number_country_code` có thể lấy từ profile hiện tại nếu FE không thu thập riêng. Các field `address.*` bắt buộc theo validation/logic địa chỉ hiện hữu.

**Validation contract**:

| Field | Rule |
|-------|------|
| `job_id` | required integer; internal `jobs.id` from `POST /api/candidate/me/jobs`; must have a `candidate_job` belonging to Candidate from token |
| `title` | required, string, giới hạn theo cột hiện tại |
| `first_name`, `last_name` | required, string, giới hạn theo cột hiện tại |
| `email` | required, email; phải khớp Candidate từ token (form không được đổi chủ tài khoản) |
| `phone_number` | required, string, validation theo Candidate/profile hiện tại; country code lấy từ profile nếu không gửi |
| `date_of_birth` | required, date `YYYY-MM-DD` |
| `address` | required object; các thành phần required theo rule CandidateAddress hiện tại, không thêm Data8 workflow mới |
| `contact_dates`, `contact_times` | required arrays; validate từng value theo lựa chọn hiện tại |
| `transportation_method`, `transportation_distance`, `recruitment_source` | required; option/value phải map đến các Question hiện tại |
| `journey_type` | required; enum backend hiện tại `passport`, `share_code`, `others`; chỉ ghi loại đã chọn, không xác minh RTW |
| `work_finder_agreement_accepted` | required boolean và bắt buộc `true`; chỉ dùng để validate submit, không persist giá trị hoặc thời điểm đồng ý |
| `files` | required array; có đúng một `{file_id,type=cv}`; tối đa một `{file_id,type=other}` tùy chọn, không phụ thuộc `journey_type`; ID phải tồn tại/thuộc token Candidate và `type` phải khớp row `files`; chỉ CV ID được chuyển vào MatchMaker |

`job_id` trong body xác định application context; backend xác minh `candidate_job` thuộc Candidate từ token rồi tự resolve branch/entity. Không nhận `candidate_id`, `candidate_job_id`, external invitation ID, branch/entity, MM status, URL hoặc file binary trong body. Submit không yêu cầu Idempotency-Key phía MM.

**Success — 200 OK**: GAP đã lưu, MatchMaker trả thành công trực tiếp theo timeout mặc định HTTP client, và GAP đã cập nhật `match_maker_people_number`/`match_maker_status=PERM`. Response không phơi bày sync-status; HTTP status thể hiện request hoàn tất.

`PermanentCandidateIntakeResult` được trả top-level:

```json
{
  "candidate_id": 123,
  "job_id": 501,
  "candidate_job_id": 808,
  "submission_status": "submitted"
}
```

Khi MatchMaker call lỗi transient/non-retryable sau khi GAP commit, backend không enqueue hoặc resync; service ghi log rồi throw Candidate API exception với key `permanentMatchMakerSyncFailed`, framework render Candidate `Status` `502` ngay. Response body dùng Candidate error format:

```json
{
  "success": false,
  "message": "",
  "detail": "Candidate was saved, but MatchMaker synchronization failed.",
  "errors": [
    {
      "code": 1017,
      "message": "Candidate was saved, but MatchMaker synchronization failed."
    }
  ]
}
```

GAP data vẫn đã lưu khi MatchMaker lỗi; không có `503 sync_enqueue_failed` hoặc endpoint resync trong flow này. Trong cả hai trường hợp Candidate đã có `is_permanent=true`, submit tiếp theo trả `409 already_submitted` và không tạo sync attempt mới. Config endpoint chỉ phục vụ Agreement URL; API không cung cấp sync status.

**Business error response**: dùng Candidate `Status::error()` (`success=false`,
`message=""`, `detail`, `errors[]`). FormRequest validation là response legacy
`status/errors` của `JsonRequest`; FE mock cần tách hai loại response này.

| HTTP | Tình huống |
|------|-----------|
| 401 | Token thiếu/hết hạn/không phải Candidate |
| 404 | `job_id` không tồn tại hoặc không thuộc Candidate token; không tiết lộ owner khác |
| 400 | FormRequest required/enum/format sai hoặc Agreement false |
| 422 | Email không khớp Candidate/business input cần giữ status hiện tại |
| 409 | Candidate đã submit Permanent |
| 502 | MatchMaker transient/non-retryable failure; GAP data đã commit, không enqueue/retry/resync; log/alert để vận hành xử lý |

`PermanentCandidateIntakeService::submit()` chỉ return success payload. Các business
failure được Service throw bằng một `App\Exceptions\Api\Candidate\APIErrorException`
nhận `error key/message`; exception tự render Candidate `Status`. Service không
return các flag `conflict`, `not_found`, `email_mismatch`, `sync_failed` hoặc
`http_status`. MatchMaker typed exceptions chỉ được catch để log rồi chuyển thành
Candidate API error `permanentMatchMakerSyncFailed` (`502`).

## 4. Business Logic (Service Layer)

### 4.1 Luồng xử lý chính

```text
Signup hiện tại
  → POST /candidate/me/jobs (external job/branch IDs + job_ref từ invitation)
      → tạo hoặc tìm Job nội bộ + tạo candidate_job
      → trả data.id = internal jobs.id
  → GET Permanent config → backend resolve branch URL trước, entity URL fallback
  → upload CV qua POST /candidate/me/files/cv (hiện tại, CV rule mới)
  → POST Agreement click → backend lưu first-click IP/time vào candidate_timings → FE mở public URL
  → POST /candidate/me/permanent-intake (body.job_id = internal jobs.id)
      → auth Candidate + xác minh ownership CandidateJob/Job/Branch/LegalEntity/File
      → validate các trường, chưa submit trước đó, checkbox true
      → persist Candidate + address + answers + is_permanent=true
      → commit DB writes
      → gọi MM trực tiếp theo timeout mặc định HTTP client
          → success: cập nhật MM identity/status PERM → trả 200
          → transient/non-retryable failure: không retry/enqueue → log/alert → trả 502
```

### 4.2 Business rules và failure handling

- Candidate/job/entity/file ownership được kiểm tra từ DB trước khi write; mọi input identity/scope lấy từ token/path và quan hệ đã lưu, không tin Candidate/branch/entity IDs từ FE.
- Dùng persistence path riêng cho Permanent: preload/validate Candidate, address, Question/Answer options và file ownership trước transaction; transaction chỉ ghi Candidate, address, answers và `is_permanent=true`, không query/eager-load hay gọi external API bên trong. Giữ field mapping hiện tại và set `first_applied_at` nếu đang trống. Không gọi nguyên trạng `updatePersonalInfo()`/`updateCandidateAddress()` vì chúng đọc DB trong method, phát sinh duplicate-check/escalated-issue side effects và `updatePersonalInfo()` còn ném generic exception. Theo quyết định đã chốt, không chạy lại duplicate checks tạo escalated issue trong Permanent intake.
- `is_permanent=true` là marker GAP để ẩn Candidate sau submit và chặn submit trùng; không tạo intake/sync-state row riêng. Commit xong mới gọi MatchMaker trực tiếp; mọi lỗi được log/alert sau commit.
- Direct call dùng Permanent-specific orchestration để resolve CandidateJob/Branch/legal entity và dùng CV `file_id` đã xác thực. Payload MM chứa các field form đã map và TODO còn thiếu; không gửi dữ liệu RTW evidence vì không verify.
- Dùng low-level endpoint/API sync Candidate hiện có cho create/update nhưng tạo Permanent-specific mapping/orchestration; không gọi `sendCandidateToMatchMaker()` nguyên trạng, không gửi RTW files, không cập nhật appointment/job sang worker/live, không set local/MM status `LIVE`.
- Local `match_maker_status` và people number chỉ cập nhật theo phản hồi MM thành công, dùng mapping `PERM`; không thêm cột trạng thái đồng bộ riêng. Timeout có thể xảy ra sau khi MM đã tạo candidate; flow không tự retry hoặc resync nên operator phải xử lý theo quy trình ngoài API nếu cần.
- CV phải được upload lên Contact Log/MM theo integration hiện tại bằng file đã được xác minh. `MatchMakerService::saveAdditionalFiles()` hiện nuốt lỗi attachment và chỉ log; Permanent flow phải throw custom exception phân biệt transient (timeout/connection/5xx) với non-retryable (4xx), không báo synced giả.
- FE click gate là trách nhiệm FE; backend lưu lần click đầu trong `candidate_timings`. Backend vẫn enforce checkbox `true` nhưng không persist boolean/thời điểm; click audit không đồng nghĩa consent.
- Chỉ Candidate collection filter endpoints nêu tại Phase 4 loại Permanent. Các ID-based response/actions và report/export không tự động loại Permanent chỉ vì cờ này; quyền/branch authorization hiện hữu tiếp tục áp dụng.

### 4.3 Side effects

| Loại | Trigger | Mô tả |
|------|---------|-------|
| File/storage | Upload CV hiện tại | Lưu CV + metadata `files` type `cv`; giữ ownership theo Candidate |
| Audit | Agreement click API | Lưu lần click đầu, IP và backend timestamp vào `candidate_timings` |
| Database | Submit form | Cập nhật profile/address/answers và `is_permanent`; checkbox chỉ được validate |
| External | Sau khi GAP commit | Gọi MatchMaker trực tiếp theo timeout mặc định HTTP client; success cập nhật MM identity/status |
| Ops error | MM transient/non-retryable failure | Không retry/enqueue; ghi log/alert sau khi GAP đã commit |

## 5. Data Origin & Call Chain

```text
Sourceflow RT=P
  → existing POST /candidate/auth/signup
  → Candidate JWT
  → existing POST /candidate/me/jobs {job_ref, branch_id, external_id, title}
      → map external invitation IDs; create CandidateJob; response data.id = internal jobs.id + branch/legal_entity
  → existing GET /candidate/me (profile prefill) + new GET config (resolved branch/entity Agreement URL)
  → existing POST /candidate/me/files/cv → File resource data.id
  → optional existing POST /candidate/me/files/other → File resource data.id
  → new POST click (Candidate JWT + jobId path; backend adds time/IP)
  → new POST /candidate/me/permanent-intake (JWT + internal job_id in body + form values + files[])
      → FormRequest validates array shape/types and requires one CV; Other remains optional regardless of journey_type
      → PermanentCandidateIntakeService batch-loads files and validates Candidate ownership/database type
      → dedicated Permanent persistence writes profile/address/answers + Candidate.is_permanent atomically
          → reads/validation outside transaction; no duplicate-issue side effects
      → commit
      → MatchMakerService Permanent method → existing MM API integration (default HTTP-client timeout)
          → success: persist MM identity/status PERM
          → transient/non-retryable failure: no retry/enqueue, log/alert, return 502
```

**Biến cần verify ở implementation**:

| Biến/key | Nguồn | Ràng buộc |
|----------|-------|----------|
| Candidate ID | `auth:candidateApi` JWT | Không nhận từ body |
| `job_id` | `POST /me/jobs` response `data.id` | Nội bộ là `jobs.id`; submit body bắt buộc; xác minh có `candidate_job` cho token Candidate. Invitation `job_id` là external ID và không dùng trực tiếp ở đây |
| `branch_id`, `legal_entity_id` | CandidateJob → Job → Branch → LegalEntity | Resolve backend; chọn MM endpoint/db source và Agreement URL |
| `branch_agreement_url` | `branches.work_finder_agreement_url` | Optional; ưu tiên nếu có |
| `entity_agreement_url` | `legal_entities.work_finder_agreement_url` | Fallback khi branch URL null/rỗng |
| `agreement_url` | Backend resolver | URL cuối cùng branch > entity; không nhận URL từ form |
| `files[].file_id` | `data.id` của upload CV bắt buộc và Other tùy chọn | File phải thuộc Candidate token; row type phải khớp `files[].type`; CV là loại duy nhất dùng khi sync MM |
| `files[].type` | `data.type` từ upload response (`cv` hoặc `other`) | So sánh với row `files`; không dùng để override loại file đã lưu |
| contact/transport/recruitment answers | JSON submit | Map đúng Question category/options; lấy option keys từ data hiện hành |
| click IP/time | HTTP request/backend clock | Không nhận client-supplied values; lưu một lần trên CandidateTiming |
| sync identifiers | Candidate token + submit `job_id` + CV ID từ `files[]` | Direct call dùng CV đã resolve; không tạo sync payload mới |

## 6. Constants & Enums

- `Candidate::IS_PERMANENT` hoặc tên boolean column (`is_permanent`) không cần enum; default false.
- MM status mapping constant cho `PERM` ở `MatchMakerCandidate`; giá trị GAP và MM phải theo format hiện tại (`perm` local, `PERM` external) sau khi kiểm tra mapper.
- `File::TYPE_CV` hiện hữu; không thêm file type mới.
- `CandidateTiming` dùng field riêng cho Agreement; không tái sử dụng field KID/ToE/medical vì chúng ghi nhận sự kiện khác.
- `Candidate::JOURNEY_TYPE_BRITISH_IRISH_PASSPORT`, `JOURNEY_TYPE_SHARE_CODE`, `JOURNEY_TYPE_OTHERS` hiện hữu.
- Các MIME/extension/size cố định phải được khai báo tại config/constant dùng chung, không rải magic string/size ở validator và service.

## 7. Files cần tạo/sửa

### 7.1 Files mới

| File | Mô tả |
|------|-------|
| `database/migrations/*_add_is_permanent_to_candidates_table.php` | Thêm cờ ẩn Permanent |
| `database/migrations/*_add_work_finder_agreement_url_to_legal_entities_table.php` | Thêm URL entity |
| `database/migrations/*_add_work_finder_agreement_url_to_branches_table.php` | Thêm URL override nullable cho branch |
| `database/migrations/*_add_work_finder_agreement_click_fields_to_candidate_timings_table.php` | Thêm first-click time/IP vào bảng hiện có |
| `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php` | Config/click/submit endpoints; thin controller |
| `app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php` | Required/format validation |
| `app/Http/Resources/Api/Candidate/PermanentCandidateIntakeConfig.php` | Config response |
| `app/Http/Resources/Api/Candidate/PermanentCandidateIntakeResult.php` | Shared 200 direct-success response |
| `app/Exceptions/Api/Candidate/APIErrorException.php` | Candidate-domain API exception dùng chung, nhận error key/message và render Candidate `Status` |
| `app/Contracts/Services/PermanentCandidateIntakeServiceInterface.php` | Service contract |
| `app/Services/PermanentCandidateIntakeService.php` | Ownership, dedicated atomic profile persistence and direct MM call; failure returns immediately |
| `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php` | Legacy queue retry/failure handler retained for existing payloads |
| `database/seeders/PermanentAgreementUrlSeeder.php` | CSV-driven, update-only entity URL seeder |
| `database/seeders/data/permanent_agreement_urls.csv` | Client-provided entity ID → URL input |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | API contract/auth/validation/ownership tests |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Atomic persistence, direct success, transient/non-retryable failure and duplicate submit tests |
| `tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php` | Fallback transient retry (current fixed 3 attempts)/non-retryable 4xx/final failure/CV tests |

### 7.2 Files sửa

| File | Thay đổi dự kiến |
|------|------------------|
| `app/Models/Candidate.php` | Cast/fillable/accessor cho `is_permanent` (không thay guard thành LIVE) |
| `app/Models/LegalEntity.php` | Fillable/property cho URL Agreement |
| `app/Models/Branch.php` | Fillable/property cho URL Agreement theo branch |
| `app/Http/Requests/Api/Compliance/BranchAdd.php`, `BranchUpdate.php` | Shared request cho Admin và Compliance; nhận URL nullable khi tạo/cập nhật Branch; không bắt buộc vì entity là fallback |
| `app/Http/Resources/Api/Compliance/Branch.php`, `Branches.php`; Admin/Compliance `BranchController.php` | Shared resource cho cả hai CRUD; expose URL trong list/get/create/update response qua cùng `BranchService` |
| `app/Models/CandidateTiming.php`, `app/Repositories/CandidateTimingRepository.php`, `app/Contracts/Repositories/CandidateTimingRepositoryInterface.php` | Persist lần click đầu vào row Candidate/job hiện có; IP field mới dài 45 |
| `app/Models/MatchMakerCandidate.php` | Mapping status `PERM` |
| `app/Services/MatchMakerService.php` + `app/Contracts/Services/MatchMakerServiceInterface.php` | Thêm Permanent-specific sync/mapping; tái sử dụng API registration/contact-log attachment cấp thấp, không gọi live transfer nguyên trạng |
| `app/Http/Controllers/Api/Candidate/MeFileController.php` | CV-specific MIME/extension/size validation, các loại file khác giữ nguyên |
| `config/files.php` | CV allowlist/limit dùng chung theo quyết định cuối |
| `routes/candidate.php` | Thêm GET config, POST click, POST submit trong auth Candidate group |
| `app/Http/Kernel.php` | Không thêm response middleware riêng; giữ middleware hiện hữu |
| `app/Providers/AppServiceProvider.php` | Binding repository/service contracts |
| `database/seeders/DatabaseSeeder.php` | Đăng ký update-only seeder URL entity sau migration/entity seed; không dùng `BranchSeeder` để cập nhật URL vì CSVSeeder mặc định xóa bảng |
| `app/Services/CandidateService.php` / Candidate repositories | Filter query shared search cho Permanent nếu code impact review xác nhận; không sửa call paths nghiệp vụ background |
| Consultant/Compliance/Admin controllers/services và SMS/issues/appointments/export query files | Ẩn khỏi toàn bộ CRS staff-facing candidate surfaces; chi tiết chốt inventory ở Phase 4 trước code |
| `tests/Feature/Api/Candidate/MeFileTest.php` | CV validation allowlist/size/ClamAV response |
| Các tests cho Candidate list/search, SMS, escalated issues, appointments, detail và exports | Đảm bảo Permanent không xuất hiện ở các API thường |
| `.business-spec/backend-business-flow-spec.md` | Thêm flow đang chạy GAP-691 và deviation/runtime config notes |
| `.business-spec/backend-api-route-inventory.md` | Ghi route mới + middleware/handler |
| `.business-spec/backend-database-relationship.md` | ERD/dictionary cho cờ và Agreement timing fields trên bảng hiện có |
| `documents/Gap-API-Candidate.yaml` | Dùng native Resource/Status/JsonRequest schemas; MatchMaker failure trả 502, không còn 202/503 hoặc `queued` |
| `config/api.php` | Giữ error keys còn dùng; queue failure key không được dùng bởi Permanent intake |
| `.specs/GAP-691/GAP-691-permanent-candidate-intake.md` | Cập nhật status/API contract/implementation evidence; vẫn là tài liệu GAP-691 hợp nhất |

## 8. Các phase triển khai và phân chia agent

### Phase 0 — Contract freeze và FE mock (không sửa runtime; đã duyệt)

- Các quyết định và API contract GAP→FE ở mục 3 đã được người dùng duyệt; dùng làm baseline mock.
- FE có thể mock signup/job/file upload hiện tại và 3 API mới: GET config, POST click, POST submit.
- Enum Sourceflow và giới hạn CV chính thức vẫn deferred; không tự suy diễn giá trị cuối trong implementation.
- Exit: API contract này là baseline FE mock; sau khi triển khai và xác nhận contract, nhập phần API/implementation evidence vào tài liệu GAP-691 canonical để chỉ duy trì một task spec lâu dài.

### Phase 1 — Data foundation (Agent A; trước Phase 2/3/4) — IMPLEMENTED

**File ownership độc quyền**: migrations mới, `Candidate.php`, `CandidateTiming.php`, `CandidateTimingRepository*`, `LegalEntity.php`, `Branch.php`, shared `BranchAdd`/`BranchUpdate` requests, shared Compliance `Branch`/`Branches` resources, `BranchService*`, seeder + CSV template; không tạo model/repository/table intake hoặc click.

1. Thêm `is_permanent`, URL nullable cho entity và branch, cùng hai click fields vào `candidate_timings`; không thêm sync status/CV reference/checkbox columns.
2. Seed URL entity theo CSV bằng update-only theo entity ID; không xóa bảng, không ghi các field khác, báo rõ entity ID không tồn tại/duplicate CSV row. Branch URL được sửa qua đầy đủ hai Branch CRUD surface dùng chung service/request/resource: `GET/POST /api/admin/branches`, `GET/PUT/DELETE /api/admin/branches/{id}` và `GET/POST /api/compliance/branches`, `GET/PUT/DELETE /api/compliance/branches/{id}`. List/get/create/update response trả `work_finder_agreement_url`; delete không có payload URL. Nếu cần nạp hàng loạt branch URL thì dùng update-only seeder riêng, không dùng `BranchSeeder` mặc định xóa bảng.
3. Mở rộng CandidateTiming repository thuần data access để đọc/ghi first click; query đơn record có return type `?Model`.
4. Viết migration/model/repository/seeder tests.

**Exit**: migrate fresh/rollback, repository/Branch CRUD tests và seeder tests đạt; Candidate có `is_permanent=false` mặc định; timing row lưu được Agreement first-click time/IP; entity seeder không phá dữ liệu hiện có.

### Phase 2 — MatchMaker direct adapter + legacy queue job (Agent B; song song Phase 3 sau Phase 1) — IMPLEMENTED

**File ownership độc quyền**: `MatchMakerService.php`, `MatchMakerServiceInterface.php`, `MatchMakerCandidate.php`, `MatchMakerTransientException.php`, `MatchMakerNonRetryableException.php`, `SyncPermanentCandidateToMatchMakerJob.php`, job/service unit tests. Hai exception đặt dưới `App\Exceptions\Services`. `Candidate::MM_STATUS_PERM` do Phase 1 sở hữu; Phase 2 chỉ dùng constant đó. Không sửa routes, Candidate API controller, `AppServiceProvider.php`, hoặc Candidate list repositories.

1. Tạo method Permanent-specific: build payload theo fields GAP-691; gọi luồng Candidate registration hiện có (`Candidates/RegisterCandidate` qua `upsertCandidateToMatchMaker()`), đúng legal-entity-selected DB source. Map trước các field đã có mapping trong `MatchMakerService::getCandidateParams()` / `prepareUpsertParams()`; field không có tương đương phải để `// TODO(GAP-691): ...` ngay tại điểm build payload để bổ sung sau, không tự suy diễn mapping.

   | GAP-691 field | Mapping hiện có trong MM payload |
   |---|---|
   | `title` | `candidate.peo_title` |
   | `first_name`, `middle_name`, `last_name` | `candidate.peo_forename`, `candidate.peo_middlename`, `candidate.peo_surname` |
   | `email`, `phone_number`, `date_of_birth` | `candidate.peo_email`, `candidate.peo_other_tel`, `candidate.peo_date_birth` |
   | `address.building` + `address.street`, `town_city`, `county`, `postcode` | `candidate.peo_establish`, `candidate.peo_town`, `candidate.peo_county`, `candidate.peo_postcode` |
   | `transportation_method`, `transportation_distance` | `overview.transport_type`, `overview.travel_radius` qua Question categories hiện có |
   | `recruitment_source` | `candidate.peo_source` qua Question category hiện có |

   `contact_dates`, `contact_times`, `journey_type`, Work Finder Agreement accepted/click metadata hiện chưa có field tương đương được xác nhận trong MM payload: thêm TODO tại mapping để người dùng bổ sung sau; không gán nhầm GDPR consent hoặc RTW payload vào các field này. Không yêu cầu Permanent cung cấp dữ liệu ngoài form như interview, bank, RTW, careers/education.
2. Gửi `journey_type` và status đích `PERM` theo GAP→MM contract; nếu code hiện tại chưa có MM field tương đương cho `journey_type`, giữ TODO như bảng trên. Cập nhật local `peo_no`/status chỉ sau response thành công và map `PERM` rõ ràng.
3. Upload đúng CV được chọn qua `file_id` đã xác thực vào MM Contact Log; dùng API attachment/contact-log hiện có (`addContactLog` + `uploadToContactLog` qua `MatchMakerApiInterface`). Không gọi `saveAdditionalFiles()` nguyên trạng nếu nó upload hàng loạt file và nuốt lỗi. Nếu payload legacy chạy trong Job và upload fail thì throw custom service exception để Job retry.
4. Không gọi readiness/interview/RTW gates, RTW attachments, job/appointment `MATCHMAKER`/`FINISHED`, application pack, `LIVE` update.
5. Expose qua `MatchMakerServiceInterface` một Permanent sync method nhận Candidate/job/file IDs. Phân loại bằng custom exceptions riêng: `MatchMakerTransientException` cho timeout/connection/5xx và lỗi tích hợp tạm thời; `MatchMakerNonRetryableException` cho mọi MM 4xx, bao gồm lỗi nghiệp vụ/duplicate. Candidate intake catch hai loại này để trả 502 ngay, không enqueue; job class cũ nếu đã có payload vẫn gọi lại cùng method nhưng không tự enqueue lồng nhau.
6. Job nhận `candidate_id`, `job_id`, `file_id`; reload candidate/job/file ngoài transaction; giữ số lần thử cố định hiện tại (3) tạm thời. Chỉ retry `MatchMakerTransientException`; khi gặp `MatchMakerNonRetryableException` thì fail ngay, không tiêu hết số lần thử. `failed()` ghi failed_jobs, structured log và configured ops alert (không cập nhật sync state trong bảng nghiệp vụ).
7. Thử xử lý partial success/retry rõ: nếu MM create đã thành công mà CV/contact step fail hoặc phản hồi bị timeout, fallback retry có thể tạo duplicate; ghi nhận rủi ro, không tuyên bố exactly-once.

**Exit**: unit tests prove direct MM success → local `PERM`; Candidate intake timeout/connection/5xx và 4xx đều trả 502/no queue; legacy job vẫn phân loại CV/contact failure và không báo synced giả; không có RTW/live side effects; terminal legacy job failure vào failed jobs/log.

### Phase 3 — Candidate-facing GAP APIs + upload rule (Agent C; song song Phase 2 sau Phase 1) — IMPLEMENTED; FILE ARRAY AMENDMENT DONE

**File ownership độc quyền**: `routes/candidate.php`, các API Controller/Request/Resource/Service/Service Contract mới, `MeFileController.php`, `config/files.php`, API service binding trong `AppServiceProvider.php`, Candidate API tests và `MeFileTest.php`. Phase 3 chỉ dùng repository contracts hiện có để persist; không sửa `CandidateService`, Candidate repositories hoặc MatchMakerService/job. Nếu cần mở rộng shared persistence/repository behavior, làm thành subtask tích hợp trước Phase 4 để giữ ownership không chồng nhau.

1. Implement config endpoint: nhận query `job_id` là internal `jobs.id`; xác minh job thuộc token Candidate qua `candidate_job`; resolve URL theo branch → entity và chỉ trả `work_finder_agreement_url`; không resolve được thì trả `""`; không trả ID, URL từng cấp, required fields, journey types, trạng thái submit, profile PII hay queue status.
2. Implement click endpoint: Candidate/job ownership; ghi first-click time/IP vào CandidateTiming hiện có; không nhận URL/candidate/time/IP từ body; các click sau không ghi đè.
3. Implement submit endpoint: validate exact contract; yêu cầu đúng một file type `cv` và cho phép tối đa một file `other` tùy chọn, không ràng buộc Other theo `journey_type`; batch-load và kiểm tra file ownership/type; kiểm tra email khớp account; enforce Agreement boolean true nhưng không persist checkbox; dùng Permanent-specific persistence thay vì gọi nguyên `updatePersonalInfo()`/`updateCandidateAddress()`; không chạy duplicate checks tạo escalated issue; set `first_applied_at` nếu đang trống.
4. Tất cả reads/ownership checks hoàn tất trước transaction. Trong transaction chỉ persist Candidate, address, answers và `is_permanent=true`; commit xong mới gọi MatchMaker trực tiếp theo timeout mặc định HTTP client. Thành công trực tiếp cập nhật MM identity/status rồi trả `200`; transient/non-retryable exception không retry/enqueue, trả `502` và log/alert. Không gọi external API trong transaction và không có DB transaction bao quanh HTTP call. Repeated submit khi `is_permanent=true` trả `409` và không tạo sync attempt khác.
5. Siết upload riêng cho type `cv`; không đổi validation file khác. MIME/extension/size final lấy từ mục 10 deferred, mặc định provisional theo contract để FE mock.
6. Thêm API feature tests: no auth, foreign job/file, invalid required field/enum, false agreement, checkbox không được persist, click first-time/IP và repeated click không overwrite, URL resolve, direct success 200, transient timeout/connection/5xx → 502/no queue, non-retryable 4xx → 502/no queue, double-submit 409, file accept/reject/virus; xác nhận không phát sinh duplicate escalated issues từ profile persistence.

**Exit**: contract request/response khớp plan; Candidate data + marker persist nguyên tử trước MM call; tests không gọi MM thật và cover direct success/failure branches không queue.

### Phase 4 — Ẩn Permanent trong các Candidate list/filter trả về (điều chỉnh phạm vi theo review GAP-691) — IMPLEMENTED, SCOPE NARROWED

Chỉ thêm `is_permanent=false` vào các bộ lọc trả về Candidate collections: Candidate list/search, Escalated Issue candidate list, Appointment list và SMS eligible-recipient filter. Không áp dụng quy tắc ẩn rộng cho detail/action, lookup theo ID/IDs, aggregate/count, reports, exports hoặc campaign đã tạo.

Các lookup đặc thù chỉ được tạo để áp điều kiện Permanent đã bị xóa: `getStaffCandidateById()`, `getStaffCandidateWithAllRelations()`, `getStaffCandidatesByIds()` và `findForStaffById()`. Callers dùng lại API gốc (`find()`, `getById()`, `getByIds()`, `getCandidateWithAllRelations()`). Các kiểm tra authentication, ownership, role và branch authorization hiện hữu không đổi. Không thêm global Eloquent scope; Permanent intake và MatchMaker-specific handling giữ nguyên.

**Exit**: list/filter tests tiếp tục xác nhận Permanent không xuất hiện; lookup/detail/action theo ID hoạt động nếu các quyền hiện hữu cho phép; các flow aggregate/report/export và campaign không bị loại record chỉ do `is_permanent`.

### Phase 5 — Tích hợp, regression và living specs (Agent E / integrator; sau Phase 1–4) — COMPLETE

1. Chạy migration/seeder trên test DB; hoàn tất fixture test data mà không gọi destructive LegalEntitySeeder ngoài phạm vi.
2. Chạy API tests, new service/job tests, mọi suite đã liệt kê cho visibility/file impacts; sau đó chạy toàn bộ `./vendor/bin/phpunit` theo workspace rules.
3. Rà soát status `PERM` không được map/treated as `LIVE`; Candidate intake MatchMaker failure ghi error và trả 502 không queue; terminal legacy queue jobs ghi failed state và critical log; Slack delivery chỉ là cấu hình cần xác minh; Candidate collection filters đã chốt loại Permanent, còn ID lookup/non-filter flow vẫn hoạt động.
4. Cập nhật 3 `.business-spec` canonical files với implementation evidence, route, relationships và CODE/DATA/CONFIG/EXTERNAL/INFRASTRUCTURE deviations; không biến queue config source thành bằng chứng worker production đang chạy.
5. Cập nhật master GAP-691 plan và canonical living specs sau khi implementation được xác nhận; giữ plan theo phase đã review làm evidence lịch sử.

**Exit**: toàn bộ PHPUnit đạt; business-spec và task spec khớp code; các thay đổi người dùng đang có trước task được giữ nguyên. Webhook và alert delivery ở deployment vẫn cần được xác minh; source/test local không chứng minh các điều kiện vận hành này.

### 8.1 Ma trận song song / conflict

| Agent/Phase | Có thể chạy song song với | Không được cùng sửa |
|-------------|---------------------------|--------------------|
| Phase 1 — schema/repos/seeder | Không; prerequisite | Candidate/CandidateTiming/LegalEntity/Branch/repository/seeder files được phase khác chạm; Phase 1 thêm `Candidate::MM_STATUS_PERM` |
| Phase 2 — MM direct adapter/fallback job | Phase 3 và Phase 4 sau Phase 1 | MatchMakerService/interface/job/MatchMakerCandidate thuộc owner Phase 2; không sửa Candidate model |
| Phase 3 — GAP candidate APIs/persistence | Phase 2 sau khi chốt interface contract; Phase 4 chỉ khi không sửa shared service/repository | routes/candidate.php, intake service/request/resource, MeFileController, API service binding; không sửa shared CandidateService/repositories |
| Phase 4 — staff visibility | Phase 2 sau Phase 1; Phase 3 chỉ sau khi xác nhận không có shared-file overlap | Toàn bộ shared CandidateService/Repository + staff controller/query files; một Agent sở hữu cả phase |
| Phase 5 — integrator/tests/specs | Sau merge 1–4; test files độc quyền có thể viết song song | Không rebase/format unrelated user changes; business-spec chỉ do integrator cập nhật |

Giao kèo giữa Phase 2 và 3: Phase 2 sở hữu direct sync method và legacy job; Phase 3 gọi method sau commit, nhận custom transient/non-retryable result và trả 502 mà không dispatch job. Job đã tồn tại gọi lại cùng direct sync method và không dispatch đệ quy. Hai phase phải khóa method signature/exception contract trước khi tách branch; merge xong chạy integration tests.

## 9. Test Cases / Acceptance

| Test area | Acceptance cases |
|-----------|------------------|
| Schema | migration up/down; `is_permanent=false` default; CandidateTiming Agreement time/IP columns, IP length 45; branch/entity Agreement URL nullable; entity URL update seeder không clear/overwrite dữ liệu khác; không có intake/click tables hoặc sync/CV/consent columns |
| Branch CRUD | Cả Admin và Compliance list/create/get/update trả branch Agreement URL; delete không có URL response; null/empty branch URL cho phép fallback entity |
| Config API | auth required; only owned job; chỉ trả `work_finder_agreement_url`; resolver branch > entity, không resolve thì `""`; body không điều khiển scope |
| Click API | auth + job ownership; first click lưu backend time/IP trong CandidateTiming; không nhận spoof fields; repeated click không ghi đè |
| Submit API | mỗi required field và `journey_type` missing bị 422; `journey_type` enum hợp lệ; checkbox false rejected và giá trị checkbox không persist; email mismatch; address/answers persisted đúng nơi |
| CV | upload trả file resource ID; extension/MIME/size/ClamAV; reject wrong Candidate/file type; all non-CV upload behavior unchanged |
| GAP duplicate submit | Candidate đã `is_permanent=true` thì lần submit tiếp theo trả 409 và không dispatch job thứ hai |
| Intake files | CV item bắt buộc; `other` optional independent of journey type; duplicate/unsupported/mismatched/foreign files rejected; only CV ID reaches MM |
| MatchMaker | GAP persistence atomically commit trước HTTP; direct call theo timeout mặc định client; success cập nhật MM identity/status PERM; transient/non-retryable exception → no retry/enqueue, 502 + alert; map existing fields, TODO fields chưa có; no RTW/live/job/appointment/pack effects |
| Legacy queue job | Existing payloads only; IDs-only payload; transient retry/final failure behavior remains covered by job tests; Candidate submit does not dispatch new jobs |
| Persistence side effects | Profile/address/answers/is_permanent là một transaction write-only; `first_applied_at` set nếu trống; không gọi duplicate checks tạo escalated issue |
| Visibility | Candidate absent from từng route family đã inventory ở Phase 4; direct ID, mutation, selector và export không lộ/không thao tác như candidate thường; normal candidate unaffected; own candidate self-service và background sync still pass |
| Regression | existing signup, `POST /me/jobs`, `GET /me`, CV upload tests; Candidate search, Compliance/Admin, SMS, issues, appointments, file and export tests |
| Full suite | `./vendor/bin/phpunit` passes after implementation; no formatter/linters unless requested |

## 10. Deferred from approved task spec — giữ để xử lý sau

- Branch-specific URLs là optional override được cấu hình qua Admin/Compliance Branch CRUD. Resolver cố định branch > entity; client bảo đảm entity URL có dữ liệu; nếu resolver vẫn nhận giá trị rỗng thì API trả chuỗi `""`; không có URL brand.
- Enum labels/value cuối cùng từ Sourceflow cho các option của form (backend map theo Question/Answer values hiện có).
- CV max size/MIME final; API contract tạm ghi PDF/DOC/DOCX, 10 MiB theo đề xuất trước.
- Legacy queue worker/ops alert channel ở môi trường triển khai; Candidate submit không phụ thuộc queue fallback nữa.
- No MM idempotency/upsert: timeout có thể để lại partial MM state; không mở rộng scope hiện tại.

Các mục này không cản FE mock theo API contract; enum/file/alert delivery vẫn phải được xử lý trước release tương ứng.

## 11. Checklist trạng thái duyệt

- [x] User duyệt endpoints/fields/response contract để FE mock.
- [x] User duyệt database markers/tables và Candidate hiding scope.
- [x] User duyệt ranh giới phase/agent ownership như trên.
- [x] Các mục deferred được xác nhận là để sau, không bị diễn giải thành đã chốt.
- [x] Chưa có runtime code/migration/seed command được chạy trước approval.

## 12. Follow-up — CV PNG/JPEG upload validation (2026-10-08, DONE)

### 12.1. Request, evidence và root cause

User báo POST `/api/candidate/me/files/cv` không upload được PNG. Đây là mở rộng scope CV upload hiện hữu trong plan này, không tạo plan trùng. User approve follow-up bằng “ok” ngày 2026-10-08.

- Call chain đã trace: `routes/candidate.php` → auth candidate / lock middleware → `MeFileController::upload` → ClamAV validation → CV-specific extension/MIME/size validation → general extension allowlist → `FileService::createFile` → `FileUtility::uploadFile` / `buildFileData` → File repository create → File resource HTTP 201.
- **CONFIG deviation**: `config/files.php` hiện cho extensions PDF/DOC/DOCX/JPG/`jpge`/PNG nhưng MIME thiếu `image/png`; `jpge` là typo của `jpeg`. Trong lúc đọc, workspace bổ sung `image/jpeg`; giữ thay đổi user này.
- Read-only reproduction bằng Laravel bootstrap và `UploadedFile::fake()->image('cv.png')`, chạy đúng CV rules của Controller: MIME `image/png`, validation fails duy nhất `Mimetypes`. Không gọi ClamAV, DB, storage hay MM; chưa tái hiện authenticated HTTP request trên localhost. Curl user cung cấp không có Authorization; actual request cần Candidate Bearer token để qua auth.
- Baseline living spec SPEC-039 và API contract §3 của plan chỉ ghi PDF/DOC/DOCX; image acceptance cần docs-first synchronization. Đã đọc ba canonical living specs và trace source. Không xác minh DATA/EXTERNAL/INFRASTRUCTURE production.
- `PermanentCandidateIntakeConfig` lấy static `APPROVED_DOCUMENTS`, không expose `files.cv`; không tự thêm response fields. Không cần migration, thay đổi Service/Repository/route hoặc MM workflow.

### 12.2. Phase 1 — API docs trước implementation

**Input/dependency**: explicit approval cho follow-up này; kiểm tra instructions và git state của `~/projects/crs-api-docs`, preserve unrelated changes. API docs assessment: **affected** do CV upload allowlist mở rộng.

**Owned files**:

- `~/projects/crs-api-docs/docs/api/candidate/post-me-files-type.md`: ghi type `cv` chấp nhận PDF/DOC/DOCX/PNG/JPG/JPEG; MIME PDF/Word/`image/png`/`image/jpeg`; multipart field `file`, limit 10 MiB, ClamAV, Candidate auth, candidate-level CV không cần Gap-Job-ID. Request example PNG dùng Bearer placeholder. Success giữ HTTP 201 và top-level File resource; validation giữ HTTP 400 / `wrongParameter` theo source Status contract, có example MIME/size rejection.
- `~/projects/crs-api-docs/docs/flows/permanent-intake.md`: cập nhật CV allowlist nếu trang đang mô tả rule này; không sửa các workflow khác.
- Nếu docs có canonical OpenAPI cho rule CV này, trace source thật và đồng bộ cùng task; ghi exact path trong execution evidence trước implementation. Page hiện chỉ reference `documents/Gap-API-Candidate.yaml`, không coi reference là bằng chứng file tồn tại trong docs repo.

**Output/acceptance**: request/schema/examples/errors nhất quán, planned contract đánh dấu chưa deploy theo convention của docs repository; không tuyên bố deployment.

**Gate**: docs checks theo repo + `npm run build`; stage chỉ task-owned changes, commit và normal push remote `main` (đã được workspace rules authorize). Ghi actual paths/diff, validation, commit SHA và successful main push ở §12.5. Phase 2 chỉ bắt đầu khi gate PASS; không PASS nếu validation/commit/push bị block. Không commit/push backend.

### 12.3. Phase 2 — Minimal fix và verification

**Input/dependency**: Phase 1 PASS; đọc lại relevant debug skill và current config trước edit để giữ concurrent user changes.

**File ownership / implementation**:

- `config/files.php`: thêm `image/png` trong CV MIME allowlist; sửa duy nhất `jpge` → `jpeg`; giữ image/jpeg, PDF/Word, size 10240 KiB và allowlist file types khác.
- `tests/Feature/Api/Candidate/MeFileTest.php`: review existing CV upload tests; thêm real image PNG/JPG/JPEG datasets qua production HTTP route, auth, fake storage; assert 201/File metadata/ownership/stored bytes. Regression reject unsupported MIME và over-limit without file row/storage writes; giữ existing PDF coverage. Không thêm Repository unit tests.
- Review `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` và intake/MM Service tests cho CV contract assumptions; chỉ update/add nếu assertion hoặc workflow thực sự bị ảnh hưởng. Upload regression không gọi MM thật.
- `.business-spec/backend-business-flow-spec.md`: cập nhật current CV allowlist SPEC-009/039 sau implementation, kèm evidence; route inventory/database relationship assessment N/A vì không đổi routes/schema/relationships.
- Plan này: actual evidence và self-check. Không sửa Controller/Service/Repository nếu config đủ giải quyết lỗi.

**Gate/acceptance**: PNG/JPG/JPEG được upload CV thành công, PDF/Word không regression, MIME sai/over-limit vẫn bị reject; response/error/auth/ClamAV semantics giữ nguyên. Chạy affected MeFile và Permanent intake suites cùng relevant suites phát hiện qua test audit, sau đó full `./vendor/bin/phpunit`; report failures theo root cause, không sửa unrelated code để xanh. Không formatter/linter/migration, không backend deploy.

### 12.4. Approval gate

- [x] User approve follow-up CV PNG/JPEG contract và docs-first workflow.
- [x] Phase 1 docs validation + commit + push main PASS.
- [x] Phase 2 affected/full tests PASS và self-check against plan.

### 12.5. Execution evidence

- Phase 1 **PASS**: cập nhật `~/projects/crs-api-docs/docs/api/candidate/post-me-files-type.md` và `docs/flows/permanent-intake.md` (63 added lines). Markdown pages là source of truth theo README; không có canonical OpenAPI YAML trong docs repo, reference `documents/Gap-API-Candidate.yaml` là historical source. Không sửa historical OpenAPI/backend YAML ngoài plan ownership.
- `npm run build` và `git diff --check` PASS; log `/private/tmp/gap-691-cv-docs-build.log`. Docs commit `d245e111a336986a5bc6a7d0dd0d092dcd39244e`, normal push `origin main` thành công (`7f91a13..d245e11`). Planned contract ghi pending backend verification, deployment UNVERIFIED. Không có additional docs checks/AGENTS trong docs repo.
- Trước Phase 2, user workspace đã thêm cả `image/jpeg` và `image/png` vào CV MIME; giữ nguyên user edits. Agent chỉ cần sửa extension typo và verify current behavior/test coverage. Shared production config/logging/Resource/provider và các unrelated changes không thuộc scope.
- Phase 2 implementation: sửa một CV extension `jpge` → `jpeg`; thêm chín Feature datasets vào MeFile (PNG/JPG/JPEG, DOC/DOCX compatibility, PNG đúng 10240 KiB; GIF/text giả PNG/PNG 10241 KiB rejected). Happy paths kiểm tra top-level File metadata, candidate ownership, candidate-level job ID và storage bytes; invalid cases kiểm tra 400/1006 và không ghi storage/file row. MIME image/text được detect từ bytes bằng `mime_content_type` thay vì fake MIME theo extension; size boundaries dùng Laravel fake reported size. Existing PDF test giữ nguyên.
- Initial MeFile run 17 tests có một fixture failure ở text giả PNG: Laravel fake báo MIME theo filename, nên fake được nhận như PNG. Sửa fixture để dùng detected content MIME, không sửa production validator. Affected rerun PASS **122 tests / 7,020 assertions**, 37.996s: MeFile 17, Intake Feature 68, Compliance Files 4, Consultant Files 11, MM Unit 5, Intake Service 12, FileUtility 5. Reports `/private/tmp/gap-691-cv-affected.{log,xml}`. Reviewed existing CV tests ở các suites này; không có extension/MIME assertions cần update ngoài MeFile, không tạo Repository unit tests.
- Real user file read-only check: `/Users/nexusfrontiertech/Downloads/image-removebg-preview (4).png`, MIME `image/png`, 95,738 bytes, CV validation PASS và no failed rules. Không upload file này, không gọi real DB/storage/ClamAV/MM hoặc authenticated localhost endpoint.
- Living spec SPEC-009/039 đã đồng bộ allowlist và docs commit; route/schema/relationship changes **N/A**. Full default `./vendor/bin/phpunit` PASS, không override LOG_CHANNEL.
- Trong lúc verification, backend config/tests được commit ngoài agent tại `714951ec` (`#691: update mime type img for cv upload`). Agent không stage/commit/push backend hoặc sửa unrelated user changes. Source config và tests vẫn chứa approved fix/coverage; full run đang kiểm tra source này.
- Final full gate **PASS: 600 tests / 9,049 assertions**, 02:49.254, default environment/config, zero failures/errors. Reports `/private/tmp/gap-691-cv-full.{log,xml}`. `git diff --check` PASS; docs repository clean sau successful main push. Final self-check: approved allowlist/MIME/size/response/ownership/storage acceptance covered; no Controller/Service/Repository/schema/route changes, no formatter/linter, no manual migrations or production DB/ClamAV/MM calls. PHPUnit dùng SQLite in-memory migrations/seed theo existing test setup; external/storage boundaries giữ test conventions.
- Deployment không thuộc scope và chưa xác minh; request localhost cần valid Candidate token và middleware/ClamAV/storage availability. File user thật pass CV validator; production HTTP upload chưa chạy. Task complete ở implementation/tests/docs synchronization scope; không claim deployment hoặc external integrations verified.
