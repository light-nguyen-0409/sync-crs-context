# SPEC: GAP-722 — Chặn IDOR khi cập nhật trạng thái file candidate

> **Trạng thái**: `IMPLEMENTING`
> **Ngày cập nhật**: 2026-10-12
> **Author**: Codex

---

## 1. Tổng quan

Sửa lỗi IDOR ở endpoint candidate cập nhật trạng thái file. Hiện tại endpoint nhận file ID rồi gọi `FileService::changeFileStatus()`, trong đó repository lookup chỉ theo ID nên candidate đã đăng nhập có thể cập nhật file của candidate khác hoặc file thuộc job khác.

Phạm vi implement là route đang tồn tại trong source: `PUT /api/candidate/files/{id}/status`. Jira ghi `/api/candidate/me/files/{fileId}/status`, nhưng route thực tế và route inventory đều xác nhận path không có `/me`.

**Yêu cầu gốc**: Jira `GAP-722` — `[Security] Fix candidate file status IDOR`.

### Revision 2026-10-12 — exact file scope theo user review

- Không thêm giới hạn `file.type` trong phạm vi revision này.
- Candidate file lookup phải match chính xác cả ba điều kiện: `files.id`, authenticated `candidate_id` và `files.job_id` bằng đúng job context đã xác minh.
- Không dùng `getFileByJobIdAndId()` cho status update vì method này tự động mở rộng job scope thành `[job_id, 0]`.
- Bổ sung named repository lookup `findByIdAndCandidateIdAndJobId()` với return type `?\Illuminate\Database\Eloquent\Model`; nếu không tìm thấy thì trả `null`.
- `job_id = 0` chỉ match khi caller thực sự truyền context `0`; không tự động fallback từ job thật về candidate-level file. Ảnh hưởng tới các flow candidate-level phải được ghi trong test/acceptance trước khi implement.

### Baseline và deviation đã trace

- `CODE`: `routes/candidate.php` đặt route dưới middleware `auth:candidateApi`, `checkCandidateLockEdit`, `detectJobForCandidate`.
- `CODE`: `DetectJobForCandidate` xác minh candidate có job và đặt job hợp lệ vào request attribute `job_id`; khi candidate có nhiều job, `Gap-Job-ID` là bắt buộc.
- `CODE`: `MeFileController::updateStatus()` hiện chỉ truyền `$id` và `$status` vào global `changeFileStatus()`; không truyền candidate hoặc job context.
- `CODE`: `FileService::changeFileStatus()` gọi repository `find($fileId)` rồi update bản ghi, không kiểm tra ownership/job.
- `CODE`: `MeFileStatusUpdate` đã validate `status` là string và thuộc candidate self-service allowlist; controller vẫn giữ guard legacy cho `approved`.
- `CODE`: `FileService::changeFileStatus()` còn được dùng bởi GBG, consultant và compliance; không thay đổi method global này trong GAP-722.
- `CODE`: Các flow đọc/xóa candidate file hiện có thể cho phép candidate-level `job_id = 0`; riêng GAP-722 status update sẽ dùng exact `candidate_id` + `job_id` theo revision đã chốt, không tự mở rộng job scope.
- `DATA`: Chưa kiểm tra dữ liệu production/orphan file.
- `CONFIG`, `EXTERNAL`, `INFRASTRUCTURE`: Không tham gia trực tiếp vào endpoint; deployment/production state chưa xác minh.

---

## 2. Database Design

N/A — không thay đổi schema, migration, index hoặc relationship.

---

## 3. API Contract

### 3.1. Endpoint

```text
PUT /api/candidate/files/{id}/status
```

**Auth**: Required, guard `candidateApi`.

**Middleware**: `api`, `auth:candidateApi`, `checkCandidateLockEdit`, `detectJobForCandidate`.

**Route param**: `id` là file ID.

**Job context**: middleware xác minh `Gap-Job-ID` thuộc candidate rồi đặt giá trị đã xác minh vào request attribute `job_id`. Controller/service không tin candidate ID từ request body và không dùng raw header để bypass middleware.

### 3.2. Request

```json
{
    "status": "read"
}
```

Status candidate self-service được phép gửi là tập hiện đã được dùng bởi `MeFileStatusUpdate::fakeArray()`:

- `uploaded`
- `released`
- `read`
- `signed`

`approved`, `rejected`, `expired` và giá trị ngoài tập trên không được ghi qua endpoint candidate. FormRequest phải reject trước khi service update; service scoped cũng phải giữ defensive validation để không phụ thuộc duy nhất vào HTTP caller.

