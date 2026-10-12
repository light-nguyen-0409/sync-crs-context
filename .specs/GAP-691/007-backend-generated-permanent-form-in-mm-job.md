# SPEC: GAP-691 — BE sinh Permanent Candidate Form trong job sync MM

> **Trạng thái**: `DONE` — implementation/docs/tests workspace PASS; deployment chưa thực hiện
> **Ngày tạo**: 2026-10-08
> **Author**: Codex
> **Related**: [005 — Form PDF/MM upload](005-permanent-intake-form-pdf-mm-upload.md), [006 — Click metadata](006-agreement-click-metadata-for-form-pdf.md)

> **Amendment 2026-10-08 (§10)**: `APPROVED` — user duyệt amendment DB labels 2026-10-08; Phase 1 PASS; Phase 2 IMPLEMENTING.

## 1. Tổng quan và baseline

**Yêu cầu gốc**: FE không upload `permanent_candidate_form` nữa. BE sinh/lưu PDF trong job sync MM, rồi upload attachment lên MM. Header/footer dùng cùng layout Welfare Check; thay text bên trái tương ứng. Nội dung lấy từ payload submit, title/label theo form FE hiện tại.

Plan này thay thế phần FE export/upload form của 005 và 006 khi triển khai. API click và semantics lưu IP/thời gian click đầu tiên của 006 vẫn giữ nguyên.

Đã đọc ba canonical living specs: `.business-spec/backend-business-flow-spec.md`, `backend-api-route-inventory.md`, `backend-database-relationship.md`; đã trace source BE và FE. Áp dụng skills `backend-workflow` và `laravel-architecture`.

Baseline thực tế:

- `PermanentCandidateIntakeRequest` yêu cầu đúng 3 files: CV, Agreement, Permanent form. Service kiểm tra ownership, type, job scope và storage; lưu profile/address/answers rồi dispatch event.
- Listener hiện gọi `MatchMakerService::syncPermanentCandidate` trực tiếp, đồng bộ. `SyncPermanentCandidateToMatchMakerJob` là đường legacy, có retry và bắt lỗi non-retryable/state bằng `fail()` mà không rethrow.
- MM sync nhận file IDs, upload CV → Agreement → Permanent form, sau đó cập nhật MM status. Intake chỉ đặt `is_permanent=true` khi sync thành công. Profile đã lưu vẫn tồn tại nếu sync lỗi.
- Welfare PDF dùng Dompdf và `pdf.layouts.certificate`: title/subtitle bên trái, logo bên phải, footer cùng các logo thương hiệu. Có thể reuse layout mà không gọi Welfare Service hoặc sửa nghiệp vụ Welfare.
- FE user xác nhận: `~/projects/gap-web-frontend`, form `packages/gap-frontend/src/containers/GetStartedPerm/GetStartedPerm.tsx`, builder `permanentIntake.ts`, labels tại `locales/en/translation.json`, `locales/en/registrationJourney.json`, option labels tại `containers/GetStarted/options.ts`.
- **CODE deviation / integration mismatch**: snapshot FE local hiện submit CV + Agreement, chưa thấy luồng export/upload Permanent form; BE hiện yêu cầu 3 files. Contract mới sẽ thống nhất 2 files. Không suy ra deployed FE đang giống snapshot local.
- **DATA/CONFIG/EXTERNAL/INFRASTRUCTURE**: chưa xác minh production records, queue workers và deployed FE/MM. Giữ debug MM behavior hiện hữu; không đổi timezone/proxy settings.

### Quyết định đã xác nhận

User chọn **queue chạy nền**: submit trả trạng thái `pending`, job xử lý PDF/MM sau. User xác nhận **chưa thêm bảng `permanent_candidate_submissions`**. Snapshot serialize trực tiếp trong queue job payload; không thêm submission history, status tracking hay polling endpoint. Không dùng `dispatchSync` hoặc phụ thuộc default queue vì `config/queue.php` hiện mặc định driver `sync`.

## 2. Database design

**N/A — không thêm bảng, column hoặc migration trong scope này.** Generated PDF tiếp tục lưu qua bảng `files` hiện hữu, click metadata đọc từ `candidate_timings`.

Validated snapshot (array scalar, contact arrays, file references và click metadata) truyền trực tiếp vào constructor job và được serialize bởi queue. Snapshot tồn tại cùng queued/failed job, không có submission record riêng.

Infrastructure amendment sau approval: source `jobs` là bảng recruitment, không có queue table schema. Redis đã có trong docker-compose và worker default. Dùng connection Redis riêng `permanent_intake`, queue cùng tên, retry_after 600s. Commit profile writes trước, enqueue Redis sau; chỉ trả pending khi enqueue thành công. Nếu enqueue lỗi, local profile vẫn đã lưu, `is_permanent=false`, trả error hiện hữu HTTP 502/code 1017 với message dispatch failure. Không cam kết atomic DB/Redis và không thêm bảng để giải quyết boundary này.

Retry/re-submit cùng snapshot dùng fingerprint ổn định trong tên file và named Repository lookup theo candidate/job/type/filename. Fingerprint chứa validated business payload, file references và persisted click metadata; không chứa thời gian render thay đổi mỗi lần retry. Chỉ reuse khi metadata và object storage tồn tại. Không thay nội dung form cũ; snapshot khác sinh file mới.

## 3. API contract

### 3.1. Submit

`POST /api/candidate/me/permanent-intake`, auth/middleware hiện hữu.

- Giữ các field business hiện tại và validation tương ứng.
- `files` đổi từ đúng 3 thành đúng 2 entries, IDs và types distinct: `cv` và `work_finder_agreement`.
- Không nhận `permanent_candidate_form` trong submit; không cần FE gửi HTML/PDF, title, IP hay timestamp để render.
- Giữ ownership/storage checks cho CV/Agreement. Agreement tiếp tục thuộc job đang submit.
- Success đổi thành **HTTP 202** trong envelope hiện hữu: `candidate_id`, `job_id`, `candidate_job_id`, `submission_status=pending`. Không có `submission_id`; pending chỉ xác nhận đã enqueue, không trả `submitted` trước khi job thành công.
- Giữ validation/ownership, 401 và 409 already permanent. Không thêm in-progress status/409 dựa trên submission record. Lock chống job chạy đồng thời và check completion hiện hữu; chưa có cơ chế nhận diện từng lần submit đang pending hoặc API retry/resubmit riêng.
- PDF/storage/MM errors sau enqueue không trả HTTP 502 cho request đã hoàn tất; được xử lý qua retry, failed queue jobs và logging hiện hữu. Local persistence failure rollback; Redis enqueue failure sau commit trả HTTP 502/code 1017 theo existing custom API exception, local profile vẫn được giữ. Không tạo fake pending khi enqueue thất bại.

### 3.2. Candidate upload

`POST /api/candidate/me/files/{type}`: từ chối type `permanent_candidate_form` với HTTP 400, `wrongParameter`, message `Permanent candidate form is generated by the backend.` theo envelope hiện hữu. Reject trước ClamAV/storage write. Không bỏ type khỏi Model/global enums vì BE, file listing và MM vẫn dùng type này.

Các endpoint đọc file và dữ liệu cũ giữ nguyên. Không mở rộng thành việc cấm consultant/compliance upload trong task này.

### 3.3. Agreement click

`POST /api/candidate/me/jobs/{jobId}/work_finder_agreement/click`: không đổi response `clicked_at` raw persisted value và IP đã thống nhất trong 006. PDF lấy metadata từ BE storage, không phụ thuộc FE chuyển hai giá trị lại.

## 4. Business logic và call chain

Luồng mới:

1. FormRequest validate payload 2 files. Intake Service xác minh candidate/job/files/email và pre-fetch data cần thiết.
2. Tạo snapshot từ validated payload đã được xác minh; giữ nguyên contact arrays, optional fields và consent. Lấy timing theo đúng candidate/job, lưu first-click IP/timestamp vào snapshot render. Không dùng submit IP/time thay click metadata.
3. Transaction chỉ writes profile/address/answers. Sau commit enqueue Redis job, với snapshot/file IDs đã chuẩn bị trước transaction. Không đưa reads/PDF/storage/MM vào transaction. Trả 202 sau commit, `is_permanent` vẫn false.
4. Snapshot truyền trực tiếp vào queued job. Không rebuild từ candidate profile và không dispatch sync listener cũ thêm lần nữa cạnh queue mới. Audit event/listener để chọn một đường enqueue duy nhất.
5. Job lấy shared atomic lock theo candidate; đọc và verify candidate/job/files, skip nếu candidate đã completed. Lock dùng shared Redis cache store. Khi lock bận, release job để thử sau, không chạy MM đồng thời. Gọi generation method của `PermanentCandidateIntakeServiceInterface`; Service render/lưu PDF và File row. Job sau đó gọi `MatchMakerServiceInterface::syncPermanentCandidate` với generated form ID qua signature hiện hữu.
6. MM register/upsert và attachment flow hiện hữu. Chỉ khi thành công job gọi intake completion method set `is_permanent=true`. Request không set flag ngay sau dispatch. Không ghi submission status hoặc history mới.

Job lock TTL phải lớn hơn timeout. Proposed dedicated settings: timeout 300s, lock TTL 360s, retry_after 600s; verify MM timeout budget và worker config trước release. Không đổi retry_after/worker queue dùng chung. Cần điều chỉnh retry policy khi release vì lock bận để không tiêu hết attempts trước khi job thực sự xử lý.

Giới hạn đã chốt: chưa có polling/history cho FE và chưa đảm bảo deduplicate các submit khác payload còn đang chờ. `pending` là trạng thái enqueue trong response, không phải trạng thái persisted mới. Kết quả background failure được vận hành qua failed jobs/logs; không mở rộng API chỉ để theo dõi kết quả trong task này.

Job được phép orchestration hai Services; Service không inject Service khác. Generation dùng Repository + FileUtility/Dompdf; không inject Welfare Service hoặc FileService vào Intake Service.

### Failure, cleanup và compatibility

- PDF phải sinh/lưu thành công trước outbound MM operations của job.
- Generation method dùng custom exception trong `App\Exceptions`; distinguish non-retryable data/render failure với transient storage/MM failure. Không throw generic PHP exceptions hoặc swallow rồi completion.
- Non-retryable/state lỗi: fail job và log theo convention hiện hữu, không completion. Transient lỗi: throw để retry tối đa 3 attempts xử lý hiện hữu; terminal failure dùng failed queue storage. `failed()` chỉ dùng constructor context vì Laravel có thể tạo fresh job instance; không phụ thuộc mutated in-memory form ID.
- Append nullable snapshot array với default để constructor/job payload cũ tương thích. Legacy job có form ID tiếp tục dùng file đó; legacy payload không có snapshot không được sinh PDF rỗng. Rà soát toàn bộ event/dispatch callers trước thay đổi; intake mới dùng async path, legacy listener chỉ giữ nếu còn caller cần.
- Storage write nằm ngoài DB transaction; nếu tạo File row thất bại, xóa object vừa tạo theo compensation hiện hữu. Temp files được cleanup trong `finally`. Reuse file phải kiểm tra storage, không chỉ lookup DB.
- Snapshot fingerprint tránh tạo PDF lặp cùng dữ liệu. Không cam kết exactly-once MM attachment: baseline có nguy cơ partial MM success khi retry; giữ nguyên behavior và ghi rõ giới hạn này khi bàn giao.
- Không log payload PII hoặc binary PDF. Không xóa hàng loạt form cũ.

## 5. PDF content và data origin

New view `resources/views/pdf/permanent_candidate_form.blade.php` extends `pdf.layouts.certificate`. A4/Dompdf theo Welfare; cùng header/footer styling và logo provider, không sửa shared layout nếu không cần.

- Left header đề xuất: **Permanent Candidate Form**; subtitle **Permanent Candidate Registration**.
- Main title theo FE: **Get started**.
- Footer giữ bố cục/logo Welfare, đổi text thành thông tin form registration do CRS sinh. Không mang sang câu xác nhận Welfare/GBG/facial biometrics vì không có dữ liệu nghiệp vụ tương ứng.

| Thứ tự / section theo FE | Nội dung và nguồn |
|---|---|
| Personal information | Title, First name, Middle name (Optional), Last name, Email, Phone number, Date of birth — validated submit snapshot |
| Address | House/Apartment name/number, Street, Town/City, County, Postcode — snapshot `address` |
| When can we contact you? | Contact date, Contact time — `contact_dates`, `contact_times` |
| Transportation | What’s your primary method of transport?; How far are you willing to travel?; Where did you hear about us? — transport/distance/recruitment fields |
| Right to work status | `journey_type` label theo FE; Which document do you have? khi Others — `journey_type_other_document` |
| CV | Tên CV từ File đã xác minh ownership; không embed file binary hoặc link có token |
| Work Finder Agreement | Tên Agreement đã xác minh; I have read and agree to the Work Finder Agreement — accepted value; bổ sung click IP và click time đã lưu |

Subtitles dùng cùng English translations FE. Mapping option values sang labels theo `GetStarted/options.ts` và common enums: Mr/Mrs/Miss, transport, distance, recruitment source, contact days/times, Passport/Share code/Other. Đặt mappings cố định trong constants; giá trị hợp lệ nhưng chưa có mapping hiển thị raw text, không thêm validation ngoài scope.

Amendment §10 sẽ thay source label cho transport/distance/recruitment bằng `questions.data.options`; các mappings còn lại và section titles giữ nguyên. Đoạn baseline ở trên mô tả implementation trước amendment.

Tất cả variables Blade phải được method generation cung cấp rõ ràng, trace từ caller thật. Không rebuild content từ profile DB có thể đã đổi sau submit. Optional middle name/other document và missing click metadata có fallback explicit; không assume Carbon object cho raw `clicked_at`. Không tự đổi timestamp contract/timezone; hiển thị persisted value. Escape text bằng Blade; test HTML/Unicode và nội dung dài/multi-page.

## 6. Execution phases và gates

### Phase 1 — API docs trước code

Input: plan được duyệt; async đã được user xác nhận. Freeze 202 pending schema và async failure narrative trước code; không thêm polling.

Owned files trong `~/projects/crs-api-docs`:

