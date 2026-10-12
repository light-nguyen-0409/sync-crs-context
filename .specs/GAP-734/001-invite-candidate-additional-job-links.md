# SPEC: GAP-734 — Invite Candidate: Additional Job Links

> **Trạng thái**: Implementation trước PASS; amendment external_id không cần numeric PASS (docs-first, implementation và tests). FE/STG deployment verification chưa thực hiện.
> **Ngày tạo**: 2026-10-06
> **Cập nhật**: 2026-10-08 — user chốt thêm `invitation_default_job`; lấy `external_id`, `job_reference`, `title` từ branch registration link.
> **Author**: Codex
> **Nguồn**: [GAP-734](https://gappersonnel.atlassian.net/browse/GAP-734), description và comment 21101 đọc ngày 2026-10-06.
> **Template**: [SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md).

## 1. Tổng quan

Thêm single-select ở đầu modal Invite Candidate: lựa chọn mặc định Telephone/Branch advert và các jobs thuộc branch hiện tại. FE dùng lại GET /api/consultant/jobs; khi chọn job cụ thể chỉ truyền thêm internal job_id vào API invite. Backend lấy branch link làm base, thay thông tin job trong URL rồi gửi email.

**Thiết kế cập nhật này thay thế proposal ban đầu** về endpoint invitation_jobs riêng và cặp job_id + job_ref trong request. Không tạo endpoint options mới, không bắt FE truyền URL/ref/title/external ID để quyết định link.

Phạm vi backend: optional job_id, scoped lookup, URL replacement, email payload, bổ sung job_reference vào Job resource hiện tại, tests và living specs. FE modal/search là integration dependency chưa trace trong workspace. Comment Jira xác nhận one job selected only; screenshot chưa kiểm tra trực quan.

## 2. Database Design

Không migration, bảng/cột mới, backfill hoặc đổi quan hệ.

- Default URL: branches.registration_link.
- Custom job: jobs.id, branch_id, external_id, title, job_reference.
- job_id nhận từ FE là internal jobs.id; job_id trên URL là jobs.external_id.
- Ref của selected job theo proposal cập nhật là jobs.job_reference; backend map sang URL parameter job_ref.
- Không lấy first ref từ candidate_jobs để bù dữ liệu thiếu. candidate_jobs.job_ref vẫn là nơi lưu attribution khi candidate apply sau này.
- Không ghi selected job/link vào invitation hoặc branch; giữ invitation persistence hiện tại.
- Không tạo jobs/candidate_jobs trong invite.

**DATA gap đã trace**: JobService.getOrCreateJob hiện chỉ create external_id/title/branch_id, không populate jobs.job_reference. Vì vậy model có field không chứng minh các jobs thật đã có reference. Cần kiểm tra dữ liệu khi triển khai; job thiếu reference phải báo lỗi custom flow, không tự backfill từ application hoặc giữ lại Telephone ref.

Nguồn reference trên Job là đề xuất dựa trên hướng chọn job qua API jobs trong review; user xác nhận optional job_id/base-link replacement, chưa xác minh dữ liệu production. Nếu yêu cầu cuối cùng là exact parity với dropdown Job Refs, cần giải quyết khác biệt ở §5 trước implementation.

## 3. API Contract

### 3.1. Danh sách jobs — tái sử dụng endpoint

GET /api/consultant/jobs

Auth/middleware/header và offset/limit/order/direction giữ hiện tại. Branch context lấy từ Gap-Branch-ID đã authorize. Response thêm nullable job_reference vào mỗi Job, giữ các fields cũ:

~~~json
{
  "jobs": [
    {
      "id": 42,
      "external_id": "123",
      "title": "Warehouse Operative",
      "job_reference": "WH-001"
    }
  ],
  "count": 1,
  "invitation_default_job": {
    "external_id": "DEFAULT-001",
    "job_reference": "DEFAULT-REF",
  "title": "Telephone"
  }
}
~~~

`invitation_default_job` được parse trực tiếp từ branch `registration_link`:

- `external_id` từ query parameter `job_id`.
- `job_reference` từ query parameter `job_ref` (key rút gọn trong registration link).
- `title` từ query parameter `job_title`.

Nếu branch không có registration link hợp lệ thì trả `invitation_default_job: null`. Không trả raw `registration_link` hoặc field metadata bổ sung. `job_reference` của default option không lookup từ `candidate_jobs`.

Không đổi query hoặc ý nghĩa count, không thêm join candidate_jobs, filter status/Permanent hay search backend. FE tải đủ các trang cần thiết (default limit hiện là 1000), tìm bằng reference/title trong options đã tải và thêm một default option riêng. Job reference null/rỗng được hiển thị unavailable hoặc bỏ khỏi selectable options theo FE convention; backend vẫn kiểm tra khi submit.

**FE subtask**: [GAP-739](https://gappersonnel.atlassian.net/browse/GAP-739) — Invite Candidate job selector and client-side job reference filtering. User chốt filter theo `job_reference` ở FE vì số lượng jobs hiện nhỏ; chưa cần backend search. Subtask yêu cầu case-insensitive substring matching trên options đã tải, pagination completeness, default/null states, branch reset và submit optional internal job_id theo contract này.

Default option không phụ thuộc một Job record có sẵn: giá trị selection null, dùng branch registration_link hiện tại. Khi đổi branch, reload jobs và reset default. `invitation_default_job` chỉ chứa `external_id`, `job_reference`, `title` như mapping ở trên.

### 3.2. Invite

POST /api/consultant/candidates/invite

Headers: Authorization: Bearer {token}, Gap-Branch-ID: {internal branch ID}, Content-Type: application/json.

~~~json
{
  "name": "Example Candidate",
  "email": "candidate@example.com",
  "job_id": 42
}
~~~

Default: omit job_id hoặc job_id=null. Các fields name/email/phone/tag_ids/skill_ids/address/screening_call_note giữ như hiện tại.

CandidateInvite thêm field job_id với default null và rule:

~~~php
'job_id' => 'nullable|integer|min:1',
~~~

Không coi job_id=0 là default. Array/multi-select/noninteger/negative ID bị validation từ chối. Không dùng exists:jobs,id thay cho scoped Service check. Payload job_ref/title/registration_link/external_id không được dùng làm nguồn tạo custom link; không bổ sung prohibited rules lên legacy input ngoài scope.

Success 200 vẫn là CandidateInvitation resource gồm name/email/sent_date.

| HTTP | Trường hợp | Response |
|---|---|---|
| 400 | FormRequest invalid job_id | JsonRequest hiện tại: status/errors |
| 400 | Job không tồn tại, stale hoặc không thuộc branch | InvalidInvitationJobException, wrongParameter/errorCode 1006 |
| 400 | Selected job thiếu nonblank external ID, title hoặc nonblank job_reference | Cùng custom exception; không write/mail |
| 401 | Thiếu/sai token | Auth middleware hiện hữu |
| 400/403 | Thiếu branch header / branch không có quyền | Middleware hiện hữu |
| 500 | Branch thiếu registration_link, base link không dùng được cho custom selection hoặc mail failure | ServerSideException/legacy serverSideError |

Controller hiện catch mọi exception thành 500. Chỉ thêm catch riêng InvalidInvitationJobException trước catch legacy để giữ HTTP 400 cho selection mới. Các nhánh legacy giữ error behavior hiện tại.

## 4. Business Logic — Service Layer

### 4.1. Ordered flow

1. Middleware xác thực consultant, authorize branch và set request branch_id.
2. FormRequest validate job_id optional; Controller normalize validated ID thành int hoặc null rồi append vào invite call.
3. CandidateService.invite đọc branch như hiện tại, yêu cầu branch có registration_link.
4. Private helper resolve URL:
   - jobId=null: dùng nguyên branch registration_link, không parse/re-encode.
   - Có jobId: named repository query theo id + branch_id; validate required job fields; tạo URL theo §4.2.
5. Mọi lookup/validation mới hoàn thành trước invitation write/mail.
6. Giữ gate existing candidate/same legal entity, upsert invitation theo email và xử lý tags/address/skills hiện hữu.
7. sendInvitationEmail nhận resolved registration link làm argument bắt buộc, dùng link đó cho placeholder {registration_link}; recipient/template/branch scope giữ nguyên.
8. Return existing invitation resource.

Không update branches.registration_link khi tạo email cho job cụ thể. Không thêm job/candidate-job mutation, queue/retry hay auto-apply trong API invite. Mail lỗi sau save vẫn có khả năng để lại invitation đã lưu; task không thay đổi atomicity của flow legacy.

### 4.2. URL mapping

Default option trong jobs response dùng mapping từ branch link:

| Response field | Branch registration-link parameter |
|---|---|
| external_id | job_id |
| job_reference | job_ref |
| title | job_title |

Mapping này chỉ phục vụ hiển thị/lựa chọn default trên FE; khi invite không truyền `job_id`, backend vẫn gửi branch registration link theo legacy behavior.

| URL parameter | Nguồn khi chọn job |
|---|---|
| job_id | jobs.external_id |
| job_title | jobs.title |
| job_ref | jobs.job_reference |

`job_reference` trong response/database và `job_ref` trong URL biểu diễn cùng thông tin reference. Giữ nguyên các parameter keys `job_id`, `job_title`, `job_ref` của registration link; không đổi tên sang key của response. Khi có selected job, chỉ thay value tương ứng theo bảng trên; khi không truyền job, giữ nguyên link mặc định.

Giữ scheme/host/path/fragment route và các branch/tracking/UTM parameters của link gốc. Hỗ trợ cả /#/welcome?... và /welcome?...; không xóa # theo helper legacy. Encode values RFC3986, không nối raw strings/double-encode hoặc để lại duplicate target keys.

Custom selection chỉ dùng branch base link có http/https, host và job-query context parse được. Malformed hoặc job-query context mâu thuẫn giữa query và fragment trả configuration error trước write/mail. Default vẫn gửi nguyên link theo legacy behavior.

Branch link vẫn bắt buộc kể cả chọn job. User xác nhận fill registration_link từ selected job; chưa có yêu cầu tạo link khi branch thiếu cấu hình. Không tự fallback sang frontend URL khác.

Chọn base link/mapping/errors nằm ở CandidateService. UrlUtility chỉ xử lý cú pháp URL + replacement map, không query DB hoặc chứa workflow.

**Giới hạn**: Job không có URL/RT/UTM theo từng advert. Thiết kế này dựng registration link theo selected job trên base branch link, không cam kết phục hồi exact original Sourceflow URL. RT/UTM sẽ theo base branch link; nếu cần giá trị riêng theo job phải bổ sung nguồn dữ liệu và update plan.

### 4.3. Application sau invite

Candidate nhận email → FE welcome/signup/login → FE gọi POST /api/candidate/me/jobs bằng external ID/title/ref từ link → backend get/create Job và create CandidateJob, lưu candidate_jobs.job_ref.

Invite không gọi createDefaultJob. Helper createDefaultJob hiện chỉ phục vụ applyBranchLink và approve legal-entity switching; không sửa các flows đó trong GAP-734.

FE/STG acceptance phải xác nhận selected URL parameters được truyền đúng tới application API và dùng được trên Advert Response. Backend tests không thay thế kiểm tra browser/cookie parser thực tế.

## 5. Data Origin & Call Chain

Đã đọc [business flow](../../.business-spec/backend-business-flow-spec.md), [route inventory](../../.business-spec/backend-api-route-inventory.md), [database relationships](../../.business-spec/backend-database-relationship.md) trước khi trace.

| Dữ liệu | Nguồn | Evidence |
|---|---|---|
| Authorized branch | Gap-Branch-ID → middleware attribute | app/Http/Middleware/DetectBranchForConsultant.php:27 |
| Invite input/caller | CandidateInvite → CandidateController → invite | app/Http/Controllers/Api/Consultant/CandidateController.php:282 |
| Default email URL | branchRepository.find → branch.registration_link → MailSender | app/Services/CandidateService.php:1632 và :2888 |
| Default invite job option | branch.registration_link query params `job_id`, `job_ref`, `job_title` | app/Models/Branch.php:66; app/Services/CandidateService.php:1992 |
| Selectable jobs | Existing branch-scoped jobs API | app/Http/Controllers/Api/Consultant/JobController.php:27 |
| Job fields | Job fillable, có job_reference | app/Models/Job.php:35 |
| Job reference population gap | getOrCreateJob không gán job_reference | app/Services/JobService.php:32 |
| Job Refs UI source | candidate_jobs.job_ref join jobs, groupBy ref | app/Repositories/CandidateJobRepository.php:88 |
| Application ref persistence | MeJobController.add → addCandidateJob | app/Http/Controllers/Api/Candidate/MeJobController.php:47; app/Services/CandidateService.php:640 |

~~~text
FE GET /consultant/jobs + default option
  → POST /consultant/candidates/invite (Gap-Branch-ID + optional internal job_id)
  → CandidateService → scoped JobRepository lookup
  → branch URL + job external ID/title/reference
  → existing invitation writes → MailSender(resolved URL)
  → later candidate application API → candidate_jobs.job_ref
~~~

Deviations và pending verification:

- **CODE — resolved locally**: invite đã nhận optional internal job_id, scoped lookup và resolve email URL trước writes; backend không dùng FE URL. Deployment chưa xác minh.
- **CODE — documentation deviation resolved**: đã sửa living SPEC-002 để phân biệt signup với application persistence qua POST /candidate/me/jobs; không đổi signup/application runtime.
- **DATA — source mismatch**: dropdown Job Refs hiện lấy candidate_jobs.job_ref, còn proposal job-ID-only dùng jobs.job_reference. Không mặc định hai field bằng nhau, không tuyên bố API jobs cho danh sách y hệt Job Refs. Cần xác minh product/data expectation trước chốt implementation.
- **DATA — population**: jobs.job_reference nullable và application creation không populate. Kiểm tra selected jobs có usable reference; không coi factory test data là dữ liệu production.
- **CONFIG / EXTERNAL / INFRASTRUCTURE — UNVERIFIED**: branch URL variants, RT/UTM, FE/cookie parser, actual advert URL, mail delivery và deployment chưa kiểm tra runtime.

## 6. Constants & Contracts

Tái sử dụng EmailTemplate::TYPE_TO_CANDIDATE_INVITATION_LINK_SENT. CandidateService khai báo public const cho job URL parameter names và supported schemes; InvalidInvitationJobException khai báo public const cho wrongParameter error key. Không hardcode HTTP/error codes thay config.

Contracts dự kiến:

~~~php
// CandidateServiceInterface / CandidateService:
// invite giữ arguments cũ và append:
// ..., string $note = '', ?int $jobId = null): CandidateInvitation

// JobRepositoryInterface / JobRepository:
findByIdAndBranchId(int $jobId, int $branchId): ?Model;
~~~

Single-record repository return type ?Illuminate\Database\Eloquent\Model. Repository chỉ query id/branch, không validate ref/title/external ID hoặc xử lý URL/config. Business validation nằm trong Service. Helpers workflow private; không Service inject Service, query trong loop hoặc reads trong transaction.

Jobs index có transformation/orchestration nên dùng `JobService.getInvitationJobsByBranchId` để lấy jobs/count và parse default option từ branch link; Controller không parse URL. Tái sử dụng binding JobService hiện hữu. Constants URL params dùng chung đặt ở Job model; UrlUtility xử lý cú pháp stateless cho cả jobs response và invite.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Mục đích |
|---|---|
| app/Exceptions/Services/InvalidInvitationJobException.php | Custom selection error extends Consultant APIErrorException |
| app/Utilities/UrlUtility.php | Stateless query/fragment parameter replacement |
| tests/Unit/Utilities/UrlUtilityTest.php | URL hash/query/encoding/failure tests |
| tests/Feature/Api/Consultant/InvitationJobsTest.php | Real jobs/invite HTTP flow, scoped validation, resolved email → real application persistence |

### 7.2. Files sửa

| File | Phạm vi |
|---|---|
| app/Http/Requests/Api/Consultant/CandidateInvite.php | Optional job_id field/default/rule |
| app/Http/Controllers/Api/Consultant/CandidateController.php | Pass normalized job ID và catch selection exception |
| app/Contracts/Services/CandidateServiceInterface.php | Append optional invite argument |
| app/Services/CandidateService.php | URL constants/helper; invite + sendInvitationEmail |
| app/Contracts/Repositories/JobRepositoryInterface.php | Named id/branch lookup contract |
| app/Repositories/JobRepository.php | Pure scoped lookup |
| app/Http/Resources/Api/Consultant/Job.php | Add nullable job_reference using existing columns pattern |
| app/Http/Resources/Api/Consultant/Jobs.php | Add nullable `invitation_default_job` response object |
| app/Models/Job.php | Shared registration URL parameter constants |
| app/Services/JobService.php và app/Contracts/Services/JobServiceInterface.php | Branch-scoped jobs/default-option orchestration |
| app/Http/Controllers/Api/Consultant/JobController.php | Delegate index orchestration to JobService; giữ jobRefs |
| tests/Feature/Api/Consultant/CandidateTest.php | Extend invitation coverage/default regression/mail payload |
| tests/Feature/Api/Consultant/CanidateJobsTest.php | Existing jobs response + reference, preserve jobRefs behavior |
| tests/Feature/Api/Consultant/JobsTest.php | Update existing jobs response assertions for default object/reference |
| tests/Feature/Api/Candidate/MeJobsTest.php | Selected link fields → actual application persistence |
| tests/Unit/Services/CandidateServiceTest.php | Optional signature compatibility/direct Service validation |
| .business-spec/backend-business-flow-spec.md | SPEC-032 selection behavior và clarify signup/application |
| .business-spec/backend-api-route-inventory.md | Existing invite/jobs contracts, không thêm route |
| .business-spec/backend-database-relationship.md | Clarify Job reference vs application ref, không schema mới |

Giữ semantics JobController/index query, routes, CandidateJobRepository.jobRefs, CandidateRepository filters, generic Resource, email templates, createDefaultJob và application runtime methods. Không sửa JobService.getOrCreateJob để backfill trong scope này. Không formatter/linter, reorder imports hoặc refactor unrelated methods.

Working tree đang có user edits ở generic Resource, AppServiceProvider/config và các files khác. Recheck diff trước code và bảo toàn các thay đổi đó.

### 7.3. Phase 1 — Đồng bộ API docs trước khi viết code

Sau khi plan được approve, hoàn thành bước này trước mọi thay đổi implementation:

1. Đánh giá API contract/docs impact: routes, request/response schemas, examples, error contracts và endpoint documentation. GAP-734 có thay đổi contract, không được đánh dấu N/A.
2. Trong `~/projects/crs-api-docs`, cập nhật tài liệu `GET /api/consultant/jobs`: nullable `jobs[].job_reference`, object nullable `invitation_default_job` chỉ gồm `external_id`, `job_reference`, `title`; ví dụ có/không có default link, branch header và phân trang hiện hữu.
3. Cập nhật tài liệu `POST /api/consultant/candidates/invite`: optional nullable internal `job_id`, ví dụ default/custom selection, branch-scoped validation và các error responses ở §3.2.
4. Ghi rõ response/database dùng `job_reference`, URL giữ key rút gọn `job_ref`; khi chọn job chỉ thay value, không đổi parameter keys. Đối chiếu tài liệu với contract cuối cùng trong plan. Tài liệu ghi rõ đây là contract dự kiến của GAP-734, chưa deployed, theo convention của docs repository.
5. Chạy kiểm tra tài liệu theo convention của `crs-api-docs`, review diff và ghi lại file paths/diff cùng kết quả PASS trong plan. Chỉ bắt đầu viết code sau khi bước đồng bộ PASS.

Nếu docs repository không tồn tại, không thể ghi hoặc chưa đồng bộ, dừng và báo blocker; không bắt đầu implementation hoặc deployment. Sau implementation đối chiếu lại docs với code cuối cùng, cập nhật nếu có thay đổi và xác nhận PASS trước deployment.

**Trạng thái**: PASS — hoàn thành Phase 1 ngày 2026-10-08 theo yêu cầu user. Docs repository clean trước khi thực hiện; Markdown là source of truth. Phase 2 được authorize sau đó bằng yêu cầu implement phase tiếp.

**Files/diff đã cập nhật** trong `~/projects/crs-api-docs`:

- `docs/api/consultant/get-jobs.md`: +84 lines — planned response schema/default object/null example, header/pagination, reference mapping và branch errors.
- `docs/api/consultant/post-candidates-invite.md`: +114 lines — optional job_id schema/default/custom examples, scoped lookup, URL value replacement, success/error contracts và side effects.
- Tổng diff: 2 files, 198 insertions; giữ phần inventory/metadata cũ và thêm section `GAP-734 — Planned contract (not implemented or deployed)`. Không sửa historical OpenAPI source; README xác nhận Markdown là source of truth.

**Validation evidence**:

- `npm run build` tại docs repository: PASS, Docusaurus client/server compile và generate static files thành công (exit 0).
- `git diff --check`: PASS (exit 0).
- Parse 6 JSON examples và kiểm tra default/custom mapping, null default, planned-status markers: PASS.
- Review contract consistency với §3–4: PASS; URL giữ `job_id`/`job_title`/`job_ref`, response dùng `external_id`/`title`/`job_reference`.
- Docs commit/push: PASS — commit `7e27a25` (`docs(GAP-734): document invite job selection contracts`) đã push thành công lên `origin/main` của `light-nguyen-0409/crs-api-docs`; working tree docs clean sau push. Phase 1 hoàn thành cả validation, commit và push theo rule mới.
- Runtime/STG deployment: chưa thực hiện; backend code chưa thay đổi trong Phase 1.

**Input/dependency**: Plan được approve và contract §3–4 đã chốt; docs repository truy cập/ghi được.
**File ownership**: `~/projects/crs-api-docs/docs/api/consultant/get-jobs.md` và `~/projects/crs-api-docs/docs/api/consultant/post-candidates-invite.md`. Chỉ thêm contract dự kiến có nhãn chưa implemented/deployed vào hai trang; giữ metadata hiện tại để không báo sai deployment. Plan này ghi kết quả gate.
**Output/acceptance**: Docs mô tả đầy đủ contract dự kiến, mapping URL và errors; file paths/diff được ghi trong plan; không có thay đổi backend runtime trong phase này.
**Validation gate**: Kiểm tra docs theo convention repository và review consistency với §3–4 đều PASS. Chỉ sau đó bắt đầu Phase 2.

### 7.4. Phase 2 — Implement backend và kiểm chứng

**Amendment — external ID không bắt buộc numeric (user clarification)**:

- Contract mới: selected job chỉ cần `trim((string) external_id) !== ''`; chấp nhận external ID dạng số, chữ hoặc kết hợp. Internal request `job_id` vẫn là integer|min:1, không thay rule này.
- Phase 1 amendment: sửa `docs/api/consultant/post-candidates-invite.md` để thay yêu cầu numeric external ID bằng nonblank external ID; build/review, commit và push docs `main`, ghi SHA/PASS trước sửa code.
- Phase 2 amendment: sửa đúng điều kiện external_id trong `CandidateService::resolveInvitationLink`, bỏ `ctype_digit`; cập nhật InvitationJobsTest để external ID có chữ hợp lệ và được giữ đúng value trong email URL, null/blank vẫn bị từ chối. Cập nhật living SPEC-032 tương ứng; các rule title/reference/branch scope giữ nguyên.
- File ownership/dependencies theo §7.3–7.4; docs gate là build/diff/commit/push PASS, code gate là affected suites/full PHPUnit và Self-Check PASS. Không commit/push backend tự động.
- Trạng thái amendment: APPROVED — user xác nhận `ok`; Phase 1 amendment PASS: `docs/api/consultant/post-candidates-invite.md` thay numeric bằng nonblank external ID, ghi rõ digits/letters và internal positive integer; `npm run build`, `git diff --check` PASS. Docs commit `7f91a13587e077f5fffc8b33c5afc39ed35abcf9`, push `origin/main` thành công trước code; deployment unverified. Phase 2 amendment: condition chỉ còn external ID nonblank; feature provider numeric/letters/mixed URL characters, invalid blank/space và service null/blank audit đã cập nhật. Affected suites PASS: 83 tests / 411 assertions; full PHPUnit PASS: 634 tests / 9189 assertions (04:49.444), log `/private/tmp/gap734-external-id-full.log`. Living SPEC-032 đã đồng bộ; route inventory/DB relationship không có numeric constraint cần sửa.

**Input/dependency**: Phase 1 PASS; dùng contract đã đồng bộ làm đầu vào. Nếu contract thay đổi, cập nhật plan/docs trước khi viết code phụ thuộc.
**File ownership**: Các files backend, tests và living specs liệt kê tại §7.1–7.2; docs files của Phase 1 chỉ được sửa tuần tự khi cần đồng bộ với implementation cuối cùng.
**Execution**: Đọc lại plan/skills, audit callers/tests; thực hiện types/constants → repository → service → Controller/FormRequest/resource; implement jobs default object và invite optional job selection theo §3–4. Không cần phase skeleton riêng.
**Output/acceptance**: Hai endpoints thực hiện đúng contract; branch scope, default/custom URL, errors và invitation email được kiểm chứng; cập nhật living specs và đối chiếu API docs với code cuối cùng.
**Test gate**: Affected suites và full `./vendor/bin/phpunit` PASS theo §8; Self-Check theo plan; docs final consistency PASS trước deployment. Deployment không tự được authorize bởi plan này.
**Trạng thái**: PASS — implementation, affected/full tests và docs synchronization PASS sau lần xác minh hiện tại; không authorize deployment. Default option yêu cầu đủ ba tham số scalar/nonblank; link thiếu/malformed/ambiguous trả null. Custom selection yêu cầu đủ context tham số gốc và chỉ thay values.

**Implementation/Self-Check**:

- Jobs index qua JobService để giữ business transformation ở Service; query branch/count/pagination semantics không đổi. Default object parse từ branch link; selected jobs list thêm nullable reference.
- Invite/FormRequest/contracts xử lý optional job_id; named repository lookup id + branch_id, return ?Model. Custom exception giữ 400/1006, legacy config/mail giữ 500/1010.
- UrlUtility stateless, hỗ trợ ordinary/hash query; chỉ thay job values, giữ raw unrelated parameters và route/fragment, encode RFC3986. Reject missing/blank/array/conflicting job context; deduplicate identical target params khi replace.
- Không migration/backfill/job mutation trong invite; không service inject service, DB query trong loop hoặc read trong transaction mới. Internal helpers private; constants dùng chung ở Job/UrlUtility/exception. Không formatter, sửa generic Resource hoặc user edits.
- Test audit: existing Consultant CandidateTest/JobsTest cập nhật contract assertions; InvitationJobsTest mới chạy real Controller → Service → repository → captured mail → real candidate application. CandidateServiceTest thêm direct validation trước persistence; UrlUtilityTest kiểm tra syntax/encoding/conflicting contexts. Existing CanidateJobsTest/MeJobsTest/AuthTest/JobServiceTest được chạy regression, không cần sửa behavior cũ.
- Living specs cập nhật SPEC-032, signup/application distinction, route contracts và reference relationships.

**Verification**:

- Affected suites: PASS — 77 tests, 362 assertions; chạy bằng `./vendor/bin/phpunit --filter '(UrlUtilityTest|InvitationJobsTest|Tests.Feature.Api.Consultant.CanidateJobsTest|Tests.Feature.Api.Consultant.JobsTest|Tests.Feature.Api.Consultant.CandidateTest|Tests.Feature.Api.Candidate.MeJobsTest|Tests.Feature.Api.Candidate.AuthTest|CandidateServiceTest|JobServiceTest)'`.
- Historical full-suite run: 629 tests, 9,146 assertions, 1 failure ở user-owned untracked `tests/Unit/Services/MatchMakerServiceTest.php:147` (expected `ONel`, actual `O'nel`), exit 1, 02:18.129. Standalone test tái hiện failure; MatchMakerService không có diff của task. Raw output: `/private/tmp/gap734-final-full-phpunit.log` và `/private/tmp/gap734-unrelated-test.log`.
- Latest verification theo yêu cầu clear cache: MatchMakerServiceTest.php không còn trong workspace; agent không xóa test hoặc sửa MatchMaker code. Clear Laravel bootstrap caches, file application cache và PHPUnit result cache; chạy lại full `./vendor/bin/phpunit` PASS — 628 tests, 9,140 assertions, exit 0, 03:29.623. Cache không tạo/revive test; số tests giảm vì file đã không còn. Log: `/private/tmp/gap734-after-cache-phpunit.log`. Backend task đã được commit trong workspace ở `3bed4a9f`; không deploy trong lần xác minh này.
- Docs final consistency/build/diff check PASS; hai trang GET jobs/POST invite ghi local implementation, deployment unverified, thêm rõ default link đủ ba scalar/nonblank params. Commit `a2a8ae3218f0280010362fd622911903cd907f6e` đã push `origin/main` (2 files, +9/-9); docs working tree clean sau push.
- Backend chưa commit/push/deploy; FE/STG acceptance, actual branch reference population và mail-provider delivery vẫn UNVERIFIED.

## 8. Test Impact Review & Verification

Đã review existing Consultant CandidateTest invitation test (hiện chỉ assert 200), CanidateJobsTest jobRefs test, Candidate MeJobsTest/AuthTest, CandidateServiceTest và JobServiceTest. Audit lại toàn bộ callers/tests khi implementation bắt đầu; thêm args optional giữ legacy compatibility.

| Scope | Acceptance |
|---|---|
| Default invite | Omit/null job_id gửi branch URL nguyên giá trị, unchanged response/legacy signature |
| Custom invite | Real HTTP Controller → Service → repository; capture actual MailSender placeholders/template/recipient |
| ID mapping | Request internal job ID khác external ID; URL phải dùng external ID |
| Reference mapping | jobs.job_reference khác candidate_jobs.job_ref; custom URL dùng Job reference, không application ref |
| URL keys | Default response `job_reference` đọc từ URL `job_ref`; custom selection giữ keys `job_id`/`job_title`/`job_ref`, chỉ thay values |
| Invalid selection | Wrong branch/stale/unknown ID, array/noninteger/0/negative, incomplete job fields; no write/mail |
| Input trust | FE-supplied URL/title/ref/external ID không override data từ Job |
| Branch link | Missing config vẫn lỗi; custom malformed URL fail trước writes; default không re-encode |
| URL syntax | Hash/ordinary query; spaces/Unicode/reserved characters; preserve branch/UTM/extra; remove duplicate target keys |
| Jobs API | Adds nullable reference and `invitation_default_job`; missing branch link returns null; giữ fields/count/branch scope/pagination; jobRefs endpoint vẫn theo application refs |
| Existing invitation data | Same-entity email gate, resend/upsert, tags/address/skills behavior giữ hiện tại |
| Candidate application | Parsed custom email fields gọi application API và persist đúng job_id/job_ref; mock external boundary |
| FE/STG | Default + single-select/search/branch reset; selected link tới đúng application/reporting |

Không thêm Repository unit tests. Mock mail/external boundary, không gọi provider thật; verify production call chain thay vì test isolated input giả định. Các tests mới phân biệt nguồn reference, không làm xanh bằng cách đổi generic Resource/config ngoài scope.

Sau approve: Phase 1 (§7.3) đồng bộ API docs và đạt PASS → Phase 2 (§7.4) implement và kiểm chứng. Chạy full affected files gồm Consultant CandidateTest/CanidateJobsTest, Candidate MeJobsTest/AuthTest, CandidateServiceTest/JobServiceTest và URL Utility tests; bổ sung suites nếu caller audit phát hiện impact khác. Sau đó chạy ./vendor/bin/phpunit full và Self-Check against plan. Historical test counts không thay verification cho GAP-734.

Phase 2 đã sửa code và chạy PHPUnit với SQLite in-memory; mail/external boundaries trong tests mới được mock. Không chạy migrations trên DB môi trường thật hoặc gửi mail thật.

## 9. Checklist trước khi Approve

- [x] User xác nhận optional job_id và fill branch registration link bằng selected job.
- [x] Dùng lại jobs API; bỏ endpoint options riêng và FE job_ref parameter của bản trước.
- [x] Default behavior, scoped lookup, URL mapping, error contract, files và tests đã ghi.
- [x] Chia phase theo rule docs-first: Phase 1 đồng bộ API docs; Phase 2 implement/test; mỗi phase có ownership, dependency, acceptance và gate (§7.3–7.4).
- [ ] Xác nhận jobs.job_reference là ref mong muốn cho custom URL và dữ liệu usable; không mặc định parity với Job Refs hiện tại.
- [ ] FE xác nhận query/fragment/cookie/application contract và RT/UTM theo base URL.
- [x] User approve Phase 2 bằng yêu cầu implement phase tiếp.

Sau implementation cập nhật living specs theo code thực tế; báo riêng affected/full test results và FE/STG verification còn thiếu nếu có.

### Amendment external ID — completion gate

- Phase 1 PASS: docs nonblank external ID được build/review và push `origin/main` ở commit `7f91a13587e077f5fffc8b33c5afc39ed35abcf9` trước sửa code.
- Phase 2 PASS: bỏ numeric restriction; trim check chỉ dùng để validate, link giữ nguyên external ID từ selected job. Internal request job_id vẫn positive integer.
- Test audit: InvitationJobsTest numeric/alphabetic/mixed encoded URL → real candidate apply PASS; blank/space HTTP rejection và null service rejection trước persistence PASS. Các suites liên quan default selection, jobs, candidate auth/apply và URL utility PASS: 83 tests / 411 assertions. Full suite PASS: 634 tests / 9189 assertions.
- Self-Check PASS: thay đổi runtime chỉ 1 condition tại existing private Service helper; không đổi DB/types/repository/controller/request, không thêm queries/transaction/magic values. Caller/source vẫn jobs scoped theo branch; docs/living SPEC-032 khớp implementation; git diff check PASS, không formatter. Không có CODE/DATA/CONFIG deviation mới; deployment EXTERNAL/INFRASTRUCTURE chưa kiểm chứng.
- Backend changes đã có trong workspace HEAD `b4f48ae3` sau thao tác commit bên ngoài agent trong lúc verification; agent không commit/push backend. Các local changes không liên quan được giữ nguyên.
