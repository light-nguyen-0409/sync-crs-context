# SPEC: GAP-691 Phase 5 — Tích hợp, regression và living specs

> **Trạng thái**: Phase 5 lịch sử `DONE`; follow-up §11 local evidence giữ nguyên; follow-up §12 `DONE` — MM guard variants, affected và full mặc định PASS trên snapshot hiện tại
> **Ngày tạo**: 2026-09-29
> **Author**: Codex

## 1. Tổng quan

Phase 5 xác nhận tích hợp Phase 1–4 trong working tree, rà soát các tiêu chí GAP-691 và đồng bộ ba tài liệu `.business-spec/` với hành vi đã kiểm chứng từ source. Sửa lỗi tích hợp hoặc bổ sung test chỉ khi audit phát hiện thiếu sót; mọi thay đổi runtime ngoài kế hoạch sẽ được ghi thành phần cần duyệt trước khi sửa.

**Yêu cầu gốc**: Triển khai Phase 5 của [GAP-691 implementation plan](GAP-691-implementation-plan.md) sau khi Phase 4 hoàn tất và không có vấn đề.

## 2. Database Design

Không dự kiến thay đổi schema. Xác nhận migration và seeder thuộc GAP-691 qua test suite; không chạy seeder destructive ngoài phạm vi và không kết luận trạng thái production DB từ test.

## 3. API / Business Contract

Không dự kiến thay đổi API. Đối chiếu implementation Phase 1–4 với contract hiện tại: marker Permanent/status PERM, direct MatchMaker sync và fallback queue, self-service intake/file endpoints, staff visibility filter. Nếu phát hiện khác biệt cần runtime code/API đổi, dừng thay đổi đó và lập plan cập nhật để user review.

## 4. Business Logic và kiểm chứng

1. Rà soát test coverage và code paths hiện có cho schema/defaults, branch/entity agreement URL, intake/click/submit/CV, MatchMaker direct/fallback, và lọc staff Candidate.
2. Rà soát toàn bộ PHPUnit sau Phase 4; hiện trạng lượt xác nhận cuối: `508 tests, 2,195 assertions` passed.
3. Truy vết status `PERM` để xác nhận không bị xử lý như `LIVE`; truy vết failed queue job/failure alert từ code. Chỉ ghi các khả năng được chứng minh từ source; queue config không chứng minh worker production đang chạy.
4. Cập nhật đúng ba canonical business specs: flow, route inventory và database relationship; ghi ngày đối chiếu source, route/API flow mới, quan hệ/cột đã thêm, và các deviation theo nhóm `CODE`, `DATA`, `CONFIG`, `EXTERNAL`, `INFRASTRUCTURE`. Mọi trạng thái runtime/production chưa có bằng chứng phải ghi `UNVERIFIED`.
5. Cập nhật master GAP-691 plan với phase completion/evidence và giữ các deferred decisions. Giữ task plan Phase 4 như lịch sử triển khai, không xóa lịch sử đã được review.

### Giới hạn audit

- Test DB chỉ xác nhận hành vi test; không suy diễn migration/seeder đã chạy trên production.
- Source config về queue/alert không xác nhận worker, queue connection, alert delivery hay production state.
- Không dọn/reset/stage các thay đổi đã có trong working tree. Các diff không thuộc GAP-691 phải được bảo toàn; nếu không thể xác định baseline sạch, ghi rõ giới hạn thay vì tuyên bố diff chỉ chứa GAP-691.

## 5. Data Origin & Call Chain

| Nội dung được ghi nhận | Nguồn xác minh |
|---|---|
| API route/middleware | Laravel routes/runtime route collection và controller call chain |
| Business flow/status/side effects | Controller → Request → Service → Repository/job/external adapter và tests liên quan |
| Quan hệ/cột | Migrations + Eloquent models/relations; production data/schema là `UNVERIFIED` |
| Queue/alert vận hành | Job, queue config, failure handling, deployment/worker evidence nếu có; thiếu deployment evidence thì ghi `UNVERIFIED` |

## 6. Constants & Enums

Không dự kiến thêm constants/enums trong Phase 5.

## 7. Files cần sửa

| File | Mục đích |
|---|---|
| `.business-spec/backend-business-flow-spec.md` | Ghi flow GAP-691 mới và evidence/deviations |
| `.business-spec/backend-api-route-inventory.md` | Cập nhật inventory cho intake endpoints và các thay đổi route thực tế |
| `.business-spec/backend-database-relationship.md` | Ghi cột/quan hệ Phase 1–3 theo migration/model |
| `.specs/GAP-691/GAP-691-implementation-plan.md` | Đánh dấu Phase 1–5/evidence/deferred items chính xác |
| Test files liên quan | Chỉ cập nhật/thêm khi audit chứng minh có gap hoặc contract mismatch |