- `docs/api/candidate/post-me-permanent-intake.md`: files=2, request examples, 202 pending không submission ID, enqueue failure và transition từ sync response.
- `docs/api/candidate/post-me-files-type.md`: backend-only form type, HTTP 400 example.
- `docs/flows/permanent-intake.md`: snapshot trong queued job → generated PDF → MM, retry/failed jobs/legacy behavior; queue config/worker dependency.
- Rà soát các schema/index/job references liên quan; cập nhật nếu còn nói FE upload form. Click endpoint chỉ sửa narrative FE-export nếu tồn tại, không đổi raw timestamp contract.

Đánh dấu planned contract chưa deployed theo convention docs repo. Validate links/examples/schema và chạy docs build theo package scripts. Stage đúng task files, commit và normal push remote `main` theo AGENTS authorization; giữ unrelated edits. Phase PASS chỉ khi validation + commit + push thành công. Nếu docs repo không writable/sync được, báo blocker và không bắt đầu dependent implementation.

Output/gate cần ghi khi thực thi:

- Actual files/diff: 4 docs files theo owned list; request files=2, HTTP202, upload rejection, async PDF/Redis flow và superseded FE export handoff
- Validation result: `npm run build` PASS; `git diff --check` PASS
- Docs commit SHA / successful push main: `358edb65d582a8d8f8090f6832215f39b13bb44a`; successful normal push origin/main
- Phase 1: `PASS`

### Phase 2 — Implementation, integration, tests

Dependencies: Phase 1 PASS. Không có skeleton phase riêng.

Owned backend files dự kiến:

- `app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php`: 2-file contract.
- `app/Services/PermanentCandidateIntakeService.php` và Contract: snapshot, generation method, file checks, failure mapping; constants cho file identity/title/mappings.
- `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php`: async snapshot loading/generation/MM/completion/failure và legacy compatibility; audit event/listener để intake mới không sync/dispatch hai lần.
- Existing intake Controller/Resource/Service/Contract cho HTTP 202 pending nếu cần; không thêm route, polling Resource, submission Model/Repository hoặc migration.
- `config/queue.php`: dedicated Redis connection/queue; `docker/8.1/supervisord.conf` thêm worker riêng theo §4, giữ user-edited default worker, không đổi queue chung.
- `app/Contracts/Repositories/FileRepositoryInterface.php`, `app/Repositories/FileRepository.php`: named generated-file lookup, single record return `?Model`; pure DB access.
- `app/Http/Controllers/Api/Candidate/MeFileController.php`: reject FE form upload, giữ các type khác.
- New PDF Blade; custom exception chỉ khi cần phân loại generation failure ngoài existing exceptions.
- `documents/Gap-API-Candidate.yaml`: schema/examples 2 files, 202 pending và backend-only upload type.
- Existing/new affected Service/Feature/Job tests.
- Ba canonical `.business-spec/` files: cập nhật implemented flow/routes/file relationships sau code; runtime docs chỉ lưu tại đây, crosslink nếu thêm living-spec file.

Không sửa MM upload contract/order, Welfare business/layout, unrelated Controller/Resource/config, frontend code hoặc backend commit/push trong task này. FE handoff: submit CV+Agreement, bỏ form export/upload nếu deployed client có; xử lý 202 bằng thông báo đã tiếp nhận/đang xử lý, không hiển thị MM sync hoàn tất hoặc poll endpoint chưa có. Local snapshot đã gửi 2 files nhưng chưa xác nhận UI hỗ trợ pending.

Acceptance: submit trả 202 chỉ sau successful Redis enqueue, không gọi MM/render trong request. Background real call chain sinh PDF đúng queued payload snapshot/FE labels/branding/click metadata; lưu job-scoped file; MM nhận đủ 3 attachments; chỉ successful sync đánh dấu completed. Background failure dùng failed jobs/logs hiện hữu, không thêm bảng hoặc polling. Client không upload form được. Legacy callers được test. Không query trong loops/read transaction; không Service→Service injection; minimal diff/no formatter.

## 7. Test impact review và verification

- Audit mọi tests/assertions với required files=3, submit/events/job signatures, form upload, click metadata, MM attachment handling và Welfare PDF.
- Update `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`, `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` và affected upload/job/listener/MM suites tìm được khi implementation.
- Add coverage: 2-file success; missing/duplicate/wrong-owner/wrong-job files; client form entry/upload rejected; PDF body đúng validated fields và FE labels; optional/null metadata, raw click time, IPv6; HTML escaping, Unicode, long text; logos/header/footer data từ production caller.
- Integration coverage đi qua caller thật: request→serialized queued snapshot→job→generator→MM; generated form ID dùng cho attachment. Verify DB profile đổi sau enqueue không làm thay snapshot PDF. Không chỉ mock view payload tự tạo.
- Async tests: 202 pending không submission ID, không MM trong request; local rollback và Redis enqueue failure sau commit; snapshot serialize đầy đủ; concurrent delivery lock/completed candidate skip; transient retry/exhaustion/non-retryable; completion chỉ cập nhật candidate khi job thành công; không thêm polling routes hoặc phụ thuộc submission table.
- Failure tests: render/storage/DB file-write/MM failure không fake success hoặc set completion; cleanup; identical-snapshot reuse, missing storage regeneration, changed snapshot creates new file; debug mode; legacy job compatibility; lock release và worker timeout safety.
- Không viết Repository unit tests; cover lookup qua Service/Feature tests. Shared Welfare regression cần chạy vì dùng cùng layout/provider conventions.
- Chạy tất cả affected PHPUnit suites, sau đó full `./vendor/bin/phpunit` theo workflow; chỉ PASS khi 100% tests passing. Không chạy formatter/linter.
- Self-check theo plan và approved docs; nếu thay đổi documented contract, update plan/docs trước dependent code, validate/commit/push docs bổ sung.

## 8. Checklist approval

- [x] Đã đọc living specs, skills và trace BE/FE.
- [x] Source FE được user xác nhận: `~/projects/gap-web-frontend`, GetStartedPerm.
- [x] User xác nhận queue chạy nền, submit pending.
- [x] User xác nhận chưa thêm bảng submission; snapshot truyền qua job, không polling.
- [x] User duyệt plan đã thu gọn và PDF header/subtitle.
- [x] User duyệt 2-file contract và backend-only form upload.
- [x] Phase 1 docs validation/commit/push PASS.
- [x] Phase 2 implementation/test audit/full suite/self-check PASS.

**Execution status**: Phase 1 PASS; Phase 2 implementation/affected suites/full-suite/self-check PASS. Không có migration hoặc submission table.

## 9. Execution notes

- APPROVED 2026-10-08. Queue infrastructure amendment: Redis thay database để tuân thủ no-new-table và source infrastructure. Docs updated before code.
- CODE deviation mới khi rescan: working tree hiện click API là void/basic success, không còn raw click response trong plan 006/docs. Task này đọc persisted timing cho PDF và không khôi phục/thay click response ngoài scope.

### Phase 2 implementation evidence

- New submit explicitly dispatches Redis queue job after profile commit. Event/listener unchanged for legacy callers, no double dispatch. Shared Resource user change supports withStatus(202), task does not overwrite it.
- Snapshot serialized in job; generated form uses existing Intake Service, FileRepository named lookup and shared Welfare layout. New custom generation exception is non-retryable; upload/File write exceptions retry.
- Lock contention uses tries=0/maxExceptions=3 and 24h retry deadline; real processing failures counted, lock release does not consume exception budget. Existing jobs without snapshot keep original MAX_ATTEMPTS=3 behavior.
- Infra source: Guzzle MM client has no explicit HTTP timeout; dedicated worker bounds job to 300s and failOnTimeout=true. Redis retry_after=600s > lock TTL=360s > worker timeout=300s. No unrelated MM client change.
- Test impact audit: affected intake Service/Feature, new form Feature, legacy/new Job, MM Permanent sync, CV upload, Welfare Service/Feature/Job. Affected gate PASS: 144 tests / 7,094 assertions. Full suite PASS: 613 tests / 9,146 assertions, 02:13.666.

### Final verification / self-check

- Full `./vendor/bin/phpunit`: PASS — 613 tests / 9,146 assertions; affected gate PASS — 144 / 7,094. Report: `/private/tmp/gap691-full-phpunit.txt`.
- OpenAPI YAML parse PASS; submit HTTP 202 and click HTTP 200 verified. `git diff --check` PASS. No formatter/linter run.
- Plan compliance: 2 client files, backend-only form upload, async queue payload snapshot, same Welfare layout/FE labels, persisted click metadata, reuse/cleanup, legacy compatibility, background completion, no migration/submission table/polling, no new API route.
- Production call chain tested via actual submit → queued snapshot → generation → mocked MM boundary → candidate completion. Real external MM/target deployment/worker availability not claimed.
- Data access batch-loaded before in-memory loops; DB transaction retains existing writes only; generation/storage/MM outside transaction; new File lookup returns nullable Model; Service does not inject another Service. Existing default worker/user changes preserved; only new worker block added to supervisor.
- Canonical living specs updated for async flow, file relationships and unchanged route inventory. Prior click API/raw-response mismatch recorded; task does not restore previous response code.
- Docs first gate complete: build PASS, commit/push `358edb65d582a8d8f8090f6832215f39b13bb44a` on origin/main before code.
- Release requirements: publish new Blade/config/worker; enable Redis `permanent_intake` worker and shared Redis locks. FE uses 202 as accepted/processing and removes form export/upload. No backend commit/push or deployment performed.

## 10. Amendment — Query DB cho question answer display labels

**Trạng thái**: `APPROVED`. User duyệt 2026-10-08. Yêu cầu user: “chuyển sang query DB đi”, sau khi xác nhận raw value keys đã được pass vào job và label của ba question đã có trong DB theo seeder.

### 10.1. Scope và data source

| Payload field | Question category constant | Label source |
|---|---|---|
| transportation_method | Question::PRIMARY_METHOD_OF_TRANSPORT | questions.data.options[value] |
| transportation_distance | Question::WILLING_TO_TRAVEL | questions.data.options[value] |
| recruitment_source | Question::WHERE_DID_YOU_HEAR_ABOUT_US_CANDIDATE_ANSWER | questions.data.options[value] |

Source đã trace: Question Model cast `data` thành array; QuestionSeeder seed đủ ba options maps. `answer_options` chỉ có value/association, không phải source display label. Submit hiện đã prefetch ba categories để lưu answers; dùng cùng data thay vì thêm ba queries. Seed source không chứng minh dữ liệu production đã có; fallback thiếu mapping phải rõ ràng.

Giữ section titles/field labels theo FE; title, contact days/times và journey type giữ mappings hiện hữu vì không thuộc ba question DB này. Không sửa câu trả lời lưu DB, request validation, MM mapping, click API hoặc các user edits (Consultant File Resource/Blade/staged files).

### 10.2. Thiết kế

1. Thêm named batch query `QuestionRepositoryInterface::getByCategories(array $categories)` và implementation trả Eloquent Collection, order by id ascending; chỉ DB access. Thay query `allByFilter` hiện hữu trong submit để grouping/chọn first giữ behavior cũ. Mapping field→category nằm trong Service constants.
2. Service dùng questions đã prefetch để resolve **selected display label** của ba fields từ `data.options`. Không queries trong loop/transaction; không lấy label từ FE hay hardcoded options maps.
3. Queue snapshot giữ `data` raw values như hiện tại và thêm `display_labels` associative map cho đúng ba fields. Ví dụ raw `transportation_method=car`, `display_labels.transportation_method=Car` lấy từ DB. Chỉ label đã chọn được snapshot, không cần serialize toàn bộ options.
4. PDF ưu tiên display labels này cho ba fields. Xóa ba maps transport/distance/recruitment khỏi `FORM_OPTION_LABELS`; không query DB lại cho snapshot mới. DB label đổi sau enqueue không làm đổi nội dung PDF của job đó.
5. Missing question, data/options không phải array, key không có, label null/rỗng hoặc không phải string: fallback raw payload value. Không quay về hardcoded maps và không thêm reject validation ngoài scope.
6. Legacy jobs trước amendment không có `display_labels`: generation batch-fetch ba categories một lần trước render và resolve theo DB hiện tại. Legacy không thể tái tạo label tại thời điểm submit cũ; ghi rõ compatibility boundary. Snapshot mới có key nhưng missing mapping dùng raw fallback, không requery. Giữ snapshot-based file fingerprint/reuse; không regenerate PDF đã lưu khi DB đổi.

Data origin: validated request → existing questions batch read → Service resolve selected labels → snapshot raw values + display_labels → job serialization → generator → Blade sections. Tránh isolated tests tự giả định snapshot có keys; phải test production submit cung cấp keys thật.

### 10.3. API/docs assessment và phases

Routes, external request/response/error schemas giữ nguyên (2 files, HTTP202 pending, no polling). Queue payload thêm optional internal map; không migration/model hoặc bảng mới. PDF label source đổi nên update flow docs trong cùng task.

**Phase 1 — Docs trước code**:

- Owned file `~/projects/crs-api-docs/docs/flows/permanent-intake.md`: source DB cho ba fields, snapshot labels, missing mapping/raw fallback và legacy queued jobs. Endpoint schemas/examples/error contracts không đổi; review endpoint docs để xác nhận không còn claim static option maps.
- Mark amendment approved/planned/not deployed theo docs convention. Build + diff check; task-only docs commit và normal push main trước code.
- Gate: `docs/flows/permanent-intake.md` updated (8 inserted lines); build + diff check PASS; commit `e815a2adf3db2c05d89fc22ffb8dd4de5a796b41` pushed origin/main; Phase 1 PASS.

**Phase 2 — Code/test** (sau Phase 1 PASS):

- Owned files: QuestionRepository Contract/Implementation; PermanentCandidateIntakeService; existing intake Service/Feature tests và PermanentCandidateFormTest; ba canonical living specs. Job/Blade không cần sửa nếu forwarding/rendering đã generic; không sửa ngoài scope.
- Tests: DB labels khác constants cũ thực sự xuất hiện trong snapshot/PDF; raw values giữ nguyên; label DB đổi sau enqueue vẫn dùng snapshot; thiếu question/options/key/empty/invalid label fallback raw; legacy snapshot batch lookup; không requery cho snapshot mới; transport/distance answer_option_id và recruitment answer persistence không đổi.
- Update fixtures/mock expectations đúng named batch lookup và questions.data.options thật. Cover data access qua Service/Feature, không thêm Repository unit tests.
- Chạy affected suites, full `./vendor/bin/phpunit`, self-check minimal diff/no N+1/reads outside transaction và canonical docs update.

