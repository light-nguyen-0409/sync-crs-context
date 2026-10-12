# SPEC: GAP-691 — Roll back Service DTO flow, retain queued Job DTO

> **Trạng thái**: `IMPLEMENTED` — implementation redirected by user on 2026-10-09; full test audit deferred to plan 013
> **Ngày tạo**: 2026-10-09
> **Author**: Codex
> **Related**: [009 — Reuse Service data in Permanent sync Job](009-reuse-service-data-in-permanent-sync-job.md), [010 — Remove CV-only Job branch](010-remove-cv-only-job-branch.md)

## 1. Mục tiêu

Rollback phần refactor Service DTO/context và flow direct `build → validate → handle`. Giữ `SyncPermanentCandidateToMatchMakerJob::$data` làm DTO duy nhất đi qua queue; Service trở lại xử lý submit/sync theo flow cũ với dữ liệu request và IDs, còn Job chịu trách nhiệm điều phối generate form, MatchMaker sync và completion.

Loại bỏ `Illuminate\Pipeline\Pipeline` khỏi Permanent intake/MM sync để flow dễ đọc và trace trực tiếp theo thứ tự nghiệp vụ. Không đổi queue contract và không đổi public API.

## 2. API contract assessment

Không đổi route, request, response hoặc error contract của `/api/candidate/me/permanent-intake`. `~/projects/crs-api-docs` không cần cập nhật vì chỉ quản lý API contract; **N/A — no API contract/API docs change**. Flow logic hiện tại cập nhật trong backend `.business-spec/` sau khi implementation hoàn tất.

## 3. Business flow sau thay đổi

### Submit

`submit()` gọi tuần tự:

1. Load request data và tạo snapshot bằng private Service helpers.
2. `assertOwnedCandidateJob()`.
3. `validateIntakeData()`.
4. `persistIntakeData()` transaction writes rồi tạo queue DTO một lần tại dispatch boundary.

### Worker

Job nhận `PermanentCandidateSyncData`, gọi Service generate/reuse form, gọi MatchMaker Service bằng các scalar IDs trong DTO và file form vừa sinh, rồi đánh dấu candidate permanent sau khi đồng bộ thành công. Service không nhận/trả runtime execution DTO.

### MatchMaker sync

Job gọi MatchMaker Service bằng local data đã chuẩn bị; Service gọi trực tiếp `validatePermanentSyncData()` rồi `processPermanentSyncData()`, không nhận runtime DTO và không query lại dữ liệu đã truyền.

## 4. Files và ownership

- `app/Services/PermanentCandidateIntakeService.php`: khôi phục Service submit/generation flow không dùng runtime context DTO.
- `app/Services/MatchMakerService.php`: khôi phục scalar `syncPermanentCandidate()` flow.
- `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php`: giữ Job DTO, lock/retry và điều phối form → MM → completion.
- `app/Dto/PermanentCandidateSyncData.php`: giữ làm queue payload; các projection runtime không được Service context hóa.
- `tests/Feature/Api/Candidate/PermanentCandidateFormTest.php`, `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`, `tests/Unit/Services/MatchMakerPermanentSyncTest.php`: cập nhật về scalar Service/Job contract.
- `.business-spec/backend-business-flow-spec.md`, `.business-spec/backend-api-route-inventory.md`, `.business-spec/backend-database-relationship.md`: ghi nhận flow direct validation, không thay đổi schema/API.

Không sửa DTO shape, Job routing, migration, Controller, FormRequest, queue worker config hoặc external docs.

## 5. Data origin and invariants

- `submit()` nhận `PermanentCandidateIntakeRequest` đã được FormRequest validate; private Service helpers là nguồn duy nhất của request data.
- Sau writes thành công, Service tạo queue DTO một lần từ snapshot cần render PDF.
- Job retry rebuilds dữ liệu theo các scalar IDs và Service cũ; không serialize model/runtime context.
- Direct call thay thế Pipeline phải giữ nguyên thứ tự, exception type/message, lock release, retry behavior, PDF/MM upload order và completion semantics.

## 6. Test and acceptance

- Affected Feature/Service suites pass.
- Full `./vendor/bin/phpunit` pass with final counts recorded in this plan.
- `rg` confirms no removed runtime context DTO is referenced by Service/Job contracts; queued `PermanentCandidateSyncData` remains.
- `git diff --check` and PHP lint pass.
- No API docs commit/push required; backend code remains uncommitted by Codex.

Approval gate: [x] user approved implementation direction; [x] code implementation complete; [x] affected suites updated; [x] full PHPUnit PASS (612 tests, 9,281 assertions); [x] business specs updated.

## 7. Follow-up — default queue routing

`SyncPermanentCandidateToMatchMakerJob` sẽ bỏ việc gọi `onConnection('redis')->onQueue('default')` trong constructor. Khi dispatch, Job dùng connection và queue mặc định từ `config/queue.php`/`.env` của môi trường; không hard-code routing trong Job.

Acceptance criteria:

- Job không gọi `onConnection()` hoặc `onQueue()` trong constructor.
- Payload, retry, lock và xử lý nghiệp vụ hiện tại không đổi.
- Test routing được cập nhật trong plan 013 sau khi code thay đổi.

Implementation result: constructor routing override removed; PHP lint and `git diff --check` pass. Test assertions for routing remain deferred to plan 013 as requested.
