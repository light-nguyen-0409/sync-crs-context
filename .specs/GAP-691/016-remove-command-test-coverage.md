# SPEC: Remove TestCommand Test Coverage

> **Trạng thái**: `IMPLEMENTED`
> **Ngày tạo**: 2026-10-09
> **Author**: Codex
> **Related**: [008 — Test command permanent sync job](008-test-command-permanent-sync-job.md), [015 — Permanent sync completion retry](015-permanent-sync-completion-retry.md)

## 1. Tổng quan

Loại bỏ test `testCommandRunsTypedSnapshotSynchronously()` khỏi `PermanentCandidateFormTest`. Permanent sync tiếp tục được kiểm tra qua Feature tests ở submit/queued-job boundary và Unit tests ở Service layer; không dùng test command làm một phần của PHPUnit suite.

**Yêu cầu gốc**: Chỉ cover Feature và Service test; bỏ test phụ thuộc vào `cmd:test` vì command hiện phục vụ chạy thủ công/test data và không nên là PHPUnit contract.

## 2. Database Design

N/A — không thay đổi schema, migration hoặc dữ liệu runtime.

## 3. API Contract

N/A — không thay đổi route, request/response schema, error contract hoặc API docs. `~/projects/crs-api-docs`: N/A.

## 4. Test Scope

- Xóa duy nhất test `testCommandRunsTypedSnapshotSynchronously()` trong `tests/Feature/Api/Candidate/PermanentCandidateFormTest.php`.
- Giữ nguyên `app/Console/Commands/TestCommand.php` để chạy thủ công; plan này không xóa hoặc thay đổi command.
- Giữ các Feature tests kiểm tra submit, queue payload, PDF generation, retry/completion và MatchMaker boundary.
- Giữ các Unit tests hiện có cho Service logic.
- Không thêm test mới vì mục tiêu là loại bỏ coverage ngoài scope, không thay đổi production behavior.

## 5. Data Origin & Call Chain

Phần coverage còn lại bắt đầu từ các caller production:

```text
Permanent intake HTTP request
  → FormRequest validation
  → PermanentCandidateIntakeService
  → SyncPermanentCandidateToMatchMakerJob
  → Feature assertions for PDF/MM/completion behavior
```

Test command không còn là caller được PHPUnit xác minh.

## 6. Files cần tạo/sửa

| File | Thay đổi |
|------|----------|
| `tests/Feature/Api/Candidate/PermanentCandidateFormTest.php` | Xóa test command synchronous và các assertion chỉ phục vụ command đó. |
| `.business-spec/backend-business-flow-spec.md` | N/A — không thay đổi business flow; command vẫn tồn tại để chạy thủ công. |

## 7. Validation

- Chạy affected Feature/Service suites.
- Chạy full `./vendor/bin/phpunit --no-coverage`.
- Kiểm tra `git diff --check`.

## 8. Acceptance Criteria

- PHPUnit không còn chạy hoặc phụ thuộc vào `cmd:test`.
- Feature và Service coverage hiện hữu vẫn pass.
- Full PHPUnit pass.
- Không thay đổi production command, API contract, migration hoặc docs repository.

## 9. Implementation Record

- Removed `testCommandRunsTypedSnapshotSynchronously()` from `tests/Feature/Api/Candidate/PermanentCandidateFormTest.php`.
- `TestCommand` remains available for manual local execution and was not changed.
- Affected Feature/Service suites: **101 tests passed**.
- Full PHPUnit: **613 tests / 9,289 assertions passed**.
- `git diff --check` and PHP lint passed.