### 10.4. Acceptance và approval

- [x] Trace source DB/seeder và real request→snapshot→job→PDF chain.
- [x] User duyệt amendment DB label source và snapshot/legacy fallback design.
- [x] Phase 1 docs validation/commit/push PASS.
- [x] Phase 2 affected/full tests và self-check PASS.

Lượt này chỉ cập nhật amendment plan; chưa sửa implementation hoặc API docs.

### 10.5. Execution notes

- Phase 1 PASS: flow docs build/diff check PASS; commit `e815a2adf3db2c05d89fc22ffb8dd4de5a796b41` normal-pushed origin/main before code.
- Code implemented: named questions batch lookup; shared private grouping/resolution helpers; selected DB labels snapshotted; removed three hardcoded maps; legacy lookup once before render only when no stored form reused.
- Tests cover actual submit→serialized snapshot→generator, custom DB labels distinct from old constants, raw values/answer associations, no requery on new map, one batch for legacy and missing/invalid data fallbacks.
- CODE/user-edit baseline: user removed main Get started heading/subtitles in Service/Blade after prior delivery. Preserve those edits; remove stale Get started HTML assertion, keep header/sections/escaping/PDF checks. Consultant File Resource/staging state untouched.
- API docs/schemas/routes/errors unchanged apart from documented internal label source. No migration or production seeding.
- Affected/full suites pending; self-check pending.

Latest §10 verification: focused PDF/DB suite PASS 20 tests / 158 assertions. Affected suite 157 tests / 7,181 assertions có một failure ở test chặn upload form: user đã bỏ guard MeFileController ngoài scope label amendment. Đã hỏi intent qua async clarification; không tự restore guard. Full suite đang chạy, cần review kết quả và chạy tuần tự lại nếu có test artifact interference từ focused/full overlap. Không mark §10 DONE trước khi xử lý test gate.

## 11. Amendment — PDF trình bày như certificate, bỏ subtitles

**Trạng thái**: `APPROVED` — user duyệt 2026-10-08; docs-first đang thực thi. User yêu cầu: “loại bỏ subtitle trong form pdf, làm pdf trông giống 1 certificate chứ k phải 1 form điền”. Giữ §10 DB label amendment đang thực thi; đây là steering thêm về presentation, không hủy scope DB labels.

### 11.1. Baseline và hướng trình bày

Blade hiện tại đã bỏ main Get started heading và subtitle của section theo user edits. Header vẫn render `$headerSubtitle` qua `pdf.layouts.certificate`; CSS còn `.form-section-subtitle` và bảng có border-bottom ở mỗi field nên presentation vẫn giống form.

Thiết kế đề xuất:

- Bỏ toàn bộ subtitle của Permanent PDF, gồm header `Permanent Candidate Registration` dưới heading. Không sửa shared Welfare layout; child view không yield subtitle và ẩn empty subtitle block bằng CSS riêng nếu cần. Không thay behavior Welfare.
- Header chính đề xuất **Permanent Candidate Registration**; giữ logo bên phải và footer/brand logos theo Welfare layout. File type và tên file vẫn permanent_candidate_form.
- Phần nội dung dùng bố cục certificate: tên candidate nổi bật, các nhóm thông tin gọn, section heading màu thương hiệu, labels nhỏ/màu nhẹ và giá trị rõ ràng. Bỏ đường kẻ dưới từng ô và mọi styling giống vùng nhập/chỗ điền.
- Giữ thứ tự section và caption theo FE; giữ đủ payload values, DB display labels, CV/Agreement references và click metadata. Không thêm lời chứng nhận identity/compliance, biometric hoặc chữ ký không có dữ liệu.
- Giữ A4; ưu tiên spacing/typography dễ đọc. Nội dung dài được xuống trang, không ép một trang bằng cách cắt text hoặc giảm font quá nhỏ.

### 11.2. Data origin và ownership

- Tên candidate nổi bật nếu thêm phải do generation method truyền rõ ràng, lấy `first_name`, optional `middle_name`, `last_name` từ validated `snapshot.data`, không đọc profile DB mới nhất hoặc assume Blade có `$candidate`.
- Sections vẫn từ `buildPermanentFormSections`; raw/display-label behavior giữ đúng §10. Không thêm query DB hoặc đổi snapshot để phục vụ styling, trừ value view-only được derive từ snapshot đã có.
- Owned code: `resources/views/pdf/permanent_candidate_form.blade.php`, phần constants/view data liên quan trong `PermanentCandidateIntakeService.php`, existing PermanentCandidateFormTest. Không tạo Controller/Resource/Repository mới hoặc sửa shared certificate/Welfare business.
- Bỏ subtitle constant/view variable chỉ khi hết caller; trace trước xóa. Giữ mọi user edits còn lại và staging state.

### 11.3. API/docs assessment và phases

Routes/request/JSON responses/errors/DB schema/queue retry không đổi. PDF presentation/title đổi nên flow docs phải được đồng bộ trước implementation.

**Phase 1 — Docs**: `~/projects/crs-api-docs/docs/flows/permanent-intake.md` cập nhật header chính, no-subtitle/certificate presentation, source tên candidate từ snapshot, thay narrative Get started/subtitle đã stale. Mark approved/planned/not deployed; docs build + diff check; task-only commit/push main. Gate `PASS`: build/diff check thành công; commit `7928b19` pushed origin/main trước implementation.

**Phase 2 — Template/service/tests**: sau docs PASS và §10 dependencies được giữ. Thực hiện presentation ở child Blade, derive candidate name từ source thật, update impacted rendering assertions theo approved design. Gate gồm actual caller test, PDF render/layout checks, preview synthetic PDF và affected/full PHPUnit PASS. Ghi path preview và verification vào plan; không dùng live candidate PII.

Acceptance: không có header/section subtitle; nhìn như certificate với branded heading và thông tin đã hoàn tất; đủ/đúng dữ liệu, Unicode/escaping, optional fields và multi-page; shared Welfare layout/PDF không bị sửa. DB labels tiếp tục snapshot và không bị đọc lại cho job mới. File generation/retry/upload MM giữ nguyên.

### 11.4. Approval và status

- [x] User duyệt presentation và header `Permanent Candidate Registration`.
- [x] Docs-first gate PASS.
- [x] Template/service/render preview/affected/full tests/self-check PASS.

Lượt này chỉ cập nhật plan §11; chưa sửa Blade/service cho presentation mới. §10 implementation đã có, test completion còn pending như ghi ở §10.5.

### 11.5. Execution evidence

- Docs-first PASS: `docs/flows/permanent-intake.md`, build/diff check PASS, commit `7928b19` pushed origin/main before presentation code.
- Child Blade now hides empty shared header subtitle, has no section subtitles, shows queued full name and branded sections with muted labels/no field underlines. Service explicitly derives first/optional middle/last name from validated snapshot; subtitle/old Get started constants and view input removed after caller search. Shared certificate/Welfare unchanged.
- Actual submit→queued snapshot→Service→Blade tests PASS: 21 tests / 171 assertions. Optional-middle/complete-name cases, escaped Unicode, section order/all values, DB label sources, metadata, generation/reuse and long multi-page content covered.
- Synthetic preview: `/private/tmp/gap691-certificate.pdf`; raster pages `/private/tmp/gap691-page-1.png`, `/private/tmp/gap691-page-2.png`. Visually inspected both pages: heading/name/labels legible, no input underlines or subtitles, all sections and footer logos retained. PDFKit text extraction confirms final Agreement/IP rows. Two A4 pages are expected; no forced truncation.
- Self-check: no shared Welfare edit, no new DB query for presentation, no snapshot/public JSON change, no migration/formatter/backend commit. Stored PDF reuse remains unchanged. Canonical specs updated for presentation and explicitly document user-removed upload-guard CODE deviation.
- Full suite running sequentially; upload guard intent remains pending and gates not marked DONE.

Final sequential verification (2026-10-08): full `./vendor/bin/phpunit` ran all affected suites, 627 tests / 9,246 assertions, exactly one failure: `PermanentCandidateIntakeTest::testPermanentFormUploadIsRejectedBeforeScanningOrStorage` at line 1363 expected400/actual500 because user removed guard from MeFileController. No storage/Welfare error on sequential rerun. PDF/DB-label focused suite PASS21/171 and self-check/diff check PASS. §10/§11 full-test gate remains NOT PASS; no deployment/backend commit claimed. Pending explicit user decision on removed guard; do not restore/delete test without resolving intent. Docs push complete and preview available.

### 11.6. Approved upload compatibility decision

User explicitly chose “giữ upload” after the concrete alternatives (keep upload/update tests vs restore guard). Preserve the removed MeFileController guard. This supersedes the earlier BE-only upload rejection, while intake still accepts exactly CV/Agreement and generates its own form in the background job. No production code change required.

Docs-first: update `docs/api/candidate/post-me-files-type.md` and `docs/flows/permanent-intake.md` to document existing generic upload support for permanent_candidate_form (Gap-Job-ID required, normal scan/extension checks,201/File metadata; not an intake input). Validate/build/commit/push main before test update. Then replace rejection test with actual successful upload/read/storage/metadata assertions, retaining missing-header400. Run affected/full suites sequentially. Canonical CODE deviation resolves to approved compatibility behavior. Approval already given; no separate confirmation needed.

Upload compatibility docs-first PASS: docs endpoint/flow build and diff check PASS, commit `166b28f` pushed origin/main before test/local-doc edits. Existing controller kept unchanged. Replaced obsolete rejection test with missing-header400 plus real upload201/storage/owned job metadata/read assertions: focused PASS1 test/13 assertions. Updated local YAML and all canonical specs. Full suite rerun sequentially pending. User choice resolves previous guard-intent blocker.

Final gate PASS after approved upload decision: sequential full `./vendor/bin/phpunit` PASS627 tests/9,255 assertions (includes all affected suites), no failures/errors. Focused upload PASS1/13; focused certificate/DB labels PASS21/171. Diff check PASS. §10 DB labels, §11 certificate presentation and upload compatibility complete in workspace; documentation commit/push complete. No backend commit/deployment claimed. All user edits preserved; MeFileController guard remains removed. No extra table/migration/formatting.

## 12. Amendment — Logo Hawk3 thứ tư ở footer Permanent PDF

> Trạng thái: APPROVED — user ok 2026-10-09.

### 12.1. Yêu cầu và baseline

Thêm logo thứ tư lấy đúng `config('company.logo_hawk3_talen_solutions_thumbnail')` cho tài liệu Permanent Candidate Registration. Ba logo hiện tại giữ thứ tự: Gap Personnel, Driving Force, Gap Technical; Hawk3 Talent Solutions ở cuối cùng hàng. Search existing plans: scope footer thuộc007, extend tại đây, không tạo duplicate plan. Skill backend-workflow áp dụng; lượt này chỉ plan.

Source verified: config/company.php đã có key trỏ storage/logos/hawk3_talen_solutions_thumbnail.png (user asset/config). Shared certificate layout đang render ba logo cố định và dùng cho cả Permanent/Welfare. Permanent Service là caller cung cấp view data; child CSS có thể override riêng. Không tự sửa/đổi tên config hoặc asset user.

CODE deviation với §11: child Permanent hiện đã bỏ h2 candidate name theo user edit nhưng view data/test cũ vẫn có candidateName assertion. Preserve user edit, không tự restore heading trong task logo; ghi nhận baseline khi audit test. Shared layout dùng bởi Welfare nên không append Hawk3 vô điều kiện.

### 12.2. Thiết kế và data origin

- Service generatePermanentCandidateForm cung cấp rõ ràng optional `additionalFooterLogos` chỉ cho Permanent view, một item `{path: config(key), alt: Hawk3 Talent Solutions}`. Fixed config identifier dùng public const phù hợp trong Service.
- Shared layout giữ nguyên ba logo mặc định, merge thêm optional list (default empty), dùng cùng asset-exists/base64 rendering hiện tại. Welfare caller không truyền list nên vẫn ba logo, không duplicate footer HTML/business logic.
- Child Permanent CSS giảm max width/margin của footer-logo để bốn logo cùng hàng vừa A4, giữ aspect ratio và không ảnh hưởng CSS Welfare. Không sửa header/body hoặc queue/MM/data contracts.
- Missing/null Hawk3 config/file được bỏ qua theo existing footer missing-asset behavior, tránh file_exists(null)/broken image; không tạo placeholder. Khi đủ bốn files render đúng bốn logo. Existing stored PDFs vẫn reuse, không tự regenerate/restyle.

### 12.3. API docs assessment và execution gates

Public routes/JSON request/response/errors/schema không đổi. PDF branding đổi nên flow documentation cập nhật trước code theo docs-first gate.

**Phase 1 — Docs**: owned `~/projects/crs-api-docs/docs/flows/permanent-intake.md`: planned/not deployed branding có bốn footer logos cho Permanent, thứ tự/logo config và Welfare vẫn ba. Nêu asset deployment prerequisite và old-file reuse. Build/diff check, task-only commit và normal push main; ghi SHA/PASS trước Phase2. Không đổi endpoint schemas/errors/examples JSON.

**Phase 2 — Implementation/verification**: owned PermanentCandidateIntakeService.php view data/constants, pdf/layouts/certificate.blade.php optional list merge/safe file-exists, pdf/permanent_candidate_form.blade.php scoped footer CSS, existing PermanentCandidateFormTest và affected Welfare tests nếu cần; canonical business flow doc. Không sửa config/company.php, TestCommand hoặc asset files/user content.

Tests qua actual queued snapshot→Service→Blade caller: four footer image elements (order/alt/bytes), Hawk3 from supplied config path, missing/null config fallback three/no broken image, Welfare no extra logo, A4 footer layout không wrap/clip và content unchanged. Audit current candidate-heading test against user-edited baseline; report unrelated failures rather than silently restoring heading. Preview synthetic PDF/raster để review footer. Run affected PDF/Welfare/Job suites và full PHPUnit sequentially; process-only APP_CONFIG_CACHE override nếu local cache vẫn freezes pgsql. Known previous unrelated LaravelCacheScriptTest failures remain out of scope.