Jira yêu cầu validate permitted status transitions. Source hiện không có state-transition matrix (source status → destination status); vì vậy plan này chốt policy an toàn ở mức candidate destination allowlist, không tự suy diễn thứ tự transition chưa có bằng chứng. Nếu BA/owner yêu cầu state machine có thứ tự, phải bổ sung ma trận vào plan trước Phase 2.

### 3.3. Scope và response

- File hợp lệ phải khớp đồng thời `id`, authenticated `candidate_id` và job context đã middleware xác minh.
- File hợp lệ phải có `files.job_id` bằng đúng job context đã xác minh. Không tự động thêm `File::CANDIDATE_LEVEL_JOB_ID` (`0`) vào filter khi context là job khác.
- File của candidate khác, file của job khác, hoặc file không tồn tại đều trả cùng lỗi not-found hiện dùng cho candidate file lookup, không tiết lộ bản ghi có tồn tại hay không.
- Thành công giữ response File hiện tại và HTTP 200.
- Status không hợp lệ trả validation error hiện hành; không có write.

### 3.4. API docs impact

Đây là thay đổi API contract ở validation, authorization scope và error behavior dù không đổi method/path. Bắt buộc thực hiện docs-first trước backend implementation.

Phase 1 phải cập nhật và validate tối thiểu:

- `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/candidate/put-files-id-status.md`
- `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/path-parameter-values.md` nếu phần file status dùng chung cần phân biệt candidate self-service allowlist với staff status values.

Docs phải ghi rõ route thực tế, `Gap-Job-ID`/job resolution, candidate status allowlist, ownership scope, response not-found cho out-of-scope file, validation error và ví dụ request/response. Contract mới phải được đánh dấu `NOT YET DEPLOYED` theo convention của docs repo cho tới khi backend deploy.

Docs validation gate: chạy build/validation hiện có của `crs-api-docs` (tối thiểu `npm run build` nếu dependencies đã sẵn sàng), chỉ stage file thuộc GAP-722, commit và push lên remote `main`. Plan sau đó phải ghi actual diff, validation result, commit SHA và push result. Repo docs hiện có thay đổi không liên quan trên branch `develop`; phải giữ nguyên, không stage hoặc overwrite các file đó.

---

## 4. Business Logic (Service Layer)

### 4.1. Call chain

```text
PUT /api/candidate/files/{id}/status
  → auth:candidateApi resolves authenticated Candidate
  → DetectJobForCandidate validates candidate/job membership and sets request attribute job_id
  → MeFileStatusUpdate validates status
  → MeFileController reads auth candidate ID + request attribute job_id + route file ID
  → FileService scoped candidate status method
  → FileRepository exact lookup by id + candidate_id + current job_id
  → update only the scoped File model
  → File resource / notFound response
```

### 4.2. Implementation design

- Thêm method scoped riêng trong `FileServiceInterface`/`FileService`, ví dụ `changeFileStatusByCandidateIdAndJobId(int $candidateId, int $jobId, int $fileId, string $status): ?File`.
- Bổ sung `FileRepositoryInterface::findByIdAndCandidateIdAndJobId()` và implementation tương ứng; query thuần dùng đúng ba cột `id`, `candidate_id`, `job_id`, return type `?\Illuminate\Database\Eloquent\Model`.
- Method scoped trong `FileService` dùng named repository lookup exact nêu trên, sau đó update đúng model đã lookup bằng `fileRepository->update()`. Không gọi `getFileByJobIdAndId()` và không gọi lại global `find($fileId)` trong candidate path.
- Controller lấy candidate từ `auth()->user()` và job từ `$request->get('job_id')`, xử lý `null` result bằng response not-found hiện hành trước khi tạo Resource.
- Giữ nguyên `changeFileStatus($fileId, $status)` cho GBG/consultant/compliance/internal callers; không mở rộng security boundary của task sang các actor khác.
- FormRequest dùng cùng nguồn constants/helper với service để tránh magic strings và mismatch giữa HTTP validation với defensive service validation.
- Không dùng transaction cho một update đơn lẻ; không có query trong loop.
- Repository method mới là bắt buộc vì lookup hiện có không đáp ứng exact job scope; method phải là named query theo convention và single-record return type `?\Illuminate\Database\Eloquent\Model` trong contract/implementation.

### 4.3. Business rules

1. Candidate ID chỉ đến từ authenticated candidate.
2. Job ID chỉ đến từ request attribute do `DetectJobForCandidate` đặt sau khi membership được xác minh.
3. File ID là route parameter; không dùng file ID để suy ngược ownership rồi update global.
4. Candidate chỉ được yêu cầu các status `uploaded`, `released`, `read`, `signed`.
5. `approved`, `rejected`, `expired` chỉ được xử lý bởi các flow staff/system hiện hữu, không đi qua candidate self-service method.
6. File ngoài candidate/job scope được xử lý như not-found và không làm thay đổi DB.

