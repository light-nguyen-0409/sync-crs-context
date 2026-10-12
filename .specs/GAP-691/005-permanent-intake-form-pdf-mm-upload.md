# SPEC: GAP-691 — Permanent intake form PDF upload và đồng bộ MatchMaker

> **Trạng thái**: `DONE` — implemented and verified after user approval.
> **Ngày tạo**: 2026-10-07
> **Author**: Codex
> **Related**: `004-gphl-shared-entity-agreement-template.md`, `GAP-691-permanent-intake-files-array.md`, `GAP-691-agreement-upload-response-alignment.md`

## 1. Tổng quan

Flow Permanent intake mới cần FE export màn hình form đã hoàn thành thành PDF,
upload PDF đó trước khi submit, rồi truyền File ID cùng CV và Work Finder
Agreement. File form phải được lưu trong `files` theo Candidate/Job và gửi sang
MatchMaker bằng cùng contact-log/attachment flow đang dùng cho Agreement.

Đồng thời, production config hiện đã bỏ toàn bộ branch mapping cho Work Finder
Agreement/Hawk3. Test production mapping phải phản ánh `branches = []`; việc
test trực tiếp Blade Hawk3 vẫn có thể dùng config override trong test và không
được hiểu là thêm mapping production.

**Giả định contract**:

- “API get agreement” được hiểu là endpoint hiện tại
  `POST /api/candidate/me/permanent-intake/work-finder-agreement`; route không
  đổi thành GET.
- Endpoint Agreement chỉ yêu cầu `job_id`. FE không cần truyền các trường
  candidate/intermediary như trước. Các field optional hiện tại được giữ để
  backward-compatible với caller cũ; khi không truyền, Service dùng Candidate
  đã xác thực và address đã lưu làm fallback hiện có.
- Tên File type đề xuất là `File::TYPE_PERMANENT_CANDIDATE_FORM` với value
  `permanent_candidate_form`. Nếu business muốn tên khác, cần chốt trước khi
  implementation.

## 2. Database / data contract

Không tạo migration, bảng hoặc quan hệ mới. Reuse bảng `files` hiện có:

- Thêm public constant File type `permanent_candidate_form`.
- Đăng ký type trong `File::getAllFileTypes()` để Candidate upload/list nhận
  diện type.
- Không thêm type vào `getCandidateAssociatedFileTypes()` vì form gắn với một
  Job và upload phải dùng `Gap-Job-ID` header, giống các file job-scoped.
- Row form lưu `candidate_id`, `job_id`, storage `url`, original filename và
  status hiện có; không tạo bảng liên kết hoặc cột sync status.

## 3. API Contract

### 3.1. Upload PDF form

Giữ endpoint upload file hiện có:

```http
POST /api/candidate/me/files/permanent_candidate_form
Authorization: Bearer <candidate_token>
Gap-Job-ID: <internal_job_id>
Content-Type: multipart/form-data
```

Request có field `file`. File form phải là PDF; response giữ Candidate File
resource top-level và HTTP `201`. File được lưu job-scoped theo `Gap-Job-ID`.

### 3.2. Generate Work Finder Agreement

```http
POST /api/candidate/me/permanent-intake/work-finder-agreement
```

Request tối thiểu:

```json
{
  "job_id": 501
}
```

`job_id` là internal `jobs.id` và phải thuộc Candidate hiện tại. Không thay
đổi response File resource, status, error contract hoặc việc Agreement được
persist trước khi submit. FE không còn phải gửi dữ liệu form để generate.

### 3.3. Submit Permanent intake

`POST /api/candidate/me/permanent-intake` giữ response và các field profile
hiện có, nhưng `files` đổi thành đúng ba item, không phụ thuộc `journey_type`:

```json
{
  "files": [
    { "file_id": 101, "type": "cv" },
    { "file_id": 102, "type": "work_finder_agreement" },
    { "file_id": 103, "type": "permanent_candidate_form" }
  ]
}
```

Rules:

- `files` bắt buộc, exact size `3`; mỗi `file_id` và `type` distinct.
- Phải có đúng một CV, một Work Finder Agreement và một Permanent Candidate
  Form; không chấp nhận `other` hoặc type khác.
- Mọi row phải thuộc Candidate hiện tại và persisted DB type phải khớp type FE.
- Agreement và Form phải có `job_id` đúng với request; storage object phải tồn
  tại trước khi ghi profile.
- CV tiếp tục là file dùng cho CV upload MM; Agreement và Form đều được truyền
  vào MM sync.
- Validation/ownership failure không được ghi profile/address/answers,
  dispatch event hoặc gọi MatchMaker.

### 3.4. MatchMaker sync contract

Mở rộng contract hiện có để truyền thêm Form File ID sau Agreement File ID:

```php
syncPermanentCandidate(
    int $candidateId,
    int $jobId,
    int $cvFileId,
    ?int $agreementFileId = null,
    ?int $permanentFormFileId = null
): void;
```