### 12.4. Acceptance / approval

- [x] User duyệt thêm logo cuối hàng chỉ Permanent, shared layout optional extension và scoped CSS.
- [x] Docs-first build/commit/push PASS.
- [ ] Actual caller/fallback/Welfare regression/layout preview/affected/full-test gates/self-check PASS.

No implementation edits in this turn. No migration/new table/backend commit/formatter/live job invocation.

### 12.5. Execution evidence

- Docs-first PASS: flow docs build/diff check PASS; commit `770a750` pushed origin/main before implementation.
- Permanent Service passes additionalFooterLogos with exact requested config key and alt constant. Shared layout merges optional list/default empty and filters null/missing paths safely. Permanent-only footer-logo CSS max-width120px/margin8px; Welfare styles/default three logos unchanged.
- Test impact: real Service/queued snapshot caller tested; footer order/config bytes/valid image decoding/A4 box containment/non-overlap/same row verified. Missing/null asset fallback tested. Real Welfare processPostCheck caller verified no additional list and three original logos. Stale h2 rendering assertion aligned to user's already-removed name heading by checking the retained middle-name field; no heading restored or content changed.
- Focused footer tests PASS3/46; affected Permanent/Welfare/Job/Command suites PASS63 tests/371 assertions. Scoped diff check PASS.
- Preview `/private/tmp/gap691-four-logos.pdf`, page2 raster `/private/tmp/gap691-four-logos-page-2.png` visually reviewed: four ordered logos fit one row, no overlap/clipping. Existing user Hawk3 thumbnail is embedded unchanged (including its image background). Two-page A4 content preserved. No asset/config edits, DB/public API/queue changes, formatter or backend commit.
- Full suite running sequentially with process-only config-cache override; gate pending, prior unrelated cache-script baseline may remain.

Final §12 verification: full PHPUnit executed all649 tests/9,375 assertions, exactly four failures all in pre-existing unrelated LaravelCacheScriptTest (still expects route:cache/count3 while user script has config:cache/view:cache). No new/footer/Welfare failures. Affected gate PASS63/371; preview/layout and self-check PASS, docs commit/push PASS770a750. Overall full-test gate remains NOT PASS; do not claim complete regression/deployment. Runtime feature implemented, user assets/config/staging preserved; no baseline script/test edit.

## 13. Amendment — Permanent job dùng chung Redis/default worker

> Trạng thái: APPROVED — user duyệt triển khai chung13/14, 2026-10-09.

### 13.1. Yêu cầu và current source

User muốn gộp job vào default thay vì cấu hình Supervisor riêng. Extend007 vì cùng queue/deployment scope; existing008 command vẫn dispatchSync và không đổi. Backend-workflow áp dụng; chưa sửa implementation.

Source: snapshot job currently pins permanent_intake connection/queue; config defines dedicated Redis alias retry_after600. Local Supervisor already has queue-worker `queue:work redis --queue=default --sleep=3 --tries=3 --timeout=60` plus permanent-intake-worker. Production Supervisor file currently has no queue-worker block. INFRASTRUCTURE deviation/unknown: server actual Supervisor command/connection/queue chưa verified; không suy ra worker production từ local file. Three canonical specs describe dedicated queue baseline; update after code.

### 13.2. Proposed routing / behavior

- Job snapshot branch explicitly pins connection `redis`, queue `default`, phù hợp worker hiện có trong source. Không chỉ bỏ onConnection vì queue.default có thể là sync và user vẫn muốn submit202 chạy nền. Legacy jobs without snapshot giữ constructor behavior hiện tại.
- Reuse Job queue constants đổi target redis/default; preserve job-specific timeout300, retryUntil24h, tries0/maxExceptions3, failOnTimeout, Redis lock TTL360/release30, generation/MM/completion ordering và pending response.
- Shared Redis connection retry_after đổi90→600 bằng existing Job constant để reservation không expire trước job timeout300. Chỉ giảm timeout job xuống60 để tránh config change không đáp ứng thời gian PDF/MM nên không chọn.
- Keep existing default worker command --timeout60/--tries3: Laravel Worker.timeoutForJob ưu tiên serialized job timeout300, job tries/maxExceptions riêng vẫn được dùng. Add stopwaitsecs360 cho default Supervisor block để graceful stop không kill job giữa chừng; remove permanent-intake-worker block. Không tạo worker mới/không đổi numprocs hoặc production Supervisor ngoài scope.
- Shared default queue có thể bị Permanent jobs chiếm worker lâu hơn; retry_after600 cũng làm reserved jobs khác phục hồi chậm hơn khi worker chết. Chấp nhận tradeoff để đơn giản vận hành, không thay retry logic các job khác.

### 13.3. Compatibility / rollout

- Giữ deprecated connection/queue `permanent_intake` trong config bằng LEGACY constants cho backlog cũ. Không dùng new redis/default constants làm key cho alias cũ hoặc đổi queue của backlog thành default vì sẽ strand messages.
- New jobs chỉ vào redis/default. Legacy alias không cần permanent Supervisor process lâu dài; nếu còn jobs queued/reserved cũ, drain bằng worker tạm trước bỏ dedicated process: `php artisan queue:work permanent_intake --queue=permanent_intake --stop-when-empty --timeout=300`. Không queue:clear/delete/copy/re-dispatch tự động và không cam kết reserved jobs đã drain chỉ qua empty check; cần kiểm tra pending/reserved/delayed và failed jobs khi cutover.
- Refresh config cache/restart default worker sau deployment; local Supervisor config baked into Docker image cần rebuild/recreate để áp dụng remove block/stopwaitsecs. Production phải xác minh worker hiện có thật sự consume Redis/default và đủ graceful-stop timeout; nếu đã đúng routing không cần tách thêm program. Repo production config không có worker nên không claim deploy alone tự chạy.
- Không live queue manipulation/deployment trong implementation turn; chỉ prepare configs/docs/tests để review. Không tự drain trên server với IDs/integration chưa verified.

### 13.4. API/docs phases

Public routes/request/response/errors/examples JSON không đổi, nhưng queue execution/deployment docs đổi nên docs-first gate áp dụng.

**Phase1 docs**: owned `~/projects/crs-api-docs/docs/flows/permanent-intake.md`, plus endpoint page only if references dedicated worker. Mark approved/planned/not deployed; replace dedicated Redis routing/worker with redis/default, shared retry_after600/job-timeout300/stopwait360, legacy-drain prerequisites/cache+worker restart. Endpoint202/pending and502 unchanged. Build/diff check, task-only commit/push main, record PASS SHA before code.

**Phase2 code/tests**: owned SyncPermanentCandidateToMatchMakerJob constants/routing, config/queue.php shared retry_after + deprecated alias, docker/8.1/supervisord.conf removal/stopwait, README queue instructions if relevant; affected existing Job/Intake Feature tests and canonical3 specs. No Service workflow, DB migration, production Supervisor, TestCommand or logo edits.

Tests: literal redis/default routing for serialized/new snapshot job and actual submit; config redis retry_after600 > job timeout300, legacy alias remains old queue; legacy no-snapshot and cmd dispatchSync unchanged. Default Supervisor existing worker command preserved and only dedicated block removed/stopwait added. Review job worker timeout/tries precedence in installed framework source. Affected Job/Intake/Command suites then full PHPUnit sequentially; local config-cache override if needed. Known unrelated cache-script failures out of scope. Self-check no false pending, no sync fallback, no stranded backlog/deletion, docs/cache/worker rollout limitations recorded.

### 13.5. Approval / gates

- [x] User approve redis/default shared worker, shared retry_after600 and legacy backlog compatibility.
- [x] Docs-first build/commit/push PASS.
- [x] Implementation/affected/full tests/self-check PASS.

Plan only in this turn; no runtime/source/config edit.

## 14. Amendment — Reusable file lookup và typed job DTO

> Trạng thái: APPROVED — user duyệt triển khai chung13/14, 2026-10-09. §13 queue redis/default vẫn chưa approved; đây là scope bổ sung, không mặc định triển khai routing change khi chỉ duyệt14.

### 14.1. Yêu cầu / source verified

1. Rename findGeneratedPermanentForm to findByCandidateIdAndJobIdAndTypeAndFileName để tái sử dụng lookup.
2. SyncPermanentCandidateToMatchMakerJob constructor đang six positional args + untyped nested snapshot array; đổi DTO rõ data shape.

Existing source traced: FileRepository method filters candidate_id/job_id/fixed permanent type/original_file_name, latest(id)->first. Callers: intake generator, TestCommand; no other production callers. Job callers: intake submit, legacy PermanentCandidateSubmittedEvent listener, TestCommand; affected Unit/Feature tests use serialized jobs and mutable arrays. Current job invokes generator with five args. Snapshot creation comes from validated request + actual DB file names/click timing/DB selected labels; timing column currently raw value (no datetime casts in CandidateTiming), preserve raw timestamp and no timezone conversion. Skills backend-workflow/laravel-architecture apply.

### 14.2. Repository contract

`findByCandidateIdAndJobIdAndTypeAndFileName(int $candidateId, int $jobId, string $type, string $fileName): ?Illuminate\Database\Eloquent\Model`

- Exact same query/order, except type becomes supplied parameter.
- Remove old method name after updating all callers; Service/Command pass File::TYPE_PERMANENT_CANDIDATE_FORM. No generic firstByFilter for this stable condition, no business/config logic in Repository.
- Cover via Service/Feature tests, not Repository unit tests. Verify different type/job/candidate/filename not matched and latest matching metadata reused only when storage exists.

### 14.3. DTO design / one constructor input

Use PHP8.1-compatible classes with public readonly typed properties (not PHP8.2 readonly class). New files under App\Dto:

- `PermanentCandidateSyncData`: candidateId:int, jobId:int, cvFileId:int, agreementFileId:?int, permanentFormFileId:?int, snapshot:?PermanentCandidateFormSnapshotData. Job constructor takes exactly this DTO, using named arguments at callers. Legacy CV-only/optional Agreement/form cases keep null semantics.
- `PermanentCandidateFormSnapshotData`: explicit typed fields for submitted Personal/contact/transport/journey/consent data plus CV/Agreement names, clickedAt:?string, ip:?string and selected displayLabels:?PermanentCandidateFormDisplayLabels. Include submitted jobId for existing mismatch check. Fields include title/firstName/middleName/lastName/email/phoneNumber/phoneNumberCountryCode/dateOfBirth, address:PermanentCandidateFormAddressData, contactDates:list<string>, contactTimes:list<string>, transportationMethod/distance/recruitmentSource:string, journeyType:string, journeyTypeOtherDocument:?string, workFinderAgreementAccepted:bool. No catch-all public array data/snapshot property.
- `PermanentCandidateFormAddressData`: building/street/townCity/county/postcode:string.
- `PermanentCandidateFormDisplayLabels`: transportationMethod:?string, transportationDistance:?string, recruitmentSource:?string. Null container means no map/legacy batch resolution; existing container with a missing individual label means raw-key fallback without requery. Constructor/source adapter preserve missing/empty semantics.

Collection fields remain arrays with PHPDoc list<string>; this is a typed collection, not unstructured snapshot data. Conversion helpers operate only at validated request/legacy serialization/view boundaries, never query DB or orchestrate workflow. Service retains DB label resolution rules, generator and rendering coordination. Don't just wrap existing raw `array $data` in a DTO.

Job uses public readonly typed input DTO; derived generated form ID is job runtime result/private property, not mutated DTO. failed() still logs effective generated ID and all existing identifiers. generator Service contract accepts `PermanentCandidateSyncData` instead of five positional args; requires snapshot and agreement in background path, same custom state errors. Sections may use explicit toArray for presentation field iteration, no runtime assumed keys. Internal helper methods private; public DTO conversion methods only for documented boundary callers.

### 14.4. Queue compatibility / fingerprint contract

- Existing queued objects are PHP-serialized and constructors are not called during unserialize. Before changing public property types/remove old properties, add explicit legacy deserialization boundary to normalize old scalar IDs + array snapshot into typed DTO; use existing SerializesModels behavior for other inherited queue properties. Preserve connection/queue/retry deadline/tries/timeouts on old jobs; do not reroute old backlog or re-enqueue automatically.
- New jobs serialize typed DTO with scalar/value objects only, no Eloquent Models/container/Service. Optional null snapshot preserves old job behavior.
- File reuse currently hashes serialize(original snapshot). Preserve exact original SHA256 fingerprint when normalizing an old array before any DB label fallback/order/type normalization. DTO stores this immutable fingerprint (not raw legacy array); generator/Command share its public identity method instead of independently hashing DTO objects. New snapshot factory computes identity once from canonical scalar snapshot at enqueue. Changing DTO class/property order must not regenerate an old stored PDF.
- DB labels remain frozen for new jobs; legacy missing labels resolved once before render and never change stored identity. Retry/upload/MM ordering, raw clicked_at, record ownership, cleanup and completion unchanged.
- Immutable input tests rebuild DTO for changed payload rather than mutating arrays. Explicit legacy fixture serializes an old-format job payload (not just new constructor with array), tests deserialization both snapshot and CV-only and old stored-file reuse.

### 14.5. API/docs phases / dependencies

No HTTP routes/request/response/errors/schema/migration change. Internal queue payload/serialization/fingerprint contract changes, so update internal flow docs first.

**Phase1 docs** owned `~/projects/crs-api-docs/docs/flows/permanent-intake.md`: typed internal DTO data source and legacy serialized-job/fingerprint compatibility; no extra public fields, planned/not deployed. Build/diff check/task-only commit+push main PASS before code. If §13 approved together, combine docs update and implementation on shared Job/config files sequentially; otherwise preserve currently dedicated queue routing.

**Phase2 code** owned four new DTO files, FileRepository Contract/Implementation, Job, Intake Service Contract/Implementation, legacy Event Listener, TestCommand; affected existing Job/Intake Service/Form/Command Feature tests and canonical living specs. No Event public constructor change required; listener maps existing event fields into DTO. No empty new layers, no configs/Supervisor change unless13 separately approved.

