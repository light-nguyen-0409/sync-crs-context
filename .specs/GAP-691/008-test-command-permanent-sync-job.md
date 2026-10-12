# GAP-691 — TestCommand chạy Permanent MM job với payload mẫu

> Trạng thái: IMPLEMENTING
> Ngày: 2026-10-09
> Liên quan: [007 — BE-generated form / MM job](007-backend-generated-permanent-form-in-mm-job.md)

## 1. Mục tiêu và baseline

User muốn gọi phần chạy job trong TestCommand với fake data tương ứng. Scope độc lập là entry point CLI thử job thật, không thay workflow production. Đã tìm các plan GAP-691 hiện có; chưa có plan cho command này. File TestCommand hiện là untracked user file: handle gọi agreementGenerate với candidate4248/job1 rồi dd Resource. Giữ các helpers email/Welfare/Agreement của user, chỉ đổi entry point và thêm private helper cần thiết.

Canonical baseline: ba living specs đã đọc; source xác nhận job snapshot khác null lấy Redis lock, kiểm tra ownership/files, render PDF, sync MM và complete is_permanent. Không có CODE deviation mới ở flow job; INFRASTRUCTURE/EXTERNAL (Redis/storage/MM đang chạy) chưa xác minh.

## 2. CLI và data contracts

- `php artisan cmd:test --candidate-id=<id> --job-id=<id> --cv-file-id=<id> --agreement-file-id=<id>` chạy job ngay qua `Bus::dispatchSync(new SyncPermanentCandidateToMatchMakerJob(new PermanentCandidateSyncData(..., snapshot: $snapshot)))`; không cần queue worker để thực thi lần này. Redis vẫn cần cho shared candidate lock.
- Giữ option branch-id đang tồn tại để tránh sửa contract ngoài scope; bỏ candidate/file ID hardcoded cho entry point mới. Bốn ID mới là required positive integers khi chạy job. Lookup actual candidate/file data qua Repository Interfaces; không tạo empty Controller/Service/Repository layers.
- Dùng candidate/job/CV/Agreement có thật ở DB/storage, thuộc cùng candidate/job theo contract. Không fake ID/file URL vì job revalidates records/storage. Candidate phải chưa permanent; không tự reset is_permanent hoặc MM state để ép chạy lại.
- Fake `snapshot.data` đủ fields theo PermanentCandidateIntakeRequest: title, first/middle/last name, email/phone, DOB, nested address, contact dates/times, raw transport/distance/recruitment keys, journey type, agreement accepted, job_id và hai file references. Fixed sample values/constants khai báo trong command, file types/journey constants tái sử dụng Model.
- `cv_name`/`agreement_name` lấy original_file_name từ actual File records. Click IP dùng documentation/sample IP, clicked_at dùng thời điểm tạo fixture; ghi rõ simulated metadata, không phải click thật của candidate.
- Không gửi display_labels hardcoded; snapshot thiếu map dùng chính legacy batch-resolution path của generator để lấy label DB và raw fallback. Không sửa Service chỉ để expose private snapshot helper.
- Fake payload phục vụ PDF; MM sync vẫn lấy profile hiện có trong DB. Command không gọi submit/không ghi đè profile thật bằng thông tin mẫu. Đây là kiểm tra job, không phải end-to-end submit test.

## 3. Execution và side effects

1. Validate CLI input, lookup required DB data, kiểm tra preconditions trước side effects; báo lỗi/exit failure khi thiếu input hoặc candidate đã permanent.
2. Dựng snapshot mẫu trong private helper, tạo job mới với six constructor args và dispatchSync để container inject đúng services và Laravel xử lý job lifecycle.
3. Job thật giữ nguyên lock, file reuse và ordering: generated form → MM CV/Agreement/form → completion. In thông tin candidate/job/files, generated form id khi lookup được, completed state; không dd hoặc in secrets/profile chi tiết.
4. Nếu exception, fail/lock contention/no completion thì exit failure; không in thành công chỉ vì dispatchSync return. Kiểm tra post-state bằng intakeService.isPermanentCandidate sau dispatch. Direct synchronous run không kiểm tra worker retry/backoff/reservation; cần queue worker test riêng cho phần đó.

Command gọi MM và ghi storage/files/is_permanent theo cấu hình hiện tại. Dùng candidate test và MM test configuration. Không tự gọi command với IDs hardcoded trong quá trình implementation; chỉ kiểm tra isolated automated tests dùng fake storage/mock external boundaries.

