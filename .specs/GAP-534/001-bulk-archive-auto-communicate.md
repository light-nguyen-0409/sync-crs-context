# SPEC: GAP-534 — Bulk archive & one-time profile deletion

> **Trạng thái**: `R8 PLAN AMENDMENT — PENDING APPROVAL` — cập nhật ownership của candidate purge; chưa implement amendment.
> **Ngày tạo**: 2026-10-06; **cập nhật contract**: 2026-10-12; **cập nhật phạm vi**: 2026-10-12; **Phase 1 evidence**: 2026-10-12
> **Author**: Codex
> **Jira**: [GAP-534](https://gappersonnel.atlassian.net/browse/GAP-534), “Consultant - Multi Candidate Selection for Bulk Archive & Auto Communicate”. Bản Jira/comment mới nhất đã đọc cập nhật 2026-10-12; In Progress; bổ sung lựa chọn gửi email Yes/No và ghi chú retention phía MatchMaker.
> **Revision mới nhất theo user (2026-10-19)**: Archive phải tái sử dụng `CandidateRepositoryInterface::archiveCandidateJobsByBranch()` để update nhiều candidate bằng một query set-based; phạm vi field/status được giới hạn đúng theo method này, không tự mở rộng theo logic khác. Không tạo hoặc sử dụng bảng archive-log mới. Link email chứa `id` candidate và token `StringUtility::uniqueHash(id)`; API deletion nhận `id` + token hash và cho phép xóa khi `hash_equals(StringUtility::uniqueHash(id), token)` đúng. Luồng purge phải tái sử dụng `CandidateService::deleteCandidate()`; plan phải liệt kê các cleanup còn thiếu nếu method hiện tại outdate. Giữ nguyên email content hiện có, không tự sáng tạo nội dung. Scope chỉ CRS; MatchMaker/provider out of scope.
> **Revision mới nhất theo user (2026-10-19, pending approval)**: Bulk archive phải follow behavior archive cũ bằng cách update `candidate_jobs.status`; không soft-delete `candidates`. Phải tái sử dụng/centralize logic của `CandidateService::updateCandidateJobStatus()` thay vì tạo archive behavior riêng. Phải bổ sung reset document theo flow `ArchiveCandidates::resetDocuments()` (contract document status, contract progress và các file contract/medical liên quan). `archiveCandidateJobsByBranch()` không còn là contract chính của archive bulk nếu không thể đáp ứng đầy đủ behavior này.
> **Revision mới nhất theo user (2026-10-19, R8 pending approval)**: Không tạo `purgeCandidateData()` trong `CandidateRepository`. `CandidateService::deleteCandidate()` phải trực tiếp điều phối các repository theo từng bảng/domain để purge candidate; chỉ bổ sung method vào repository hiện hữu hoặc tạo repository owner còn thiếu khi thật sự cần. `CandidateRepository` không được trở thành nơi gom cleanup của toàn bộ candidate.
> **Template**: [SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md)
> **Execution**: Hai implementation phases bắt buộc: Phase 1 đồng bộ API docs trước code; Phase 2 implement và verify backend sau khi Phase 1 pass. Phase 2 backend implementation và verification đã hoàn tất; rollout/persistent DB còn phụ thuộc blocker được ghi ở execution record cuối plan.
> **Token đã chốt**: 2026-10-07 — user chọn random token32bytes + SHA-256; không dùng JWT cho quyền xóa hồ sơ.
> **Contract FE đã chốt**: GET deletion chỉ trả `can_delete`; POST không body, xoá đồng bộ và trả `deleted`. FE không polling kết quả purge; chi tiết tại mục 3.2–3.3.

## 0. Rule chung áp dụng

- Chỉ bắt đầu implementation sau khi user approve plan này; plan là source of truth cho contract, scope và quyết định dữ liệu.
- **Docs-first bắt buộc**: Phase 1 cập nhật và validate API docs tại `~/projects/crs-api-docs`, commit và push docs lên remote `main`; Phase 2 chỉ bắt đầu khi Phase 1 pass. Không commit/push backend code theo rule này.
- Giữ kiến trúc `Controller → FormRequest → Service → Repository`; Repository chỉ data access, Service giữ business logic/orchestration, không Service → Service.
- Batch read trước loop; không query DB trong loop; bulk insert/update/delete; transaction chỉ bọc writes cần atomicity, không đặt read query/eager load trong transaction.
- Dùng constants, custom exceptions và private internal helpers; không magic values, generic exceptions hoặc formatter/linter ngoài yêu cầu.
- **Ưu tiên tái sử dụng code**: trước khi tạo class, method, repository, service, exception, job hoặc workflow mới, phải kiểm tra và tái sử dụng contract/logic hiện có nếu đáp ứng cùng business behavior. Chỉ tạo code mới khi code hiện tại không phù hợp; plan/implementation phải ghi rõ lý do không thể tái sử dụng và tránh tạo duplicate business logic.
- **Purge ownership**: `CandidateService::deleteCandidate()` là orchestration point; không tạo một method purge tổng hợp trong bất kỳ repository nào. Service gọi các repository chuyên trách theo bảng/domain, còn mỗi repository chỉ chứa query/delete data access của chính nó.
- Trace data origin/call chain trước khi dùng biến trong DTO/Resource/Mail/template; review và cập nhật affected tests, chạy affected suites rồi full `./vendor/bin/phpunit` ở Phase 2.
- Diff tối thiểu, không sửa unrelated callers; giữ nguyên email content hiện tại; scope chỉ CRS. MatchMaker/provider, external tracking, email đã gửi và backup retention không thuộc purge này.
- “Atomic” được cam kết ở DB transaction; storage deletion là synchronous/idempotent nhưng không thể rollback xuyên hệ thống nếu DB commit thất bại.

## 1. Tổng quan

Consultant chọn candidates ở Advert Response/Interview, chọn Yes/No gửi email, rồi gọi một API bulk archive. Archive mới là **xóa mềm bản ghi Candidate (`candidates.deleted_at`)**. Nếu Yes, gửi một email/candidate vừa archive, chứa link xác nhận xóa hẳn hồ sơ; nếu No, chỉ archive. Candidate dùng token trong email để xác nhận, **không cần login/JWT, mật khẩu hoặc OTP**. Mở link chưa xóa; POST xác nhận mới bắt đầu purge.

Thiết kế này thay thế các phương án manual Compliance request, signed link 30 ngày và self-delete JWT/password/24 giờ trong bản plan trước. Không triển khai đồng thời những phương án cũ.

### 1.1. Quyết định và tác động

| Nội dung | Contract |
|---|---|
| Email Yes/No | `send_email` boolean bắt buộc; false vẫn ghi archive log, không tạo token hoặc dispatch email job |
| One-time token | CSPRNG 32 bytes; TTL 7 ngày từ lúc phát hành trước enqueue; chỉ quyền xóa đúng candidate/archive cycle |
| Không phản hồi / token hết hạn | Giữ hồ sơ xóa mềm; **không tự hard-delete sau 7 ngày** |
| Xóa mềm | Candidate bị ẩn khỏi query Eloquent thông thường, không còn account hoạt động qua provider mặc định; verify login/JWT/refresh bằng tests |
| Phạm vi xóa mềm | Cấp account, ảnh hưởng mọi branch; khác với archive job/status của branch hiện hữu |
| Archive job | Cập nhật các jobs đủ điều kiện trong branch sang ARCHIVED để dữ liệu application nhất quán; giữ dữ liệu/files tới khi candidate xác nhận purge |
| Advert Response / Interview | Đề xuất map `STATUS_SCREENING_CALL` / `STATUS_INTERVIEW`; frontend xác nhận tên tab |
| Select all | Chỉ candidate đang hiển thị trên trang/view có filter user áp dụng; không tự áp dụng toàn bộ filtered pages |
| Branch | Một `Gap-Branch-ID` mỗi thao tác; không thao tác từ `all_branches` |
| Limit | Đề xuất 100 distinct candidate IDs/request |
| UX Yes/No | Thu Yes/No trong confirmation dialog trước submit; cả hai lựa chọn đều archive. Không dùng retry No → Yes làm resend |
| Bulk archive response | Chỉ `archived_candidate_ids` và `already_archived_candidate_ids` |
| GET deletion | HTTP 200, chỉ `{"can_delete": true}` hoặc `{"can_delete": false}`; lỗi request/hệ thống dùng HTTP error như mục 3.2 |
| POST deletion | Không body; token qua header. HTTP 200, chỉ `{"deleted": true}` sau khi xóa CRS hoàn tất; không yêu cầu `confirmed` |
| FE sau xác nhận | Hiển thị đã tiếp nhận yêu cầu, không hiển thị đã xóa hoàn tất và không polling; trạng thái job chỉ dùng nội bộ backend |
| Đăng ký lại | Email vẫn bị unique index giữ khi soft-deleted; trả lỗi nghiệp vụ rõ ràng. Sau hard purge mới cho đăng ký mới cùng email |

**Guard đề xuất để bảo vệ account liên branch**: chỉ bulk archive candidate local, không Permanent, không approved/transferred worker, không có job APPROVED/MATCHMAKER và không có application còn hoạt động ở branch khác. Nếu không đạt, reject toàn batch trước writes. Guard này cần review cùng tác động global của `deleted_at`; không âm thầm xóa mềm candidate đang được branch khác xử lý. Restore/resend/public renew-link không thuộc scope; nếu bổ sung cần cập nhật plan.

### 1.2. Baseline và deviations

Đã đọc [business flow](../../.business-spec/backend-business-flow-spec.md), [route inventory](../../.business-spec/backend-api-route-inventory.md), [database relationships](../../.business-spec/backend-database-relationship.md), rồi trace source liên quan SPEC-007/027/028/034/035/038.

| Source evidence | Hiện trạng / thay đổi cần thiết |
|---|---|
| `app/Models/Candidate.php:99`; migration `2022_10_20_024044_create_candidates_table.php` | Candidate đã có `SoftDeletes` và `deleted_at`; không tạo lại cột/trait |
| `app/Services/CandidateService.php:682`, `updateCandidateJobStatus` | Archive cũ chỉ đổi job status cùng branch, trừ sibling MATCHMAKER; không xóa mềm Candidate. **CODE**: bulk mới là workflow khác; không tự đổi single archive/unarchive |
| `app/Http/Controllers/Api/Consultant/CandidateJobController.php:41` | API update đơn không đối chiếu branch ownership; bulk phải có guard riêng |
| `app/Repositories/CandidateRepository.php:59`; consultant `CandidateController::index` | Query Candidate thông thường loại trashed/Permanent; INVITED và NO_ACCOUNT lấy nguồn khác, không dùng làm target local Candidate IDs |
| `app/Services/CandidateService.php:243`; `AuthenticatableService.php:83`; migration `2023_09_11_094510_add_indexes.php:35` | Lookup email mặc định bỏ trashed nhưng unique email vẫn giữ soft-deleted row. **CODE**: signup có thể chạm unique violation; thêm lookup gồm trashed cho candidate signup, không sửa shared staff signup |
| `config/auth.php:44`; `routes/candidate.php:93` | `candidateApi` dùng JWT/provider Candidate. Public deletion cần token scope riêng ngoài auth/edit-lock/job groups; không đưa link về `/me` yêu cầu account đang hoạt động |
| `app/Services/CandidateService.php:1534`, `deleteCandidate` | Lookup thường không thấy soft-deleted Candidate; cleanup hiện tại chưa đủ, query/delete trong loop, thứ tự FK có rủi ro. **CODE**: không gọi trực tiếp method này làm purge cho token flow |
| `app/Facades/MailSenderAccessor.php:59` | Lookup recipient thường không thấy trashed; catch transport rồi vẫn return true/log “Email Sent”. **CODE**: batch gửi cần kết quả thật, preloaded archived recipient, log không chứa token |
| `app/Services/EmailTemplateService.php:234` | Giữ resolution branch → legal entity → global → master, rich-text flags/cache hiện hữu |
| `database/seeders/EmailTemplateSeeder.php:15` | Import lọc max numeric ID; cần targeted idempotent seed theo type để master mới có trên DB IDs cao |

**DATA**: Chưa query DB production/migration drift. **CONFIG**: Chưa xác minh frontend URL, mail tester/ignore flags và production transport. **EXTERNAL**: Chưa gửi mail thật, chưa xác minh MM/provider deletion capabilities. **INFRASTRUCTURE**: Chưa xác minh scheduler/shared locks/storage deployment. Không coi đề xuất trong plan là flow hiện đang implement.

## 2. Database Design

### 2.1. Bảng duy nhất `candidate_archive_logs`

Một log/candidate/lần archive cho cả Yes và No. Queue gửi email theo lựa chọn trong request; bảng log chỉ giữ owner/actor/branch, lifecycle hồ sơ, token và cleanup receipt. Không tạo bảng notification hoặc lưu email, send_email, email_status, email_attempts trong bảng log. Phương án đã được user chọn; implementation vẫn chờ approve toàn plan.

| Cột | Kiểu / default | Mục đích |
|---|---|---|
| `id` | bigIncrements | ID duy nhất của lần archive và receipt |
| `candidate_id` | FK nullable | Owner; nullOnDelete giữ receipt sau hard purge |
| `archive_user_id` | FK users nullable | Consultant từ staff auth; nullOnDelete |
| `branch_id` | FK required | Branch thao tác/gửi email; restrictOnDelete |
| `status` | string, default archived | archived / deleted |
| `token_hash` | nullable char(64), unique | SHA-256 digest CSPRNG token32bytes; không lưu raw token |
| `token_expires_at` | nullable timestamp | Lúc issue trước enqueue +7 ngày; job trễ không tự gia hạn |
| `token_used_at` | nullable timestamp | Atomic consume khi purge DB hoàn tất, cùng status=deleted |
| `created_at`, `updated_at` | timestamps | Audit; created_at cùng thời điểm/precision với Candidate.deleted_at của lần archive |

Index `(candidate_id, id)` cho latest-log lookup, `(branch_id, status, id)` và `(status, id)` cho cleanup. Token hash unique lookup. Model casts datetime; belongsTo Candidate gồm trashed/Branch/archiveUser. Repository join hoặc eager-load candidate theo ID để lấy email/name/DNU, không snapshot email trong log. Candidate đã force-delete thì job không gửi mail.

**Không cần batch UUID**: mỗi lần archive tạo log ID mới. Latest log theo candidate_id/id + candidate.deleted_at khớp log.created_at xác định đúng lần archive; active/restored candidate hoặc log cũ bị từ chối. Một shared archive timestamp được ghi cho Candidate.deleted_at và log.created_at, chuẩn hóa timezone/precision; không suy ra cycle chỉ từ created_at gần giống nhau. Token lookup bind chính log ID/owner, không bind bằng email. Conditional soft-delete và counts ngăn hai bulk requests tạo log trùng cho cùng active state. Purge claim phải recheck latest-log/expected archived state trong write guards, không chỉ pre-read.

No: log status archived, token fields null. Yes: chuẩn bị token/hash/expiry trong memory và insert vào log trong transaction archive; token gắn duy nhất log đó. Retry gửi mail dùng lại token/expiry, không rotate. Expired tính từ token_expires_at, không tự đổi status thành deleted. Purpose cố định là profile deletion endpoint, dùng Service constant; không cần purpose column.

Token algorithm: random_bytes(32) → Base64URL không padding thành raw token text43chars → hash('sha256', raw_token_text) thành lowercase hex64chars lưu token_hash. Email/FE/header dùng raw token text43chars, không dùng digest làm bearer token. API hash đúng token text nhận từ header bằng cùng SHA-256 (không đổi hoa/thường hoặc hash random bytes trước encoding), repository lookup digest unique, rồi Service verify expiry/unused/latest owner state và conditional consume. SHA-256 ở đây là hash của high-entropy random token, không dùng làm password hashing. Expiry và one-time do các cột state/atomic writes kiểm tra, không được bảo đảm bởi riêng thuật toán hash.

Collision guard: kiểm tra hashes trùng trong batch bằng in-memory set và generate lại tối đa3 lần/hash, không DB query trong generation loop. DB unique index token_hash là chốt cuối cho collision giữa requests hoặc SHA-256 digest collision; chỉ nhận diện đúng unique constraint này, không coi mọi integrity error là token collision. Nếu DB chặn, rollback toàn transaction archive và dùng custom bulkArchiveStateConflict/HTTP409; caller có thể gửi lại request để phát hành tokens mới, không retry transaction trong query loop. Không overwrite/rebind log cũ, không dùng chung token giữa candidates. Mail jobs chỉ enqueue sau commit nên token collision chưa được gửi ra ngoài.

`status=deleted` chỉ khi storage và DB đã xóa xong. Synchronous purge đọc paths từ metadata files hiện hữu; giữ Candidate/dependencies/file rows cho tới lúc storage hoàn tất, không cần lưu bản sao paths hoặc retry counters trong log. Chỉ email archive queue quản lý attempts/backoff. Log còn sau hard purge cho backend operation audit; GET bằng token cũ chỉ trả can_delete=false, không cần join Candidate.

### 2.2. Bảng hiện hữu

- `candidates`: dùng deleted_at hiện hữu, **không thêm archive UUID/current-log pointer/token columns**. Verify actual state bằng latest archive log và shared archive timestamp.
- `candidate_jobs`: batch status update SCREENING_CALL/INTERVIEW cùng branch, giữ archived; model không có SoftDeletes, không giả định restore jobs bằng deleted_at.
- `starred_candidates`: batch detach stars consultant thao tác, không sửa stars users khác khi mới archive.
- `activity_logs`: giữ audit hiện hữu nếu cần, không duplicate email/profile/token/mail body; archive log cung cấp actor/branch. Không dùng activity log để dựng lại email queue hoặc bí mật reintroduce các email fields đã bỏ. Purge xóa candidate-owned PII logs.
- `email_templates`: một master type mới, targeted idempotent seeder theo type, không overwrite custom templates.
- Không dùng should_delete_personal_info làm bằng chứng purge; không reuse candidate_tokens hiện hữu vì giữ JWT.

## 3. API Contract

### 3.1. Bulk archive

`POST /api/consultant/candidates/bulk_archive`

Auth `userApi`, middleware consultant branch + autoLogout + API throttle hiện hữu. Headers bearer staff JWT, `Gap-Branch-ID`, JSON.

```json
{"candidate_ids": [101, 102], "send_email": true}
```

FormRequest `BulkArchiveCandidatesRequest`:

- `candidate_ids`: required array, min 1/max 100; mỗi ID required integer/distinct/min 1. Không query `exists` từng ID; Service batch load/validate ownership.
- `send_email`: required boolean, chỉ quyết định dispatch email cho candidates vừa archive trong request này; không lưu cột này trên archive log.
- Prohibit `view_status`, `batch_key`, `branch_id`, `all_branches`, `filter`, `select_all`, `job_ids`, arbitrary target `status`. Public body chỉ có candidate_ids/send_email; không truyền cấu trúc bảng log hoặc token vào bulk API.

Resource theo `$columns`, top-level convention hiện hữu:

```json
{
  "archived_candidate_ids": [101],
  "already_archived_candidate_ids": [102]
}
```

| Response field | Kiểu / ý nghĩa |
|---|---|
| archived_candidate_ids | integer[]; candidates vừa soft-archive trong lần gọi |
| already_archived_candidate_ids | integer[]; candidates no-op theo matching latest log |

Success body **chỉ có đúng hai arrays trên**, luôn có kể cả rỗng, không data wrapper/count/group identifier/token/email-dispatch fields. 202 khi có email jobs đã được broker chấp nhận; 200 với No/no-op hoặc không enqueue được job nào. HTTP/body archive không là bằng chứng email đã gửi.

Nếu enqueue error sau commit, archive vẫn thành công và giữ body hai fields; xử lý bằng redacted operational logging/queue monitoring, không thêm error IDs vào response. FE refresh danh sách, không submit archive lại hoặc hiển thị archive rollback. Broker timeout outcome có thể chưa rõ; không tự resend. Validation/auth/conflict/write failure trước commit vẫn dùng error contract hiện hữu ở bảng HTTP bên dưới, không giả vờ success.

No: soft archive/jobs/stars như Yes, ghi log token null nhưng không email job/transport. Retry Candidate đã trashed cùng branch/latest matching log là no-op; không log mới/enqueue lại, không đổi No → Yes thành resend. Legacy trashed không có matching log hoặc ownership/state không xác minh được thì conflict. Response không cần batch/group identifier; worker dùng archive log IDs.

Backend tự kiểm tra DB: candidate có application SCREENING_CALL hoặc INTERVIEW ở branch và đạt guards §1.1; chuyển giữa hai trạng thái vẫn hợp lệ. Cả hai tab cùng rule, không nhận trạng thái tab từ FE. Reject toàn bộ trước mutation khi target thiếu/quyền sai/ineligible; không sửa Permanent/APPROVED/MATCHMAKER. Một log/candidate dù nhiều jobs; stale writes rollback toàn batch.

| HTTP | Điều kiện |
|---|---|
| 400 | Validation theo project convention; notFound dùng key hiện hữu |
| 401 / 403 | Staff auth / branch access hoặc ownership sai |
| 409 | Custom `bulkArchiveStateConflict`: ineligible, legacy archive hoặc concurrent change |
| 429 | Rate limit |
| 500 | Unexpected write failure; rollback batch |

### 3.2. Candidate profile deletion — contract tối giản cho FE

| Method / path | Mục đích | Response success |
|---|---|---|
| GET /api/candidate/profile_deletion | Kiểm tra link có còn được phép xóa | HTTP200, chỉ can_delete boolean |
| POST /api/candidate/profile_deletion | Xác nhận và xóa đồng bộ hồ sơ CRS | HTTP200, chỉ deleted=true |

FE không đọc status nội bộ hoặc polling cleanup. Backend giữ archived/deleted trong archive log; không expose enum ra public API.

#### 3.2.1. Headers / token authentication chung

```http
Accept: application/json
X-Profile-Deletion-Token: <raw-token>
```

- Hai routes public theo token scope riêng, ngoài auth:candidateApi/checkCandidateLockEdit/detectJobForCandidate; không cần login/JWT/current_password/OTP.
- Email URL `https://<configured-candidate-host>/profile-deletion#token=<raw-token>`. FE lấy fragment vào memory, clear fragment và dùng header; không đưa token hash/candidate ID vào request.
- Raw token Base64URL không padding43chars `[A-Za-z0-9_-]`; FormRequest validate required/string/format từ header. Service SHA-256 đúng text rồi tìm archive log; TTL7days tính từ issue trước enqueue, không gia hạn khi GET/retry mail.
- GET/POST không body/query parameters; không cần Content-Type. Owner resolve từ log, không từ client. Token không accept trong body/path/query.
- HTTPS/trusted frontend host/CORS header allowlist, Referrer-Policy no-referrer, không raw-token logs/localStorage/third-party analytics. Throttle GET30/phút/IP, POST5/phút/IP + digest; HEAD read-only body rỗng.

#### 3.2.2. GET — kiểm tra có thể xóa

```http
GET /api/candidate/profile_deletion
Accept: application/json
X-Profile-Deletion-Token: <raw-token>
```

HTTP200 **chỉ một field**, không data wrapper:

```json
{"can_delete": true}
```

can_delete=true khi digest tồn tại, chưa expired, token_used_at null, log.status archived, owner còn soft-deleted, log latest của owner và Candidate.deleted_at khớp log.created_at. Purpose cố định là quyền profile deletion.

Mọi trường hợp token đúng format nhưng unknown/expired/used/stale, owner active/restored/purged hoặc workflow đã deleted trả cùng HTTP200:

```json
{"can_delete": false}
```

FE true → enable Delete profile; false → hiển thị một thông báo “This link is no longer available” và không cho xóa. Không cần phân biệt hết hạn/đã dùng/đang xử lý/xóa thành công/thất bại. false không chứng minh hồ sơ đã xóa hoặc request đã được tiếp nhận; chỉ có nghĩa token hiện không cho phép xác nhận mới.

GET/HEAD tuyệt đối không consume token, dispatch job, update timestamps hoặc ghi audit. Header malformed/missing400, throttle429, system500 vẫn là request/system errors, không đánh đồng với can_delete=false. Không trả token expiry, PII, owner/log ID hoặc lifecycle enum. Hết TTL không hủy job đã được xác nhận.

#### 3.2.3. POST — gửi yêu cầu xóa

```http
POST /api/candidate/profile_deletion
Accept: application/json
X-Profile-Deletion-Token: <raw-token>
```

**Không request body**. Chỉ gọi sau khi user đồng ý ở FE dialog. POST bằng token hợp lệ chính là confirmation; không boolean xác nhận hoặc candidate target từ client.

Sau khi storage cleanup thành công và DB purge commit, HTTP200 top-level chỉ một field:

```json
{"deleted": true}
```

deleted=true nghĩa **hồ sơ CRS đã được xóa hoàn tất** trong request. FE hiển thị “Your profile has been deleted”, bỏ nút xóa và không polling GET. Email archive vẫn có job riêng; profile deletion không dispatch purge job.

Storage failure hoặc DB transaction failure trả HTTP500, không trả `deleted=true`; token/DB transaction được rollback khi có thể. Storage deletion có thể đã thực hiện một phần trước DB rollback và không thể rollback tuyệt đối; thao tác retry phải idempotent và được vận hành kiểm soát, không có purge job tự động.

**Lifecycle/concurrency**:

1. GET/page load/HEAD/Cancel không consume; POST kiểm tra đúng unused/unexpired/latest archived state và thực hiện purge đồng bộ. Hai concurrent requests chỉ một request được commit.
2. Storage/DB failure trước DB commit không trả `deleted=true`; DB transaction rollback giữ token chưa used khi có thể. POST đã commit thì replay410; concurrent stale claim có thể409.
3. Timeout sau POST: FE có thể GET lại một lần. `can_delete=true` nghĩa request chưa commit và có thể xác nhận lại; `can_delete=false` không tự kết luận nguyên nhân, chỉ báo link không còn sử dụng được.
4. Public token không dùng cho restore/resend/renew/login/API profile khác. Scope không thêm API theo dõi completion/renew link.

#### 3.2.4. Error contract

| HTTP | GET | POST | FE behavior / internal key |
|---|---|---|---|
| 200 | Token check hoàn tất; can_delete true/false | — | FE chỉ kiểm tra boolean |
| 200 | — | Purge CRS đã hoàn tất; deleted=true | Hiển thị hồ sơ đã xóa |
| 400 | Missing/malformed token header hoặc unexpected input | Tương tự GET | Validation message theo convention hiện hữu |
| 403 | Không dùng cho token-invalid case; trả200/false | Digest unknown/owner mismatch | profileDeletionTokenInvalid; FE gộp thành link không sử dụng được |
| 410 | Expired/used/stale trả200/false | Expired/revoked/used/stale | profileDeletionTokenUnavailable; không POST retry/renew |
| 409 | State không cho xóa trả200/false | Concurrent claim/state/guard conflict | profileDeletionStateConflict; có thể GET lại, không retry mù |
| 429 | Preview throttle | Confirmation throttle | Existing throttle response |
| 500 | Unexpected system/read error | Storage hoặc DB purge failure | Generic system error; vận hành kiểm tra/retry idempotent |

Validation400 giữ status400/errors map từ app/Http/Requests/JsonRequest.php. Custom business errors giữ Candidate APIErrorException/Status hiện hữu, numeric codes khai báo config/api.php khi implementation. FE không cần branch theo các token-related keys; gộp unavailable message, giữ thông báo system/throttle riêng. Không fake can_delete=false khi system lỗi.

Tradeoff token-holder đã chọn: ai giữ link có thể confirm owner tương ứng. Backend trả completed chỉ sau khi synchronous CRS purge commit; public API không expose chi tiết cleanup. Contract là proposal trong plan, chưa có routes production tương ứng.

### 3.3. FE landing page — chỉ kiểm tra link và gửi yêu cầu

Public route /profile-deletion không login guard/dashboard redirect. Card giữa màn hình: tiêu đề Delete your profile, mô tả xóa toàn bộ hồ sơ và cần đăng ký lại, nút Delete profile; không menu/sidebar/PII.

1. Lấy token fragment vào memory, clear fragment, gọi GET can_delete; thiếu token hiển thị unavailable, không POST. Reload sau clear fragment thì mở lại link email, không persist token localStorage.
2. can_delete=true enable nút; false hiển thị một unavailable message. System error hiển thị không thể kiểm tra lúc này, không giả vờ token invalid.
3. Click mở dialog Cancel/Delete permanently. Cancel đóng dialog, không API xóa. Đồng ý mới POST không body với token header; disable nút tránh double click.
4. HTTP200/`deleted=true` → “Your profile has been deleted”; bỏ nút, kết thúc FE flow. Không polling.
5. Token-related403/409/410 → unavailable message; timeout xử lý theo §3.2.3 bằng optional GET một lần, không tự POST lại. Throttle/system errors giữ generic messages phù hợp.

FE acceptance: public/no login; GET/HEAD/page load/Cancel không xóa; boolean true/false UI; correct token header/no POST body; no double submit; `deleted=true` chỉ hiển thị sau purge hoàn tất; không polling/delivery-status mapping. FE repo/ownership cần xác định trước implementation.

## 4. Business Logic

### 4.1. Bulk archive atomic, không N+1

1. Middleware cấp actor/branch; Service batch load candidates include-trashed, jobs/branch scope và latest archive logs cho no-op.
2. Validate toàn batch/guards theo DB, không dựa tab FE. Capture shared archive timestamp, build expected states/job updates/log rows. Nếu send_email=true, generate token32bytes/hash/expiry trong memory cho candidates mới; false giữ token null.
3. Transaction **chỉ writes**: conditional batch job updates; conditional Candidate soft-delete theo expected state; actor-star detach; batch archive-log insert (cả Yes/No) với created_at bằng archive timestamp và token fields đã chuẩn bị. Counts phải khớp; custom conflict rollback toàn bộ.
4. Sau commit, batch query latest log IDs cho candidates vừa archive và đối chiếu timestamp để map đúng rows. Nếu Yes, dispatch **một SendCandidateArchiveEmailJob/log**; nếu No không dispatch. Không DB queries trong dispatch loop; dùng Redis/SQS, tránh database queue jobs trùng domain table. Job payload gồm logId và token, Laravel ShouldBeEncrypted bảo vệ serialized token; không JWT/email/full profile.
5. Token CSPRNG được chuẩn bị trước insert; plaintext chỉ trong process và encrypted queue payload. Bảng log chỉ hash. Encryption cần active Encrypter, verify runtime; fail closed nếu không encrypt được. Không đưa payload/token vào app logs, exception context hoặc mail body audit. Failed queue records cũng phải giữ encrypted payload.
6. Dispatch sau commit bằng afterCommit hoặc sau transaction return; không gửi mail trong transaction. Theo dõi enqueue outcomes nội bộ/operational logs và chọn HTTP theo §3.1, không thêm fields vào success body archive. Không có email tracking/recovery từ bảng log: commit rồi enqueue thất bại cần vận hành xử lý, không tự scan log token null/hash để suy ra consultant chọn Yes.
7. No-op không phát hành token/dispatch lại. Không gọi single archive API/service trong loop, không reset progress/RTW/files/MM hoặc sửa single archive/unarchive ngoài scope. Conditional writes bảo vệ ownership/job/current candidate state races.

### 4.2. Queue email job

SendCandidateArchiveEmailJob implements ShouldQueue + ShouldBeEncrypted. Local Laravel9.52.5 có interface/encryption path (`vendor/laravel/framework/src/Illuminate/Queue/Queue.php:156`); verify Encrypter binding trên deployment. Job delegate CandidateService contract, không query Model trực tiếp. Queue dùng async Redis/SQS + workers; config fallback sync/after_commit=false cần kiểm tra. Không dùng database queue config nguyên trạng vì table jobs trùng domain jobs.

- Job đọc log join/eager-load candidate **include-trashed** theo candidate_id để lấy email/name/DNU; load branch/template context. Check status archived, latest-log match/deleted_at, token payload hash bằng log.token_hash, unused và chưa expired. Owner đã active/restored/purged hoặc log cũ → no-op; không rebind bằng email. Expiry là issue trước enqueue +7 ngày; queue delay không gia hạn token.
- DNU/ignore/tester settings phải giữ. Không gửi production deletion capability tới tester thay owner; non-production tests dùng isolated fixtures/capture. Log không lưu suppression hoặc delivery status; operator dùng queue outcome/redacted operational logs.
- Mail adapter dùng dữ liệu owner/context đã load và kết quả transport thật; MailSender::send bool hiện tại không proof success. Có thể dùng batch technical helper với một recipient; không DB queries trong render/send loop và không log token/full HTML.
- Queue max3 attempts/backoff5min, timeout<retry_after, shared lock theo logId tránh overlap. Retry **chỉ khi chứng minh lỗi trước transport**; dùng lại token/expiry từ encrypted job, không issue mới. Timeout/provider accepted/process crash có thể gửi trùng: không claim exactly-once hoặc DB sent-state dedup khi không có email_status.
- Known ambiguous transport lỗi chủ động fail job/manual review, không auto resend; worker bị kill sau transport vẫn có thể bị queue redeliver mà app không biết đã gửi. Đây là giới hạn chấp nhận của thiết kế bỏ delivery state. Unique job/lock không giải quyết cửa sổ crash này. Duplicate email nếu xảy ra dùng cùng một token, không làm link cũ mất hiệu lực hoặc kéo dài TTL.
- failed(Throwable) chỉ log operation ID/error code đã redact, không serialize decrypted token. Không automatically queue retry all failed jobs; operator kiểm tra transport outcome trước retry. Queue job success không phải inbox receipt.

**Giới hạn recovery email**: không có command scan archive logs để tự gửi mail vì logs không giữ Yes/No hoặc email delivery state. Broker enqueue failure sau commit có thể để candidate archived nhưng chưa có email. Queue chỉ retry jobs đã được nhận; application không hứa recover khoảng commit→enqueue. Nếu cần guarantee/reconcile delivery sau này, phải duyệt thêm durable email intent/state vào plan, không âm thầm thêm lại fields user đã bỏ.

Template giữ nguyên email content hiện tại theo Jira; không tự viết hoặc thay đổi exact English copy. Chỉ verify dữ liệu runtime như candidate name, branch name, deletion URL/token và thời hạn link 7 ngày. Vì Candidate soft-delete vô hiệu account thông thường, không hứa account còn đăng nhập được; không tự overwrite branch custom content.

### 4.3. Xác nhận xóa đồng bộ → storage trước, DB sau

Không dùng deleteCandidate() hiện hữu như purge hoàn chỉnh. CandidateService sở hữu workflow, inject Repository interfaces, không inject Service khác. Utilities chỉ stateless technical helpers, không query DB. Không thêm cột/file/table khác để lưu retry counters hoặc bản sao danh sách cleanup.

1. POST: resolve token/log + trashed owner/guards và preload toàn bộ dependency IDs/files trước transaction. Hai concurrent requests chỉ một request được phép tiếp tục theo latest archived state/token guard.
2. **Xóa và xác minh storage đồng bộ trước**, ngoài DB transaction. Xóa paths theo disk/batch; missing files là idempotent success. Nếu storage error, không bắt đầu DB purge và trả lỗi; một phần files có thể đã mất nên thao tác retry phải idempotent. Không DB queries trong path loop.
3. Sau khi storage verified absent, transaction writes-only conditional batch delete dependencies theo FK order, Candidate force-delete cuối, archive log candidate_id null/status=deleted và token_used_at=completion_time cùng transaction. Conditional writes recheck latest log/expected archived state; affected count mismatch hoặc FK error rollback DB. Storage deletion không thể rollback bởi DB transaction; đây là giới hạn atomic xuyên hệ thống.
4. Chỉ trả HTTP200/`deleted=true` sau DB commit. DB transaction failure trả HTTP500 và không consume token nếu rollback thành công; không dispatch purge job, không tự enqueue retry và không expose partial cleanup state.
5. Old JWT/login/reset/candidate login links phải fail sau soft archive/purge theo actual provider tests. Xóa candidate-owned persisted auth state trong DB purge; không claim mọi JWT blacklisted nếu chưa có adapter. Log/token cũ không bind candidate mới bằng email. GET can_delete không mutate hoặc consume thêm token; token cũ trả false sau status=deleted.

**Dependency inventory để triển khai** (trace migration/model/caller lần cuối trước viết query; không copy schema lịch sử):

| Nhóm | Cleanup/ownership rule |
|---|---|
| Candidate scalar/addresses/bank/NOK/answers/skills/tags/stars | Xóa dữ liệu/pivots scoped candidate; không xóa shared dictionaries/tags |
| Employment history | References trước histories; refs có logical candidate_id/history_id |
| Jobs/progress/timings/progress emails | Xóa scoped jobs, progress, timings và candidate_progress_emails trước Candidate; progress-email FK không cascade |
| Notes/issues | Change logs trước communication notes/escalated issues; chỉ đúng parent IDs |
| Appointments | Xóa candidate-job pivots trước parent; xóa appointments có candidate_id thuộc owner; giữ appointments của candidate khác và resources/campaign dùng chung |
| Welfare/files | Welfare checks trước files vì FK image/certificate restrict; include files candidate_id và original_candidate_id; cả original/converted paths, snapshot files |
| Candidate snapshots | Xóa serialized data/raw_data theo owner; không giữ snapshot PII sau purge |
| Candidate tokens/password reset/tracking | Xóa candidate-owned token/reset records và tracking_record_histories scoped candidate; verify email-based reset ownership, không nhầm staff tokens |
| Authentication logs | Model hiện belongsTo staff User; không delete bằng candidate numeric ID vì trùng ID giữa hai bảng |
| SMS | Xóa candidate receiver/pivot data; không xóa shared SMS campaigns |
| Invitations/MM snapshots | Mapping logical email/people-number/source phải trace trước cleanup; không dùng email đơn thuần để delete tài nguyên shared/external |
| Activity/API logs | Xóa/anonymize candidate-owned PII khi ownership xác minh được; API logs không có reliable candidate FK thì phải xác định mapping. Không dùng substring/email scan làm chứng cứ ownership |
| Archive log receipt | Giữ token hash/state/timestamps/actor/branch, null candidate FK sau complete; không giữ PII/file-path copies |

**Purge completion contract**: xóa hồ sơ CRS (DB cùng candidate-owned snapshots/history và storage). Không gọi completed nếu còn FK/owned resource chưa map hoặc cleanup thất bại. MatchMaker/provider records, đã gửi email và backup retention là phạm vi external riêng, chưa được kiểm chứng; không tự hứa token xóa các hệ thống đó. Nếu Jira/product yêu cầu “our system” bao gồm external records, phải bổ sung adapter/confirmation/retry contract vào chính plan trước implementation. Candidate có approved/transferred/MM state bị guard loại khỏi bulk này để tránh áp dụng applicant purge vào worker flow.

### 4.4. Signup / account availability

CandidateService::signUp kiểm tra `findByEmailIncludingTrashed` trước parent signup. Nếu email thuộc candidate archived thì trả custom Candidate API error `candidateArchived` (409), không thử insert, không gửi reset-password về account bị ẩn. Không đổi staff signup hoặc bỏ unique index. Sau purge, candidate mới dùng cùng email có ID mới; cũ token/digest không bind lại bằng email. UI message/support hành vi khi archived cần integration review; không thêm restore endpoint ngoài scope.

### 4.5. Data Mutation Contract — danh sách thay đổi dữ liệu bắt buộc

Mục này là checklist implementation/test cho §4.1–4.3, không phải xác nhận code đã có. Schema đối chiếu migration chain/models trong workspace; **DATA**: chưa đối chiếu schema/data production. `C` là tập candidate IDs vừa archive; `c` là owner ID xác minh từ archive log khi purge; `B` là branch từ middleware; `U` là consultant đang thao tác; `T` là shared archive timestamp. Mọi purge dùng owner `c` trên **toàn account/mọi branch**, không chỉ branch phát hành email. Batch reads bao gồm soft-deleted rows, preload các parent IDs trước transaction; mutations theo batch, không query trong loop.

#### 4.5.1. Bulk archive — mutations sau khi toàn batch vượt guards

| Table/resource | Scope | Mutation cụ thể |
|---|---|---|
| `candidates` | IDs trong C, đang active và expected state còn đúng | UPDATE `deleted_at=T`, `updated_at=T`; không đổi email/status/progresses/RTW/MM/password hoặc thông tin cá nhân |
| `candidate_jobs` | candidate_id trong C, job thuộc B, expected states đã đọc và đủ điều kiện | UPDATE `status=CandidateJob::STATUS_ARCHIVED`, `updated_at=T`; bao gồm các application trong branch theo §4.1, không chỉ selected job. Không archive APPROVED/MATCHMAKER; guards reject trước write. Jobs ngoài B giữ nguyên |
| `starred_candidates` | candidate_id trong C AND user_id=U | DELETE pivot của actor; stars của consultant khác giữ nguyên tới purge |
| `candidate_archive_logs` (mới) | Một row/candidate trong C | INSERT candidate_id, archive_user_id=U, branch_id=B, status=archived, created_at/updated_at=T; token_used_at=NULL. Yes: token_hash/expiry đã generate; No: cả hai NULL |
| Async queue | Chỉ C khi send_email=true | Sau commit enqueue một encrypted email job/log. Không thêm email tracking/notification rows; No không enqueue |
| Các tables/files khác | Toàn bộ dữ liệu candidate liên quan | Không DELETE/reset: addresses/bank/answers/employment/jobs progress/timings/files/snapshots/appointments/notes/issues/tokens đều giữ nguyên tại archive |

No-op IDs trong already_archived_candidate_ids không update timestamps, job status, stars hoặc log/token và không gửi email lại. Expired token/không click link không tự cập nhật hay purge dữ liệu. Toàn bộ DB mutations archive ở trên atomic; queue không nằm trong DB transaction. Không thêm activity-log insert hoặc thay đổi `no_remind`, contract-document status/RTW ngoài checklist này nếu chưa cập nhật plan.

#### 4.5.2. POST deletion — synchronous purge trong request

| Table/resource | Scope | Mutation cụ thể |
|---|---|---|
| `candidate_archive_logs` | Đúng hash/log mới nhất của c, token unused/unexpired, status archived | Giữ token unused trong lúc preload/storage; sau khi DB purge thành công SET `token_used_at=completion_time`, `status=deleted`, `updated_at=completion_time`; giữ token_hash/expiry/created_at/actor/branch |
| `candidates` | c vẫn soft-deleted đúng T/latest cycle | Guarded conditional write để serialize confirmation với affected mutators; chỉ `updated_at` có thể đổi theo confirmation time, không thay `deleted_at` hoặc dữ liệu hồ sơ. Expected-state/affected-row strategy phải được test trên PostgreSQL |
| Files và mọi candidate-owned dependency | c | Xóa storage đồng bộ trước; sau đó DELETE DB trong transaction theo FK order |

Storage cleanup và DB purge cùng nằm trong một request; chỉ phần DB có transaction atomic. Nếu DB rollback sau storage cleanup, không thể khôi phục storage tự động; retry phải idempotent và được vận hành kiểm soát.

#### 4.5.3. Synchronous deletion — storage trước, DB sau

**Storage**: preload `files` với `candidate_id=c OR original_candidate_id=c`, gồm archived rows (`candidate_id=0`) và snapshot file types. Xóa `url`, `converted_file_url` trên đúng disk; bỏ NULL/empty/sentinel `FileUtility::S3_EMPTY_CONVERTED_URL` (`nothing`), deduplicate paths. Trace thêm candidate-owned paths nằm trong snapshots/profile/appointment documents trước freeze inventory; URL external hoặc shared path chưa xác minh không được delete mù. Không gọi cleanup với backup=true để chuyển file thành `.bak`. Verify mọi owned path absent trước DB purge; lỗi/mapping chưa đủ thì không báo deleted. Metadata vẫn còn để retry, missing path là idempotent success.

**DB purge**: DELETE vật lý cả rows đã soft-deleted, không chỉ Eloquent default scope. Các tables có direct `candidate_id` xóa theo c; các children dùng parent IDs preloaded, không suy đoán ownership qua numeric ID ở bảng khác.

| Table | Ownership/scope và thao tác |
|---|---|
| `employment_history_references` | DELETE candidate_id=c hoặc employment_history_id thuộc employment_histories của c; references trước histories |
| `employment_histories` | DELETE candidate_id=c sau references |
| `communication_note_change_logs` | DELETE communication_note_id thuộc communication_notes của c; trước notes |
| `communication_notes` | DELETE candidate_id=c |
| `escalated_issue_logs`, `escalated_issue_change_logs` | DELETE escalated_issue_id thuộc escalated_issues của c; trước issues |
| `escalated_issues` | DELETE candidate_id=c |
| `candidate_job_appointments` | DELETE candidate_job_id thuộc candidate_jobs của c OR appointment_id thuộc appointments của c; trước cả hai parents |
| `appointments` | DELETE candidate_id=c, gồm note/meeting/documents metadata trên row; không xóa appointments của candidate khác. Migration create_appointments và Appointment::candidate xác nhận đây là candidate-owned parent, không phải shared campaign |
| `candidate_progress_emails` | DELETE candidate_id=c trước Candidate; FK không cascade |
| `candidate_timings`, `candidate_jobs` | DELETE candidate_id=c, mọi branch; timings và job children trước candidate_jobs |
| `candidate_welfare_checks` | DELETE candidate_id=c trước files vì interview_image_file_id/welfare_image_file_id/certificate_file_id FK restrict; shared referenced files cần ownership checks |
| `files` | DELETE rows candidate_id=c OR original_candidate_id=c chỉ sau storage hoàn tất và welfare dependencies được xử lý |
| `candidate_snapshots` | DELETE candidate_id=c, gồm toàn bộ serialized `data` và `raw_data`; không giữ bản sao PII |
| `candidate_addresses`, `candidate_bank_accounts` | DELETE candidate_id=c; địa chỉ/bank data thuộc account |
| `answers`, `candidate_skills`, `candidate_tags` | DELETE candidate_id=c; giữ questions/options/skills/tags catalogs |
| `starred_candidates` | DELETE candidate_id=c cho mọi consultant, khác archive chỉ gỡ actor |
| `candidate_face_matching_rates`, `consultant_declarations` | DELETE candidate_id=c; không xóa User của consultant |
| `legal_entity_switching_requests`, `match_maker_duplication_processes` | DELETE candidate_id=c, gồm local workflow/token data; không gọi external MM deletion chỉ vì xóa local row |
| `candidate_tokens` | DELETE candidate_id=c; không xóa staff JWT/token data |
| `candidate_password_resets` | DELETE email bằng email của c đã preload. Candidate broker dùng table riêng (`config/auth.php:106`); không xóa `password_resets` của staff dù trùng email |
| `tracking_record_histories`, `activity_logs` | DELETE candidate_id=c; tracking_records/catalog và staff-only logs giữ nguyên |
| `sms_candidate_campaigns`, `sms_receivers` | DELETE candidate_id=c, gồm recipient-local message metadata; giữ shared sms_campaigns |
| `sms_pre_campaigns` | UPDATE `receiver_ids` loại c khỏi array, giữ các candidate khác. Source SmsService::createSmsPreCampaign lưu candidate IDs, không phải sms_receiver IDs; không xóa toàn campaign. Recompute estimated_cost qua technical calculation tương thích SMS workflow, không inject SmsService vào CandidateService; freeze empty-list handling và batch CAS trước implementation |
| `candidate_archive_logs` | Giữ **mọi log của c**: SET candidate_id=NULL; log khớp token purge SET status=deleted, token_used_at=completion_time, updated_at=completion_time. Giữ hash/expiry/used_at/actor/branch/created_at; các log cũ không đổi lifecycle tùy tiện. Không giữ email/name/path copies |
| `candidates` | FORCE DELETE id=c cuối cùng; xóa toàn bộ scalar PII/NOK/progresses/password/MM identifiers trên row |

Trật tự bắt buộc: storage verified absent → child/change-log/pivot/reference deletes → candidate-owned parents (welfare trước files) → candidate rows cuối + receipt update cùng writes-only transaction. FK/expected-state failure rollback DB; không rollback storage. Mọi candidate-owned rows còn sót là gate failure, kể cả logical relations không có FK. Không có purge queue/retry counter; retry thủ công chỉ sau khi kiểm tra post-state và storage paths.

#### 4.5.4. Giữ nguyên và ownership blockers cần đóng trước implementation

- Giữ shared `users`, `user_branches`, `branches`, `legal_entities`, domain `jobs`, `agencies`, dictionaries/questions/options/tags/skills, `sms_campaigns`, `tracking_records`, mail templates/custom configuration. Không DELETE `authentication_logs` theo candidate ID vì belongsTo staff User. Không coi Redis/SQS/failed_jobs là candidate-owned domain tables để purge hàng loạt.
- `candidate_invitations` không có candidate FK, unique email; children là `invitation_addresses.candidate_invitation_id`, `invitation_skills.candidate_invitation_id`, `invitation_tags.invite_id`. **Blocker ownership**: xác minh candidate signup/invite lifecycle và approve mapping trước khi DELETE invitations/children; không tự giữ PII rồi báo purge hoàn tất, không xóa bằng email đơn thuần khi ownership chưa chứng minh.
- `match_maker_candidates` là local MM mirror theo email/peo_no/db_source, không direct candidate FK. **Blocker ownership/scope**: chốt mapping composite và nguồn sync/reimport; xác định delete/anonymize local rows và ảnh hưởng provider. Không broad-delete theo email hoặc hứa external removal. `api_result_logs` có url/message nhưng không candidate FK: cần source-backed ownership/redaction strategy cho PII trước khi claim full purge; không substring scan làm chứng cứ. `api_exception_logs` đã drop trong migration 2024_12_02, không ghi query với historical table như schema hiện hành.
- **CONFIG/INFRASTRUCTURE**: disk/path ownership, shared binaries, snapshots embedded paths, application caches/exports/temp files và queued candidate payloads phải audit để chốt cleanup/invalidation; không invent cache keys hoặc delete shared resources. **EXTERNAL**: provider records, emails đã gửi và backups ngoài active CRS purge, retention/scope cần product xác nhận.
- Trước code: đóng từng ownership/mapping/empty-SMS/cost/guard strategy blocker, cập nhật checklist bằng source evidence và tests. Không coi toàn bộ purge inventory đã freeze khi các mục này còn mở; không phát hành email hứa xóa đầy đủ hoặc mark completion khi còn candidate-owned data chưa map.

**Source evidence bổ sung**: migrations `2023_06_21_045634_create_consultant_declarations_table.php`, `2022_12_27_051721_create_candidate_face_matching_rates_table.php`, `2026_05_05_034625_create_legal_entity_switching_requests_table.php`, `2024_07_29_033158_create_matchmaker_duplication_processes_table.php`; `app/Models/Appointment.php:92`; `app/Repositories/FileRepository.php:19`; `app/Utilities/FileUtility.php:104`; `app/Services/SmsService.php:92–119`; migration `2024_12_02_142648_create_api_result_logs_table.php` và candidate-password-reset broker. Checklist này thay thế diễn giải cũ “appointments chỉ xóa pivot”.

## 5. Data Origin & Call Chain

| Dữ liệu | Nguồn đã xác minh / caller cần cung cấp |
|---|---|
| Actor/branch | `auth:userApi` + detectBranchForConsultant; không lấy target scope từ body |
| Selection/send_email (request only) | Frontend confirmation → FormRequest → CandidateService; UI checkbox không phải ownership proof |
| Candidate archive state | CandidateRepository batch include-trashed + branch jobs/expected states + latest matching archive log; repo single-record return `?Model` |
| Recipient/name/DNU | CandidateRepository include-trashed preload; không dùng normal findByEmail để lấy archived owner |
| Branch name/legal entity | BranchRepository/relations preload một lần trước mail loop |
| Template | Resolver hiện hữu qua MailSender boundary; CandidateService không inject EmailTemplateService |
| `profile_deletion_url`, expiry | Server trusted frontend config + generated token → mail recipient context → rendered template; không giả định data array cũ đã có keys |
| Token HTTP input | Email fragment → memory/header → FormRequest → Service digest lookup; không client candidate ID |
| GET deletion response | CandidateService token-check DTO cung cấp can_delete từ actual digest/expiry/owner/log state; Resource đúng một field §3.2.2 |
| POST deletion response | CandidateService synchronous purge DTO deleted=true chỉ sau DB commit; Resource đúng một field §3.2.3 |
| Purge dependency/storage paths | CandidateService preload scoped IDs/files original_candidate_id/conversions → synchronous storage cleanup → DB transaction; không purge job |
| Cleanup results | Storage adapter verified per path/group → Service batch status update nội bộ/operation logs; không expose cho FE |

Trace actual production queue job→Service→MailSender→template parameters trước sửa template. Không viết tests chỉ bơm mock key mà caller thật không truyền.

## 6. Constants / Types / Errors

Public constants ở Model/Service/Contract: batch max100, token random bytes32/purpose/TTL7days (604800 seconds)/hash algorithm SHA-256/in-memory collision max3, archive lifecycle statuses nội bộ, job max100, mail maxattempts3, mail retry5min, preview/confirm rate limits, template type, cache/lock keys. Reuse CandidateJob status constants; không hardcode magic strings/numbers trong queries/conditions. DTOs readonly đúng project convention, Resource dùng `$columns`.

Custom API errors `bulkArchiveStateConflict`, `profileDeletionTokenInvalid`, `profileDeletionTokenUnavailable`, `profileDeletionStateConflict`, `candidateArchived` theo exception/config convention project. Không generic PHP exceptions. Internal helpers private.

## 7. Files / Ownership

Chỉ một coordinating implementation owner trong repo này; không parallel edits vào shared files. Không ghi đè user changes hiện hữu ở AppServiceProvider/config/logging hoặc files unrelated.

| Files | Phạm vi |
|---|---|
| `.specs/GAP-534/001-bulk-archive-auto-communicate.md` | Plan duy nhất, cập nhật quyết định ở đây |
| `app/Models/CandidateArchiveLog.php` + migration tạo table | Archive log/token/lifecycle receipt; không email fields/cleanup payload/counters |
| `app/Models/Candidate.php` chỉ nếu cần constants/relationship | Không migration thêm cột candidate cho archive cycle/token |
| `app/Contracts/Repositories/CandidateArchiveLogRepositoryInterface.php`, `app/Repositories/CandidateArchiveLogRepository.php` | Named batch/latest-log lookup/conditional token claim/cleanup writes; single result `?Model` |
| Candidate/CandidateJob/ActivityLog và dependency Repository interfaces/implementations | Named reads including trashed, batch CAS/archive/purge; pure DB access |
| `app/Contracts/Services/CandidateServiceInterface.php`, `app/Services/CandidateService.php` | Bulk archive, email queue dispatch, synchronous profile purge, candidate signup guard |
| `app/Dto/BulkCandidateArchiveResult.php`, `ProfileDeletionResult.php`, `BatchMailResult.php` | Real operation/delivery/cleanup results |
| `app/Http/Controllers/Api/Consultant/CandidateController.php` | Dùng controller hiện hữu, thêm `bulkArchive`; delegate CandidateService qua FormRequest/Resource, không sửa methods unrelated |
| `app/Http/Requests/Api/Consultant/BulkArchiveCandidatesRequest.php` | Input validation |
| `app/Http/Resources/Api/Consultant/BulkCandidateArchive.php` | `$columns` chỉ archived_candidate_ids/already_archived_candidate_ids |
| `app/Http/Controllers/Api/Candidate/MeController.php` | Dùng controller hiện hữu, thêm `previewProfileDeletion`/`confirmProfileDeletion`; delegate CandidateService, lấy owner qua token thay vì `auth()->user()` |
| `app/Http/Requests/Api/Candidate/PreviewProfileDeletionRequest.php`, `ConfirmProfileDeletionRequest.php` | Token header validation và empty-body contract |
| `app/Http/Resources/Api/Candidate/ProfileDeletionResult.php` | GET đúng can_delete; POST đúng deleted; `$columns`/optionalColumns theo DTO và contract §3.2 |
| Candidate/Consultant `APIErrorException` definitions + `config/api.php` | Custom keys/statuses theo convention |
| `app/Jobs/SendCandidateArchiveEmailJob.php` | Email archive queue wrapper, attempts/backoff/failure hooks; delegate Service |
| `config/queue.php` chỉ nếu cần | Async queue/encryption/worker verification; không thêm recovery command hoặc scheduler |
| `app/Facades/MailSenderAccessor.php`, facade docblock, mail context/helpers cần thiết | Preloaded batch send/truthful results/redaction; giữ behavior callers cũ ngoài thay đổi contract cần thiết |
| `app/Models/EmailTemplate.php`; `database/seeders/data/email_templates.csv`; `database/seeders/EmailTemplateSeeder.php` | Một template type và existing targeted CSV seed |
| `app/Providers/AppServiceProvider.php`; rate-limit provider hiện hữu | Binding repository/limiter; giữ local changes |
| `routes/consultant.php`, `routes/candidate.php`; `config/app.php`; CORS config chỉ nếu cần | Endpoint placement/trusted frontend URL/header |
| `tests/Feature/...`, `tests/Unit/Services/...`, `tests/Unit/Mail/...` | Test impact review/tests ở §8; không Repository unit tests |
| Ba canonical `.business-spec/` files | Chỉ cập nhật implemented routes/schema/flow/schedule **sau implementation và verification** |
| `~/projects/crs-api-docs/docs/` | Cùng owner đồng bộ endpoint docs, request/response examples, errors, auth, flow và route inventory theo §8.1; hoàn tất trước deployment |

Không cần routes/compliance/removal-request controllers/list/template trong thiết kế đã chọn. Không sửa existing single archive/admin purge/restore/CLI reset nếu không cần cho contract hiện tại; nếu share helper phải trace affected callers và test regression. Frontend repo chưa xác định; checkbox/Yes-No/dialog/token fragment/confirmation/deleted UX là dependency để hoàn tất end-to-end.

**Controller reuse đã chốt**: không tạo CandidateArchiveController/ProfileDeletionController. Source xác nhận cả CandidateController và MeController đã inject CandidateServiceInterface. `routes/candidate.php:95` áp dụng auth:candidateApi/checkCandidateLockEdit cho group `/me`, không phải mọi action của MeController; `stopRemindMe` đã có route public ở dòng 52. Hai route `/api/candidate/profile_deletion` giữ URI/contract §3.2, trỏ tới methods mới của MeController và đặt ngoài authenticated/edit-lock/job groups. Không bỏ auth của các route `/me` hiện hữu. **CODE deviation cần triển khai**: hiện chưa có hai deletion methods/routes hoặc job purge theo plan; reuse controller không đồng nghĩa reuse `get`/`update` đang dựa vào authenticated candidate.

## 8. Test Impact Review & Verification

Audit trước code và cập nhật tests liên quan: consultant `CanidateJobsTest.php`, `CandidatesTest.php`, `CandidateTest.php`, `JobsTest.php`; candidate `AuthTest.php`, `PasswordTest.php`, `MePasswordTest.php`, `MeTest.php`, `MeJobsTest.php`; admin/compliance candidate deletion tests; `CandidateServiceTest.php`; EmailTemplateService/Conflict/RichTextMailProcessor/RichTextBase/mail-template tests. Shared mail callers (invitations/appointments/password/welfare/docs) cần affected regression nếu batch helper dùng chung thay đổi.

| Test mới / mở rộng | Coverage bắt buộc |
|---|---|
| `BulkCandidateArchiveTest` (Feature) | Both views, 1/100/max-invalid IDs, distinct/header/auth/branch guards, Permanent/approved/MM/cross-branch active jobs; Yes/No required, archive log cho cả Yes/No, No token null + zero email job/transport, one log/candidate; deleted_at/latest log/shared timestamp/jobs/stars/audit, rollback toàn batch, no-op retry/No→Yes, legacy trashed reject; success body đúng hai ID arrays cho Yes/No/no-op/empty arrays và broker failure sau commit |
| Candidate auth/signup regressions | Staff lists/auth lookup không thấy archived; JWT cũ/refresh/login failure; archived email không unique violation/reset-mail; re-register sau purge thành ID mới |
| `SendCandidateArchiveEmailJobTest` (Feature Job/Integration) | Actual job→Service→mail data origin/join trashed owner, giữ nguyên email content hiện tại, encrypted token payload/failed queue records, after-commit/rollback/no-dispatch No, latest log guard, TTL7days từ issue trước enqueue, retry cùng token/expiry, suppression/truthful outcomes/ambiguous failure, no token logs; zero SQL render loop |
| `ProfileDeletionTest` (Feature) | Actual mail token→GET boolean/no mutation→POST empty-body200/deleted; GET unknown/expired/used/stale/restored/purged/deleted200false, no expiry/status/PII, malformed400/system500 không false; POST replay410/conflict/rollback/header/owner/throttle, synchronous storage/DB failure, only one concurrent commit, latest ID/timestamp guard và link cũ không bind newaccount; timeout không chứng minh deleted |
| Full purge fixtures | Toàn bộ mutation matrix §4.5: mỗi table có owned/other-candidate/shared fixtures; references before histories/welfare before files, appointments và pivots, face rates/declarations/switch requests/MM duplication, progress emails, snapshots/archived original_candidate_id/converted storage, SMS pre-campaign arrays/cost, candidate-only password reset, mọi archive logs null FK; shared resources preserved, no candidate→staff authlog ID collision, oldlink không xóa newaccount; ownership blockers phải có approved mapping tests trước completion |
| Synchronous profile purge coverage | POST không dispatch purge job; preload/ownership, storage-before-DB, storage error/partial success, missing-file idempotence, DB transaction rollback, concurrent commit guard, archive log sống sau hard-delete, token cũ chỉ can_delete=false; ghi rõ giới hạn không rollback storage |
| `MailSenderBatchTest` / service tests | Accurate outcomes/redaction, no false Email Sent, technical helper/constructor bindings; meaningful behavior, không implementation-mirroring-only tests |
| Migration/seed coverage | FK/null receipt behavior, indexes, idempotent master seed khi existing IDs cao, preserve branch custom templates |
| Token generation/collision Service + Feature coverage | Random source giả lập cho collision deterministic trong tests; in-memory regenerate bound, DB unique token_hash rollback toàn archive, không overwrite log cũ/enqueue mail; unique errors khác không bị coi nhầm collision; raw token/hash/expiry mapping đúng production caller |

Instrument SQL **bulk API** với1 vs20 candidates chứng minh DB query count không tuyến tính; dispatch loop chỉ async queue calls, no DB queries. Mỗi email job xử lý một log, không hứa tổng background SQL của20 jobs bằng1 job; query count/job bounded và không SQL render loops/read trong write transactions. PostgreSQL/STG concurrent POST/archive/jobs và restore/mutator race cần verify; SQLite tuần tự không đủ bằng chứng concurrency. Audit current JWT provider/cache/refresh implementation, không chỉ mock missing candidate.

Sau implementation: affected `./vendor/bin/phpunit` suites, rồi full `./vendor/bin/phpunit` do shared CandidateService/mail/seeds. Chỉ claim complete khi tests pass và cleanup completion evidence đủ; ghi rõ baseline failures thay vì claim green. Lượt plan này không chạy tests/migrations/send email thật và không sửa code.

### 8.1. Phase 1 — API Contract/API Docs Sync — bắt buộc trước implementation

Áp dụng rule `AGENTS.md:59–63`. **Impact: có thay đổi API contract/API docs**, không áp dụng `N/A`: GAP-534 thêm bulk archive và public GET/POST profile deletion. Repo `~/projects/crs-api-docs` đã tồn tại; README xác định Markdown là source of truth, Docusaurus là build layer. Phase 1 chỉ cập nhật docs, chưa viết implementation code/migration/config/template trong backend.

**Phase 1 input**: contract §3, source evidence/baseline và route inventory hiện tại.

**Phase 1 output**: docs mô tả đúng contract dự kiến, đánh dấu behavior chưa deploy theo convention của docs repo, kèm diff/file list, validation result, commit SHA và push result.

Đối chiếu routes, FormRequest, Resource, custom errors và production call chain với §3; cập nhật docs trong **cùng task**:

- Tạo `~/projects/crs-api-docs/docs/api/consultant/post-candidates-bulk-archive.md`: consultant/branch auth, `candidate_ids` và `send_email`, guards/limit, ví dụ Yes/No, response đúng hai ID arrays, HTTP 200/202 và error contracts.
- Tạo `~/projects/crs-api-docs/docs/api/candidate/get-profile-deletion.md` và `post-profile-deletion.md`: public token header, token hạn 7 ngày/one-time, GET chỉ `can_delete`, POST không body/chỉ `deleted`, HTTP200 sau synchronous CRS purge, giới hạn storage/DB atomicity và HTTP errors. Ví dụ chỉ dùng token giả, không chứa token/PII thật.
- Cập nhật `~/projects/crs-api-docs/docs/api/consultant/index.md`, `~/projects/crs-api-docs/docs/api/candidate/index.md`, `~/projects/crs-api-docs/docs/api/index.md` và `~/projects/crs-api-docs/docs/_meta/route-coverage.md` cho ba method/route mới; đối chiếu `source-inventory.md` và `openapi-drift.md`, cập nhật khi có thay đổi tương ứng.
- Cập nhật phần liên quan trong `~/projects/crs-api-docs/docs/authentication.md`, `~/projects/crs-api-docs/docs/errors.md`, `~/projects/crs-api-docs/docs/flows/candidate-lifecycle.md`, `~/projects/crs-api-docs/docs/operations/queue-and-events.md`: token auth riêng, numeric error codes thực tế, soft archive → email Yes/No queue → synchronous CRS storage/DB purge. Đánh dấu các routes/behavior chưa deploy theo convention repo docs.

**Phase 1 gate pass**: review diff chỉ thuộc GAP-534, kiểm tra schemas/examples/error codes/auth khớp §3 và source evidence; chạy `npm run build` tại `~/projects/crs-api-docs`, kiểm tra links/pages của ba endpoints, commit docs và push commit lên remote `main`. Ghi danh sách files/diff, build/contract review result, commit SHA và push result vào plan; chỉ đánh dấu Phase 1 passed khi có đủ evidence. Build không bao gồm publish/deploy site.

**Phase 1 evidence (2026-10-12)**: Updated files: `docs/api/consultant/post-candidates-bulk-archive.md`, `docs/api/candidate/get-profile-deletion.md`, `docs/api/candidate/post-profile-deletion.md`, candidate/consultant/API indexes, `docs/_meta/route-coverage.md`, `docs/_meta/source-inventory.md`, `docs/authentication.md`, `docs/errors.md`, `docs/flows/candidate-lifecycle.md`, `docs/operations/queue-and-events.md`. `git diff --check`: PASS. `npm run build` in `~/projects/crs-api-docs`: PASS, Docusaurus generated static files. Commit: `ea0a16c` (`docs: add GAP-534 archive and profile deletion contract`). Push: PASS, `origin/main` advanced `3dc252e..ea0a16c`. All three new endpoints are explicitly marked `PLANNED — NOT YET DEPLOYED`; runtime route counts remain unchanged.

Nếu repo không tồn tại, không thể ghi hoặc chưa đồng bộ/build chưa pass, báo blocker và dừng trước deployment code; không báo deployment complete. Quyền ghi repo docs cần được xác minh lúc triển khai; việc đọc được repo trong lượt plan này không chứng minh đã có quyền ghi.

**Phase 2 entry gate**: Phase 1 docs sync/build/commit/push đã pass và user approve plan; sau đó mới được viết backend code/config/template/migration.

**Phase 1 amendment evidence (2026-10-13)**: Updated `docs/api/consultant/post-candidates-bulk-archive.md` with the structured `invalidParams` error example and reason catalog, and `docs/errors.md` with the consultant error-family note. `git diff --check`: PASS. `npm run build`: PASS. Commit `26038e4` (`docs: document bulk archive invalid candidate details`) pushed successfully to `origin/main` (`57d8718..26038e4`). Phase 2 implementation may proceed for this approved error-contract delta.

**Phase 1 reason-catalog amendment evidence (2026-10-13)**: Added
`archived_state_conflict` to the bulk-archive reason catalog and rebuilt the
docs successfully. Commit `2f3fbe5` (`docs: add archive state conflict reason`)
pushed successfully to `origin/main` (`26038e4..2f3fbe5`).

## 9. Acceptance / Review Gate

- [x] Merge vào plan GAP-534 hiện hữu, không tạo plan trùng.
- [x] User chọn soft archive + email deletion link + one-time token 7 ngày.
- [x] User chốt random token32bytes + SHA-256; expiry/atomic one-time trong DB; unique digest chặn collision trước enqueue mail, không dùng JWT deletion token.
- [x] User xác nhận giữ consultant Yes/No theo Jira.
- [x] User chọn candidate_archive_logs + queue jobs; đã bỏ phương án/bảng notification và đồng bộ API/flow/files/tests.
- [x] GET/POST deletion contracts tách riêng: shared headers/auth, body/validation, GET can_delete/POST deleted, HTTP errors/token lifecycle; FE không polling hoặc map lifecycle statuses.
- [x] Bulk archive success response chỉ archived_candidate_ids và already_archived_candidate_ids; không counts/email errors/token/wrapper.
- [x] Log không lưu email/send-email/delivery state/attempts; email join Candidate gồm trashed; send_email chỉ request.
- [x] Không giữ cleanup payload/retry counters trong log; email queue chỉ cho email archive, profile purge synchronous với DB transaction và storage atomicity limitation được ghi rõ.
- [x] Bỏ trạng thái tab input và batch UUID; log ID/latest state bảo vệ từng lần archive; không migration cột Candidate.
- [x] Logs cho cả Yes/No; token/email queue chỉ Yes; retry cùng token/expiry bằng encrypted job; receipt sống sau hard-delete.
- [x] Public deletion API tối giản: GET boolean can_delete, POST200 deleted=true sau synchronous CRS purge; FE không polling/claim completed.
- [x] Không login/OTP/password; GET không xóa; FE dialog confirm rồi POST không body, chỉ token header.
- [x] Expiry không tự purge; token chỉ đúng candidate/cycle/purpose.
- [x] Mail đọc archived owner; token/receipt survive workflow; DB purge atomic, giới hạn storage rollback được ghi rõ.
- [x] Có source evidence/deviations, data origin, contracts/file ownership/test gate.
- [x] Đã ghi data mutation matrix §4.5 cho archive, synchronous POST storage/DB purge, retained/shared resources và ownership blockers; bổ sung test impact tương ứng.
- [ ] Freeze §4.5: chốt invitation/MM mirror/API-log ownership, embedded/shared storage paths, SMS empty-list/cost và candidate-state serialization; đối chiếu deployed schema trước rollout.
- [x] Đã đánh giá API docs impact và thêm Phase 1 docs-first `~/projects/crs-api-docs` cùng task theo rule mới.
- [x] Phase 1 API docs sync §8.1 passed: files/diff, contract review, build, commit SHA và push-to-main evidence đã ghi ở §8.1.
- [ ] Review global soft-delete impact, cross-branch/worker guards, signup behavior, 100-ID/current-page selection và tab mapping; bỏ input tab không bỏ DB eligibility guards.
- [x] Chốt giữ nguyên email content hiện tại theo Jira; không tự sáng tạo hoặc chỉnh sửa nội dung mail. Chỉ verify placeholder, deletion URL/token và branch name.
- [x] Chốt phạm vi “our system” là CRS; MatchMaker/provider out of scope, không gọi external deletion API.
- [ ] Xác nhận đầy đủ CRS DB/storage purge inventory trước implementation.
- [ ] Xác minh transport/tester/DNU, async Redis/SQS email worker/encrypted payload, rate limits, synchronous storage-before-DB behavior và manual retry/post-state monitoring trên môi trường rollout.
- [x] **Phase 2 email content source**: Jira GAP-534 description cung cấp body nguyên văn; comment 21128/attachment 16318 chỉ là ảnh menu UI, không phải email content. Seeder dùng body trong description, không tự đặt subject (`title=''`) hoặc sửa copy.
- [x] Phase 2 backend implementation and verification: bulk archive, encrypted post-commit email job, synchronous CRS profile deletion, migration/model/repositories, routes/requests/config/errors and feature coverage are implemented and verified by the recorded test gates.
- [x] User approve plan; Phase 1 docs-first gate passed trước bất kỳ backend code/config/template/migration implementation.

### Phase 2 execution record — email template and backend implementation

- Source: Jira GAP-534 description, fetched 2026-10-12; body giữ nguyên các placeholder `{CandidateName}`, `{here}`, `{branch name}` và nguyên văn tiếng Anh.
- Backend files: `database/seeders/data/email_templates.csv`, `app/Models/EmailTemplate.php`; dùng `EmailTemplateSeeder` hiện tại, không tạo seeder riêng.
- Seeder behavior: thêm row master `id=53`, `type=candidate_archive`; giữ cách import CSV hiện hữu và không thêm registration ngoài `EmailTemplateSeeder`.
- Validation: chạy test suite với SQLite in-memory để cover `DatabaseSeeder`/`EmailTemplateSeeder` và CSV multiline parsing.
- Seeder-stage full verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (613 tests, 9,289 assertions) before the backend implementation tests were added.
- Seed execution: `php artisan db:seed --class=EmailTemplateSeeder` không chạy được trên workspace vì `.env` trỏ PostgreSQL host `pgsql` nhưng host không resolve; `127.0.0.1:5432` cũng không có PostgreSQL listener. CSV đã được parse và verify trong test SQLite in-memory, nhưng chưa ghi vào DB local/staging persistent.

**Phase 2 backend implementation record (2026-10-12)**:

- Migration/model/repository: `candidate_archive_logs`, `CandidateArchiveLog`, `CandidateArchiveLogRepository`, `CandidatePurgeRepository`; archive receipts retain candidate ownership metadata after purge and mark only the consumed log `deleted`.
- Bulk archive call chain: `BulkArchiveRequest` → `CandidateController::bulkArchive` → `CandidateService::bulkArchive` → named CandidateRepository batch reads/writes. Candidate/job/star/log writes are in one DB transaction; email jobs dispatch only after commit and use `ShouldBeEncrypted`.
- Profile deletion call chain: public `ProfileDeletionRequest` → `MeController::previewProfileDeletion`/`confirmProfileDeletion` → `CandidateService`; storage paths and SMS pre-campaign rows preload before the writes-only purge transaction. CRS-owned candidate data, tracking/activity logs and candidate-owned relationships are deleted synchronously; MatchMaker/provider data is out of scope.
- Routes/config/errors/bindings: `routes/consultant.php`, `routes/candidate.php`, `config/app.php`, `config/api.php`, `RepositoryServiceProvider`. Success bodies remain exactly the two bulk arrays, `can_delete`, and `deleted` as documented.
- Tests added: `tests/Feature/Api/Consultant/CandidateArchiveTest.php` covers atomic bulk mutations, encrypted email-job dispatch boundary, token preview/confirm, archive receipt retention and hard purge.
- Targeted verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit tests/Feature/Api/Consultant/CandidateArchiveTest.php` — PASS (3 tests, 18 assertions).
- API docs post-implementation sync: `~/projects/crs-api-docs` build and `git diff --check` PASS; docs commit `b8077ed` (`docs: mark GAP-534 routes code-verified`) pushed successfully to `origin/main`.
- Living spec sync: `.business-spec/backend-business-flow-spec.md`, `.business-spec/backend-api-route-inventory.md`, and `.business-spec/backend-database-relationship.md` updated with the code-verified CRS routes, flow, and `candidate_archive_logs` relationship.
- Static verification: `php -l` passed for all new PHP files; backend `git diff --check` passed.
- Full verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (616 tests, 9,307 assertions).
- Runtime seed/migration execution remains environment-blocked: `.env` PostgreSQL host `pgsql` is unresolved and localhost has no listener; no persistent local/staging DB was modified by this workspace run.

**Invalid-candidate error-contract implementation record (2026-10-13)**:

- `CandidateService::bulkArchive` now completes all pre-mutation checks from
  the batch-loaded candidate collection, collects every rejected ID, and
  returns consultant `invalidParams` entries with per-candidate `reasons`.
- Implemented reason constants: `not_available_in_selected_branch`,
  `candidate_is_permanent`, `matchmaker_status_not_archivable`,
  `no_archivable_candidate_job`, `candidate_has_blocked_job`, and
  `archived_state_conflict`; blocked job statuses and MatchMaker status are
  included when available. Matching already-archived candidates remain
  idempotently valid.
- Batch atomicity is unchanged: any pre-mutation invalid candidate rejects the
  complete request and no valid candidate is partially archived; no database
  query was added inside the validation loop.
- Feature coverage added to `tests/Feature/Api/Consultant/CandidateArchiveTest.php`.
- Targeted verification: PASS (4 tests, 28 assertions).
- Full verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (617 tests, 9,317 assertions).
- API docs reason-catalog amendment: build and `git diff --check` PASS; commit
  `2f3fbe5` pushed to `origin/main` after `26038e4`.

### Post-approval delta — split `bulkArchive()` orchestration

- Refactor `CandidateService::bulkArchive()` into private helpers without
  changing the public service contract, HTTP payload, validation reasons,
  repository calls, transaction semantics, or email dispatch timing.
- Keep the public method as orchestration for input normalization, batch
  context loading, validation, archive preparation, atomic writes, post-commit
  email dispatch, and response mapping.
- Extract cohesive private boundaries for candidate validation, archive log/token
  preparation, the writes-only atomic archive transaction, and post-commit email
  dispatch. Candidate validation helpers must use the already eager-loaded
  collection and must not issue queries inside loops.
- Keep all extracted helpers in `CandidateService`; do not create another
  Service or move business rules into Repositories. Preserve private visibility
  for internal helpers.
- Acceptance: existing targeted/full PHPUnit suites remain green, API response
  JSON is unchanged, and `git diff --check` passes.

**Refactor implementation record (2026-10-14)**:

- `CandidateService::bulkArchive()` now orchestrates private helpers for input
  normalization, batch validation, archive data preparation, atomic writes, and
  post-commit email dispatch. No public contract, repository call semantics,
  transaction scope, or queue timing changed.
- Existing `CandidateArchiveTest` coverage remains green after the refactor.
- `php -l app/Services/CandidateService.php`: PASS.
- Targeted verification: PASS (4 tests, 28 assertions).
- Full verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (617 tests, 9,317 assertions).
- Backend `git diff --check`: PASS. Backend changes remain uncommitted.

### Post-approval delta — document `CandidateArchiveLog` properties

- Add PHPDoc `@property` annotations for the model fields used by the archive
  and profile-deletion flow, including IDs, status, token hash/expiry/used time,
  and timestamps.
- Documentation-only model change; no schema, cast, runtime behavior, API
  contract, or test behavior change is intended.

**CandidateArchiveLog PHPDoc implementation record (2026-10-14)**:

- Added `@property` annotations for IDs, status, token fields, and Carbon
  timestamp fields in `app/Models/CandidateArchiveLog.php`.
- PHP lint: PASS. Backend `git diff --check`: PASS.
- Full verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (617 tests, 9,317 assertions).

### Post-approval delta — return invalid candidate IDs

- Requirement: when bulk archive validation rejects candidates, the response
  must identify every rejected input candidate instead of failing on the first
  ID with only a generic message.
- Keep the existing error code/status `bulkArchiveStateConflict` / `1020` / `409`.
- Add structured `invalidParams` entries to the consultant error response,
  identifying each rejected `candidate_id` and its `reasons`. Supported reasons
  are `not_available_in_selected_branch`, `candidate_is_permanent`,
  `matchmaker_status_not_archivable`, `no_archivable_candidate_job`, and
  `candidate_has_blocked_job`; one candidate may contain multiple reasons.
  Preserve all-or-nothing batch behavior and do not partially archive valid IDs.
- `approved`/`matchmaker` blocked-job statuses should be included as reason
  detail where available. A candidate already archived in the matching cycle is
  idempotently valid and must not be reported as invalid.
- The IDs must be computed from the already batch-loaded collection and
  in-memory validation; no database query is allowed inside the candidate loop.
- This is an API error payload change. Before implementation, update the
  corresponding API docs/error example and add Feature coverage for multiple
  invalid IDs and rejection reasons.

## 10. Thứ tự triển khai sau approve

### Phase 1 — API docs first

1. Đọc approved plan/skills/source/tests và freeze API/data contracts ở §3.
2. Cập nhật `~/projects/crs-api-docs` theo §8.1, đánh dấu routes/behavior chưa deploy theo convention docs repo.
3. Review contract/examples/errors/routes, chạy docs build/link checks, commit docs changes và push lên remote `main`.
4. Ghi files/diff, validation result, commit SHA và push result vào plan. Nếu gate không pass thì dừng, không viết backend code.

### Phase 2 — Backend implementation and verification

1. Chỉ bắt đầu sau Phase 1 gate pass và user approve plan; đọc lại skills/source/tests, freeze dependency cleanup mapping; giữ user changes hiện hữu.
2. Database/types: migrations/model/constants/DTO, log/receipt và template seeder contract.
3. Repository/interfaces: named batch reads/conditional writes/purge order/bindings.
4. Service: bulk archive/signup guard, email queue job, synchronous profile purge/storage trước DB transaction (không purge job/recovery cron); kiểm tra không Service→Service/N+1/read transaction.
5. Controller/FormRequest/Resource/routes, queue jobs/limiters và frontend integration theo contract.
6. Test impact audit → affected/full PHPUnit → concurrency/STG/mail/cleanup evidence → self-check against acceptance → living specs cập nhật sau implement.
7. **Deployment readiness**: chỉ tiếp tục rollout đã được authorize khi code/test/living specs và Phase 1 docs sync đều pass; repo docs thiếu/không ghi được/chưa sync là blocker. Plan không tự cấp quyền deployment hoặc publish docs.

Rollout chỉ khi migrations/master template/trusted frontend link/async email queue workers sẵn sàng; không phát hành email link hứa xóa khi synchronous purge chưa hoạt động. Rollback phải dừng email dispatch/workers và giữ archive receipts/file metadata cùng pending encrypted email queue payloads; không drop bảng log khi còn cleanup. Không xóa pending email queue jobs trước khi xác định và lưu recovery state. Không chạy old archive CLI làm bước thử bulk workflow mới.

### Post-approval delta — remove unused bulk-archive repository method

- Remove `getActiveCandidatesForBulkArchive()` from
  `CandidateRepository` and `CandidateRepositoryInterface` because the current
  `CandidateService::bulkArchive()` uses `getCandidatesForBulkArchive()` and
  performs the complete validation in the Service to return per-candidate
  invalid reasons.
- No API contract, database behavior, transaction scope, or runtime bulk archive
  flow change is intended.
- Verification: search for remaining references, run PHP lint on the changed
  repository files, run the affected CandidateArchive feature test and the full
  PHPUnit suite, then run `git diff --check`.

**Unused-method removal implementation record (2026-10-14)**:

- Removed `getActiveCandidatesForBulkArchive()` from
  `CandidateRepository` and `CandidateRepositoryInterface`.
- Confirmed no remaining references in the repository outside `vendor/`.
- PHP lint: PASS for both changed PHP files.
- Targeted verification: `CandidateArchiveTest` PASS (4 tests, 28 assertions).
- Full verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (617 tests, 9,317 assertions).
- Backend `git diff --check`: PASS.

### Post-approval delta — hard-purge storage ordering and local duplication cleanup

- Move candidate file `Storage::delete()` calls from before the profile-deletion
  database transaction to after the transaction commits successfully. File paths
  remain preloaded before the transaction, but physical storage deletion must
  never happen while the database state can still roll back.
- A post-commit storage failure cannot roll back the already committed database
  purge. Log the candidate ID and affected paths for recoverable orphan-storage
  cleanup without converting a successful database deletion into a retryable
  token failure.
- Extend `CandidatePurgeRepository::purgeCandidateData()` to delete local
  `match_maker_duplication_processes` rows by `candidate_id` inside the existing
  database transaction. This is CRS-local candidate-owned state; external
  MatchMaker/provider data remains out of scope.
- No API contract, migration, external MatchMaker behavior, or archive flow
  change is intended. API docs: N/A — no API contract/API docs change.
- Verification: add/update profile-deletion Feature coverage for transaction
  rollback preserving storage files and successful post-commit cleanup, cover
  duplication-process cleanup, run PHP lint, affected tests, full PHPUnit, and
  `git diff --check`. Update the living business/database specs with the final
  ordering and relationship behavior after implementation.

**Storage-ordering and local-relationship cleanup implementation record (2026-10-14)**:

- Profile deletion now commits the database purge before deleting preloaded
  candidate storage paths. Post-commit storage failures are logged as
  recoverable orphan-storage cases and do not invalidate the committed purge.
- `CandidatePurgeRepository` now deletes local
  `match_maker_duplication_processes` rows by candidate ID inside the purge
  transaction; external MatchMaker/provider records remain out of scope.
- Feature coverage verifies successful post-commit storage cleanup,
  duplication-process cleanup, and storage preservation when the DB state
  conflict rolls back the transaction.
- PHP lint: PASS for changed PHP files.
- Targeted verification: `CandidateArchiveTest` PASS (5 tests, 40 assertions).
- Full verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (630 tests, 9,361 assertions).
- Living specs updated: `.business-spec/backend-business-flow-spec.md` and
  `.business-spec/backend-database-relationship.md`; API docs: N/A — no
  contract change.
- Backend `git diff --check`: PASS.

### Post-approval delta — inline trivial bulk-archive helper

- Inline the single-use `getExpectedBulkArchiveJobUpdates()` calculation into
  `CandidateService::bulkArchive()` and remove the private helper.
- Keep the other private helpers because they represent separate validation,
  data-preparation, transaction, or post-commit dispatch responsibilities.
- No API contract, database behavior, transaction scope, queue timing, or
  business rule change is intended.
- Verification: PHP lint, affected CandidateArchive feature test, full PHPUnit,
  and `git diff --check`.

**Trivial-helper inline implementation record (2026-10-14)**:

- Inlined the expected candidate-job update count calculation into
  `CandidateService::bulkArchive()` and removed the single-use
  `getExpectedBulkArchiveJobUpdates()` helper.
- The bulk archive business logic, transaction boundary, API contract, and
  queue timing remain unchanged.
- PHP lint: PASS.
- Targeted verification: `CandidateArchiveTest` PASS (4 tests, 28 assertions).
- Full verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (617 tests, 9,317 assertions).
- Backend `git diff --check`: PASS.

### Post-approval delta — Finding 1: enforce consultant branch authorization

#### 1. Finding và baseline đã xác minh

- `POST /api/consultant/candidates/bulk_archive` nằm sau middleware
  `detectBranchForConsultant`, middleware lấy `Gap-Branch-ID` từ request header
  và gọi `UserService::allowToAccessTheBranch()` trước khi gắn `branch_id` vào
  request.
- `UserService::allowToAccessTheBranch()` hiện coi mọi user có role
  `consultant` là được truy cập mọi branch, vì `ROLE_CONSULTANT` đang nằm trong
  nhánh bypass trước khi gọi
  `UserBranchRepository::existByUserIdAndBranchAndRole()`.
- Đây là authorization bypass nghiêm trọng hơn khi áp dụng cho bulk archive:
  consultant có thể gửi branch ID bất kỳ và kích hoạt archive hàng loạt cùng
  các side effect purge qua email deletion link.
- Phạm vi ảnh hưởng không chỉ bulk archive: mọi consultant route dùng
  `detectBranchForConsultant` sẽ dùng chung helper authorization này. Cần sửa
  centralized rule và regression-test các route quan trọng, không thêm guard
  riêng trong `CandidateController`.

#### 2. Quyết định contract cần approve

- `ADMIN` và `COMPLIANCE` giữ nguyên blanket branch access hiện tại khi user có
  đúng role.
- `CONSULTANT` không được blanket bypass. User phải có row trong
  `user_branches` với `user_id`, `branch_id` được yêu cầu và role
  `consultant` trong JSON `roles`.
- `can_access_all_branches` không tự tạo bypass mới cho consultant trong scope
  này; quyền consultant vẫn được quyết định bằng branch membership hiện có.
- Consultant có membership hợp lệ được tiếp tục qua middleware và nhận đúng
  behavior hiện tại.
- Consultant không có membership, hoặc gửi `Gap-Branch-ID` của branch khác,
  bị reject tại middleware với HTTP/error contract hiện tại
  `branchAccessNotAllowed`; controller/service không được chạy và không có DB
  mutation, queue dispatch hoặc storage side effect.
- Không thay đổi request body, response success payload, candidate validation
  reasons, archive transaction, email template/content, token hoặc purge
  scope của GAP-534.

#### 3. API docs-first phase

**Phase 1 — API docs assessment/update trước backend code**

1. Review docs contract của
   `POST /api/consultant/candidates/bulk_archive`, đặc biệt auth/header,
   branch scope và lỗi `branchAccessNotAllowed`.
2. Nếu docs hiện chưa mô tả đủ branch membership, update tối thiểu các file
   thuộc contract:
   - `~/projects/crs-api-docs/docs/api/consultant/post-candidates-bulk-archive.md`
   - `~/projects/crs-api-docs/docs/flows/candidate-lifecycle.md` nếu flow
     archive có mô tả branch authorization.
   - route/coverage metadata chỉ khi validation hiện tại yêu cầu thay đổi.
3. Ghi rõ consultant phải có `user_branches` membership cho branch header;
   request branch không được phép trả lỗi authorization hiện tại và không có
   mutation. Không thay đổi error code/message nếu source contract hiện tại đã
   khớp.
4. Chạy docs build, link/format checks và `git diff --check`; đánh dấu docs
   behavior theo convention repo.
5. Chỉ khi docs pass mới commit các file docs thuộc Finding 1 và push commit
   lên remote `main`. Ghi file diff, validation result, commit SHA và push
   result vào plan trước khi bắt đầu Phase 2.

**Phase 1 acceptance gate**: docs phản ánh đúng branch-membership rule,
`branchAccessNotAllowed` error và no-mutation boundary; docs checks pass; docs
commit đã push thành công lên `main`.

#### 4. Backend implementation phase

**Phase 2 — centralized authorization fix và verification**

1. Sau Phase 1 pass và user approve delta này, sửa
   `app/Services/UserService.php` để chỉ `ADMIN`/`COMPLIANCE` giữ bypass;
   `CONSULTANT` đi qua `UserBranchRepository::existByUserIdAndBranchAndRole()`.
2. Không query trong loop, không thêm query/logic vào Controller hoặc
   `CandidateService`; giữ middleware làm điểm resolve branch và giữ
   architecture `Middleware → UserService → UserBranchRepository`.
3. Audit toàn bộ routes dùng `detectBranchForConsultant`; xác nhận thay đổi
   centralized này không phá behavior của consultant có membership và không
   mở quyền cho branch ngoài membership.
4. Bổ sung/update Feature tests, tối thiểu:
   - consultant có membership đúng branch: bulk archive vẫn thành công;
   - consultant gửi branch khác/không có membership: middleware trả
     `branchAccessNotAllowed`, HTTP error hiện tại, candidate không bị soft
     delete, candidate job/star/archive log không đổi và không enqueue email;
   - admin/compliance blanket access hiện tại không regression;
   - consultant role có `can_access_all_branches=true` nhưng không có
     membership vẫn không được dùng cờ này để bypass trong rule mới;
   - regression cho ít nhất một consultant read/update route dùng cùng
     middleware, nếu test inventory cho thấy route đó có coverage hiện hữu.
5. Test impact review các test consultant branch và user branch hiện có; không
   tạo Repository unit test. Nếu cần test business method độc lập thì đặt tại
   `tests/Unit/Services/`, còn authorization boundary ưu tiên Feature test.
6. Chạy `php -l` các PHP files sửa, affected PHPUnit suites và full
   `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit`;
   chạy `git diff --check` và self-check theo contract này.

#### 5. Files ownership dự kiến

| File | Thay đổi dự kiến |
|---|---|
| `app/Services/UserService.php` | Bỏ consultant khỏi blanket bypass; giữ admin/compliance rule |
| `tests/Feature/Api/Consultant/CandidateArchiveTest.php` | Thêm cross-branch authorization/no-mutation coverage cho bulk archive |
| `tests/Feature/Api/Consultant/CandidatesTest.php` hoặc test phù hợp đã có | Regression route dùng `detectBranchForConsultant`, chỉ sửa nếu cần |
| `tests/Feature/Api/User/...` | Chỉ sửa nếu test hiện hữu trực tiếp assert branch authorization helper behavior |
| `~/projects/crs-api-docs/...` | Docs-first contract update và commit/push theo Phase 1 |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật current branch authorization behavior sau implementation |
| `.business-spec/backend-api-route-inventory.md` | Cập nhật nếu route middleware/error contract được mô tả chưa đúng |

Không tạo migration, model, repository mới, exception mới, email template,
queue job hoặc thay đổi MatchMaker/purge logic cho Finding 1.

#### 6. Rollout/verification boundary

- Không triển khai backend code trước khi docs Phase 1 pass và được ghi nhận
  trong plan.
- Không cần migration hoặc data backfill; rule đọc membership hiện hữu trong
  `user_branches`.
- Rollback code là khôi phục điều kiện authorization cũ, nhưng không được dùng
  rollback để cấp lại quyền cross-branch nếu security finding chưa được đánh
  giá; mọi rollback phải được ghi nhận cùng impact.
- **Trạng thái delta sau Phase 1**: `PHASE 1 PASS — sẵn sàng Phase 2`; chưa sửa
  backend, chưa chạy migration, chưa commit/push backend.

**Finding 1 Phase 1 implementation record (2026-10-14)**:

- API docs updated:
  - `~/projects/crs-api-docs/docs/api/consultant/post-candidates-bulk-archive.md`
  - `~/projects/crs-api-docs/docs/flows/candidate-lifecycle.md`
- Docs now state that consultants must have a matching `user_branches` row with
  the `consultant` role, arbitrary `Gap-Branch-ID` and consultant
  `can_access_all_branches` do not bypass membership, and middleware rejection
  has no candidate/job/star/archive-log/email-job mutation.
- Docs explicitly mark the security hardening as `NOT DEPLOYED` until backend
  Phase 2 is complete.
- `npm run build`: PASS.
- Docs `git diff --check`: PASS.
- Docs commit: `fc5698c` (`docs(GAP-534): document consultant branch authorization`).
- Push: PASS to `origin/main`.
- Phase 1 gate: PASS. Backend Phase 2 is now authorized to proceed under the
  approved contract above.

**Finding 1 Phase 2 implementation record (2026-10-14)**:

- `UserService::allowToAccessTheBranch()` now keeps blanket access only for
  users with global `ADMIN`/`COMPLIANCE` role. `CONSULTANT` falls through to
  `UserBranchRepository::existByUserIdAndBranchAndRole()` and must have the
  requested branch membership with the consultant role.
- No controller, middleware, CandidateService, repository contract, migration,
  email, queue, purge or MatchMaker logic was added/changed. The existing
  middleware remains the centralized rejection boundary and returns the current
  `branchAccessNotAllowed` response before service execution.
- Feature coverage added for bulk archive cross-branch rejection with
  `can_access_all_branches=true`; candidate, candidate job, star, archive log
  and email queue remain unchanged after rejection.
- Existing consultant Feature fixtures were updated only where they used a
  branch in the request without assigning that branch to the authenticated
  consultant. Existing compliance/consultant mixed-role fixture was updated to
  express both memberships explicitly; no production role rule was broadened.
- Living business spec updated:
  `.business-spec/backend-business-flow-spec.md`. Route inventory already
  listed `detectBranchForConsultant`; no route declaration change was needed.
- PHP lint: PASS for all changed PHP files.
- Targeted GAP-534 archive test: PASS (6 tests, 47 assertions).
- Full consultant Feature suite: PASS (150 tests, 778 assertions).
- Full PHPUnit: PASS (631 tests, 9,368 assertions).
- Backend `git diff --check`: PASS.
- Final docs sync after implementation: `npm run build` PASS and docs
  `git diff --check` PASS; commit `bd5e55f`
  (`docs(GAP-534): verify branch authorization guard`) pushed successfully to
  `origin/main`. Initial docs-first commit was `fc5698c`.
- **Finding 1 status**: `DONE` on working tree; backend changes remain
  uncommitted and production deployment/persistent DB behavior remain
  unverified.

### Post-implementation clarification — require global and branch consultant roles

- The current Finding 1 implementation removes `ROLE_CONSULTANT` from the
  blanket branch bypass and falls through to the branch-membership lookup.
- Contract clarification: consultant branch access must require both:
  1. the authenticated `User` has the global `consultant` role; and
  2. `user_branches` contains the requested branch with `consultant` in its
     `roles` JSON.
- A user who has only the branch-level consultant role but lacks the global
  consultant role must be rejected with the existing
  `branchAccessNotAllowed` response. This prevents a branch row from granting
  consultant privileges by itself.
- Keep the existing behavior for global `ADMIN`/`COMPLIANCE` blanket access.
  No migration, route, archive, email, queue, purge or MatchMaker behavior
  changes are needed.
- Update API docs to state the dual-role requirement, add Feature coverage for
  branch-role-only rejection, rerun affected/full PHPUnit and docs build, then
  update the implementation record.
- **Status**: `SUPERSEDED — không thuộc scope GAP-534`.

### Scope decision — defer shared consultant branch authorization to security task

- Finding 1 là lỗi authorization dùng chung của
  `allowToAccessTheBranch()`/`detectBranchForConsultant`, ảnh hưởng nhiều
  consultant endpoint chứ không chỉ bulk archive. Không tiếp tục sửa logic này
  trong GAP-534.
- GAP-534 giữ nguyên scope archive/profile deletion đã được approve; không yêu
  cầu global-role + branch-role dual check trong task này.
- Security follow-up riêng phải chốt và implement rule:
  `global consultant role AND branch-level consultant role`, đồng thời audit
  toàn bộ consultant routes dùng middleware chung.
- Các backend test fixture/docs được thêm riêng cho Finding 1 trong working
  tree/docs repo phải được rollback hoặc revert khỏi GAP-534 trước khi đóng
  task. Không dùng rollback để xóa các thay đổi unrelated của user.
- API docs synchronization cho Finding 1 phải được revert về contract hiện tại;
  commit revert docs cần được ghi nhận nếu đã push lên `origin/main`.
- **Trạng thái**: `SCOPE DEFERRED — chờ approve rollback các thay đổi Finding 1`.

**Finding 1 rollback implementation record (2026-10-14)**:

- Rolled back the uncommitted `UserService` authorization change and all
  Finding 1-only Feature fixture/test changes from the GAP-534 backend
  worktree. Existing unrelated user changes were preserved.
- Reverted the two Finding 1 docs changes in `crs-api-docs`; docs build and
  `git diff --check` passed before the revert commit.
- Docs revert commit: `4f9820f`
  (`revert(GAP-534): defer branch authorization docs`) pushed successfully to
  `origin/main`.
- Backend `git diff --check`: PASS; no Finding 1 backend diff remains.
- Full PHPUnit after rollback: PASS (630 tests, 9,361 assertions).
- GAP-534 no longer changes shared consultant branch authorization. Finding 1
  is deferred to a separate security task requiring the agreed dual check:
  global consultant role **and** branch-level consultant role.

## Latest plan revision — reuse existing archive/delete logic (2026-10-19)

Phần này là source of truth mới nhất cho implementation tiếp theo. Các phần
trước mô tả candidate_archive_logs, random one-time token, token expiry,
token consumption, CandidatePurgeRepository và contract POST không body chỉ
còn là historical record; không được implement lại các quyết định đó.

**Rule ưu tiên tái sử dụng**: mọi bước implementation phải bắt đầu bằng việc
trace và đánh giá code hiện có. Ưu tiên gọi lại hoặc mở rộng có kiểm soát
`CandidateRepositoryInterface`, `CandidateService`, `StringUtility`,
`ProfileDeletionRequest`, email template/seeder và các contract hiện hữu. Không
tạo một method/service/repository/job/table mới nếu có thể dùng lại logic hiện
tại với thay đổi tối thiểu. Nếu bắt buộc tạo mới, phải ghi rõ trong plan
business behavior nào chưa có, vì sao không thể tái sử dụng, và cách bảo đảm
không duplicate logic với caller cũ.

### R1. Archive candidate jobs bằng repository hiện hữu

CandidateRepositoryInterface::archiveCandidateJobsByBranch() hiện đã có trong
working tree tại app/Contracts/Repositories/CandidateRepositoryInterface.php
và implementation tại app/Repositories/CandidateRepository.php. Vì vậy,
không tạo thêm một method archive khác. Nếu branch triển khai thực tế chưa có
method này, bổ sung đúng contract hiện tại:

- nhận candidateIds, branchId, danh sách status được archive, status đích và
  archivedAt;
- dùng một set-based UPDATE trên candidate_jobs;
- scope bằng candidate_id IN (...), job.branch_id = branchId và
  status IN (...);
- chỉ update candidate_jobs.status và candidate_jobs.updated_at;
- trả về số row thực sự được update.

Service sẽ preload và validate candidate/branch trước transaction, sau đó gọi
method này một lần trong transaction cùng các write archive khác. Không gọi
repository này trong loop và không dùng nó để update Candidate, stars, email,
activity log hoặc deletion state.

#### Phạm vi logic phải kiểm tra lại trước code

Current implementation dùng CandidateJob::ARCHIVABLE_STATUSES, hiện gồm
screening_call và interview, và target CandidateJob::STATUS_ARCHIVED. Đây là
phạm vi duy nhất được phép đưa vào bulk archive theo revision này, trừ khi user
approve thay đổi khác.

Các điểm có thể outdate hoặc khác với archive đơn:

- archiveCandidateJobsByBranch() không tự bỏ qua matchmaker; việc này được bảo
  đảm bằng allowlist status đầu vào, không được truyền thêm approved/matchmaker
  một cách ngầm định;
- method này không thực hiện nhánh unarchive, không gửi welcome-back email,
  không detach star và không xử lý side effect của
  CandidateService::updateCandidateJobStatus();
- method này update mọi candidate job đủ điều kiện của candidate trong branch
  được truyền vào, không chỉ một selected job. Cần xác nhận đây là phạm vi
  mong muốn của bulk archive;
- method này không archive job ở branch khác. Tuy nhiên Candidate.deleted_at
  là global, nên Service vẫn phải giữ guard hiện có để không soft-delete
  candidate đang có workflow active ở branch khác;
- method này không update Candidate.deleted_at. Soft archive candidate, detach
  star và các side effect còn lại vẫn thuộc Service workflow;
- Service phải so sánh số row update thực tế với trạng thái đã preload và xử lý
  state conflict theo custom exception hiện có.

**Cần user kiểm tra trước implementation**: giữ nguyên allowlist
SCREENING_CALL/INTERVIEW, update toàn bộ job cùng branch như method hiện tại,
và không mang các side effect của archive đơn vào bulk archive ngoài các side
effect đã được plan ghi rõ.

### R2. Bỏ archive log và chuyển sang uniqueHash(id)

Không tạo bảng mới và không lưu lifecycle/token state cho archive. Cần loại bỏ
dependency runtime vào candidate_archive_logs trong luồng mới. Việc xử lý
migration phụ thuộc trạng thái deploy:

- nếu migration tạo candidate_archive_logs chưa từng deploy: loại bỏ các
  artifact chưa cần thiết khỏi implementation. Migration hiện mới chạy local,
  nên được xác nhận là có thể xoá khỏi scope/code path của task;
- nếu đã deploy ở bất kỳ environment nào: giữ lịch sử migration và tạo một
  migration drop riêng theo quy trình deploy, không xóa migration cũ khỏi
  history;
- trước khi code phải xác nhận trạng thái này để không làm sai migration
  history.

Không dùng lại random token, token hash lưu DB, TTL 7 ngày, token_used_at,
latest archive log hoặc one-time consume. Token mới là deterministic hash từ
candidate ID bằng utility hiện hữu:

    $token = StringUtility::uniqueHash($candidateId);

Email link truyền id và token theo URL contract của frontend:
...?id={candidateId}&token={uniqueHash(candidateId)}. Không đưa raw secret,
archive-log ID hoặc token state khác vào link. Email job chỉ cần truyền
candidate ID (và context branch nếu template hiện tại cần); token được tạo khi
compose link bằng StringUtility::uniqueHash().

API deletion giữ route profile deletion hiện có nhưng đổi request contract:

- GET preview nhận id và token từ query string;
- POST confirm nhận id và token từ body theo API docs; nếu frontend đang dùng
  cùng request shape cho GET/POST thì ghi rõ cùng tên field ở cả hai;
- FormRequest validate id là integer candidate ID và token là string hash;
- Service lấy candidate theo id, sau đó dùng constant-time comparison:
  hash_equals(StringUtility::uniqueHash($id), $token);
- sai ID/token, candidate không tồn tại hoặc candidate không ở trạng thái đủ
  điều kiện deletion đều trả custom API error hiện hữu; không query một bảng
  token mới.

Vì hash deterministic và không có DB state, link có thể replay về mặt token.
Replay sau khi candidate đã force-delete phải fail vì candidate không còn tồn
tại. Cần ghi rõ đây là contract được chấp nhận thay cho expiry/one-time token;
nếu vẫn cần expiry hoặc one-time semantics thì revision này phải được dừng để
user chọn thiết kế khác.

### R3. Tái sử dụng CandidateService::deleteCandidate()

Profile deletion không gọi CandidatePurgeRepository::purgeCandidateData()
riêng nữa. Service sẽ gọi cùng workflow:

    ProfileDeletionRequest(id, token)
      -> verify id/token and archived/deletion eligibility
      -> CandidateService::deleteCandidate(id, includeTrashed: true)
      -> synchronous CRS cleanup and force-delete

deleteCandidate() phải giữ tương thích với các caller admin/compliance hiện
tại. Cách dự kiến là thêm option nội bộ có default bảo toàn behavior cũ để
lookup được soft-deleted candidate cho public deletion flow; không tạo một
service purge thứ hai và không copy lại danh sách cleanup ở controller.

#### Những cleanup hiện tại cần bổ sung/kiểm tra trong deleteCandidate()

So với cleanup matrix của flow profile deletion hiện tại, method hiện hữu đang
thiếu hoặc cần xác nhận các mục sau:

- communication_note_change_logs cùng communication_notes;
- escalated_issues, escalated_issue_logs, escalated_issue_change_logs;
- candidate_job_appointments và appointments;
- candidate_progress_emails, candidate_timings, candidate_snapshots,
  candidate_welfare_checks, consultant_declarations;
- candidate_skills, candidate_tags, starred_candidates,
  candidate_face_matching_rates;
- legal_entity_switching_requests, candidate_tokens;
- match_maker_duplication_processes;
- tracking_record_histories, activity_logs;
- sms_candidate_campaigns, sms_receivers;
- cập nhật sms_pre_campaigns.receiver_ids để loại candidate ID khỏi JSON,
  không xóa toàn bộ pre-campaign dùng chung;
- candidate_password_resets theo email candidate nếu đây là record
  candidate-owned trong flow hiện tại.

Các mục không được tự thêm vào purge:

- match_maker_candidates: không có candidate_id ổn định và liên kết bằng
  peo_no/email; flow GDPR hiện tại không có cleanup trực tiếp cho bảng này.
  Không bulk-delete theo email trong GAP-534 nếu chưa có quyết định/contract
  riêng của MatchMaker;
- shared staff data như users, user_branches, branches, auth logs của staff,
  legal entities, jobs hoặc dictionaries;
- email đã gửi, backup/retention ngoài CRS và provider/MatchMaker data.

File cleanup phải bao phủ metadata rows có candidate_id hoặc
original_candidate_id, và storage paths ở cả url lẫn converted_file_url nếu
có. Paths phải được preload trước transaction; DB deletes phải batch/set-based,
không forceDelete() từng file trong loop. Storage delete chạy sau DB commit.
Nếu storage delete lỗi, giữ DB state đã purged và ghi nhận orphan storage theo
logging/retry convention hiện tại; không đưa storage call vào transaction và
không để file delete trước commit.

CandidatePurgeRepository, binding, contract, model/migration của
CandidateArchiveLog và các Service references chỉ được xóa khi không còn
caller sau khi chuyển deleteCandidate(). Nếu repository còn cần làm pure data
access, nó chỉ được gọi từ CandidateService::deleteCandidate() và không được
chứa business branching hoặc tạo thêm purge workflow.

### R4. Email và seeder

- Giữ nguyên chính xác email content hiện có trong Jira/template; chỉ thay
  placeholder/link data theo contract id + uniqueHash(id).
- Không tạo seed file mới. Cập nhật row/template hiện có trong
  database/seeders/data/email_templates.csv theo format đang dùng và chạy
  seeder hiện hữu theo quy trình của project.
- Email archive vẫn dispatch sau khi archive transaction commit; deletion API
  vẫn xử lý đồng bộ, không tạo purge job.
- Vì không có archive log/token state, email job không được phụ thuộc vào
  archiveLogId, rawToken, expiry hoặc token consume state.

### R5. API docs-first và test gate

Đây là API contract change nên Phase 1 phải cập nhật
~/projects/crs-api-docs trước code:

- document GET/POST profile deletion với id và token;
- document invalid hash, missing candidate, non-eligible candidate và success
  responses;
- document bulk archive job update chỉ giới hạn theo
  archiveCandidateJobsByBranch;
- giữ nguyên email content/link semantics trong examples, không invent content;
- validate docs, commit và push docs lên origin/main, ghi SHA vào plan.

Phase 2 chỉ bắt đầu sau khi Phase 1 pass. Test bắt buộc:

- bulk archive nhiều candidate chứng minh một set-based repository update,
  đúng branch/status allowlist, không update matchmaker/branch khác và không có
  archive-log insert;
- email job/link chứa đúng candidate ID và StringUtility::uniqueHash(id);
- GET/POST deletion với đúng/sai ID-token, candidate active, candidate soft
  deleted và replay sau force-delete;
- deleteCandidate() cover cleanup matrix ở R3, gồm
  match_maker_duplication_processes, tracking/activity logs, SMS relations,
  file original/converted paths và storage-after-commit behavior;
- existing admin/compliance callers của deleteCandidate() không đổi contract;
- không còn query, model, job hoặc migration runtime nào phụ thuộc
  candidate_archive_logs trong flow mới;
- review toàn bộ affected tests, chạy targeted suites và full
  ./vendor/bin/phpunit.

### R6. Các quyết định cần user confirm trước khi implement

1. **Đã xác nhận** — Giữ đúng CandidateJob::ARCHIVABLE_STATUSES hiện tại
   (screening_call, interview) và update tất cả job đủ điều kiện của candidate
   trong branch, không mang behavior unarchive/welcome-back của archive đơn vào
   bulk flow.
2. **Đã xác nhận** — Chấp nhận token deterministic uniqueHash(candidateId) không expiry và không
   one-time DB state; candidate đã force-delete sẽ là chốt replay.
3. **Đã xác nhận** — Migration candidate_archive_logs mới chạy dưới local,
   chưa deploy môi trường khác; được phép xoá artifact, không tạo drop migration.
4. **Đã xác nhận** — Giữ danh sách cleanup bổ sung ở R3, đặc biệt tracking histories,
   activity logs, SMS relations, files converted/original và
   match_maker_duplication_processes.

**Implementation gate**: bốn điểm R6 đã được user approve. Phase 1 docs-first
đã pass; backend implementation được phép bắt đầu từ Phase 2. Turn cập nhật
plan này không sửa backend code, không chạy migration và không seed dữ liệu.

### Phase 1 docs-first evidence (2026-10-19)

- Updated files in `~/projects/crs-api-docs`:
  - `docs/api/candidate/get-profile-deletion.md`
  - `docs/api/candidate/post-profile-deletion.md`
  - `docs/api/consultant/post-candidates-bulk-archive.md`
  - `docs/flows/candidate-lifecycle.md`
  - `docs/authentication.md`
  - `docs/api/index.md`
  - `docs/api/candidate/index.md`
  - `docs/api/consultant/index.md`
  - `docs/_meta/route-coverage.md`
  - `docs/_meta/source-inventory.md`
- Contract status is marked `PLANNED_NOT_DEPLOYED`; the revised contract is
  not represented as deployed runtime behavior before backend implementation.
- Validation: `git diff --check` PASS; `npm run build` PASS.
- Docs commit: `3424501` (`docs(GAP-534): revise archive deletion contract`).
- Push: commit `3424501` pushed successfully to `origin/main`.
- **Phase 1 status: PASS.** Phase 2 backend implementation may start.

### Phase 2 backend implementation evidence (2026-10-19)

- Reused the existing CandidateRepositoryInterface::archiveCandidateJobsByBranch
  set-based update; bulk archive now limits job updates to the existing
  CandidateJob::ARCHIVABLE_STATUSES and selected branch.
- Removed the local-only candidate_archive_logs migration, model, repository
  contract/implementation and provider binding. No drop migration was created.
- Replaced random/header token flow with id + StringUtility::uniqueHash(id);
  GET uses query parameters and POST uses JSON fields. Comparison uses
  constant-time hash validation.
- Reused CandidateService::deleteCandidate() for profile deletion with an
  include-trashed lookup. Candidate cleanup remains centralized through the
  existing CandidatePurgeRepository data-access helper; storage deletion runs
  after the DB transaction commits.
- Added missing cleanup coverage for candidate-owned CRS data, including local
  MatchMaker duplication rows, tracking/activity rows, SMS relations and both
  original/converted file storage paths. match_maker_candidates remains out
  of scope.
- Kept the existing candidate_archive email template/content; no new seed file
  was created and the existing CSV row already contains the approved content.
  The email link now carries candidate ID and deterministic hash.
- Updated affected Feature coverage in
  tests/Feature/Api/Consultant/CandidateArchiveTest.php.
- Verification: targeted GAP-534 suite PASS (6 tests, 34 assertions); PHP lint
  PASS for changed PHP files; git diff --check PASS; full PHPUnit PASS
  (631 tests, 9,355 assertions).
- Living business specs updated:
  .business-spec/backend-business-flow-spec.md,
  .business-spec/backend-api-route-inventory.md,
  .business-spec/backend-database-relationship.md.
- Post-implementation docs sync in ~/projects/crs-api-docs updated the
  endpoints from PLANNED_NOT_DEPLOYED to CODE_ONLY/code-verified. Docs build
  and git diff --check passed; amendment commit 07ee130
  (docs(GAP-534): mark revised contract verified) was pushed successfully to
  origin/main.
- Phase 2 status: PASS. Backend code remains uncommitted; unrelated
  pre-existing worktree changes were preserved.

## R7. Revision — bulk archive follows the existing job-archive flow

**Status**: Approved; R7 docs-first gate passed. This section supersedes the current bulk
archive behavior described in earlier sections and the Phase 2 evidence above.
The earlier implementation soft-deleted `candidates` and used
`archiveCandidateJobsByBranch()` with an allowlist; that behavior must not be
carried forward into R7.

### R7.1. Archive contract

- Bulk archive must follow the existing archive behavior in
  `CandidateService::updateCandidateJobStatus()` by changing
  `candidate_jobs.status` to `CandidateJob::STATUS_ARCHIVED`.
- The Candidate row must remain active: do not update `candidates.deleted_at`,
  do not call `archiveActiveByIds()`, and do not change Candidate login,
  signup, or default Eloquent visibility as a side effect of archive.
- Archive the candidate's jobs in the selected branch using the same rule as
  the existing flow: archive every job in that branch except jobs whose
  current status is `CandidateJob::STATUS_MATCHMAKER`. Existing eligibility
  guards for `APPROVED`/`MATCHMAKER` must remain explicit and must be reconciled
  with the old single-candidate behavior before implementation.
- Do not call `updateCandidateJobStatus()` once per candidate/job from a bulk
  loop. That would reintroduce per-record reads/writes and would violate the
  batch/no-N+1 rule. Instead, extract or centralize the old archive rule so the
  single-candidate path and bulk path use the same business behavior, while
  bulk writes are performed in a set-based/atomic operation.
- Audit all callers of `archiveCandidateJobsByBranch()` and
  `archiveActiveByIds()`. Remove the obsolete bulk-only archive method and its
  contract entry if no other caller needs it; otherwise keep it only for its
  remaining caller and do not use it as the source of truth for R7 archive
  semantics.
- Keep the existing response shape and `send_email` choice. Email dispatch
  remains after the archive writes commit. The existing candidate archive
  email content is unchanged.

### R7.2. Reset document behavior

Bulk archive must include the same reset-document behavior currently used by
`ArchiveCandidates::resetDocuments()` after an archive:

1. For affected candidate jobs whose `contract_document_status` is at or past
   `CandidateJob::CONTRACT_DOCUMENT_STATUS_SIGNED_SERVICES_AND_TERMS_OF_ENGAGEMENT`,
   reset the document status to
   `CandidateJob::CONTRACT_DOCUMENT_STATUS_WATCHED_KEY_INFORMATION_DOCUMENT`.
2. Reset contract progress to `CandidateJob::PROGRESS_STATUS_IN_PROGRESS`.
3. Delete the existing candidate-owned files of types
   `File::TYPE_WORK_CONTRACT`, `File::TYPE_WORK_CONTRACT_SIGNATURE`,
   `File::TYPE_MEDICAL_CONTRACT`, and
   `File::TYPE_MEDICAL_CONTRACT_SIGNATURE`, preserving the existing
   `backup=true` behavior used by `ArchiveCandidates::resetDocuments()`.

The implementation must reuse the current reset behavior instead of copying
the command's private helper into the controller. Because the command helper
is private and its current calls are per job/file, the implementation phase
must first choose a shared, batch-safe owner (CandidateService plus repository
data access, or an approved existing workflow boundary), preserve the current
file-safety checks, and avoid injecting one Service into another. Reads and
affected file/job IDs must be preloaded before the write transaction; no DB
query may be introduced inside a bulk loop. File/storage failures and partial
reset outcomes must have an explicit error/rollback policy recorded before
code is changed.

### R7.3. Profile-deletion flow after removing Candidate soft-delete

The deterministic link flow must remain usable even though archive no longer
sets `candidates.deleted_at`:

- `isAvailableForProfileDeletion()` must validate candidate ID, the
  `StringUtility::uniqueHash(candidateId)` token, and the archived-job state;
  it must not require `deleted_at != null`.
- `isAlreadyArchivedCandidate()` and bulk validation must use the archived job
  state rather than Candidate soft-delete state for no-op/deletion eligibility.
- `sendCandidateArchiveEmail()` and `SendCandidateArchiveEmailJob` must accept
  an active Candidate whose selected-branch job has been archived; they must
  not silently return only because `deleted_at` is null.
- `deleteArchivedProfile()` continues to reuse
  `CandidateService::deleteCandidate()` for the synchronous CRS purge. The
  purge remains the operation that physically removes the Candidate; archive
  alone does not remove or hide the account.
- Recheck whether the existing email/link wording still accurately describes
  this state. Keep the seeded email content unchanged unless the user
  explicitly approves a content change; update only runtime eligibility/link
  data as required.

### R7.4. API docs and execution gates

The endpoint path, request fields, response fields, and error keys are
unchanged unless implementation tracing proves otherwise. The side-effect
contract does change: the archive endpoint must document that it archives job
statuses and resets contract documents but does not soft-delete the Candidate.
Therefore R7 requires a new docs-first amendment in
`~/projects/crs-api-docs` before backend implementation:

- update the bulk archive endpoint/flow documentation and any profile-deletion
  wording affected by the active Candidate state;
- mark the revised contract as planned/not deployed;
- run documentation validation, commit only the task docs, push to
  `origin/main`, and record the commit SHA in this plan;
- start backend implementation only after that docs phase passes.

Backend implementation must then update affected Feature/Service tests and
run the targeted GAP-534 suite plus the full `./vendor/bin/phpunit` suite.
Acceptance requires: Candidate `deleted_at` remains null after bulk archive;
all eligible same-branch jobs follow the old archive rule; MatchMaker jobs are
preserved; document status/progress/files follow the existing reset flow; the
email job is dispatched only after commit; and the id/hash deletion flow can
purge the still-active archived Candidate successfully.

#### R7.4 execution evidence — docs-first gate (2026-10-19)

- Updated docs in `~/projects/crs-api-docs`:
  - `docs/api/consultant/post-candidates-bulk-archive.md`
  - `docs/api/candidate/get-profile-deletion.md`
  - `docs/api/candidate/post-profile-deletion.md`
  - `docs/flows/candidate-lifecycle.md`
- Revised contract is marked `PLANNED_NOT_DEPLOYED` and documents job-status
  archive, document reset, active Candidate state and archived-job deletion
  eligibility.
- `git diff --check`: PASS.
- `npm run build`: PASS.
- Docs commit `b0d7b0c` (`docs(GAP-534): revise archive flow behavior`) pushed
  successfully to `origin/main`.
- **R7 docs-first gate: PASS.** Backend implementation may proceed.

### R8. Purge implementation — repository-per-domain orchestration

The profile-deletion purge must not use `CandidatePurgeRepository` anymore and
must not replace it with `CandidateRepository::purgeCandidateData()`.
`CandidateService::deleteCandidate()` remains the single orchestration point
for the existing delete flow and all R8-required cleanup additions. Remove the
temporary `purgeCandidateData()` contract/implementation from
`CandidateRepository` and update all callers after an exact repository-wide
usage audit. Do not leave a dead purge repository or create another aggregate
purge method.

The service must still respect the repository boundary: `deleteCandidate()`
coordinates preload, storage cleanup, transaction order, repository call order
and force-delete, but database reads/writes remain in the repository that owns
each table/domain. Reuse the existing injected repositories and inherited
`deleteByFilter()` only when it expresses the required operation clearly; for
stable candidate cleanup conditions, prefer named methods such as
`deleteByCandidateId()`. Add narrowly scoped methods to an existing repository,
or create a missing table/domain repository only when no suitable owner exists.
Do not put raw `DB::table()` cleanup queries in `CandidateService`. Move the
current purge operations into their owning repositories, including:

- preload of candidate file paths and SMS pre-campaign rows;
- communication notes/change logs and escalated issue logs/issues;
- candidate-job appointments, appointments, progress emails, timings and
  candidate jobs;
- files/snapshots/welfare checks, addresses, bank accounts, employment data,
  answers, skills/tags, stars, face matching rates, declarations, legal-entity
  switching requests and candidate tokens;
- local `match_maker_duplication_processes`, tracking/activity rows, SMS
  candidate rows/receivers, `sms_pre_campaigns` receiver ID updates and
  candidate password-reset rows; and
- the final Candidate force-delete.

`match_maker_candidates` remains out of scope because the task is CRS-only and
its logical email/people-number ownership is not safely resolvable here.
`deleteCandidate()` must preserve the current storage-after-DB-commit failure
handling, FK-safe deletion order, batch SMS update, include-trashed option and
existing admin/compliance callers. Any cleanup that is not currently covered
must be added to this method's workflow through the owning repository, not by
copying raw `DB::table()` queries into the Service or a catch-all repository
method. The implementation phase
must update the deletion test matrix to prove no candidate-owned CRS rows or
storage paths remain after successful purge and that a failed storage delete is
logged without falsely rolling back the committed DB purge.

#### R8.1. Repository ownership mapping and transaction order

Before code changes, audit every table currently removed by the old aggregate
method and map it to an owning repository. The service call order must be
explicit and FK-safe: dependent logs/junctions first, candidate-owned domain
rows next, candidate jobs/timings/files after their children, SMS pre-campaign
JSON update, then final `forceDelete($candidate)`. Reads needed for storage
paths, SMS pre-campaign rows and welfare-file references happen before the write
transaction; the transaction contains only repository writes plus candidate
force-delete.

The mapping must explicitly cover the current CRS cleanup set: communication
notes/logs, escalated issue logs/issues, candidate-job appointments,
appointments, progress emails, timings/jobs, snapshots/welfare checks/files,
declarations, addresses, bank accounts, employment history/references, answers,
skills/tags, stars, face matching, legal-entity switching, candidate tokens,
local MatchMaker duplication processes, tracking/activity logs, SMS candidate
campaigns/receivers, SMS pre-campaign receiver-ID updates and candidate
password resets. `match_maker_candidates` remains out of scope.

Acceptance for this amendment: `CandidateRepositoryInterface` exposes no
aggregate purge method; `CandidateService::deleteCandidate()` calls only
table/domain repository contracts for database cleanup; no candidate cleanup
query is added directly to the Service; transaction and post-commit storage
behavior remain unchanged; existing admin/compliance delete callers and the
profile-deletion flow still pass.

#### R7 implementation evidence (2026-10-19)

- Bulk archive now follows the existing job archive behavior: it updates
  eligible same-branch candidate jobs to ARCHIVED, preserves MatchMaker jobs,
  resets contract document status/progress, removes contract/medical files and
  does not update candidates.deleted_at.
- CandidateService::updateCandidateJobStatus() reuses the shared repository
  archive operation for the single-candidate archive path. ArchiveCandidates
  now calls CandidateService::resetCandidateJobDocuments() instead of keeping
  a duplicate private reset workflow.
- CandidatePurgeRepositoryInterface, CandidatePurgeRepository and its binding
  were removed. R8 will remove the temporary aggregate
  CandidateRepository::purgeCandidateData() method and move each cleanup
  operation behind its owning repository contract, with CandidateService as the
  orchestration point.
- Profile-deletion eligibility now checks the deterministic ID/hash and an
  archived candidate job; the Candidate may remain active until the synchronous
  deleteCandidate() purge.
- Updated Feature assertions in
  tests/Feature/Api/Consultant/CandidateArchiveTest.php for active Candidate
  state, job archive, document reset, file cleanup and profile purge.
- Verification: targeted archive/job suites PASS (10 tests, 52 assertions);
  PHP lint and git diff --check PASS; full PHPUnit PASS (631 tests, 9,360
  assertions).
- Living business specs updated:
  .business-spec/backend-business-flow-spec.md,
  .business-spec/backend-api-route-inventory.md,
  .business-spec/backend-database-relationship.md.
- R7 docs amendment in ~/projects/crs-api-docs passed git diff --check and
  npm run build. Commit de56c49
  (docs(GAP-534): mark archive flow code verified) was pushed successfully to
  origin/main; follow-up branch-scope clarification commit 0dd5129 was also
  pushed successfully to origin/main.
- **R7 status: PASS for the previously approved implementation. R8 status:
  PASS.** `CandidateRepository::purgeCandidateData()` was removed. `deleteCandidate()`
  now preloads required read data and directly calls the owning repositories for
  candidate-job children, candidate domain rows, tags, stars, local duplication,
  tracking/activity and SMS cleanup before force-deleting the Candidate.
- Added repository owners for candidate progress emails, candidate tags and
  starred candidates; moved file-path lookup/file deletion to
  `FileRepository`, SMS pre-campaign lookup/update to `SmsPreCampaignRepository`,
  and candidate password-reset deletion to
  `CandidatePasswordResetRepository`.
- Targeted verification: `CandidateArchiveTest` PASS (6 tests, 39 assertions).
- Full verification: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php
  ./vendor/bin/phpunit` — PASS (631 tests, 9,360 assertions).
- `git diff --check`: PASS; PHP lint passed for all changed/new PHP files.
- Living business specs updated to record repository-per-domain purge ownership.
- Backend code remains uncommitted; unrelated pre-existing worktree changes are
  preserved.

## R9. Revision — Remove withTrashed, Revert ArchiveCandidates Command & Batch Reset Documents Function (2026-10-19)

### R9.1. Đánh giá và xác nhận về `withTrashed`
- **Xác nhận**: Kể từ Revision 7 (R7), bulk archive quay về đúng hành vi archive gốc của hệ thống: chỉ cập nhật trạng thái `candidate_jobs.status = ARCHIVED` và reset contract documents; **HOÀN TOÀN KHÔNG soft-delete `candidates`**. Candidate vẫn ở trạng thái active bình thường (`candidates.deleted_at` luôn là `NULL`).
- **Xử lý**:
  1. Loại bỏ toàn bộ việc sử dụng `withTrashed()` trong flow bulk archive và profile deletion:
     - `CandidateRepository::getCandidatesForBulkArchive()`: Bỏ `Candidate::withTrashed()`, chuyển về `Candidate::query()`.
     - `CandidateRepositoryInterface` & `CandidateRepository`: Xóa bỏ phương thức `findWithTrashed(int $candidateId): ?Model`.
     - `CandidateService`: Các method `canDeleteArchivedProfile`, `deleteArchivedProfile`, `sendCandidateArchiveEmail` chuyển sang dùng `find($candidateId)` thông thường.
     - `CandidateServiceInterface` & `CandidateService`: Xóa bỏ tham số `bool $includeTrashed = false` trong `deleteCandidate(int $id)`, khôi phục đúng signature ban đầu `deleteCandidate(int $id): bool`.
  2. Toàn bộ các mô tả/yêu cầu cũ trong Plan 534 về `include-trashed` hoặc query Candidate trashed được coi là obsolete và chính thức loại bỏ.

### R9.2. Giữ nguyên Command `ArchiveCandidates` (Revert changes)
- Command `app/Console/Commands/ArchiveCandidates.php` được revert về nguyên bản gốc (unmodified), không thay đổi bất kỳ dòng code hay injection nào:
  - Giữ nguyên các service injection: `CandidateServiceInterface`, `CandidateRepositoryInterface`, `RegistrationProgressServiceInterface`, `FileServiceInterface`.
  - Giữ nguyên method private `resetDocuments(Candidate $candidate, CandidateJob $candidateJob): void`.
- Bảo toàn tuyệt đối git blame và tránh sửa đổi code ngoài phạm vi của task theo Workspace Rule §1.

### R9.3. Viết function mới cho CandidateService để reset documents cho nhiều candidate/job cùng lúc (Batch Reset)
- Thay vì gọi đơn lẻ hoặc viết inline toàn bộ trong `bulkArchive()`, tạo function mới chuyên trách trong `CandidateService`:
  - Tên đề xuất: `resetCandidateJobsDocuments(Collection $candidateJobs): array` (hoặc `resetCandidateJobsDocumentsBatch`).
  - Phạm vi chức năng:
    1. Nhận vào collection các `CandidateJob` (đã được eager-load/filter thuộc scope cần archive).
    2. Lọc các jobs có `contract_document_status` >= `CandidateJob::CONTRACT_DOCUMENT_STATUS_SIGNED_SERVICES_AND_TERMS_OF_ENGAGEMENT`.
    3. Chuẩn bị dữ liệu cập nhật trạng thái:
       - `contract_document_status = CONTRACT_DOCUMENT_STATUS_WATCHED_KEY_INFORMATION_DOCUMENT`
       - `progresses['contracts'] = PROGRESS_STATUS_IN_PROGRESS`
       - Trả về payload cấu trúc để thực hiện update batch (hoặc cập nhật trực tiếp trong transaction của bulkArchive).
    4. Batch read files cần xóa cho toàn bộ candidate IDs liên quan:
       - Types: `File::TYPE_WORK_CONTRACT`, `File::TYPE_WORK_CONTRACT_SIGNATURE`, `File::TYPE_MEDICAL_CONTRACT`, `File::TYPE_MEDICAL_CONTRACT_SIGNATURE` thông qua `FileRepository::getByCandidateIdsAndTypes()`.
    5. Preload welfare check referenced file IDs bằng `CandidateWelfareCheckRepository::getReferencedFileIds()`.
    6. Thực hiện xóa an toàn các files này thông qua helper xóa files hiện có (không xóa file đang được welfare check tham chiếu).
  - Bỏ method đơn lẻ `resetCandidateJobDocuments(Candidate $candidate, CandidateJob $candidateJob)` khỏi `CandidateServiceInterface` và `CandidateService` (vì command đã tự giữ logic riêng, và bulk archive dùng hàm batch mới).

### R9.4. File ownership và impact
- `app/Console/Commands/ArchiveCandidates.php`: REVERT về HEAD (unmodified).
- `app/Contracts/Repositories/CandidateRepositoryInterface.php`: Xóa `findWithTrashed`.
- `app/Repositories/CandidateRepository.php`: Xóa `findWithTrashed`, bỏ `withTrashed()` trong `getCandidatesForBulkArchive`.
- `app/Contracts/Services/CandidateServiceInterface.php`: Xóa `findWithTrashed` dependencies, bỏ `resetCandidateJobDocuments`, khôi phục `deleteCandidate(int $id): bool`, bổ sung signature cho batch reset documents (nếu public).
- `app/Services/CandidateService.php`: Triển khai hàm batch reset mới, xóa hàm reset đơn lẻ `resetCandidateJobDocuments`, đổi các lookup trashed sang `find()`.
- `tests/Feature/Api/Consultant/CandidateArchiveTest.php`: Cập nhật các test case để đảm bảo assertion kiểm tra candidate active và test bao phủ hàm batch reset mới.

#### R9 implementation evidence (2026-10-19)

- `app/Console/Commands/ArchiveCandidates.php` đã được revert 100% về nguyên bản gốc (unmodified), bảo toàn git blame và method private `resetDocuments()`.
- Đã gỡ bỏ toàn bộ việc sử dụng `findWithTrashed()` và `withTrashed()` trong flow bulk archive và profile deletion:
  - `CandidateRepository::getCandidatesForBulkArchive()` dùng `Candidate::query()`.
  - Xóa `findWithTrashed()` khỏi `CandidateRepositoryInterface` và `CandidateRepository`.
  - Khôi phục signature `CandidateService::deleteCandidate(int $id): bool`.
  - `canDeleteArchivedProfile`, `deleteArchivedProfile`, `sendCandidateArchiveEmail` dùng `find($candidateId)`.
- Triển khai method mới `CandidateService::resetCandidateJobsDocuments(Collection|SupportCollection|array $candidateJobs): void` để reset documents cho nhiều candidate jobs cùng lúc (batch-safe, pre-load files, không N+1).
- `bulkArchive()` ủy quyền reset documents qua `resetCandidateJobsDocuments($archiveJobs)`.
- Bổ sung Feature test `testResetCandidateJobsDocumentsBatchResetsEligibleJobsAndFiles` trong `CandidateArchiveTest`.
- Verification:
  - PHP lint: PASS trên toàn bộ file thay đổi.
  - `git diff --check`: PASS.
  - `CandidateArchiveTest`: PASS 7/7 tests (44 assertions).
  - `CandidateServiceTest`: PASS 1/1 test.
  - Full PHPUnit: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (632 tests, 9,365 assertions).
- **R9 status: PASS.**

## R10. Revision — Preload & Prepare Document Reset Data Before Archive Transaction (2026-10-19)

### R10.1. Đánh giá và phân tích kiến trúc
- **Hiện trạng tại R9**:
  - `archiveBulkCandidatesAtomically` chạy Transaction 1 để đổi `candidate_jobs.status` sang `ARCHIVED` và gỡ star.
  - `resetCandidateJobsDocuments` chạy sau đó với Transaction 2 để update `contract_document_status`, `progresses`, và `timings`.
- **Hạn chế**:
  - Nếu Transaction 1 thành công nhưng Transaction 2 gặp sự cố (disconnect, deadlock, crash), dữ liệu sẽ rơi vào trạng thái không đồng nhất: Candidate job đã bị chuyển sang `ARCHIVED` nhưng contract documents/progresses vẫn chưa được reset.
- **Giải pháp theo góp ý của user**:
  - Tách pha chuẩn bị dữ liệu (Pre-read / Prepare): trích xuất method `prepareCandidateJobDocumentResetData(Collection|SupportCollection|array $candidateJobs): array`. Method này chỉ đọc và format data, không ghi database.
  - Đưa toàn bộ các thao tác ghi DB vào **MỘT TRANSACTION DUY NHẤT** trong `archiveBulkCandidatesAtomically`:
    1. Archive candidate jobs theo branch (`archiveCandidateJobsByBranch`).
    2. CAS update count check.
    3. Update `contract_document_status` sang `WATCHED_KEY_INFORMATION_DOCUMENT`.
    4. Upsert `progresses` (`contracts => IN_PROGRESS`).
    5. Reset timings (`resetKidLinkViewed`).
    6. Gỡ star cho acting user (`removeStarsForUserByCandidateIds`).
  - Sau khi transaction commit thành công mới thực hiện xóa file vật lý bằng `deleteResetDocumentFiles()`.
  - Giữ lại hàm `resetCandidateJobsDocuments()` công khai để phục vụ các caller độc lập khác (nếu cần reset document mà không archive job), hàm này sẽ tái sử dụng `prepareCandidateJobDocumentResetData()`.

### R10.2. Thay đổi chi tiết trong `CandidateService.php`
1. Thêm private helper `prepareCandidateJobDocumentResetData(Collection|SupportCollection|array $candidateJobs): array`:
   - Lọc các jobs có `contract_document_status` >= `SIGNED_SERVICES_AND_TERMS_OF_ENGAGEMENT`.
   - Chuẩn bị `$jobIds`, `$progresses`, `$timingKeys`.
   - Batch query files và referenced file IDs.
   - Trả về payload chuẩn: `['job_ids', 'progresses', 'timing_keys', 'files', 'referenced_file_ids']`.
2. Cập nhật `archiveBulkCandidatesAtomically()`:
   - Nhận thêm `$documentResetJobIds`, `$documentResetProgresses`, `$documentResetTimingKeys`.
   - Thực thi tất cả trong 1 `DB::transaction(...)`.
3. Cập nhật `bulkArchive()`:
   - Gọi `prepareCandidateJobDocumentResetData($archiveJobs)`.
   - Gọi `archiveBulkCandidatesAtomically(..., $resetData['job_ids'], $resetData['progresses'], $resetData['timing_keys'])`.
   - Gọi `deleteResetDocumentFiles($resetData['files'], $resetData['referenced_file_ids'])`.
   - Dispatch email sau commit.
4. Cập nhật `resetCandidateJobsDocuments()`:
   - Dùng `prepareCandidateJobDocumentResetData($candidateJobs)`.
   - Chạy transaction reset document riêng cho các caller độc lập.
   - Xóa file sau commit.

#### R10 implementation evidence (2026-10-19)

- Đã trích xuất private helper `prepareCandidateJobDocumentResetData(Collection|SupportCollection|array $candidateJobs): array` trong `CandidateService`:
  - Thực hiện toàn bộ logic pre-read, filter và format dữ liệu reset document trước khi mở transaction.
  - Pre-fetch danh sách file cần xóa và danh sách file ID được welfare check tham chiếu theo batch.
- `archiveBulkCandidatesAtomically` nhận trực tiếp `$resetData['job_ids']`, `$resetData['progresses']`, `$resetData['timing_keys']` và gộp toàn bộ thao tác ghi database (archive jobs, CAS check, update contract document status, upsert progresses, reset timings, remove stars) vào **MỘT TRANSACTION DUY NHẤT**.
- File vật lý được xóa an toàn sau khi transaction commit bằng `deleteResetDocumentFiles($resetData['files'], $resetData['referenced_file_ids'])`.
- Method `resetCandidateJobsDocuments()` công khai tái sử dụng `prepareCandidateJobDocumentResetData()` cho các caller độc lập.
- Verification:
  - PHP lint: PASS trên toàn bộ file thay đổi.
  - `git diff --check`: PASS.
  - `CandidateArchiveTest`: PASS 7/7 tests (44 assertions).
  - `CandidateServiceTest`: PASS 1/1 test.
  - Full PHPUnit: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (632 tests, 9,365 assertions).
- **R10 status: PASS.**

## R11. Revision — Audit & Clean Up Unused Newly Added Functions (2026-10-19)

### R11.1. Kết quả rà soát toàn bộ method thêm mới trong task
Qua rà soát toàn bộ diff giữa nhánh task GAP-534 và nhánh gốc, phát hiện 2 functions được thêm mới nhưng không được gọi trong production code:

1. **`resetCandidateJobsDocuments(Collection|SupportCollection|array $candidateJobs): void`**
   - Vị trí: `app/Contracts/Services/CandidateServiceInterface.php` và `app/Services/CandidateService.php`.
   - Lý do không sử dụng: Ở revision R10, flow `bulkArchive()` đã trực tiếp gọi `prepareCandidateJobDocumentResetData()` rồi truyền dữ liệu vào `archiveBulkCandidatesAtomically()` để thực thi trong 1 transaction duy nhất. Do đó, `resetCandidateJobsDocuments()` trở thành dead code, chỉ được gọi duy nhất trong test `testResetCandidateJobsDocumentsBatchResetsEligibleJobsAndFiles`.
   - Hành động: Xóa bỏ khỏi interface và service, đồng thời xóa test case tương ứng trong `CandidateArchiveTest`.

2. **`getByCandidateIdAndTypes(int $candidateId, array $types): Collection`**
   - Vị trí: `app/Contracts/Repositories/FileRepositoryInterface.php` và `app/Repositories/FileRepository.php`.
   - Lý do không sử dụng: Ban đầu được tạo cho reset document đơn lẻ của 1 candidate. Sau đó hệ thống đã chuyển sang dùng hàm batch `getByCandidateIdsAndTypes(array $candidateIds, array $types)`. Method này không còn được gọi ở bất cứ đâu trong cả `app/` và `tests/`.
   - Hành động: Xóa bỏ khỏi interface và repository.

Tất cả các method thêm mới còn lại (thuộc `CandidateRepository`, `CandidateJobRepository`, `CandidateTimingRepository`, `CandidateWelfareCheckRepository`, `FileRepository`, `SmsPreCampaignRepository`, `CandidateProgressEmailRepository`, `CandidateTagRepository`, `StarredCandidateRepository`, `CandidateService`, `CandidateController`, `MeController`) đều đang được gọi trực tiếp trong production call chain.

### R11.2. Kế hoạch xóa bỏ
- Xóa `resetCandidateJobsDocuments()` khỏi `app/Contracts/Services/CandidateServiceInterface.php` và `app/Services/CandidateService.php`.
- Xóa `getByCandidateIdAndTypes()` khỏi `app/Contracts/Repositories/FileRepositoryInterface.php` và `app/Repositories/FileRepository.php`.
- Xóa `testResetCandidateJobsDocumentsBatchResetsEligibleJobsAndFiles()` trong `tests/Feature/Api/Consultant/CandidateArchiveTest.php`.
- Chạy PHP lint, test `CandidateArchiveTest` và full test suite `./vendor/bin/phpunit`.

#### R11 implementation evidence (2026-10-19)

- Đã xóa hoàn toàn 2 method không sử dụng:
  1. `resetCandidateJobsDocuments()` trong `app/Contracts/Services/CandidateServiceInterface.php` và `app/Services/CandidateService.php`.
  2. `getByCandidateIdAndTypes()` trong `app/Contracts/Repositories/FileRepositoryInterface.php` và `app/Repositories/FileRepository.php`.
- Đã xóa test case `testResetCandidateJobsDocumentsBatchResetsEligibleJobsAndFiles` khỏi `tests/Feature/Api/Consultant/CandidateArchiveTest.php`.
- Toàn bộ codebase sạch sẽ, không còn dead code từ các method mới thêm.
- Verification:
  - PHP syntax lint (`php -l`): PASS trên toàn bộ files.
  - `git diff --check`: PASS (không có whitespace lỗi).
  - Feature test: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit tests/Feature/Api/Consultant/CandidateArchiveTest.php` — PASS (6 tests, 39 assertions).
  - Service unit test: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit tests/Unit/Services/CandidateServiceTest.php` — PASS (1 test, 1 assertion).
  - Full PHPUnit: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (631 tests, 9,360 assertions).
- **R11 status: PASS.**

## R12. Revision — Switch Archive Email Token to `randomHash` with 7-Day Cache Expiration (2026-10-19)

### R12.1. Yêu cầu & Bối cảnh
Theo yêu cầu người dùng:
> "chôx sinh token để gán vào link gửi email archive thay vì dùng hash thì chuyênr sang dùng randomHash và set vào cache để exp 7 ngày, sau check thì lấy từ cache ra để kiểm tra"

#### Hiện trạng:
- Token gửi trong archive email link hiện tại sinh qua `StringUtility::uniqueHash($candidateId)` (SHA-256 xác định, không expire, không lưu cache/DB).
- `MeController::previewProfileDeletion` và `confirmProfileDeletion` gọi `CandidateService::isAvailableForProfileDeletion`, so sánh token gửi lên với `StringUtility::uniqueHash($candidateId)`.
- `ProfileDeletionRequest` validate `token` theo regex `/^[a-f0-9]{64}$/`.
- Docs tại `~/projects/crs-api-docs` ghi chú token là deterministic hash (`StringUtility::uniqueHash(id)`), độ dài 64 hex, không expire.

#### Thiết kế mới:
1. **Sinh token ngẫu nhiên**: Dùng `StringUtility::randomHash()` (32 ký tự hex: `bin2hex(random_bytes(16))`).
2. **Lưu trữ Cache**:
   - Cache key: `candidate_archive_profile_deletion_token:{candidate_id}`
   - TTL: 7 ngày (604,800 giây = `7 * 24 * 60 * 60`).
   - Constant:
     - `CandidateService::ARCHIVE_PROFILE_DELETION_TOKEN_CACHE_KEY_PREFIX = 'candidate_archive_profile_deletion_token:'`
     - `CandidateService::ARCHIVE_PROFILE_DELETION_TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60`
3. **Kiểm tra Token**:
   - Khi client gọi `GET /api/candidate/profile_deletion?id={id}&token={token}` hoặc `POST /api/candidate/profile_deletion`:
   - Lấy token từ cache: `Cache::get(self::ARCHIVE_PROFILE_DELETION_TOKEN_CACHE_KEY_PREFIX . $candidateId)`.
   - Nếu cache miss (hết hạn 7 ngày hoặc chưa từng gửi), hoặc token không khớp: coi như token không hợp lệ (`can_delete: false` ở preview, HTTP 403 `profileDeletionTokenInvalid` ở confirm).
   - Kiểm tra an toàn `hash_equals($cachedToken, $token)`.
4. **Vô hiệu hóa Token sau khi xóa**:
   - Sau khi `deleteCandidate($candidateId)` thành công trong `deleteArchivedProfile`, gọi `Cache::forget(self::ARCHIVE_PROFILE_DELETION_TOKEN_CACHE_KEY_PREFIX . $candidateId)` để token không thể replay trong thời hạn 7 ngày.
5. **Cập nhật Request Validation**:
   - Trong `ProfileDeletionRequest`: Đổi regex sang `/^[a-f0-9]{32,64}$/` để chấp nhận token 32 hex từ `randomHash()`.
6. **API Contract / Docs Assessment**:
   - `N/A — no API contract/API docs change`: Endpoint paths (`GET|POST /api/candidate/profile_deletion`), request shape (`id`, `token`), and response shapes (`can_delete`, `deleted`) remain identical for API clients. Token generation and cache TTL are internal backend implementation details. User approved proceeding with backend-only implementation.

### R12.2. Kế hoạch thực hiện (Backend Implementation & Verification)

1. Cập nhật `app/Services/CandidateService.php`:
   - Khai báo constants:
     - `public const ARCHIVE_PROFILE_DELETION_TOKEN_CACHE_KEY_PREFIX = 'candidate_archive_profile_deletion_token:';`
     - `public const ARCHIVE_PROFILE_DELETION_TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60; // 604,800 seconds (7 days)`
   - Sửa `sendCandidateArchiveEmail()`:
     - Dùng `StringUtility::randomHash()`.
     - Lưu token vào cache: `Cache::put(self::ARCHIVE_PROFILE_DELETION_TOKEN_CACHE_KEY_PREFIX . $candidateId, $token, self::ARCHIVE_PROFILE_DELETION_TOKEN_TTL_SECONDS);`.
   - Sửa `isAvailableForProfileDeletion()`:
     - Lấy `$cachedToken = Cache::get(self::ARCHIVE_PROFILE_DELETION_TOKEN_CACHE_KEY_PREFIX . $candidateId);`.
     - Kiểm tra: `!empty($cachedToken) && is_string($cachedToken) && hash_equals($cachedToken, $token)`.
   - Sửa `deleteArchivedProfile()`:
     - Gọi `Cache::forget(self::ARCHIVE_PROFILE_DELETION_TOKEN_CACHE_KEY_PREFIX . $candidateId);` sau khi xóa profile thành công.
2. Cập nhật `app/Http/Requests/Api/Candidate/ProfileDeletionRequest.php`:
   - Đổi regex token sang `/^[a-f0-9]{32,64}$/`.
3. Cập nhật Test Suite:
   - `tests/Feature/Api/Consultant/CandidateArchiveTest.php`:
     - Cập nhật test email archive để kiểm tra token ngẫu nhiên được sinh và lưu vào cache đúng TTL.
     - Cập nhật test preview & confirm profile deletion: set token vào cache trước khi gọi endpoint.
     - Bổ sung test case cho token hết hạn 7 ngày (cache miss) -> trả về `can_delete: false` và 403.
     - Bổ sung test case token bị xóa khỏi cache sau khi confirm deletion thành công.
4. Chạy kiểm tra:
   - `php -l` cú pháp PHP.
   - `git diff --check`.
   - `./vendor/bin/phpunit tests/Feature/Api/Consultant/CandidateArchiveTest.php`.
   - `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` toàn bộ test suite.

#### R12 implementation evidence (2026-10-19)

- Đã khai báo constants trong `CandidateService`:
  - `public const ARCHIVE_PROFILE_DELETION_TOKEN_CACHE_KEY_PREFIX = 'candidate_archive_profile_deletion_token:';`
  - `public const ARCHIVE_PROFILE_DELETION_TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60; // 604,800 seconds (7 days)`
- Trong `sendCandidateArchiveEmail()`:
  - Sinh token ngẫu nhiên bằng `StringUtility::randomHash()`.
  - Lưu vào Cache với prefix và TTL 7 ngày (`Cache::put(...)`).
- Trong `isAvailableForProfileDeletion()`:
  - Lấy token từ cache: `Cache::get(...)`.
  - Xác thực token hợp lệ bằng `hash_equals($cachedToken, $token)`. Trả về `false` nếu cache miss hoặc token không khớp.
- Trong `deleteArchivedProfile()`:
  - Sau khi xóa candidate thành công (`deleteCandidate`), gọi `Cache::forget(...)` để vô hiệu hóa token ngay lập tức, ngăn ngừa link replay.
- Trong `ProfileDeletionRequest`:
  - Mở rộng regex token: `regex:/^[a-f0-9]{32,64}$/` tương thích token 32-char hex của `randomHash()`.
- Cập nhật test suite trong `CandidateArchiveTest.php`:
  - `testBulkArchiveSendsArchiveEmailWithProfileDeletionLink`: kiểm tra token trong email link khớp với token được lưu vào cache và có độ dài 32 ký tự.
  - `testProfileDeletionUsesCandidateIdAndCachedRandomTokenAndReusesDeleteCandidate`: kiểm tra preview và confirm xóa thành công, verify cache key bị xóa sau khi xóa profile.
  - `testProfileDeletionRejectsUncachedOrInvalidToken`: kiểm tra token chưa cache hoặc không khớp bị từ chối.
  - `testProfileDeletionRejectsExpiredToken`: kiểm tra token hết hạn sau 7 ngày (cache miss) bị từ chối với preview `false` và POST HTTP 403.
- Verification:
  - PHP syntax lint (`php -l`): PASS trên toàn bộ files.
  - `git diff --check`: PASS.
  - Feature test: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit tests/Feature/Api/Consultant/CandidateArchiveTest.php` — PASS (7 tests, 43 assertions).
  - Full PHPUnit: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (632 tests, 9,364 assertions).
- **R12 status: PASS.**

## R13. Revision — Duplicate Query Removal & Performance Optimization (2026-10-19)

### R13.1. Yêu cầu & Mục tiêu
Dựa trên kết quả rà soát code toàn bộ nhánh `GAP-534`, tối ưu hóa 4 điểm trùng lặp query và hiệu năng:

1. **Bỏ câu query `updateContractDocumentStatusByIds` trùng lặp**:
   - `archiveBulkCandidatesAtomically()` trong `CandidateService` hiện đang gọi `updateContractDocumentStatusByIds` ngay trước `upsertProgresses()`.
   - `upsertProgresses()` trong `CandidateJobRepository` đã cập nhật cả 3 cột `['contract_document_status', 'progresses', 'updated_at']` với cùng giá trị status `WATCHED_KEY_INFORMATION_DOCUMENT`.
   - Câu lệnh `updateContractDocumentStatusByIds` tạo thêm 1 query UPDATE không cần thiết trên cùng danh sách job IDs.
   - Hành động: Bỏ lời gọi `updateContractDocumentStatusByIds()` và xóa method này khỏi `CandidateJobRepositoryInterface` / `CandidateJobRepository`.

2. **Bỏ eager load `with('job.branch')` trong `getCandidatesForBulkArchive`**:
   - Trong `CandidateRepository::getCandidatesForBulkArchive()`, query đang load thêm `->with('job.branch')` cho relation `candidateJobs`.
   - Toàn bộ flow `bulkArchive()` chỉ đọc các thuộc tính của `CandidateJob` (`id`, `status`, `contract_document_status`, `progresses`, `candidate_id`, `job_id`). Không hề truy cập `$candidateJob->job` hay `$candidateJob->job->branch` (do `branchId` đã có sẵn từ controller/request).
   - Hành động: Bỏ `->with('job.branch')` trong eager load của `getCandidatesForBulkArchive()`, tiết kiệm 2 câu truy vấn SQL (`SELECT * FROM jobs` và `SELECT * FROM branches`).

3. **Gộp vòng lặp & rút gọn cấu trúc dữ liệu Reset Document**:
   - `prepareCandidateJobDocumentResetData()` đang duyệt `$documentResetJobs` 3 lần để sinh ra `$documentResetJobIds`, `$documentResetProgresses`, và `$documentResetTimingKeys`.
   - Rút gọn: Duyệt 1 vòng lặp duy nhất để chuẩn bị `$documentResetProgresses` và `$documentResetTimingKeys`. Không cần mảng `$documentResetJobIds` riêng biệt vì `!empty($documentResetProgresses)` đã đại diện đầy đủ.
   - Cập nhật signature `archiveBulkCandidatesAtomically()` loại bỏ tham số `$documentResetJobIds`.

4. **Bỏ bọc `collect(...)` dư thừa trong `deleteCandidate`**:
   - Trong `CandidateService::deleteCandidate()`: Các hàm `getByFilter()` của repository vốn đã trả về Eloquent `Collection`. Xóa các lời gọi `collect(...)` bao ngoài.

5. **API Contract / Docs Assessment**:
   - `N/A — no API contract/API docs change`: Tất cả các thay đổi trên hoàn toàn là refactoring và tối ưu hóa query nội bộ của Backend, không thay đổi bất kỳ route, request hay response nào của API.

### R13.2. Kế hoạch thực hiện chi tiết

1. **`app/Contracts/Repositories/CandidateJobRepositoryInterface.php` & `app/Repositories/CandidateJobRepository.php`**:
   - Xóa method `updateContractDocumentStatusByIds(array $candidateJobIds, string $status, Carbon $updatedAt): int`.

2. **`app/Repositories/CandidateRepository.php`**:
   - Trong `getCandidatesForBulkArchive()`: Bỏ `->with('job.branch')`, chỉ giữ `whereHas('job', ...)`.

3. **`app/Services/CandidateService.php`**:
   - Trong `prepareCandidateJobDocumentResetData()`: Gộp việc duyệt `$documentResetJobs` thành 1 vòng lặp, trả về payload gồm: `progresses`, `timing_keys`, `files`, `referenced_file_ids`.
   - Trong `archiveBulkCandidatesAtomically()`:
     - Bỏ tham số `$documentResetJobIds`.
     - Bỏ dòng `$this->candidateJobRepository->updateContractDocumentStatusByIds(...)`.
     - Điều kiện chạy reset: `if ([] !== $documentResetProgresses)`.
   - Trong `bulkArchive()`: Truyền `$resetData['progresses']` và `$resetData['timing_keys']`.
   - Trong `deleteCandidate()`: Bỏ các wrapper `collect(...)` dư thừa quanh `getByFilter()`.

4. **Kiểm tra & Xác minh**:
   - `php -l` toàn bộ file thay đổi.
   - `git diff --check`.
   - Chạy Feature test: `tests/Feature/Api/Consultant/CandidateArchiveTest.php`.
   - Chạy full PHPUnit test suite: `./vendor/bin/phpunit` đảm bảo 100% 632 test cases PASS.

#### R13 implementation evidence (2026-10-19)

- Đã xóa method `updateContractDocumentStatusByIds` khỏi `CandidateJobRepositoryInterface` và `CandidateJobRepository`.
- Đã bỏ câu query `updateContractDocumentStatusByIds` trong `archiveBulkCandidatesAtomically()`, loại bỏ hoàn toàn 1 câu UPDATE trùng lặp trước `upsertProgresses()`.
- Đã loại bỏ `->with('job.branch')` trong `CandidateRepository::getCandidatesForBulkArchive()`, tiết kiệm 2 câu truy vấn SQL eager loading không cần thiết.
- Đã refactor `prepareCandidateJobDocumentResetData()`: duyệt qua `$documentResetJobs` trong 1 vòng lặp duy nhất, loại bỏ tham số trung gian `$documentResetJobIds`.
- Đã xóa các lời gọi `collect(...)` bao ngoài các method `getByFilter()` trong `deleteCandidate()`.
- Verification:
  - PHP syntax lint (`php -l`): PASS trên toàn bộ files.
  - `git diff --check`: PASS.
  - Feature test: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit tests/Feature/Api/Consultant/CandidateArchiveTest.php` — PASS (7 tests, 43 assertions).
  - Full PHPUnit: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` — PASS (632 tests, 9,364 assertions).
- **R13 status: PASS.**