Test audit/acceptance: generic lookup passes explicit type and preserves scoping/order/reuse; one typed constructor input; full field/nullable/list mapping through real submit and command; queue serialize/unserialize new DTO and old payload; frozen DB labels/legacy lookup count; raw timestamp; old identity/stored reuse; immutable payload changes; Job failure logs/generated ID/lock/completion/legacy CV-only; public202/pending unchanged; no query-in-loops or DTO DB queries. Run affected suites then full PHPUnit sequentially with process-local cache override if needed. Known cache-script baseline failures remain out of scope. Record self-check/diff/test results; no formatter/backend commit/live MM run.

### 14.6. Approval

- [x] User duyệt reusable lookup signature + one typed job DTO input, typed snapshot/address/labels và legacy serialization/fingerprint compatibility.
- [x] Docs-first gate PASS.
- [x] Code/affected/full tests/self-check PASS.

This turn modifies plan only, not implementation. §13 remains pending approval.

13/14 source-trace correction: Event Listener calls MatchMaker Service directly and does not construct Job; therefore no listener/Event edit required. Legacy queued Job still needs normalization. Joint approval granted before code, docs-first in progress.

### Joint §13/14 execution evidence

- Approval: explicit user “triển khai chung”, before implementation. Docs-first flow build/diff check PASS; commit4fa64fc pushed origin/main before code. Public APIs unchanged, internal queue contract/deployment docs synchronized.
- DTOs implemented: readonly SyncData + typed flattened SnapshotData + AddressData + DisplayLabels. Mapping at validated request/legacy/command boundaries only; no public catch-all payload property, DB/service injection or business workflow in DTOs. Collections PHPDoc list<string>.
- Job one constructor argument, generated form result private. Legacy __unserialize adapter delegates inherited queue property restore and saves original snapshot fingerprint. New redis/default routing; old permanent_intake alias/queue untouched. Existing default worker command preserved, stopwait360 and shared retry_after600; dedicated local block removed, production Supervisor untouched. README includes shared worker/old drain/cache/rebuild notes.
- Generic named File lookup uses supplied type with original latest(id)/nullableModel semantics; Service and Command updated. All old method/runtime snapshot array references removed from affected callers. Listener verified direct-MM, unchanged. Current TestCommand user sample IP/content preserved; previously removed command test file not restored, integration case added to existing Form Feature suite.
- Tests: actual submit/typed field mapping/queue routing; serialized new DTO; exact old PHP-job serialization preserving queue/deadline/flags; old CV-only; original hash with reordered legacy keys/stored file reused without question read; generic type/owner/job/filename/latest reuse; missing label-container vs missing individual field; generated result logging; real synchronous Command with mocked MM/immutable input/profile unchanged; shared config/default Supervisor. Focused first50/406 PASS, affected123/7008 PASS, command1/14 PASS; final affected137 tests/7200 assertions PASS. After final snapshot-construction hoist full suite runs all affected cases again.
- Self-check/diff check PASS; no new query loop/read transaction, migration/formatter/production worker/live MM/queue drain/backend commit. Initial contract/implementation signature mismatch corrected before tests. Full gate pending; deployment and queue drain not executed.

Joint §13/14 final gate PASS (2026-10-09): full process-isolated PHPUnit PASS636 tests/9,375 assertions, including all current affected suites and final typed snapshot construction. Diff check PASS. Former unrelated Unit/Scripts and Console test files are no longer present in current user workspace; not restored or modified by this task. Implementation/legacy compatibility/generic lookup/shared config/tests/living specs complete; API docs commit4fa64fc pushed main. No backend commit/push/deployment, actual worker restart or queue drain. Operator still must refresh config/restart workers (rebuild baked local Supervisor image) and inspect/drain any old permanent_intake messages before retiring old worker. Production Redis/default worker availability remains infrastructure prerequisite, not verified from repo production Supervisor.

## 15. Follow-up — Restore Service alignment with approved DTO contract

Status: DONE with §16 (2026-10-09); affected/full tests and self-check PASS. Extends §14; no new design or public API contract.

Current source verification: Service interface line23 accepts `PermanentCandidateSyncData`, Job passes `$this->data`, and FileRepository exposes the generic lookup. However, current `PermanentCandidateIntakeService.php` still has the previous five-argument generator at line456, old six-argument Job construction at line410, raw-array snapshot/section helpers, and removed `findGeneratedPermanentForm` lookup at line471. Its DTO imports are also absent. This is a CODE deviation from §14 and the canonical living specification; the previously recorded PASS is not evidence that the current working tree is aligned. The source of the file reversal has not been established.

Scope/ownership: only affected methods/imports in `app/Services/PermanentCandidateIntakeService.php`, necessary existing affected tests, and this plan's execution evidence. Preserve all staged/unstaged user edits and unrelated Service methods. No formatter, migration, backend commit/push, queue drain or deployment.

Implementation steps:
1. Construct the typed snapshot from actual validated submit data, DB file names/selected labels/raw timing before writes; dispatch Job with one `PermanentCandidateSyncData`.
2. Change generator signature to the exact interface DTO contract. Extract typed IDs/snapshot, enforce required Agreement/snapshot with the existing custom state exception, and preserve ownership/storage checks.
3. Use DTO's original fingerprint and `findByCandidateIdAndJobIdAndTypeAndFileName` with explicit Permanent form type. Preserve existing PDF reuse before legacy DB label resolution.
4. Use typed snapshot/display-label data through rendering/section helper; retain missing label-container resolution and individual-field fallback, raw clicked_at, certificate layout and four footer logos.
5. Review existing submit/generator/Job/Command tests; add a reflection regression assertion that Service implementation and interface have the same single DTO parameter. Run affected suites then full PHPUnit sequentially with process-local APP_CONFIG_CACHE override; run diff check and record actual results.

API/docs assessment: N/A — no API contract/API docs change; restores the already documented §14 behavior (docs commit4fa64fc). No route/request/response/example/error/schema changes. Canonical living specs already describe the target; trace after correction to confirm CODE alignment.

Acceptance: Service loads without signature incompatibility; actual submit passes one typed DTO; generator uses generic repository method and immutable fingerprint; existing legacy/new payload, stored-PDF reuse, DB label and certificate tests pass; full suite passes against the current tree. No success claim before these gates pass.

### 15.1. Expanded read-only audit (2026-10-09)

User requested a complete omission review; no implementation approval inferred. Verified Controller validated input -> Service submit -> Job DTO -> generator -> FileRepository -> view, plus TestCommand, legacy Event Listener, DTO serialization, provider bindings, queue configuration and existing tests.

Confirmed current CODE deviations, all within PermanentCandidateIntakeService:
- Line456: five-argument generator incompatible with interface's single DTO. `php -r` class loading reproduces fatal error/exit255 before any workflow runs.
- Line410: submit still invokes the new one-DTO Job constructor with six old positional arguments; after signature fix this would raise TypeError during enqueue and be translated into queue-failed502 after profile writes.
- Lines470–471: generator recalculates raw-array hash and calls removed repository method. Must use immutable DTO fingerprint and the generic typed lookup to preserve old stored-file reuse.
- Lines371,476–478,494–505,557–576: submit snapshot, display-label fallback, view name fields and sections still use array contract; three DTO imports are absent. Merely changing the public signature leaves these dependent operations broken.

Working-tree vs index diff explicitly shows DTO imports, typed generator/section signature, typed dispatch and generic lookup changed back to their old forms in this Service. This establishes the current divergence, not who or what caused it. Preserve unrelated constructor formatting/other edits when correcting it.

No further old Permanent Job property accesses or old runtime lookup callers found outside that Service. Job/new+legacy serialization, four DTOs, File/Question Repository implementations and TestCommand classes LOAD PASS. Provider bindings match contracts. Event Listener intentionally calls MatchMaker directly. Shared redis/default routing, retry_after600, job timeout300, stopwait360 and legacy queue alias are present. Actual production worker/backlog remains INFRASTRUCTURE unverified.

Test audit: existing Form and Intake feature tests already exercise actual submit/typed fields/new+legacy fingerprint/reuse/DB labels and synchronous Command; Job unit tests cover typed constructor, legacy queue payloads and shared worker settings. Targeted Form regression test attempted with process-local config-cache override; blocked by the reproduced signature fatal/exit255 before assertions. Current full-suite PASS cannot be claimed; rerun after correction. Four new DTO files are currently untracked and must be included when the user commits the task.

Documentation findings: plan008's historical dispatch example still shows old positional arguments; canonical living-spec main paragraph and external flow docs retain prominent-name wording although the current Blade no longer renders that heading (canonical §12 already records the removal). These are documentation drift, not new runtime defects. Record/synchronize applicable current descriptions separately if included in correction scope; no external docs mutation during this read-only audit.

## 16. Amendment — Service-built DTO, validation pipelines and per-execution query reuse

Status: DONE / user approved clarified build-first design with ok (2026-10-09); all verification gates PASS. Extends §14–15 rather than creating a duplicate task. Includes the contract corrections in §15. Applies backend-workflow and laravel-architecture; template sections below cover design/data origin/contracts/files/tests. No implementation changes in this turn.

### 16.1. Verified purpose and query audit

`getOwnedCandidateJob` (current Service line617) queries candidate_jobs by candidate_id/job_id and throws the existing Candidate API error if missing. Calls ignoring its result are authorization/existence guards, not unused business work. Config, Agreement generation, click and submit are independent HTTP requests; their guards cannot share prior request validation.

Worker-side counts below are static call-chain counts for a non-completed snapshot job, not measured SQL timings (current Service signature fatal prevents live execution). Repository cache behavior can change physical SQL counts.

| Data | Current worker reads | Proposed reads per attempt |
|---|---|---|
| candidate_jobs ownership | isPermanentCandidate + generator + MatchMaker sync + completion = 4 | 1 shared runtime context |
| candidate | status + MatchMaker + completion = 3 | 1 shared model, reused for writes |
| CV / Agreement | generator batch, then individual MatchMaker finds | 1 batch, shared validated records |
| generated form | generic lookup/create, then MatchMaker find | reuse returned File; no MM reload |
| MM question categories | getAnswerByCategory called separately for source/transport/distance = 3 | 1 categories batch, in-memory resolution |
| MM job / branch / address / answers | once each | once each; current DB data |
| submit question options | 2 answer-option lookups for transport/distance | 1 named batch query by the exact question/value pairs |

Submit's files/ownership/labels/timing and worker reads occur at different times and are intentionally separate. PDF labels remain frozen at submit; MM currently reads persisted profile/address/answers/current question definitions, and must retain that behavior. PDF and MM recruitment category constants differ in source: preserve each current category rather than assume they are identical. Click timing `firstOrCreate` + conditional update + refresh preserves first-click concurrency behavior; do not optimize away its refresh/atomic condition in this scope.

### 16.2. Flow and runtime DTO boundaries

User clarification supersedes the previous staged-loader design: the Service builds the complete runtime data DTO FIRST. All subsequent validation and business steps consume/pass that DTO and perform no additional DB reads, except a documented dependency on data that genuinely becomes available only after a previous processing step. This is not a separate task to validate DTO structure. FormRequest still validates input shape; the business pipeline checks rules using preloaded data.

Use Illuminate Pipeline with ordered closures delegating to private Service methods. Builders own Repository reads; pipeline validation, mapping, rendering, MM processing and completion cannot hide reads, use lazy-loading relationships or call ID-based wrappers that rebuild data. Runtime DTOs expose typed preloaded models/value fields, not a catch-all array. Nullable members represent missing records/legacy optional data until the rule pipeline checks them. Missing builder prerequisites do not dereference null; dependent reads use IDs from already loaded records inside the initial build step. A builder does not throw a competing business error that masks the pipeline's existing error priority.

**Submit:** `submit(Candidate, validated input)` starts with a private builder. It reads CandidateJob, one files batch, address, existing answers, question categories, exact matching answer options batch and timing, and builds `PermanentCandidateIntakeContextData` with typed submitted fields, preloaded records, actual names/labels/raw timing and the final frozen snapshot. Preserve the original validated scalar payload's identity when constructing the snapshot, not a reordered presentation array. Then pipeline rules check ownership, already-Permanent state, file owner/type/job/storage and email using only context fields, in the current public error order. The write step uses preloaded models/answers/options, dispatch builds SyncData from DTO, and response uses its candidateJob ID. All data reads finish before the transaction/pipeline processing; no second lookup through getOwnedCandidateJob/saveAnswer. Builder may perform additional reads on invalid inputs compared with today's fail-fast code; this is an explicit consequence of the user-requested build-first flow. Rejection before writes/enqueue/MM and the public error priority remain mandatory; old tests asserting rejection before downstream SELECTs must be updated to the new boundary rather than forcing loaders back into later steps.

**Worker:** acquire the existing candidate Redis lock first. Job calls new `PermanentCandidateIntakeServiceInterface::preparePermanentCandidateSync(PermanentCandidateSyncData): PermanentCandidateExecutionData`. At entry this Service builds the complete execution DTO: current Candidate/CandidateJob/Job/Branch/address/answers, one CV/Agreement batch, question definitions needed by MM and any legacy PDF label fallback, and existing generated-form metadata by the immutable fingerprint. It may issue dependent reads within the builder, e.g. branch_id from loaded Job. MM category and legacy PDF category reads are batched together where needed; preserve the distinct category constants. PDF new labels remain frozen while MM uses current persisted answers/question data. A standalone PDF-only path loads only its required sources and preserves stored-PDF reuse without unnecessary question queries.

After the worker builder returns, validation checks ownership/candidate state from the DTO; already-Permanent exits without generation/MM/file validation. Otherwise pipeline validates the preloaded files/snapshot, reuses or generates PDF, and returns context with the File obtained from lookup/create. `syncPermanentCandidateFromContext(PermanentCandidateExecutionData)` builds its MM payload entirely in memory from this same DTO; it does not fetch Job/Branch/address/answers/questions itself. `completePermanentCandidateFromContext(PermanentCandidateExecutionData)` updates the preloaded Candidate without rereading. Context ID consistency must be checked in-memory so mismatched records cannot bypass ownership. Repository update saves the supplied model's dirty fields; no stale full-profile overwrite. Configuration/storage/external API access and required DB writes are distinct from DB reads.