### 4.4. Side effects

Chỉ update `files.status`; không gọi storage, external API, event, mail hoặc queue.

---

## 5. Data Origin & Call Chain Verification

| Giá trị | Nơi dùng | Nguồn cung cấp | Trạng thái |
|---|---|---|---|
| Candidate ID | Controller → Service | `auth()->user()->id`, sau `auth:candidateApi` | ✅ Đã trace |
| Job ID | Controller → Service | `$request->get('job_id')`, do `DetectJobForCandidate` set sau membership check | ✅ Đã trace |
| File ID | Controller → Service | `{id}` route parameter | ✅ Đã trace |
| Requested status | FormRequest → Controller → Service | JSON body, validated bởi `MeFileStatusUpdate` | ✅ Đã trace và implement |
| File owner/job | Service lookup | `files` query exact với `id`, candidate ID và job ID | ✅ Implemented; regression tests pass |
| File response | Controller → Resource | Result từ scoped service | ✅ Thiết kế; null phải map not-found |

---

## 6. Constants & Enums

- Tái sử dụng `File::CANDIDATE_LEVEL_JOB_ID` và các status constants hiện có.
- Bổ sung một nguồn dùng chung cho candidate self-service status allowlist trong `File` (public const array hoặc public helper trả về danh sách từ các status constants); FormRequest và Service phải dùng cùng nguồn.
- Không hardcode `uploaded`, `released`, `read`, `signed`, `approved`, `rejected`, `expired` trong Controller/Service.
- Không tạo transition matrix mới nếu chưa có quyết định nghiệp vụ về source → destination; nếu được yêu cầu, đặt matrix thành constant có tên và test từng nhánh.

---

## 7. Files cần tạo/sửa

### 7.1. Docs-first Phase 1 — repo `/Users/nexusfrontiertech/projects/crs-api-docs`

| File | Thay đổi |
|---|---|
| `docs/api/candidate/put-files-id-status.md` | Cập nhật contract status, request allowlist, `Gap-Job-ID`, scope, success/not-found/validation responses; đánh dấu planned contract chưa deploy |
| `docs/api/path-parameter-values.md` | Chỉ sửa nếu cần làm rõ candidate self-service allowlist khác status values dùng cho staff/system |

Phase 1 không sửa backend code và không stage các thay đổi unrelated đang có trong docs repo.

### 7.2. Backend Phase 2

| File | Thay đổi |
|---|---|
| `app/Models/File.php` | Cung cấp constant/helper allowlist status candidate self-service từ status constants hiện có |
| `app/Http/Requests/Api/Candidate/MeFileStatusUpdate.php` | Validate `status` là string và thuộc candidate allowlist |
| `app/Contracts/Repositories/FileRepositoryInterface.php` | Khai báo exact lookup `findByIdAndCandidateIdAndJobId()` |
| `app/Repositories/FileRepository.php` | Implement query exact theo `id`, `candidate_id`, `job_id` |
| `app/Contracts/Services/FileServiceInterface.php` | Khai báo method update status có candidate/job/file scope |
| `app/Services/FileService.php` | Implement scoped lookup qua exact repository method + defensive status rule + update model đã scope; giữ nguyên method global cho caller khác |
| `app/Http/Controllers/Api/Candidate/MeFileController.php` | Truyền authenticated candidate ID và request attribute `job_id`; map scoped miss về not-found |
| `tests/Feature/Api/Candidate/MeFileTest.php` | Regression cross-candidate, cross-job, same-candidate happy path, invalid status và no-write |
| `tests/Unit/Services/FileServiceTest.php` | Test scoped repository lookup/update và no-update khi ngoài scope; chỉ test business logic Service |
| `.business-spec/backend-business-flow-spec.md` | Sau khi implementation/test pass, cập nhật SPEC-009 phản ánh candidate status update được scope và allowlist; ghi evidence/date |

Không sửa `routes/candidate.php` vì route/middleware hiện tại đã đúng phạm vi task.

---

## 8. Test Cases & Verification Gates

### 8.1. Feature tests

| Case | Kỳ vọng |
|---|---|
| Candidate A gửi file ID của candidate B | HTTP not-found hiện hành; status file B giữ nguyên |
| Candidate gửi file thuộc job B nhưng context đã xác minh là job A | HTTP not-found; status không đổi |
| Candidate cập nhật file có `job_id` khác job context | HTTP not-found; status không đổi |
| Candidate cập nhật file candidate-level có `job_id = 0` trong context job thật | HTTP not-found; status không đổi theo exact-match policy |
| Candidate cập nhật file thuộc đúng job context | HTTP 200; response trả đúng File status |
| Candidate gửi `approved`, `rejected`, `expired` hoặc arbitrary status | Validation failure; không ghi DB |
| Candidate nhiều job không gửi `Gap-Job-ID` | Giữ behavior middleware hiện tại: reject trước controller |
| Candidate không có auth hợp lệ | Giữ behavior auth hiện tại |