Không dự kiến sửa runtime code. Nếu audit phát hiện lỗi, chuẩn bị plan sửa cụ thể và chờ duyệt theo workspace gate trước khi sửa code.

## 8. Test Cases / Acceptance

- [x] Tất cả tiêu chí test liên quan Phase 1–4 đã có coverage hiện hữu hoặc ghi rõ gap có dẫn chứng.
- [x] `LOG_CHANNEL=single ./vendor/bin/phpunit` đạt; lượt xác nhận cuối sau Phase 4 đạt 508/508.
- [x] Business flow, routes và relationship docs khớp source và tests; phần chưa có production evidence ghi `UNVERIFIED`.
- [x] Deviation được phân loại `CODE`, `DATA`, `CONFIG`, `EXTERNAL` hoặc `INFRASTRUCTURE`.
- [x] Deferred decisions không bị ghi nhầm là đã chốt/triển khai.
- [x] Các thay đổi người dùng tồn tại trước Phase 5 được bảo toàn; không format hoặc dọn diff ngoài scope.

## 9. Checklist trước khi duyệt

- [x] User review và approve plan này trước khi cập nhật business specs/master task documentation hoặc thực hiện sửa đổi Phase 5.
- [x] Không có runtime code/schema change trong scope nếu chưa có plan amendment được duyệt.

## 10. Implementation evidence

- Đối chiếu `.business-spec/` với migrations, models, API routes, services, job, logging configuration và tests; cập nhật ba canonical files.
- Runtime route collection (`LOG_CHANNEL=single DB_CONNECTION=sqlite DB_DATABASE=:memory: php artisan route:list --json`) có 245 API entries; inventory có 245 rows và không còn URI thiếu.
- Candidate status mapping `perm` → MM `PERM`; không map thành `LIVE`. Full PHPUnit gần nhất sau patch Phase 4 đạt 508 tests/2,195 assertions.
- Terminal queue failure gọi critical logger; direct MatchMaker 4xx gọi error logger. `config/logging.php` default stack có Slack handler với error threshold, và effective config xác nhận `error` cùng `single,slack`; webhook/worker/production delivery vẫn UNVERIFIED.
- Direct MatchMaker 4xx ghi error log; `config/logging.php` default stack gồm Slack, Slack threshold mặc định `error`; effective config xác nhận các giá trị này. Production webhook/delivery vẫn UNVERIFIED.
- Follow-up alert plan được đóng theo config update; không cần runtime code change.
- Phase 4 task plan được giữ như history/evidence; các thay đổi người dùng tồn tại trước task được bảo toàn.

## 11. Follow-up — GAP-691 test audit & repair (2026-10-06, DONE)

### 11.1. Mục tiêu, phạm vi và approval gate

