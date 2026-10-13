# SPEC: GAP-691 — Permanent sync test coverage follow-up

> **Trạng thái**: `IMPLEMENTED`
> **Ngày tạo**: 2026-10-09
> **Related**: [012 — Roll back Service DTO flow, retain queued Job DTO](012-direct-permanent-sync-validation.md)

## Mục tiêu

Bổ sung và ổn định test coverage cho flow Permanent sau khi rollback Service về request/scalar-ID flow và giữ `SyncPermanentCandidateToMatchMakerJob` làm queue boundary. Plan này tách khỏi implementation hiện tại theo yêu cầu; không thay đổi production code trong scope này.

## Phạm vi kiểm thử

- Feature test submit Permanent trả HTTP 202, persist candidate/address/answers và dispatch `PermanentCandidateSyncData`.
- Feature test Job gọi đúng thứ tự: kiểm tra trạng thái, generate/reuse PDF, scalar MatchMaker sync, completion; không completion khi generation/MM lỗi.
- Unit test Intake Service cho snapshot/PDF generation, file ownership, retry reuse và click metadata.
- Unit test MatchMaker Service cho scalar validation, CV/Agreement/form uploads, external rejection/transient failure và status update.
- Regression test cho TestCommand chạy `dispatchSync` với payload mẫu và không thay profile ngoài ý muốn.
- Test audit toàn bộ caller/contract sau khi queue DTO shape thay đổi, không thêm repository unit tests.

## Cách xử lý test lỗi hiện tại

Full PHPUnit đang được tạm thời bỏ qua theo yêu cầu người dùng; lỗi/nhóm test fail phải được phân loại trước khi sửa. Không coi test run bị dừng là PASS. Khi bắt đầu plan này, chạy affected suites trước, ghi lại lỗi đầu tiên và xác định lỗi do test contract, môi trường/network, hay production behavior.

## Tiêu chí hoàn thành

- Affected Feature/Service/Job suites pass.
- Full `./vendor/bin/phpunit` pass với tổng test/assertion được ghi lại.
- `git diff --check` và PHP lint pass.
- Không thêm test Repository implementation/contract.
- Test names/assertions phản ánh queue DTO + scalar Service contract, không tham chiếu runtime context DTO đã loại bỏ.

## Progress — default queue routing amendment (2026-10-09)

- Updated existing assertions so the Job does not claim a forced connection/queue; tests now assert the Job is pushed and leaves `connection`/`queue` unset for Laravel to resolve from configuration.
- Restored the HTTP 202 assertion on the Permanent intake controller while updating the queue-routing expectations.
- Affected suites PASS: **68 tests, 6,591 assertions**.
- Full PHPUnit PASS: **612 tests, 9,281 assertions** (`02:39.849`).

## Final result

The stale tests for removed runtime-context methods and forced queue routing were removed or aligned with the scalar Service/Job contract. PHP lint and `git diff --check` pass. No repository unit tests were added.

## API/docs assessment

Không đổi route, request/response/error contract hoặc schema; `~/projects/crs-api-docs` là **N/A — no API contract/API docs change**. Plan này chỉ bổ sung kiểm thử backend.

## Amendment — align tests with default cache lock store (2026-10-12)

> **Trạng thái amendment**: `IMPLEMENTED`

### Mục tiêu

Điều chỉnh test theo thay đổi hiện tại của `SyncPermanentCandidateToMatchMakerJob`: lock dùng `Cache::lock(...)` trên cache store mặc định thay vì gọi rõ `Cache::store('redis')->lock(...)`. Không thay đổi production code trong amendment này.

### Phạm vi file sau khi được duyệt

- `tests/Feature/Api/Candidate/PermanentCandidateFormTest.php`
  - Cấu hình `cache.default` cho test thay vì chỉ cấu hình named Redis store.
  - Đổi lock tạo trước và assertion lock sau khi worker chạy sang `Cache::lock(...)`.
  - Giữ nguyên mục tiêu kiểm thử lock contention: worker không xử lý khi lock đang bị giữ và lock được release đúng cách.
- `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`
  - Đổi setup cache store của test sang `cache.default` để khớp runtime path của Job.

### Call-chain/data-origin verification

`PermanentCandidateIntakeService` dispatch `SyncPermanentCandidateToMatchMakerJob`; `SyncPermanentCandidateToMatchMakerJob::handle()` tạo lock bằng default cache manager với key từ `LOCK_KEY_PREFIX` và candidate ID. Test phải cấu hình đúng default store và dùng cùng key contract, không giả định named Redis store còn được sử dụng.

### API/docs và dữ liệu

- Không đổi route, request/response/error contract hoặc schema.
- `~/projects/crs-api-docs`: **N/A — no API contract/API docs change**.
- Không migration, seed, hoặc thay đổi dữ liệu production.

### Verification gate

- Chạy test lock contention và các affected Feature/Service/Job suites.
- Do môi trường hiện tại đang nạp cấu hình PostgreSQL thay vì SQLite in-memory, test cần chạy với config-cache override đã được ghi nhận trong plan GAP-691/008, ví dụ `APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php`, không sửa config cache trong repository.
- Sau đó chạy `./vendor/bin/phpunit` và ghi nhận kết quả thực tế; nếu còn blocker môi trường thì báo rõ, không coi là PASS.
- Chạy PHP lint và `git diff --check`, không chạy formatter/linters tự động ngoài các kiểm tra được yêu cầu.

### Acceptance criteria

- Không còn test trực tiếp phụ thuộc `Cache::store('redis')->lock(...)` cho flow này.
- Existing lock-contention regression test pass và vẫn chứng minh không xử lý trùng candidate.
- Affected suites và full PHPUnit pass, hoặc blocker môi trường được ghi nhận chính xác.
- Diff chỉ gồm các test setup/assertion liên quan đến default cache lock; không ảnh hưởng các thay đổi người dùng đang có.

### Verification result

- Updated `PermanentCandidateFormTest` và `PermanentCandidateIntakeTest` để dùng `cache.default`/`Cache::lock(...)`.
- Lock-contention regression test: **PASS — 1 test, 11 assertions**.
- Related completion-retry test: **PASS — 1 test, 11 assertions**.
- Affected Feature suites: **PASS — 22 tests, 218 assertions**.
- Full PHPUnit: **PASS — 613 tests, 9,289 assertions**.
- PHP lint trên hai test file: **PASS**.
- `git diff --check`: **PASS**.
- Không còn reference `LOCK_STORE`, `cache.stores.redis`, hoặc `Cache::store('redis')` trong `app/` và `tests/`.
- Test commands dùng process-only `APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php` để bỏ qua config cache PostgreSQL cũ; không thay đổi config cache trong repository.