Data discovered during processing is carried forward as an explicit typed result or a copied readonly context, e.g. withGeneratedForm(File); do not query again for the File returned by create. MM peopleNumber/contact-log number come from external responses and are passed directly to later steps. No required post-build DB SELECT has been identified in this traced flow. If implementation uncovers one, record its unavailable-before-processing input, reason and test in this plan before adding it; existing data is never refetched just for convenience. API-result-log/file/candidate/profile writes remain allowed, outside validation as appropriate.

Runtime contexts are local to one request/job attempt and never stored in a singleton Service property, cross-request cache or queue payload. A retry rebuilds them after acquiring the lock. A submitted ownership check cannot authorize later worker execution; deletion/reassignment/missing storage after submit still fails with existing errors. Context reuse does not create transaction-level isolation across external MM calls; current lock/TOCTOU limits remain and are documented.

Keep existing public generator `generatePermanentCandidateForm(PermanentCandidateSyncData): Model` as a standalone wrapper around the same private preparation/rendering helpers; it builds required data once at entry. Keep existing scalar MatchMaker sync and status/completion helpers as compatible wrappers for legacy Event/CV-only/TestCommand paths; each independent entry builds required data first and subsequent logic uses it. Do not invoke these ID-based entry wrappers inside the prepared worker path. MM context method accepts the already complete execution DTO and performs no hydration reads. Legacy no-snapshot branch/old serialization/routing/failure logs remain as §14. Do not move MM profile data to the frozen PDF snapshot.

### 16.3. Contracts, sources and file ownership

No new table/migration/index, endpoint or public request/response/error changes. Existing FormRequest still owns structural validation; pipelines own business validation. New public internal methods use explicit return/parameter types; all internal build/validate/process helpers private. Public constants cover any new fixed category/field identifiers; existing error/type/queue constants reused.

New runtime DTO files owned by this scope: `app/Dto/PermanentCandidateIntakeContextData.php`, `app/Dto/PermanentCandidateExecutionData.php`. The execution DTO includes the MM source data from the initial builder; a later MM data object, if helpful for formatting, is an in-memory projection only and does not require another loader/DTO file by default. Request/worker builders supply every member from actual caller/repository reads, not assumed mock-only keys. Existing four queued value DTOs remain immutable and serializable without Models. No extra candidate/question/file queries from lazy relationships after the builder.

Changed source files: Intake and MatchMaker Service contracts/implementations, snapshot Job, AnswerOption Repository contract/implementation for named pure-data batch lookup, necessary existing DTO helpers, affected tests, canonical living specs. Reuse existing QuestionRepository::getByCategories and FileRepository::allByIds/generic lookup. New single-record Repository methods if required return ?Model. Config/click/Agreement methods stay behaviorally unchanged; do not add empty Controllers/routes/migrations or refactor unrelated MM workflows.

MM question batching must preserve current getAnswerByCategory/getLabel/getLabels semantics, selection order, missing-answer errors and values. Only extract shared in-memory resolution from that affected helper where required by the Permanent payload call chain; other callers continue to query as before. Do not conflate PDF options-label rules with MM mapping rules.

### 16.4. Docs-first execution phases

**Phase 1 — docs only:** update `~/projects/crs-api-docs/docs/flows/permanent-intake.md` with planned/not-deployed Service build/validate/process flow, request vs attempt contexts, query reuse and fresh retry checks. Public endpoints remain config/Agreement/click/submit with the same request fields,202 pending examples and current 4xx/502 errors; list those as unchanged. Correct the already verified removed prominent-name description and plan008's historical constructor example. Dependencies: approved §16 design and current docs baseline; no implementation code before the gate. Acceptance: docs match these sources/rules; owned task-only diff, docs build/validation, commit and normal push main all PASS. Record paths/checks/commit SHA/push here. Failure blocks dependent code. Do not commit/push backend changes.

**Phase 2 — implement and verify:** first align §15 contracts, then typed runtime data/batch Repository boundary, Service pipeline/helper paths and compatible wrappers, Job orchestration, affected tests and living docs. Phase output is one complete reviewable implementation; no additional skeleton phase. Acceptance: public contracts preserved, no extra ownership/candidate/file read in the prepared worker path, immutable queued snapshots/old fingerprints preserved, no new read inside transaction/query loop, no fake success or MM calls on invalid contexts. Docs describing implemented business flow live under .business-spec; plans remain here.

### 16.5. Test audit and gates

Review existing Intake Unit/Feature, Form Feature, Job Unit, MatchMaker Permanent and legacy Event tests plus synchronous Command coverage. Update mocks for prepared-context Job calls; keep standalone wrapper coverage and do not delete tests to satisfy signatures.

Add meaningful tests for: actual submit data/metadata origins and unchanged errors/order/202; invalid ownership rejects before writes/enqueue/MM after initial DTO build; completed worker skips without MM/generation; ownership/candidate read once per attempt; one CV/Agreement batch shared with MM; generated File passed directly; one MM question batch with identical mapped values/categories; one answer-option batch; completion uses shared model; retry rebuilds fresh context; deleted ownership/file/storage after submit fails; forged context IDs rejected; context never serialized into the queued DTO; standalone generator/legacy Event/CV-only paths retain validation; old PHP-serialized Job and stored PDF identity remain compatible. In addition, instrument the build-to-processing boundary and assert zero subsequent SELECTs in all validation/PDF/MM/completion steps (DB writes/API-log writes still allowed), including no lazy relationship queries. Assert reads through strict Repository mocks and/or narrowly scoped Feature query logs rather than fragile total SQL counts. No Repository unit tests.

Run affected PHPUnit suites sequentially, then full `APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php ./vendor/bin/phpunit`; run diff check and self-check against §14–16. Current working-tree fatal means previous PASS is stale until rerun. No formatter, live MM request, worker restart/queue drain or deployment in this scope. Refresh deployed config/workers remains an operational prerequisite.

Approval gate: [x] user approves clarified §16 including §15 fixes/internal context methods/docs-first phase; [x] docs gate; [x] implementation/affected/full tests/self-check.


### §15–16 execution evidence (2026-10-09)

- Explicit user ok follows the clarification that ALL needed data is built first and passed to downstream processing. No implementation occurred before approval.
- Docs-first PASS: docs/flows/permanent-intake.md updated with planned/not-deployed build-once/context/retry/SELECT boundary and removed prominent-name description. npm run build and git diff --check PASS; task-only commit78cc432 pushed normally to origin/main before backend edits. No public schema/error/example change.
- Implementation uses two runtime contexts, one named AnswerOption batch (sets queried once, exact question/value pairs selected in-memory by Service), existing question/file batch methods and complete worker builder. MM context entry does no hydration query. Returned File and external IDs are passed onward. Queued DTO/legacy serialization/fingerprint unchanged.
- Existing independent config/Agreement/click guards are preserved; prepared worker avoids invoking scalar/status/generator/completion wrappers. Legacy scalar MM entry builds required records once before its pipeline. Standalone PDF-only generator preserves old stored-file reuse without question reads.
- Initial focused units PASS36/417; existing affected Feature/Welfare PASS108/6875. Added actual submit/worker SQL-boundary, fresh-attempt ownership/file, missing files, already-completed and forged-context regressions; combined affected/full gates pending. No live MM call/deployment/backend commit/push.

§15–16 final gates PASS (2026-10-09): final combined affected suites153 tests/7,368 assertions PASS; full process-local-cache PHPUnit647 tests/9,528 assertions PASS (03:18.314,139MB), log /private/tmp/gap691-build-once-full.log. SQL-boundary tests cover actual Service submit and actual worker PDF -> MM debug processing -> completion: zero SELECT after build; one ownership/candidate/job/branch/address/answers/questions read, one input-files batch plus one generated-form metadata lookup, exact answer-option pairs from one batch. Non-debug MM unit fixtures use strict mocks for registration and all three attachment APIs, including upload failures and prepared paths with no Repository read expectations. Legacy snapshot/CV-only serialization, old stored identity, raw timing/frozen labels, generic lookup and four-logo/Welfare regressions PASS. Full suite covers final code including the removed duplicate in-memory ownership rule in preparation and optional agreement context consistency.

Self-check PASS: Service-only business pipelines; pure batch Repository query and Service exact-pair selection; original submit scalar fingerprint preserved; no Model queued/cached on Service; complete runtime sources traced from real callers; no read in write transactions or query execution in loops; custom exceptions; private internal helpers; compatible standalone/legacy paths; public HTTP schemas/errors unchanged; no remaining old constructor/generator/lookup calls. canonical3 living files and plan008 example synchronized. Docs commit78cc43205b464f8009bbede1955cb76bd6cc18b1 pushed origin/main; docs repo clean; final git diff --check PASS. No formatter/migration/live MM/deployment/queue drain/backend commit/push. New DTO files must be included in the user's backend commit. Actual server worker/cache/MM delivery remains unverified operational state, not part of the code gate.

## 17. Amendment — Apply test placement policy and reduce duplicate GAP-691 coverage

Status: DONE — user approved §17–21; shared docs-first, implementation, affected/full tests and self-check PASS (2026-10-09).

### 17.1. Scope and contract assessment

Apply AGENTS.md Test Placement Policy: functional/integration coverage belongs in Feature tests; Unit tests only exercise Service business logic under tests/Unit/Services/. Reduce repeated coverage while preserving distinct business rules, failure paths and integration boundaries. Do not merely move mock-only Job unit tests to a Feature directory. Do not remove unrelated tests for other tasks or change production code to accommodate fewer tests.

API/docs assessment: N/A — no API contract/API docs change. Routes, request/response schemas, examples, errors, business flows and queue runtime behavior remain unchanged. No external docs edit/commit/push, migration, configuration change or deployment is required. Existing living specs remain the implemented-flow baseline.

### 17.2. Coverage mapping and owned files

| Existing coverage | Planned action and retained verification |
|---|---|
| tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php (19 expanded cases) | Remove this task's standalone Job unit suite after its unique coverage is incorporated into the real Feature flow below. Keep other tasks' Job tests outside this scope unchanged. |
| Typed dispatch, snapshot serialization, PDF -> MM -> completion order | Reuse existing actual HTTP-submit and worker Feature tests; extend the worker case with new-job queue/retry settings and serialization assertions. Retain both public HTTP response coverage and the SQL boundary integration test. |
| Already-completed worker | Extend the existing completed-worker Feature case to execute Job.handle and assert no MM/generation/completion side effects; retain the loaded-context assertions. |
| Legacy snapshot identity, routing and retry deadline | Superseded by §20: remove the old serialized-payload case; assert new typed Job serialization, retry settings and unchanged stored-PDF reuse through existing Feature cases. |
| Legacy CV-only dispatch | Superseded by §20: do not add a legacy serialized-payload Feature case. Current typed/scalar entry behavior is outside the serialization-removal scope. |
| Lock contention | Add one Feature case through Job.handle asserting the existing release delay, no processing and unchanged exception budget. |
| Retry/failure/lock release/log identifiers | Add one Feature data-provider test with three representative failures: non-retryable generation, transient MM failure, non-retryable MM rejection. Assert expected escape/fail policy, no permanent completion, lock release and structured identifiers including effective generated-file ID. Existing real Service Feature cases retain render/storage/metadata cleanup. Extend the ownership-removed Feature through Job.handle to retain API/state failure handling. |
| Literal Supervisor source-string assertions and trivial status mapping | Remove redundant assertions from the deleted Job suite. Runtime settings are checked with the submitted Job/config; actual Service mapping assertions remain. No Supervisor/runtime config edits. |
| testCertificateUsesCompleteQueuedNameAndRetainsInformation | Merge full queued middle-name, certificate styling, retained agreement content and no-input assertions into the comprehensive payload/PDF Feature case; then remove the duplicate test. Preserve missing-middle-name fallback in the existing fallback case and preserve the optional local PDF preview hook if still needed. |
| invalidQuestionOptionsProvider (10 executions) | Keep six representative cases: missing question, invalid data type, invalid options type, unknown key, whitespace label and non-string numeric label. Remove missing-options, null-label, empty-label and array-label variants that repeat the same fallback guards. Assert raw values and persisted answer associations as before. |
| Service business rules | Retain PermanentCandidateIntakeServiceTest and MatchMakerPermanentSyncTest under tests/Unit/Services/, including actual payload mapping, attachment order, errors and strict no-read prepared-context mocks. Do not trim unrelated Agreement rules. |
| Other distinct integration boundaries | Retain exact answer-option batch matching, zero SELECT after build, fresh retry ownership/files, missing storage, frozen DB labels, generic lookup, long PDF content, four-logo/Welfare regressions, Command flow and manual upload coverage. |

File ownership: delete only tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php; modify tests/Feature/Api/Candidate/PermanentCandidateFormTest.php and, only if needed for the actual dispatch assertions, tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php. Service test files are reviewed and retained unless a directly required expectation change is identified. Preserve unrelated staged/unstaged edits and existing formatting. No new source-layer files or Services/DTOs/Repositories are required.

Data-origin gate: new assertions must start from the real HTTP submit/queued DTO or verified legacy payload and actual Service builders. Use fake storage/queue and mocked external MM boundaries where necessary; never make live MM calls. Serialize Jobs before attaching a mock queue handle. Failure tests must demonstrate Job orchestration, not only assert a mocked Service result. Run tests sequentially to avoid shared fake-storage collisions.

### 17.3. Acceptance and verification

Baseline: last full suite 647 tests / 9,528 assertions; affected suites 153 tests / 7,368 assertions. After §20 removes the old-payload Feature case and cancels the proposed legacy CV-only case, estimated reduction is approximately 21 expanded executions (target about 626 full / 132 affected), subject to PHPUnit discovery and preserving required coverage. Counts are evidence, not a hard quota; do not discard a distinct failure condition to hit a number.

Acceptance: GAP-691 has no standalone non-Service unit suite; retained Service unit tests exercise actual Service business logic; the coverage mapping above is satisfied; no runtime changes, skipped tests or weakened business assertions. Audit deletion against each former Job test before considering the amendment complete.