Event, listener và queued Job truyền cùng ID thứ năm. Payload cũ không có
Agreement/Form ID vẫn được giữ tương thích cho legacy job/caller; submit mới
luôn dispatch đủ ba file IDs.

Sau khi RegisterCandidate thành công, MatchMaker sync phải upload theo thứ tự:

1. CV qua contact log/attachment hiện tại.
2. Work Finder Agreement qua contact log/attachment hiện tại.
3. Permanent Candidate Form qua cùng helper, với log metadata và filename
   prefix riêng để phân biệt document.

Lỗi upload Form dùng cùng phân loại `MatchMakerNonRetryableException` /
`MatchMakerTransientException` như CV/Agreement. Chỉ cập nhật local MM identity
và `is_permanent` sau khi cả ba upload thành công.

## 4. Business Logic / Service Layer

1. `MeFileController::upload()` nhận type mới, yêu cầu `Gap-Job-ID` theo cơ chế
   job-scoped hiện tại và validate PDF riêng cho Form; không thay đổi flow CV,
   Agreement hoặc các type khác.
2. `PermanentCandidateIntakeRequest` dùng named constants cho exact file count
   và allowlist ba type.
3. `PermanentCandidateIntakeService::submit()` batch-load ba File IDs bằng một
   repository call, map in-memory theo ID rồi kiểm tra ownership/type/job/storage
   trước các read tiếp theo và trước transaction. Không query DB trong loop.
4. Transaction chỉ giữ các writes profile/address/answers như hiện tại. Sau
   commit dispatch event với CV, Agreement và Form IDs; không gọi generate
   Agreement trong submit.
5. `MatchMakerService::syncPermanentCandidate()` validate Form record trước khi
   gọi external; reuse `uploadPermanentFileToMatchMaker()` cho Form, bổ sung
   constants log subject/text/prefix/failure message, không tạo Service mới.
6. Khi branch mapping production rỗng, Agreement generation phải trả lỗi
   template-not-found nếu entity cũng không map; test trực tiếp Hawk3/GPHL
   phải dùng config override cục bộ, không sửa config production trong task.

## 5. Data Origin & Call Chain

### 5.1. Form PDF

```text
FE export màn hình form thành PDF
  → POST /candidate/me/files/permanent_candidate_form + Gap-Job-ID
  → MeFileController::upload()
  → FileService::createFile()
  → FileUtility::uploadFile() + FileRepository::create()
  → File resource trả `id`
```

`file_id` submit lấy từ response upload; `type` là File type cố định và được
đối chiếu lại với row DB, không tin type do FE gửi.

### 5.2. Submit và MM

```text
FE gửi files[cv, agreement, permanent_candidate_form]
  → PermanentCandidateIntakeRequest::validated()
  → PermanentCandidateIntakeController::submit()
  → PermanentCandidateIntakeService::submit()
  → FileRepository::allByIds() + ownership/type/job/storage checks
  → transaction ghi GAP profile/address/answers
  → PermanentCandidateSubmittedEvent
  → SyncPermanentCandidateToMatchMakerListener
  → MatchMakerService::syncPermanentCandidate()
  → RegisterCandidate
  → upload CV + Agreement + Permanent Form qua contact logs
  → cập nhật local MM identity/status và is_permanent
```

### 5.3. Agreement

```text
POST .../work-finder-agreement {job_id}
  → WorkFinderAgreementRequest::validated()
  → PermanentCandidateIntakeService::generateWorkFinderAgreement()
  → authenticated Candidate + CandidateAddress + Job/Branch mapping
  → Blade/PDF → storage → FileRepository → Candidate File resource
```

Không giả định FE truyền candidate/address/intermediary; các field optional cũ
nếu có vẫn đi qua validation hiện tại và không làm thay đổi ownership.

## 6. Constants / fixed values

- `File::TYPE_PERMANENT_CANDIDATE_FORM = 'permanent_candidate_form'`.
- `PermanentCandidateIntakeRequest::REQUIRED_FILE_COUNT = 3` và allowlist dùng
  `File::*` constants.
- `MatchMakerService` constants cho Form contact log action/subject/text,
  filename prefix và failure message; không hardcode trong method.
- Reuse `File::STATUS_UPLOADED`, PDF config extension/MIME config,
  `File::TYPE_CV`, `File::TYPE_WORK_FINDER_AGREEMENT` và existing MM exception
  classes.

## 7. Files cần sửa