### 8.2. Service tests

- Scoped method gọi repository named lookup đúng ba điều kiện: file ID, candidate ID và exact context job ID.
- Scoped lookup miss không gọi update.
- Scoped method không gọi repository global `find($fileId)`.
- Status ngoài allowlist không update và dùng custom API exception phù hợp nếu service được gọi trực tiếp.
- Existing `changeFileStatus()` callers không bị thay đổi contract/behavior.

### 8.3. Gates

**Phase 1 gate**: docs diff đúng phạm vi, docs build/validation pass, commit và push remote `main` thành công; plan ghi path/diff/result/SHA.

**Phase 1 result — PASS (2026-10-12)**:

- Updated `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/candidate/put-files-id-status.md` and `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/path-parameter-values.md`.
- `git diff --check`: PASS.
- `npm run build`: PASS; Docusaurus generated static files successfully.
- Commit: `b999f13` (`docs: scope candidate file status by job`).
- Push: PASS to `origin/main`.

**Phase 2 gate**: affected Feature/Service tests pass, test audit hoàn tất, `./vendor/bin/phpunit` pass 100%, self-check đối chiếu toàn bộ acceptance criteria, cập nhật living business spec và xác nhận không có route/global lookup regression.

**Phase 2 verification — PARTIAL (2026-10-12)**:

- `php -l` trên 9 PHP files thuộc task: PASS.
- `git diff --check`: PASS.
- `tests/Unit/Services/FileServiceTest.php`: PASS — 4 tests, 12 assertions.
- GAP-722 Feature regression filter trong `tests/Feature/Api/Candidate/MeFileTest.php`: PASS — 5 tests, 10 assertions.
- Full `./vendor/bin/phpunit`: BLOCKED — 620 tests, 2,764 assertions, 16 errors, 76 failures. Các lỗi/failures phát sinh ở nhiều suite không liên quan, gồm S3/external DNS (`api.pwnedpasswords.com`), storage và các flow agreement/intake; không phải targeted GAP-722 tests. Test được chạy với temporary `APP_CONFIG_CACHE`/SQLite để tránh cached PostgreSQL config, không sửa cache trong repository.
- Test audit: đã cập nhật Feature/Service tests; không thêm Repository unit test theo policy, repository được cover qua Service/Feature tests.
- Living spec: cập nhật `SPEC-009` trong `.business-spec/backend-business-flow-spec.md` với exact candidate/job scope, allowlist và no fallback `job_id = 0`.

Phase 2 chưa đạt PASS do full PHPUnit bị môi trường/external dependency block; backend changes giữ trạng thái chưa commit để review.

---

## 9. Acceptance Criteria

- [x] Cross-candidate file status update bị reject.
- [x] Cross-job file status update bị reject.
- [x] Same-candidate đúng job context vẫn update được.
- [x] Candidate-level file (`job_id = 0`) không được implicit match khi authenticated request context là một job ID khác.
- [x] `approved`, `rejected`, `expired` và status ngoài allowlist bị reject trước khi write.
- [x] Không còn global file-ID update path trong candidate self-service endpoint.
- [x] Existing GBG/consultant/compliance/internal callers của global `changeFileStatus()` không bị thay đổi ngoài phạm vi.
- [ ] Regression Feature/Service tests được thêm/cập nhật; full PHPUnit pass. Affected tests pass; full suite bị blocker môi trường/external dependency.
- [x] API docs được đồng bộ và push trước backend implementation; plan ghi commit SHA/push result.
- [x] `.business-spec/backend-business-flow-spec.md` phản ánh behavior sau khi verify.

---

## 10. Checklist trước khi Approve

- [x] Duyệt route thực tế `/api/candidate/files/{id}/status` thay cho path Jira có `/me`.
- [x] Duyệt candidate allowlist `uploaded`, `released`, `read`, `signed`.
- [x] Xác nhận policy hiện tại là destination allowlist; nếu cần source → destination state machine, bổ sung ma trận trước Phase 2.
- [x] Duyệt file scope là exact candidate ID + exact job context đã middleware xác minh; không implicit cộng candidate-level `job_id = 0`.
- [x] Duyệt response not-found dùng cùng contract hiện hành để tránh resource disclosure.
- [x] Duyệt docs-first Phase 1 và commit/push docs lên remote `main` trước backend code.