Execution: after approval, consolidate Feature assertions/cases first, then remove the redundant tests and Job unit file; run affected Form/Intake Feature, Intake/MM Service and existing Welfare regression suites with APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php. Run the full ./vendor/bin/phpunit suite with the same process-only cache override, git diff --check and self-check against §17. Record actual counts, reductions, logs and coverage mapping results here. No formatter or backend commit/push.

Approval gate: [x] user approves §17; [x] mapped Feature coverage established; [x] redundant cases/Job units removed; [x] affected/full tests and self-check PASS.

## 18. Amendment — Typed FormRequest input at the submit Service boundary

Status: DONE — user approved §17–21; shared docs-first, implementation, affected/full tests and self-check PASS (2026-10-09).

### 18.1. Verified scope and intended flow

Current Controller.submit injects PermanentCandidateIntakeRequest, then calls Service.submit(authenticated Candidate, request.validated()). Both Service contract/implementation accept array data; private buildIntakeData also accepts that array. Laravel resolves the FormRequest and executes authorization/validation before the Controller method; calling validated() is not what initiates HTTP validation. Request derives from the project's JsonRequest/FormRequest chain; validation failure remains the existing HTTP400 response.

Change the public internal signature to submit(Candidate $candidate, PermanentCandidateIntakeRequest $request): array in both contract and implementation. Controller passes the same resolved $request directly. Private buildIntakeData accepts that concrete Request and accesses its documented named properties to read IDs, files and submitted fields; Service remains the owner of the initial DTO build and all DB hydration. Pipeline, persistence and worker processing continue to consume existing typed DTOs. Do not cache, queue or pass the Request beyond the initial builder, and do not replace the array signature with a generic Request/object lacking the form's declared fields.

Scope is Permanent intake submit, the method currently discussed and the Request the user annotated. generateWorkFinderAgreement has a separate Request and existing Command/Service callers; its array contract is unchanged in this amendment. No unrelated Service/Repository refactor.

### 18.2. PHPDoc and value semantics

Preserve the user's annotations while making the modified block usable by IDE/PHPDoc tooling: standard lowercase @property tags, all rule-backed properties including currently missing contact_times, explicit nested array shapes for address and files, and list<string> for contact_dates/contact_times. Address shape contains building/street/town_city/county/postcode strings; each file entry has file_id and type. Nullable fields retain optional/null behavior. Integer validation accepts numeric strings without automatic casting; document job_id/file_id accordingly and retain the builder's explicit casts. The accepted agreement flag can arrive as a bool/string/int; preserve current accepted-rule and DTO normalization semantics rather than claim PHPDoc performs runtime conversion.

The Service input and business helpers must no longer hide submitted values behind an untyped array $data. If the affected label resolver still requires generic payload data, change only that shared helper to explicit transport/distance/source string parameters supplied from the Request or existing snapshot DTO, retaining its identical label fallback rules for both new and legacy paths.

Arrays remain legitimate for lists, explicitly documented nested shapes and the existing serialization adapter; removing them globally is not requested. Preserve original validated snapshot fingerprint semantics, optional-key omission, scalar representation, nested key filtering and ordering. If needed, use the FormRequest's validated projection solely inside the snapshot serialization/fingerprint adapter; do not make that array the Service contract or pipeline payload and do not substitute request.all() as the snapshot. This prevents unruled fields from changing the stored identity or leaking into queued data. Continue to use named Request properties for business inputs and typed context/snapshot fields thereafter. Existing serialized Jobs/fromArray legacy adapters and stored-file fingerprints remain compatible.

### 18.3. Data origins, ownership and contract assessment

Verified callers: actual Controller.submit; direct Service test invocation in tests/Unit/Services/PermanentCandidateIntakeServiceTest.php; direct submit call in testSubmitBuildsOnceBeforeValidationAndWritesAndBatchesExactAnswerOptions in tests/Feature/Api/Candidate/PermanentCandidateFormTest.php. Audit controller mock expectations in PermanentCandidateIntakeTest for array matching and adapt to the actual resolved Request. Worker, TestCommand snapshot dispatch and legacy listener do not call submit with this input contract and retain their DTO/scalar boundaries.

Owned source files: app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php; app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php; app/Contracts/Services/PermanentCandidateIntakeServiceInterface.php; app/Services/PermanentCandidateIntakeService.php. Owned tests: existing Intake Feature, Form Feature and Intake Service unit suites. Update only affected signatures, imports, property access/adapter and expectations; preserve all other staged/unstaged work and formatting. No new classes, Repository changes, binding changes, schema, migration or constants required.

API/docs assessment: N/A — no public API contract/API docs change. Existing POST /api/candidate/me/permanent-intake rules, request schema, examples, 202 pending success and 400/business/502 errors stay unchanged. External flow documentation already says validated input is used to build the DTO and does not specify an array Service parameter, so remains accurate. No external docs synchronization/push required. After implementation, update only the affected internal call-chain description under .business-spec/backend-business-flow-spec.md to record the concrete FormRequest boundary and Service-built DTO. The API inventory/database relationship baseline remains accurate.

### 18.4. Test audit, execution and acceptance

Update existing direct Service tests to construct a real PermanentCandidateIntakeRequest with the verified fixture payload rather than mock magic properties. They remain Service business unit tests; no standalone Request/DTO unit tests. Unit construction alone is not evidence of HTTP validation: retain actual HTTP Feature validation cases and extend existing cases to assert the Controller passes the concrete resolved Request. Invalid input must reject before Service is called. Extra unruled fields must not enter queued snapshot identity/data; cover this through an existing real submit Feature where possible, avoiding duplicate happy-path tests.

Retain existing build-once query-boundary tests, persisted answer associations, optional/null/missing fields, frozen labels/raw click metadata, queued scalar-only snapshot, legacy serialized Job/storage identity and generation/MM completion cases. Add assertions to existing cases rather than proliferating methods when behavior can be covered clearly. §17's separate consolidation design still applies once approved; this amendment does not grant approval to delete its tests.

After approval: align Request PHPDoc and contract/implementation/builder/Controller call chain; update affected Service and Feature fixtures/expectations and the living internal-flow description; run affected suites sequentially, then full APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php ./vendor/bin/phpunit, diff check and self-check. No formatter, migration, live MM call, queue drain, deployment or backend commit/push. Record actual evidence here; previous 647-test PASS predates this amendment and cannot be claimed for changed code until rerun.

Acceptance: Controller passes typed Request; Service/builder have concrete Request signatures and documented property access; after the initial build, logic uses DTOs with no extra SELECT; normal FormRequest validation and all public outcomes are unchanged; unknown inputs are excluded from the serialization projection; Request never enters queued data; legacy fingerprints/storage reuse still pass; affected/full suites pass.

Approval gate: [x] user approves §18; [x] signature/property/data-origin audit PASS; [x] affected/full tests and self-check PASS.

## 19. Amendment — Remove unused Permanent submit Event/Listener

Status: DONE — user approved §17–21; shared docs-first, implementation, affected/full tests and self-check PASS (2026-10-09).

### 19.1. Source audit and removal boundary

Actual submit dispatches SyncPermanentCandidateToMatchMakerJob directly via Bus::dispatch after the local transaction. Worker uses preparePermanentCandidateSync -> syncPermanentCandidateFromContext -> completePermanentCandidateFromContext. TestCommand uses Bus::dispatchSync. Neither path emits PermanentCandidateSubmittedEvent.

Repository-wide PHP search across app/routes/tests finds the Event only in its definition, the Listener type/import, EventRegister registration/imports and obsolete Event::fake/assertNotDispatched statements in Intake Service/Feature tests. No production dispatcher/caller is present in the inspected source. Listener calls the scalar MM entry directly and is not queued. This is source evidence; it does not claim that untracked external custom callers exist or are migrated.

Delete app/Events/Definitions/PermanentCandidateSubmittedEvent.php and app/Events/Listeners/SyncPermanentCandidateToMatchMakerListener.php. In app/Events/EventRegister.php remove only their two imports and Permanent Event::listen registration. Preserve Appointment, EscalatedIssue and OverallApprove registrations and EventServiceProvider boot unchanged. Do not alter the functioning direct Job dispatch, DTOs, locks, retry policy, shared queue, workers or other events.

In tests/Unit/Services/PermanentCandidateIntakeServiceTest.php and tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php remove only the obsolete Event import, Event::fake calls and assertNotDispatched calls, plus the Event facade import if it becomes unused. Preserve each existing Agreement/business test and its meaningful assertions. Retain or extend actual Bus/Queue assertions where needed to verify Agreement does not enqueue Permanent processing and submit enqueues exactly one typed Job. No new Event/Listener unit tests and no skipped cases. Coordinate edits with the same files owned by §17–18; execute sequentially.

### 19.2. Documentation impact and drift

Public API contract remains unchanged: existing endpoints, FormRequest schemas, 202 pending response, business/validation/502 enqueue errors and background completion semantics stay intact. API documentation DOES require synchronization because event registration and operational call-chain documentation refer to the removed classes. Therefore this amendment requires a docs-first phase under AGENTS.md, even though no public API fields change.

Confirmed CODE/documentation deviation: ~/projects/crs-api-docs/docs/operations/queue-and-events.md still describes Permanent submit dispatching the Event synchronously and waiting for MM before completing; actual source dispatches an asynchronous Job. .business-spec/crs-matchmaker-crm-current-state.md §7 contains the same outdated sequence and CV-only/error-response description. The current canonical baseline's recent §16 amendment and external permanent-intake flow page describe the newer queued flow. Correct these affected references rather than preserving contradictory current-flow claims. Earlier task plans remain historical; do not rewrite old plans, but this amendment explicitly overrides their Event retention requirement.

### 19.3. Required execution phases and ownership

**Phase 1 — docs only, before dependent implementation:** owned external docs files are ~/projects/crs-api-docs/docs/operations/queue-and-events.md and docs/flows/permanent-intake.md. Remove the Permanent row from the intended post-change registered-event table; replace its obsolete synchronous timing paragraph with direct Redis/default Job dispatch after local commit, HTTP202 pending, PDF -> MM -> completion and background error/retry boundaries. In the Permanent flow page record the planned Event/Listener removal and direct Job boundary. Mark the amendment planned/not yet deployed using the repository's existing convention; retain other event/Welfare content. No endpoint/schema/example/error changes required; cross-links must remain valid. Dependencies: approved §19 and current completed §16 flow; incorporate the typed Request description from §18 only if that amendment is also approved. Validate docs with the existing build/check command and git diff --check, stage only owned task changes, commit and push normally to remote main. Record exact paths/diff, validation, commit SHA and successful push here. Phase cannot PASS without all three; dependent backend implementation must wait. Preserve unrelated docs work and integrate remote changes safely without force push.

**Phase 2 — backend removal and verification:** after the docs gate, delete the two obsolete files, remove their registration/imports, adjust affected test assertions and synchronize living documentation. Owned living files: .business-spec/backend-business-flow-spec.md (current-flow notes/source references/Event-retention text), backend-api-route-inventory.md (legacy Event reference), and crs-matchmaker-crm-current-state.md §7 (actual async sequence/diagram/source links). Inspect backend-database-relationship.md; record N/A if no obsolete Event relationship description exists. Preserve all unrelated current-flow sections. No new living-spec file is needed. Source/test ownership is the exact files in §19.1; no Controller/Service/Repository implementation change is required by removal itself.

### 19.4. Acceptance, tests and gates

Before removal, rescan all application/test registrations and dispatch callers; if a new real caller is found, record its purpose and update the concrete migration design before removing its class. After removal, no reference to either deleted class remains in runtime code/tests or current-flow docs. Historical plans may retain past references with this superseding amendment. EventRegister and EventServiceProvider still boot successfully with the other existing listeners.

Reuse real HTTP submit/worker Feature coverage to prove one Job is enqueued after persistence, no MM call occurs during submit, and PDF/MM/completion still work in the worker. Retain Agreement no-side-effect assertions through storage/profile/queue behavior. Audit affected tests together with §17–18 if approved, run affected suites sequentially and full APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php ./vendor/bin/phpunit, then git diff --check and self-check. Record counts, logs and reference-scan evidence. No formatter, migration, live MM call, deployment, worker restart, queue clear/drain or backend commit/push.

Approval gate: [x] user approves §19; [x] docs validation/commit/push PASS; [x] unused Event/Listener and registration removed; [x] current-flow docs aligned; [x] affected/full suites and self-check PASS.

## 20. Amendment — New deployment needs no old Job payload conversion

Status: DONE — user approved §17–21; shared docs-first, implementation, affected/full tests and self-check PASS (2026-10-09).

### 20.1. Removal and retained normal behavior

Remove the custom __unserialize(array $values) override in app/Jobs/SyncPermanentCandidateToMatchMakerJob.php and its SerializesModels::__unserialize alias block. Use the standard Dispatchable/InteractsWithQueue/Queueable/SerializesModels traits without the alias. Laravel's own deserialization remains necessary and continues to restore new typed Jobs; do not remove SerializesModels or normal queue serialization.

Remove PermanentCandidateSyncData::fromLegacyJob(array $values) from app/Dto/PermanentCandidateSyncData.php; the custom Job override is its only runtime caller. DTO constructor and current typed payload remain unchanged. SnapshotData::fromArray is still used by current submit/TestCommand/fixtures and is not removed. No change to build-once contexts, shared Redis/default dispatch, lock/retry policies, deterministic snapshot identity or PDF reuse.

Remove testOldSerializedJobReusesOriginalSnapshotFileIdentityWithoutDbLabelsRead from PermanentCandidateFormTest. Delete old-payload unit cases/helpers with the Job unit file already scheduled for removal in §17; do not recreate them as Feature tests. Retain new typed Job serialize/unserialize round-trip, queue/timeout/retry-deadline preservation, actual HTTP submit/worker completion and metadata/storage reuse checks in existing Feature cases. No dedicated non-Service unit suite is added.

Scope is old serialized-payload conversion and its coverage. This does not by itself remove optional snapshot/scalar entry behavior, standalone PDF generator, DB label fallback or deprecated queue configuration aliases. Those are independent contracts and remain unchanged unless separately scoped; never clear queues or failed_jobs as part of this amendment.

### 20.2. Documentation gate and verification