| File | Thay đổi |
|---|---|
| `app/Models/File.php` | Thêm Form type và allowlist all-file-types; giữ job-scoped behavior. |
| `app/Http/Controllers/Api/Candidate/MeFileController.php` | Validate PDF khi upload Form type. |
| `app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php` | Exact 3 files và allowlist CV/Agreement/Form. |
| `app/Services/PermanentCandidateIntakeService.php` | Batch validate Form file, dispatch Form ID, log context; giữ Agreement job-only caller behavior. |
| `app/Events/Definitions/PermanentCandidateSubmittedEvent.php` | Thêm optional Form File ID. |
| `app/Events/Listeners/SyncPermanentCandidateToMatchMakerListener.php` | Forward Form File ID. |
| `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php` | Forward Form File ID và structured failure context. |
| `app/Contracts/Services/MatchMakerServiceInterface.php` | Freeze extended sync signature. |
| `app/Services/MatchMakerService.php` | Validate/upload Form cùng contact-log flow; constants và error mapping. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Production branch mapping empty; Agreement job-only; upload/submit 3 files; invalid ownership/type/job/PDF cases; MM mock receives all IDs. |
| `tests/Feature/Api/Candidate/MeFileTest.php` | Cover new job-scoped PDF upload type and missing header/invalid PDF behavior nếu chưa được bao phủ qua intake test. |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Cover batch lookup, Form validation and event args. |
| `tests/Unit/Services/MatchMakerPermanentSyncTest.php` | Cover third attachment, metadata/order, failure cleanup and no local update on Form failure. |
| `tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php` | Cover extended job payload and legacy compatibility. |
| `documents/Gap-API-Candidate.yaml` | Document new File type/upload header, job-only Agreement request and three-file submit schema. |
| `.business-spec/backend-business-flow-spec.md` | Update SPEC-039 current submit/file/MM flow and current empty branch mapping. |
| `.business-spec/backend-database-relationship.md` | Record new `files.type` business value and job-scoped form semantics if required by living schema docs. |
| `.specs/GAP-691/005-permanent-intake-form-pdf-mm-upload.md` | Execution evidence, test gates and final self-check. |

Không sửa migration, routes, response Resource, MatchMaker API interface hoặc
config mapping production ngoài việc phản ánh config đã được user chỉnh.

## 8. Test Cases / Acceptance

- Production mapping assertion: `work_finder_agreement.branches` là `[]`; không
  còn test giả định branch Hawk3 được map mặc định.
- Agreement endpoint chạy thành công chỉ với `job_id`; không yêu cầu FE gửi
  candidate/address/intermediary fields; template resolver vẫn được kiểm tra
  bằng config override riêng khi cần.
- Candidate upload Form PDF có `Gap-Job-ID` trả 201, tạo row đúng candidate/job
  và `type`; thiếu header, non-PDF hoặc type không hợp lệ bị từ chối.
- Submit thành công với CV + Agreement + Form; Service dispatch/MM mock nhận
  đúng ba IDs; `is_permanent` chỉ true sau khi MM hoàn tất cả ba upload.
- Submit thiếu Form, duplicate type/ID, sai persisted type, foreign file, sai
  job hoặc missing storage bị từ chối trước writes/MM.
- MatchMaker unit test xác nhận contact-log metadata, attachment filename,
  thứ tự CV → Agreement → Form, temp-file cleanup và không update candidate khi
  Form upload lỗi.
- Legacy queued job/caller không truyền Form ID vẫn giữ hành vi tương thích đã
  có; không thêm repository unit test.
- Chạy PHP syntax, affected Feature/Service/Job/MM suites, full
  `./vendor/bin/phpunit` và `git diff --check`; không formatter/linter/migration.

## 9. Approval gate

- [x] User xác nhận tên type đề xuất `permanent_candidate_form`.
- [x] User xác nhận Agreement endpoint chỉ cần `job_id` và giữ optional fields
  cũ cho backward compatibility.
- [x] User approve plan trước khi sửa implementation/test/docs.

## 10. Implementation / Self-check

- Added job-scoped `permanent_candidate_form` type; PDF content-type validation uses the existing upload validator and ClamAV flow.
- Submit validates exactly CV/Agreement/Form, batch-loads records and verifies Form ownership/type/job/storage before profile writes. Form ID reaches the synchronous MM listener and optional legacy job contract.
- MM reuses the existing contact-log attachment helper, uploads Form after CV/Agreement, cleans temporary downloads on success/failure and updates local MM state only after all uploads complete.
- Existing job-only Agreement calls remain supported; existing optional candidate/intermediary inputs are preserved. Production empty branch mapping is asserted while explicit test mappings retain template priority/Hawk3 coverage.
- Canonical living spec had CODE/CONFIG drift: old `legal_entity` Blade/two-logo Tech and old branch/entity mappings. Added current-source correction under SPEC-039. DATA/EXTERNAL/INFRASTRUCTURE production remain unverified; tests use local storage/mocked MM.
- Affected Feature/Service/MM/Job suite PASS: **93 tests / 6,854 assertions**. New negative PDF fixture uses a real non-PDF upload; Laravel fake files report MIME from their requested filename and cannot verify spoofed extensions reliably.
- Syntax checks, OpenAPI YAML parse and `git diff --check` PASS. No migrations or formatting commands run.
- Final full `./vendor/bin/phpunit` PASS: **591 tests / 8,995 assertions** (02:09.443).