## 4. API / database assessment

N/A — no API contract/API docs change: routes, request/response/errors/examples API và DB schema không đổi. Không cần docs-first synchronization trong crs-api-docs cho CLI entry point. Không migration/seed/table. Cập nhật command inventory tại `.business-spec/backend-business-flow-spec.md` sau implementation; API inventory/database baseline unchanged.

## 5. Files, architecture và kiểm chứng

- Owned implementation: `app/Console/Commands/TestCommand.php` (user file, preserve existing methods/formatting except entry point/description/signature); new private snapshot/run helper nếu cần.
- Command boundary gọi Repository Interfaces để lookup và Job/Bus để workflow; không duplicate business rules hoặc sửa production Service/Job. Internal helpers private; constants cho fixed sample values.
- Test impact: command behavior không còn fixture-only vì gọi production workflow/MM và completion; fixture-only PHPUnit exemption không áp dụng. Add focused command Feature test theo project patterns: valid snapshot construction/dispatch to real job boundary, required IDs, missing records, already permanent, failure/non-completion exit; actual job existing suites cover PDF/MM ordering and failure.
- Mock external MM; real job must receive expected snapshot and IDs. Never call live MM in tests. Verify fake payload has all rendered fields, raw keys not display labels, filenames sourced from DB and no profile overwrite.
- New test file cần đọc laravel-architecture skill trước khi tạo. Run affected command/Job/Service/PDF suites then full `./vendor/bin/phpunit` sequentially. No formatter/linter/backend commit.
- Acceptance: CLI runs intended snapshot branch immediately; generated PDF includes sample data/DB labels; real profile not replaced; command distinguishes completion from failure/no-op; user unrelated helpers unchanged; full affected tests PASS.

## 6. Approval

- [x] Trace TestCommand → Job → Service/PDF/MM and inspect prior plan/source.
- [x] User approve CLI IDs, synchronous execution and sample snapshot scope (ok, 2026-10-09).
- [ ] Implementation/tests/self-check and living-spec command inventory complete.

This turn creates plan only; no implementation edits or runtime job invocation.

## 7. Execution evidence

- User approved 2026-10-09. Implementation changes TestCommand signature/description/entry point and adds two private helpers/constants. Existing Agreement/Welfare/email helpers preserved. No Service/Job/API/schema edit.
- Command tests exercise actual dispatchSync, serialized job, real intake PDF generation/DB-label resolution and completion with mocked MM. Snapshot validated against actual FormRequest; actual DB filenames and unchanged database profile asserted. Invalid IDs, missing records, already permanent, MM transient error and lock contention covered. Focused PASS9 tests/43 assertions.
- CONFIG deviation: new local bootstrap/cache/config.php freezes pgsql host; plain PHPUnit errors before tests in model-generator command registration. Test execution uses process-only APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php to read PHPUnit SQLite settings. No deletion/config:clear or change to user cached config.
- Temporary helper name collision with Laravel TestCase.options corrected to private commandOptions before verification.
- API docs assessment N/A confirmed; canonical command inventory updated. Affected/full tests and self-check pending. No live cmd:test invocation or MM call.

- Affected gate PASS: process-isolated config cache, 56 tests/400 assertions (command9/43 + existing Job/Intake Service/PDF suites). Syntax check two new/modified files PASS. Self-check: lookup batched files through interfaces; no DB queries in loops/transactions, private helper visibility, fixed sample constants, no new service injection/query layer, names/labels traced to actual caller. Unrelated user helpers/config cache and all staging state preserved.
- Full suite currently reports failures in other tests; review final summary before declaring gate PASS.

### Final verification (2026-10-09)

- Implementation and affected tests/self-check PASS56 tests/400 assertions, including command9/43. No live job/MM run. No API docs change, migration, formatter, backend commit or staging change.
- Full suite process-only config override: 646 tests/9,327 assertions, four failures all in unrelated `tests/Unit/Scripts/LaravelCacheScriptTest.php` (mode default/refresh/optimize at59, compose fallback at121). CODE/test fixture deviation: user script `laravel-cache.sh:64` has commands config:cache/view:cache only while tests still expect route:cache and count3. Both files untracked user work outside008; untouched. No failures in the new command/Job/Intake/PDF tests.
- Full-test gate NOT PASS; do not mark overall plan DONE until unrelated baseline is reconciled. Implementation is reviewable and runnable with four existing IDs. User local bootstrap config cache preserved; test config override not part of runtime command.