Public request/response/schema/error contracts remain unchanged. Operational docs DO change: external docs/flows/permanent-intake.md currently promises old-payload normalization, routing preservation and old backlog draining. Fold this amendment into §19's docs-first Phase 1: record new deployment/no old-payload migration requirement, remove custom-deserialization compatibility claims and describe standard Laravel restoration of typed Jobs. Any retained deprecated queue alias should be described as configuration compatibility only, not a required active old-backlog workflow. Mark the planned change not yet deployed, build/validate, task-only commit and normal push main before implementing §20. Reuse that phase rather than create duplicate commits/phases unnecessarily. Record affected files, checks and commit SHA in the execution evidence.

In Phase 2 update current-flow references under .business-spec/backend-business-flow-spec.md and inspect backend-api-route-inventory.md/backend-database-relationship.md for compatibility claims; update only affected current statements. Earlier execution records remain historical and are superseded by this amendment. Scan runtime code/tests for fromLegacyJob/restoreSerializedProperties and remove all obsolete references. Run affected suites and full PHPUnit with the documented process-local cache override, diff check and self-check together with other approved amendments. Actual test counts must be recorded; prior PASS is historical. No formatter, migration, live MM call, deployment or backend commit/push.

Approval gate: [x] user approves §20 implementation; [x] shared docs-first gate PASS; [x] custom override/adapter and obsolete tests removed; [x] new typed serialization and affected/full suites PASS.

## 21. Amendment — Consolidate worker validation and restore missing MM prerequisites

Status: DONE — user approved §17–21; shared docs-first, implementation, affected/full tests and self-check PASS (2026-10-09).

### 21.1. Verified duplication and current deviation

Job.handle contains orchestration and exception handling, not a DTO shape-validation step. preparePermanentCandidateSync builds a complete execution context, then validates candidate-job ownership, candidate identity/status and CV/Agreement IDs, owner/type/job/storage/snapshot. MM.validatePermanentSyncData repeats CV/Agreement ID/owner/type/job checks on the same loaded records. completePermanentCandidateFromContext repeats candidate-job/candidate identity checks before updating the same Candidate. These repeated checks are in-memory, not extra DB SELECTs; the goal is a clearer flow and one rule owner, not a claimed SQL performance improvement.

CODE deviation against §16's current-flow safety contract: the current MM validator checks CV/Agreement/form and branch, but no longer checks missing/mismatched Candidate/Job/candidate-job/address prerequisites. It can dereference a missing Job while checking branch or pass a nullable Candidate/Address into typed payload methods. Restore custom domain errors and explicit identity consistency; deleting the validator wholesale would leave this defect intact. Existing forged-context Feature expects MESSAGE_PERMANENT_RECORDS_MISSING and must be reviewed against the actual narrowed validator, not assumed to pass.

### 21.2. Validation ownership and processing boundaries

Prepared worker flow remains lock -> Service build full DTO -> ordered business validation -> PDF reuse/generation -> MM-specific prerequisites/processing -> completion. Intake Service owns the initial common validation for this flow: candidate-job ownership, candidate existence/identity/status, snapshot/job consistency and CV/Agreement ownership/type/job/storage. Run it once per attempt on the loaded context. Completed candidate still exits before file/PDF/MM processing. Submit validation is a separate execution and cannot substitute for worker validation; retry always rebuilds and checks fresh records.

For the prepared-context MM entry, remove repeated CV/Agreement business checks already established by preparation. Retain only MM-specific preconditions and context association checks needed at that boundary: Job exists and matches input.jobId; required Candidate/Address and their associations are valid; Branch matches that Job and has a legal entity; generated/reused form belongs to the candidate/job and has the correct type/ID where specified. Check nullable sources before dereferencing them and reject mismatched input/context before MM calls or local completion. Candidate identity/ownership rules should not be rerun as a full validator merely because another processing method is entered; place each exact rule at its owning boundary, while preserving the minimum explicit preconditions for this public internal entry.

The form is obtained during processing and must be checked after it becomes available; this is distinct from repeating validation of preloaded CV/Agreement. Do not add new DB/storage reads to confirm unchanged records already checked earlier. Continue carrying the File returned by lookup/create through withGeneratedForm.

completePermanentCandidateFromContext is the internal completion step for the prepared execution. Remove repeated ownership/identity validation from this path; update the supplied, already checked Candidate and retain the required update-result check/custom completion exception. Keep standalone ID-based completion/status wrappers independently guarded. Document prepared-context preconditions in the contracts; do not let unprepared contexts enter completion through a new public caller.

Standalone scalar syncPermanentCandidate remains supported independently of Event removal/old Job deserialization removal. It builds its own context and must retain complete validation for that distinct entry, including missing Candidate/Job/candidate-job/address, CV and optional Agreement/form. Split standalone validation from MM-specific prepared processing rather than introducing a public skipValidation boolean, caching a validated Service state or copying the whole prepared validator. Reuse private MM helpers for rules shared by its own entries. No Service-to-Service injection, DB query in Utility/DTO, business validator hidden in Repository, new Model flags or unrelated workflow refactor. Standalone PDF-only generator retains its own required validation and error semantics.

### 21.3. Owned files, docs gate and error contracts

Owned source files: app/Services/PermanentCandidateIntakeService.php; app/Services/MatchMakerService.php; their existing Service contracts for prepared-entry PHPDoc if needed. Job changes only if needed to maintain the approved orchestration boundary; no new validation layer/file, DTO class or Repository query is required by this amendment. Preserve unrelated working changes.

Public API routes, request/response schemas and synchronous validation/ownership error priority remain unchanged. Restore existing MM state errors using defined MESSAGE_PERMANENT_RECORDS_MISSING and existing file/entity/completion constants; add a named Service constant only if a distinct address error has no existing constant. Use PermanentCandidateSyncStateException or the existing Candidate API error at its established boundary, never a generic PHP exception. Transient/non-retryable Job handling, failed logs, no completion after failure and queue behavior stay unchanged.

Operational documentation changes: fold the validation ownership description into §19–20's shared docs-first Phase 1 in ~/projects/crs-api-docs/docs/flows/permanent-intake.md. State which checks run during preparation, which MM-specific checks happen after generated-file handoff, and how standalone entries remain independently guarded. No public endpoint/example/schema change. Mark planned/not deployed; docs validation, task-only commit and normal push main must PASS before dependent implementation. Update corresponding current-flow details under the three canonical .business-spec files after implementation where affected; do not rewrite historical evidence or claim a new SELECT dependency.

### 21.4. Test impact and acceptance

Review Form/Intake Feature, Intake Service unit, MM Permanent Service unit and §17's consolidated worker lock/failure coverage. Adapt existing mocked prepared-entry expectations to the new boundary; do not add standalone Job/DTO/Repository unit tests or weaken tests simply to remove a guard. Retain real worker zero-SELECT-after-build checks, storage cleanup, fresh-attempt ownership/file rejection, completed-worker skip, actual mapped MM fields/upload ordering, update failure and scalar/CV-only optional-file behavior.

Cover missing/mismatched Candidate, Job, candidate-job and Address through meaningful existing Feature/Service cases or a compact data provider for independent MM entry. Assert custom state error, no external registration/upload/completion and no subsequent SELECT. Update forged-context Feature to assert the intended existing records-missing error at the correct MM precondition. Test preparation -> returned context -> generated File -> MM -> completion using actual Service builders; mock-only DTO fixtures cannot prove that the real caller supplies checked records.

Acceptance: initial common validation has one owner per worker attempt; MM does not recheck CV/Agreement rules already established by preparation; completion does not repeat ownership lookup/checks on the same context; independently callable entries remain guarded; missing sources/forged IDs fail with custom errors before external effects; no new read after DTO build; retry rebuilds current state; docs match the implemented boundaries. Run affected suites sequentially and full PHPUnit with the established process-local config-cache override, diff check and self-check, recording evidence with other approved amendments. Estimated test totals remain provisional after restoring meaningful missing-state coverage. No formatter, migration, live MM call, deployment, queue clear/drain or backend commit/push.

Approval gate: [x] user approves §21; [x] shared docs-first gate PASS; [x] validation ownership and missing-source guards implemented; [x] affected/full tests and self-check PASS.

## §17–21 execution record (2026-10-09)

User explicitly approved all newly added amendments with "ok xử lý các phần vừa thêm". Status: IMPLEMENTING. Shared docs-first gate starts before backend code changes. Backend/database/type/repository applicability checked: no migration or new runtime class/repository change required. Preserve unrelated work; no backend commit/push.

Shared docs-first gate PASS: docs/operations/queue-and-events.md and docs/flows/permanent-intake.md updated with planned/not-deployed §18–21 boundaries. npm run build and git diff --check PASS; task-only commit aa119eb1ead3856705104dbc030ee58b2b9e7b76 pushed normally to origin/main before backend code changes. Docs build log: /private/tmp/gap691-17-21-docs-build.log.

Implementation source trace found a Request property collision: Symfony already defines public files as FileBag. JSON files is therefore read through input('files') with its explicit list shape; PHPDoc documents that distinction rather than falsely overriding the upload property. Other named submitted values use Request properties; validated() is confined to snapshot serialization/identity. No public schema change.

Affected gate PASS before final unknown-field identity assertion: 138 tests / 7,353 assertions, /private/tmp/gap691-17-21-affected-final.log. Form consolidated Feature gate also PASS39/386 before the final completion variant. Final full suite running against all latest changes. Completion failure fixture corrected to null (Repository update contract is ?Base, not bool); production write-result handling unchanged. Coverage expanded through existing providers for independent MM missing records and completion write failure instead of adding separate test methods.

Initial full run completed632 tests with one failure in the newly added fingerprint assertion: test used pre-middleware payload while XssProtection removes HTML before FormRequest validation. Corrected the test to use the real kernel-bound Request input (Kernel::sendRequestThroughRouter binds it before middleware; Service receives the resulting resolved FormRequest). No production behavior or expected snapshot identity was weakened. Rerun affected/full suites required for final PASS.

Final affected gate PASS against latest code/tests: 138 tests / 7,354 assertions (00:50.162,114.50MB), /private/tmp/gap691-17-21-affected-final.log. Unknown top-level/nested address/file fields are excluded from the actual post-middleware validated snapshot identity; typed Request fixtures and real HTTP path agree. No production code changes after this gate. Final full rerun started, /private/tmp/gap691-17-21-full-final.log.


### §17–21 final evidence and self-check (2026-10-09)

- Shared docs-first PASS: two owned docs updated and validated, task-only aa119eb1ead3856705104dbc030ee58b2b9e7b76 pushed origin/main before backend edits; docs repo remains clean. No public schema/example/error change. Updated living current-flow specs and MM sequence under .business-spec.
- Implementation PASS: submit contract/implementation/Controller and all direct test callers use PermanentCandidateIntakeRequest. Named input properties and explicit JSON files shape feed initial DTO build; validated projection is used only for original snapshot serialization/identity. PHPDoc covers contact_times and nullable/nested fields; inherited FileBag collision is documented and handled via input('files').
- Event/Listener/registration and custom Job __unserialize/fromLegacyJob removed. Runtime/test reference scan has no obsolete callers/imports. Standard SerializesModels restores typed DTO Jobs; remaining three Event registrations preserved. Deprecated queue aliases and current typed CV-only entry remain unchanged as explicitly scoped.
- Validation PASS: prepared worker checks common CV/Agreement/candidate-job ownership once during preparation; independent scalar MM has its own private entry guard; MM-specific records/address/branch/form checks use the loaded context with custom exceptions. Completion only checks the update result on the checked Candidate, with a tested null update result failing safely. Query-boundary regressions still prove zero post-build SELECTs. Per-attempt fresh ownership/storage validation remains as approved §16; MM uses current persisted data at attempt time while PDF is frozen from submit.
- Coverage audit PASS: removed19 expanded Job unit cases after incorporating unique orchestration coverage into Feature tests; removed duplicate certificate, old serialized-payload case and four repeated fallback variants. Existing providers/cases now cover lock contention, render/transient/rejected/completion failures, failed identifiers, completed-worker skip, missing file/state handling, typed serialization and independent CV-only dispatch. The forged-context case/provider covers prepared input mismatch and independently built MM missing Candidate/Job/candidate-job/address; no processing/read/write after builder completion. Retained Service unit payload/attachment/cleanup guards. Required new coverage adds back meaningful variants, so net reduction is15 expanded tests rather than the provisional21 target.
- Latest affected suites PASS138 tests /7,354 assertions, log /private/tmp/gap691-17-21-affected-final.log. Full suite PASS632 tests /9,514 assertions (02:35.610,137MB), log /private/tmp/gap691-17-21-full-final.log. Baseline647/9,528 ->632/9,514; affected153/7,368 ->138/7,354. Counts are final for this tree; no skips introduced.
- Self-check PASS: minimal incremental diff reviewed against pre-amendment backup; interfaces/callers aligned; actual HTTP/Service/worker data sources traced; private helpers/custom exceptions; pure Repository boundaries; no new DB read in transaction/loop or after build; Model/Request not queued; no unrelated runtime method/config change. Final git diff --check PASS. No formatter/migration/live MM/deployment/worker restart/queue clear/backend commit/push. Earlier full-run fingerprint fixture failure is retained above as corrected evidence, not a production regression.

Supersession: §17 replaces this task's standalone Job unit suite with Feature coverage; §18 replaces the submit array boundary; §19 removes previously retained Permanent Event/Listener; §20 removes old serialized-payload compatibility for this new deployment; §21 removes redundant prepared-flow file/ownership checks while retaining independent-entry and MM-specific guards. This completion does not approve freezing MM profile data at submit; that would be a separate business/data-origin change requiring its own design/docs gate.

## 22. Pending scope moved to a separate plan

Phần chưa thực thi “Reuse Service-built data in the queue; load only missing worker data” đã chuyển sang [009 — Reuse Service data in Permanent sync Job](009-reuse-service-data-in-permanent-sync-job.md) theo yêu cầu user (2026-10-09). Plan mới là nguồn quyết định thiết kế và checklist cho phạm vi này, vẫn DRAFT/chờ duyệt. §1–21 và execution evidence giữ nguyên để lưu lịch sử đã triển khai; các checkbox/failure cũ là bằng chứng tại thời điểm chạy, không tự động tạo scope thực thi mới.