Yêu cầu: chạy test GAP-691, kiểm tra test case dư thừa và sửa lỗi test. Mở rộng plan integration/regression hiện hữu để gom cùng context; không tạo plan mới, không đổi tên file unnumbered lịch sử, không chia implementation phases. [CSS/PNG/Via plan](002-css-letterhead-rendering.md#156-execution--self-check-2026-10-06) giữ riêng evidence presentation đã triển khai, không sửa scope/approval cũ.

Chỉ sửa test/fixture/mock đã xác định bên dưới và ghi evidence sau verification. Database/types/Repository/Service/Controller/API/migrations/runtime config: **N/A — giữ nguyên**. Không restore/change MM debug guard, date formatter, mapping, assets hoặc logging production để làm test xanh. Nếu audit phát hiện runtime bug thực sự thay vì stale test, report và xin scope/approval riêng trước khi sửa.

- [x] Đọc đầy đủ `debug-workflow`, `backend-workflow`, SPEC template và ba canonical `.business-spec/` files; trace source trước kết luận.
- [x] Chạy baseline, xác định root cause và duplicate/gap có dẫn chứng.
- [x] User duyệt follow-up §11 bằng `ok` trước test/code edits.
- [x] Implement theo scope, self-check, affected/full verification và cập nhật evidence; default full vẫn có Slack DNS errors ngoài scope, không claim default full-green.

### 11.2. Baseline và root cause

- Core/status/job/staff Permanent filter: **89 tests / 6,966 assertions**, **1 error / 0 failures**, 26.401s. Reports: `/private/tmp/gap-691-via-underline.3zaVdG/gap-691-audit-baseline.{xml,log}`. Filter: `PermanentCandidateIntake|MatchMakerPermanentSync|SyncPermanentCandidateToMatchMakerJob|testPermanentCandidate|testPermanentCandidates|AgreementUrl`.
- Adjacent suites: **140 tests / 778 assertions PASS**, 39.126s, gồm FileUtility, MeFile, Admin/Compliance branch APIs và Candidate/staff/Appointment/Issue/SMS suites. Reports `gap-691-adjacent-baseline.{xml,log}` cùng directory. Sáu staff methods trùng giữa hai lượt chạy; JUnit deduplicate bằng class + dataset/method xác nhận **223 tests riêng biệt: 222 pass, 1 error**. Không cộng số assertions thành unique coverage.
- `[Mockery\Exception\BadMethodCallException] tại app/Services/MatchMakerService.php:561 (caller test:141) — mock MatchMakerApiInterface chưa khai báo addContactLog khi code hiện tại upload CV trong debug flow.` Source `syncPermanentCandidate` đã comment debug upload guard; `upsertCandidateToMatchMaker` vẫn dùng debug logging/peopleNumber `0`. Test cũ mock registration nhưng thiếu fake CV storage/contact-log/attachment expectations. Đây là **CODE/test-fixture mismatch**, không kết luận MM/network production lỗi.
- Ba date failures của full-run trước thuộc snapshot khác: current Service constant là `Y/m/d`; user đã cập nhật ba unit provider expectations thành `2026/10/06`/`2026/10/07`. Fresh 89-test run không còn date failure. Giữ nguyên user edits và literal expected dates, không tạo assertion expected bằng chính production formatter để tránh tautology.
- **CONFIG / EXTERNAL / INFRASTRUCTURE**: Default full-run trước có sáu Slack DNS errors ở Auth/Password/Me ngoài GAP-691. Không gửi webhook thật để verify unit tests. Các lượt verification độc lập có thể dùng `LOG_CHANNEL=single` chỉ cho process test; không sửa `config/logging.php`, `.env`, shared TestCase hoặc bỏ logging assertions. Production MM/Slack/storage/deployment vẫn UNVERIFIED. **DATA**: chỉ SQLite in-memory/fake disk/unsaved models; không DB production/migrations/seed command thủ công.

### 11.3. Test repair và bổ sung coverage có mục đích

1. `tests/Unit/Services/MatchMakerPermanentSyncTest.php`: giữ registration payload/PERM và no-LIVE assertions, nhưng mock đầy đủ boundary upload hiện tại. Fake storage có bytes CV; `addContactLog` và `uploadToContactLog` dùng strict `once`, verify DTO people number/dbSource, contact-log action/subject/text và attachment filename/content. Freeze clock cho attachment date; capture temp path và assert cleanup. Không `shouldIgnoreMissing`, không network/file download thật.
2. Parameterize fixture chung cho legacy CV-only và CV + job-scoped Work Finder Agreement: mock đúng optional File lookup/ownership và thứ tự upload; verify Agreement dùng constants/metadata riêng, status PERM chỉ cập nhật sau upload thành công. Thêm một upload-failure case để assert custom exception, temp cleanup và không gọi candidate status update sau failure. Shared setup cùng behavior gom private helper trong existing test class, không copy constructor dài sang file/test mới, không Repository unit test.
3. `tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php`: delegation hiện chỉ kiểm tra optional Agreement ID = null. Thêm provider cho null/non-null vào existing delegation test để xác minh public 4-ID boundary; giữ distinct retryable/non-retryable/state failure và structured critical log cases. Job legacy được giữ theo source dù submit hiện không dispatch queue.
4. `testSubmitPersistsPermanentProfileAndSynchronizesMatchMaker`: case accepted=false hiện đồng thời làm `files` sai size, nên HTTP 400 không chứng minh accepted validator. Giữ files hợp lệ, chỉ đổi accepted và assert validation error đúng `work_finder_agreement_accepted`; mock sync vẫn chỉ nhận success call. Không đổi Request rules/business behavior.

### 11.4. Dedupe có giới hạn và coverage matrix

| Finding | Thay đổi đề xuất | Coverage được giữ |
|---|---|---|
| `additionalAgreementRenderingProvider` chạy 2 brands × 3 inputs × 2 mapping paths = 12 PDFs; input không được render trong static legal templates, mapping độc lập input | Giảm còn 3 case/brand: empty + entity fallback, Unicode/HTML-like + branch override, long/unbroken + entity fallback; tổng **6**, giảm 6 tổ hợp | Cả GPHL/Hawk3, cả resolver paths, branch-priority với entity Tech đối nghịch, empty/Unicode/long input, static body/no-PII/legal/table/logo/storage assertions |
| Happy-path submit lặp no-CV và duplicate-type requests | Bỏ đúng hai request/setup lặp này; giữ data provider `agreement only` và `duplicate file types` trong `testSubmitRejectsInvalidFilesBeforeCallingTheService` | Request validation + no-service/no-profile-write assertions vẫn kiểm tra riêng; không bỏ foreign-file, email mismatch, Other unrelated storage, max other-document, success hoặc repeat 409 |
| Binding assertion ở controller-delegation test lặp unit `testIntakeContractResolvesToConsolidatedService` | Bỏ binding assertion trùng ở Feature; giữ unit binding test và HTTP validated-input delegation | Container binding, Controller injection/call/payload/resource đều còn owner rõ |
| PDF page-count helper và inline `preg_match_all` kiểm tra cùng điều kiện trong cùng case | Chỉ bỏ assertion subsumed/repeated sau audit từng caller, giữ strong minimum-page requirement và PDF signature | PDF validity/storage và Tech Appendix >=2 pages vẫn được verify; không chỉ bỏ check để giảm assertion count |

Không xóa toàn bộ test files. Không coi Service outcome test và HTTP 502 test là trùng: chúng kiểm tra persistence/orchestration và response contracts khác nhau. Giữ tám Via datasets (missing/null/empty/whitespace khác API input path), Unicode/long candidate-field tests, six source/extra-page letterhead datasets, missing/corrupt-logo cases, production mapping/default mapping, cleanup/ownership, staff authorization/detail-vs-list và status/retry classifications. Không giảm tests chỉ theo số assertions hoặc thời gian; mỗi case bỏ phải có owner coverage tương đương ghi rõ.

### 11.5. Data origin, contracts và file ownership

- Agreement: authenticated Controller → WorkFinderAgreementRequest + API middleware → intake ownership/resolver/buildAgreementData → DTO → Blade → Dompdf/storage/File. Layout tests tiếp tục dùng data capture từ production HTTP caller, không invent view keys.
- Submit: PermanentCandidateIntakeRequest (`accepted`, exact files size/allowlist/distinct) → intake reads/write-only transaction → synchronous PermanentCandidateSubmittedEvent → listener truyền Candidate/job/CV/Agreement IDs → MM service. Unit MM fixtures phải khớp actual Service File lookup/ownership/address/answers và upload helper input; không mock một call chain không tồn tại.
- Legacy Job: nullable agreementFileId constructor → `handle` truyền đủ bốn IDs tới MatchMaker contract; catches non-retryable/state failures, retryable escapes. Tests verify đúng current contract, không đổi Job retries/logging.
- Files được phép sửa: `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`, `tests/Unit/Services/MatchMakerPermanentSyncTest.php`, `tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php`, plan này; `.business-spec/backend-business-flow-spec.md` chỉ bổ sung verified evidence/current-source clarification sau implementation. Service date unit file chỉ audit/verify, không sửa user date changes đang đúng. API inventory/DB relationship không đổi vì runtime/API/schema không đổi.
- Existing production constants cho contact logs/statuses/file types/db source dùng từ Model/Service/Contract; test-only fixture constants khai báo trong existing test class khi cần fixed identifiers. Internal fixture helpers private; public data providers theo PHPUnit contract. Không formatter/linter, import reordering hoặc unrelated refactor.

### 11.6. Verification và acceptance sau approval

1. Chạy MM unit suite riêng: strict payload/upload/cleanup/PERM assertions pass với fake storage/external mocks, không real external side effects. Kiểm tra upload-failure không update local status; không bỏ assertion hoặc exception để xanh.
2. Chạy Intake Feature/Service và legacy Job suites tuần tự; Service current-day/before-midnight/after-midnight literals pass, invalid accepted test báo đúng field, matrix 6 static-brand datasets và all Via/letterhead/logo gates pass.
3. Chạy lại toàn bộ 223-test baseline scope, có ghi test count sau reduction/addition và mapping coverage trước/sau; tất cả affected suites phải pass. Không chạy nhiều PHPUnit processes đồng thời do fake storage chung.
4. Chạy full `./vendor/bin/phpunit`; nếu chỉ lỗi Slack DNS ngoài scope, report rõ và chạy thêm `LOG_CHANNEL=single ./vendor/bin/phpunit` để verify full suite offline. Không claim default full-green nếu default run vẫn error, không sửa production logging hoặc test unrelated.
5. Self-check against scope, minimal `git diff --check`, xác nhận Via/Blade/runtime user edits không bị revert, report cả failures còn lại và artifacts. Cập nhật living-spec evidence theo snapshot source thực tế; không suy diễn migration/deployment/MM/Slack delivery production từ test success.

### 11.7. Execution, coverage ownership và final verification

- User đã duyệt §11 bằng `ok` trước code edits. Đã dùng `debug-workflow` cho fixture/call-chain mismatch và `backend-workflow` để scan/triển khai/self-check theo approved scope; Database/types/Repository/Service/Controller/routes là N/A. Không tạo implementation phases/test files hoặc sửa code runtime.
- MM test có ba datasets legacy CV-only, CV + Agreement và CV upload failure. Shared private setup/upload helpers dùng fake storage với bytes không rỗng và mock strict `once`/global ordering: CV contact log → CV attachment → optional Agreement contact log/attachment → candidate PERM update. Verify đúng DTO people number `0` từ debug registration và db source GAP_EAST cho fixture legal entity 2, log metadata, literal attachment names theo clock đã freeze, actual temp-file bytes và cleanup. Candidate status update chỉ được gọi sau success/cleanup; failed upload trả MatchMakerTransientException cho mocked 503, không update candidate và attributes giữ nguyên. No-LIVE/app-pack/appointment/other repository side effects vẫn bị strict mocks chặn; không có live MM call hoặc `shouldIgnoreMissing`.
- Legacy Job delegation được parameterize null/non-null Agreement ID, giữ MAX_ATTEMPTS/status mapping/structured critical logging và retry/non-retry/state tests. HTTP accepted=false test giờ dùng files hợp lệ và assert đúng validation field; sync mock chỉ nhận success request. Không đổi Request/Service contracts hoặc formatter.
- Dedupe: bỏ 6 Cartesian combinations trong static-brand PDFs; mỗi GPHL/Hawk3 vẫn chạy empty entity fallback, Unicode/escaped HTML branch override với entity Tech đối nghịch, long/unbroken entity fallback. Bỏ hai validation requests no-CV/duplicate-type trong happy-path; provider `agreement only` / `duplicate file types` vẫn giữ exact validation/no-service/no-write checks. Bỏ Feature binding assertion lặp, giữ unit container binding + actual HTTP delegation. Bỏ ba subsumed page-count assertions: Tech exact 2 / long >=2 vẫn giữ, static-template helper >=1 vẫn giữ cùng PDF signature/storage checks. Không bỏ Via input variants, candidate escaping, legal/privacy, fixed/multipage letterheads, PNG budgets/integrity, production/default mapping, ownership, cleanup hoặc staff authorization.

| Test group | Trước | Sau | Lý do |
|---|---:|---:|---|
| Intake Feature | 64 | 58 | 6 static-PDF combinations độc lập input/mapping được gộp; contracts/edge cases giữ owner |
| MM Permanent unit | 1 lỗi | 3 pass | Fixture repair + Agreement upload + failure/cleanup/state coverage |
| Legacy sync Job unit | 6 | 7 | Thêm non-null Agreement-ID delegation; retry/status/logging không giảm |
| Intake Service unit | 12 | 12 | User date expectations hiện tại giữ nguyên và pass |
| Unique affected scope | 223 (1 error) | **220 PASS** | Giảm 6 + thêm 3; sáu staff methods trùng giữa core/adjacent được deduplicate theo JUnit class + method/dataset |

- Serial verification: MM unit **3 tests / 74 assertions PASS**, 0.171s; core GAP-691 **86 tests / 6,674 assertions PASS**, 22.888s; adjacent **140 tests / 778 assertions PASS**, 32.100s. Core includes Feature **58 / 6,434**, Intake Service **12 / 137**, Job **7 / 13**, MM **3 / 74** và sáu staff Permanent cases. Không cộng core/adjacent counts thành unique coverage vì overlap sáu cases; 220 distinct cases đều pass.
- Default full `./vendor/bin/phpunit`: **575 tests / 8,772 assertions**, **5 errors / 0 failures**, 02:24.675. JUnit xác nhận cả năm errors chỉ là Slack DNS ở Candidate Auth (3), Me NI verification (1), Password reset (1); không còn MM fixture/date/layout/mapping failures. Không sửa/skips các tests này hoặc logging production, không gửi webhook thật/escalate network.
- Full offline `LOG_CHANNEL=single ./vendor/bin/phpunit`: **575 tests / 8,782 assertions PASS**, 0 errors/failures, 02:23.736. Environment override chỉ cho test process; PHPUnit vẫn chạy toàn bộ suites và logging assertions/mocks, không đổi `.env`, `phpunit.xml`, shared TestCase hoặc default logger. Đây là full regression PASS trong test-only single-channel environment, **không phải default-config full-green hoặc production Slack delivery verification**.
- Artifacts: `/private/tmp/gap-691-test-audit.SbC8Sg/{mm-unit,gap-691-core,gap-691-adjacent,full-default,full-offline}.{xml,log}`. Default failures được tóm tắt từ JUnit, không dump raw stack traces/secret URLs.
- Self-check: chỉ sửa ba test files đã duyệt cùng plan/SPEC-039 evidence. Runtime MatchMaker/Intake services, Tech Blade (giữ Via fix), mapping/logging config và user Service date-test edits có SHA256 không đổi trước/sau verification. Không formatter/linter, migration, DB production, deployment, unrelated refactor/staging hoặc Repository unit tests. `git diff --check` pass; API inventory/DB relationship không cần sửa vì schema/routes/public contracts không đổi. Scoped test audit/repair hoàn tất; default logging/network deviations và MM debug upload behavior production vẫn được ghi riêng, không tự restore guard.

## 12. Follow-up — Server MM test portability (2026-10-06, DONE)

### 12.1. Error, evidence và root cause

- User báo `[AssertionFailedError] tại tests/Unit/Services/MatchMakerPermanentSyncTest.php:101 — expected một temporary upload path nhưng actual count = 0` cho dataset `legacy CV only`.
- Test đang set `matchmaker.debug_mode=true` trước khi tạo Service. `MatchMakerService::__construct` chụp giá trị này; `upsertCandidateToMatchMaker` nhánh debug chỉ log payload và trả people number `0`.
- `git show HEAD:app/Services/MatchMakerService.php` xác nhận tracked `syncPermanentCandidate` vẫn có guard `if (!$this->debugMode)` bao CV/Agreement upload. Working-tree diff local comment guard này; vì thế ba datasets §11 pass local nhưng không portable sang tracked source có guard. Đây là **CODE/test-design mismatch với uncommitted local edit**, không phải bằng chứng lỗi PDF, database hoặc MM thật.
- Khi tracked guard còn hoạt động và debug=true, upload không chạy, callback không thêm temporary path, PERM update vẫn có thể chạy; assertion count trong `finally` fail. `finally` cũng có thể che exception gốc ở những nhánh fail trước callback. Chưa có quyền truy cập/source snapshot server: sự khác biệt server là inference khớp log và tracked source, cần verify lại trên server sau fix.
- Evidence §11 là kết quả của dirty working tree tại thời điểm chạy, **không phải validation clean checkout/server**. Không sửa/revert user runtime guard để làm test xanh. DATA/CONFIG/EXTERNAL/INFRASTRUCTURE server chưa kiểm chứng; không quy lỗi Slack/storage/config cache từ log này.

### 12.2. Thiết kế sửa test, không đổi runtime

1. Chỉ sửa `tests/Unit/Services/MatchMakerPermanentSyncTest.php`. Giữ ba datasets CV-only, CV + Agreement và CV upload failure cùng no-LIVE/PERM, strict repository calls, File ownership, metadata/content/temp cleanup và no-update-on-failure assertions.
2. Chạy upload-flow datasets với `matchmaker.debug_mode=false`. Mock cả registration boundary thật: Service → private `upsertCandidateToMatchMaker` → private `getNewClient` → `GuzzleHttp\\Client::post`. Chỉ đổi config=false là chưa đủ vì sẽ phát sinh outbound request thật.
3. Vì Service tạo Client trực tiếp và hai helpers private, dùng test-only Mockery `overload:GuzzleHttp\\Client` trong isolated PHPUnit process (`@runInSeparateProcess`, `@preserveGlobalState disabled`); dựng overload trước application bootstrap nếu Client được load lúc bootstrap. Không sửa visibility/DI/contracts runtime chỉ để test, không network và không mock private business helpers. Mock `post` strict once trả real PSR-7 response HTTP 200 với `peo_no` fixture khác 0; kiểm tra literal RegisterCandidate URL, JSON mapped payload/PERM và authentication options bằng config synthetic test-only.
4. Cố định API settings/target entity IDs/credentials tại test để không phụ thuộc env/server secrets; giữ branch legal entity 2 và expected db source GAP_EAST. People number và expected attachment filenames dùng test public constants/literals tương ứng, freeze clock như hiện tại. Bỏ debug Log expectations vì non-debug production path không gọi chúng; registration JSON assertion được chuyển sang HTTP mock, không mất coverage.
5. Đưa expected temp-path count và upload-failure attributes assertions ra khỏi unconditional `finally`. Với failure dataset, capture/assert đúng custom `MatchMakerTransientException` và message trước cleanup/count/no-update checks; exception không đúng loại hoặc unexpected success phải fail rõ. Callback/temp bytes assertions vẫn strict, không conditional skip nếu paths rỗng và không `shouldIgnoreMissing`.
6. Không thêm debug no-upload test trong amendment này vì local user guard vẫn comment; không quyết định runtime debug semantics thay user. Upload datasets với debug=false phải chạy cùng behavior cả khi guard còn hoạt động và khi local guard comment. Không làm test tự thích nghi theo source hoặc bỏ assertion để pass.

### 12.3. Files, contracts và verification gate

- Files được phép sửa sau approval: MM test hiện hữu, plan này và `.business-spec/backend-business-flow-spec.md` (chỉ ghi correction/evidence và giới hạn local-vs-tracked). Route inventory/DB relationship/schema/production config: không đổi. Không tạo plan/test file mới hoặc nhiều implementation phases.
- Verify overload process isolation bằng chạy riêng ba MM datasets và chạy chung MM/Intake Service/Job suites; không có real MM/Slack calls. Nếu cơ chế overload không hoạt động do class loading, report blocker trước khi mở rộng runtime scope; không bypass assertion.
- Verify tracked guard bằng disposable copy/sandbox của test và service tracked source, không checkout/revert/chạm user dirty file. Chạy MM suite trên tracked guard và local commented guard; cả hai phải pass cùng assertions. Ghi chính xác snapshot/hash/report, không claim đã chạy trực tiếp server.
- Chạy affected GAP-691 suites tuần tự, rồi full `./vendor/bin/phpunit`; nếu chỉ còn external Slack DNS, report riêng và chạy full với process-only `LOG_CHANNEL=single`. Không sửa logging production/.env/shared TestCase, không migrations/formatter/linter/staging.
- Self-check: mapped registration JSON, CV/Agreement ordering, actual file bytes/cleanup, PERM only after success, no LIVE/appointment/app-pack side effects và failed-upload unchanged state đều có owner assertions; unexpected exceptions không bị final count che. Ghi correction rõ rằng §11 không chứng minh clean checkout.

### 12.4. Approval

- [x] Debug skill + canonical business specs đã đọc; trace tracked/local Service và test.
- [x] User duyệt §12 bằng `ok` trước implementation.
- [x] Implement, test impact review, affected/full verification và living-spec correction.

### 12.5. Execution, snapshot correction và self-check

- User duyệt §12 bằng `ok`. Đã đọc đầy đủ `debug-workflow` và `backend-workflow`, scan approved scope/call chain trước edits; Database/types/Repository/Service/Controller/API layers N/A. Chỉ sửa MM test hiện hữu cùng plan/living-spec evidence; không tạo implementation phase hoặc Repository unit test.
- **Entry snapshot khác planning snapshot**: khi bắt đầu implementation, working-tree Service không còn diff với HEAD và debug upload guard đã hoạt động trở lại. Không phải agent restore/revert: Service giữ SHA256 `036e65b3a562314fa3ca5ec7353a6dd910536a8436617f1ff85280b36de57649` trước/sau task. Logging config là user snapshot mới, giữ hash `3d51f1855cc0aae7ada743a9102c92a95b6c8e9982a315c2fce22338e13802af` trước/sau. Không chỉnh bất kỳ file runtime để đạt test gate.
- MM datasets giữ nguyên ba scenarios nhưng dùng debug=false và synthetic API settings/credentials/entity mapping. HTTP Client được overload trước Laravel bootstrap trong từng isolated process với global-state preservation disabled. Constructor nhận đúng `http_errors=false`; strict post once kiểm tra literal URL, exact headers và toàn bộ mapped JSON/PERM/overview, trả PSR-7 response 200 với people number `12345`. Không mock private Service methods hoặc registration result trực tiếp; payload allowlist và không thêm unmapped fields được assert bằng exact array equality. People number mới được verify tiếp ở DTO, attachment literal filenames và candidate update.
- Strict global ordering: HTTP registration → CV contact log → CV upload → optional Agreement contact log/upload → candidate PERM update. Fake storage, actual nonempty bytes/temp path checks, cleanup trước update, no-LIVE và strict remaining repositories giữ nguyên. Failure dataset capture đúng custom MatchMakerTransientException + exact message, assert unchanged attributes/no-update rồi count/cleanup; unexpected exception không bị unconditional finally assertion che và unexpected success vẫn fail. Không giảm/skips test cases hoặc `shouldIgnoreMissing`.
- Test impact review: MM Service trực tiếp được test tại class này; legacy Job và intake Service/HTTP consumers dùng cùng contract và retained mocks. Chạy combined core suite có MM/Intake/Job/staff tests; chạy full suite kiểm tra overload không leak sang tests khác.

| Verification | Kết quả | Snapshot/giới hạn |
|---|---|---|
| MM trên working-tree Service | **3 tests / 80 assertions PASS**, 0.810s | Guard active; runtime Service khớp HEAD |
| MM với exact tracked Service copy | **3 / 80 PASS**, 0.812s | Custom test-only bootstrap require tracked Service từ disposable path |
| MM với guard-commented Service copy | **3 / 80 PASS**, 0.708s | Copy chỉ thay hai guard lines; hash `14dad32175b9d263b55f19913a33ffe460ab3975679308235113b2b719f8c918`, khớp prior commented snapshot |
| GAP-691 combined affected filter | **78 tests / 6,224 assertions PASS**, 29.808s | MM 3/80, Job 7/13, Intake Service 12/137, Intake Feature 50/5,978, sáu staff cases |
| Full mặc định `./vendor/bin/phpunit` | **567 tests / 8,332 assertions PASS**, 03:25.024 | 0 errors/failures, không process logging override |

- Không sửa/revert service workspace để kiểm tra guard variants. Disposable files tạo bằng apply_patch và custom bootstraps dưới `/private/tmp/gap-691-mm-portability.BCiE4U/`; JUnit reports `mm-tracked.xml`, `mm-tracked-copy.xml`, `mm-commented-copy.xml`, `gap-691-core.xml`, `full-default.xml`, cùng core/full `.log`. Tracked copy có cùng SHA256 với actual Service. Tests vẫn chạy production sync → registration → upload call chain; fake external boundaries, không kết nối MM thật.
- Counts hiện tại khác §11 vì entry Feature file có 50 tests thay vì 58; task §12 không sửa Intake Feature hoặc xóa tests. Giữ §11 như lịch sử snapshot, không tái sử dụng counts/cam kết clean checkout của lượt đó. Default full lần này không còn Slack DNS errors; chỉ xác nhận current test environment/config snapshot, **không chứng minh Slack production delivery hoặc server đã pass**. Không cần rerun `LOG_CHANNEL=single` vì default gate đã pass.
- Self-check: `git diff --check` pass; task chỉ sửa một repo code file MM test. API/routes/schema/Blade/fixtures khác/user runtime changes được giữ nguyên; agent không formatter/linter/migration/network escalation/staging/commit. Synthetic credentials không đọc env secrets. Mapping/data origin, ordering, error identity, PERM/no-LIVE/no-other-workflow side effects và cleanup có assertions; internal helper private, setUp protected là framework extension boundary. Living spec sửa stale current-debug claim và cross-link evidence này; API inventory/DB relationship không đổi vì public/runtime contracts không đổi.
- Read-only check cuối ghi nhận test change đã được commit ngoài agent trong HEAD `a0d6b53d` (`#691: fix unit test depend on env`); không sửa/stage/revert commit này. Rerun current MM file sau thay đổi HEAD tiếp tục PASS **3 tests / 80 assertions** (`mm-final.xml`).
- Server follow-up: deploy/checkout test change rồi chạy `./vendor/bin/phpunit tests/Unit/Services/MatchMakerPermanentSyncTest.php`; expected 3 tests / 80 assertions. Không thay production MATCHMAKER_DEBUG_MODE hoặc bỏ guard để sửa test. Server source/process/runtime configuration vẫn UNVERIFIED đến khi có kết quả chạy tại đó.
