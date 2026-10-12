# SPEC: GAP-691 — Remove standalone CV-only path from Permanent sync Job

> **Trạng thái**: `DONE` — implementation and verification complete
> **Ngày tạo**: 2026-10-09
> **Author**: Codex
> **Related**: [007 — Permanent form/MM Job](007-backend-generated-permanent-form-in-mm-job.md), [009 — Reuse Service data in Permanent sync Job](009-reuse-service-data-in-permanent-sync-job.md)

## 1. Mục tiêu và source trace

Flow `POST /api/candidate/me/permanent-intake` tạo `PermanentCandidateIntakeContextData` với `snapshot` non-null, sau đó `persistIntakeData()` truyền snapshot vào `PermanentCandidateSyncData` và dispatch `SyncPermanentCandidateToMatchMakerJob`. `TestCommand` cũng tạo Job với snapshot.

`MatchMakerService::syncPermanentCandidate()` was the former standalone entry point, tự dựng `PermanentCandidateSyncData` không có snapshot để xử lý trực tiếp. Source tracing after removing the Job branch showed no production caller remained; its contract, implementation and legacy unit path were removed.

Vì vậy nhánh `snapshot === null` trong Job đang trộn hai contract: Job Permanent intake sinh PDF và standalone MM sync. Loại bỏ nhánh này và entry point không còn caller. Job chỉ nhận và xử lý payload có snapshot/profile.

## 2. Business behavior sau thay đổi

- `SyncPermanentCandidateToMatchMakerJob` yêu cầu `PermanentCandidateSyncData::$snapshot` non-null ở boundary xử lý.
- Job luôn chạy `preparePermanentCandidateSync()`, generate/reuse Permanent PDF, sync MM và completion theo flow hiện tại.
- Không gọi `MatchMakerService::syncPermanentCandidate()` từ Job.
- Xoá `MatchMakerService::syncPermanentCandidate()` khỏi Service contract/implementation vì không còn caller production; mọi background processing đi qua snapshot-backed Job.
- `PermanentCandidateSyncData::$snapshot` là `PermanentCandidateFormSnapshotData` bắt buộc. `profile` cũng là `PreparedMatchMakerProfile` bắt buộc vì submit/TestCommand phải build đầy đủ prepared data trước khi dispatch.
- Không còn snapshot-null/profile-null Job branch hoặc guard; DTO constructor và PHP types enforce boundary trước khi queue/worker chạy.
- Giữ nguyên Redis/default routing, lock, retry deadline, PDF fingerprint, MM upload order và completion semantics.

## 3. API/docs assessment và Phase 1 — Documentation first

Public routes, request/response schemas, examples và HTTP errors không đổi. Đây là thay đổi internal queue boundary/operations documentation.

Phase 1 cập nhật:

- `~/projects/crs-api-docs/docs/flows/permanent-intake.md`: Job chỉ xử lý snapshot/profile-backed Permanent intake; standalone MM entry point đã remove.
- `~/projects/crs-api-docs/docs/operations/queue-and-events.md`: shared worker là đường Permanent sync duy nhất; DTO yêu cầu snapshot/profile.

Mark planned/not deployed. Chạy `npm run build` và `git diff --check`, stage chỉ hai file task-owned, commit và push bình thường lên `origin/main`. Ghi paths, validation, SHA và push result trước Phase 2. Không sửa backend trước khi docs gate PASS.

## 4. Phase 2 — Implementation

Owned files:

- `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php`: bỏ snapshot-null branch/guard; Job luôn xử lý snapshot-backed DTO và giữ Redis/default routing/retry settings.
- `app/Dto/PermanentCandidateSyncData.php`: đổi `snapshot` và `profile` thành required typed fields, đặt lại constructor order để PHP enforce non-null.
- `app/Services/MatchMakerService.php`, `app/Contracts/Services/MatchMakerServiceInterface.php`: xoá standalone `syncPermanentCandidate()` và builder chỉ phục vụ entry point đó.
- `app/Console/Commands/TestCommand.php`: build profile từ candidate/address trước khi dispatch typed Job.
- `config/queue.php`: Redis shared worker retry_after dùng constant 600s, lớn hơn Job timeout 300s.
- `tests/Feature/Api/Candidate/PermanentCandidateFormTest.php`, `tests/Unit/Services/MatchMakerPermanentSyncTest.php`: bỏ snapshot/profile-null Job/standalone assertions; giữ feature worker và unit context pipeline coverage.
- Các docs/living specs tương ứng sau implementation.

Không tạo migration, route, Controller, FormRequest, Event/Listener hoặc bảng mới. Không đổi public API. Không dùng generic exception; dùng `PermanentCandidateSyncStateException` và message/constant hiện có hoặc constant Service/Job có tên rõ nghĩa.

## 5. Test impact and acceptance

- Feature test thực tế submit → queued Job có snapshot/profile và worker hoàn tất vẫn PASS.
- `PermanentCandidateSyncData` cannot be constructed without snapshot/profile; PHP type checks enforce the queue contract.
- Không còn method/call `syncPermanentCandidate()` trong production hoặc tests.
- Affected suites và full `./vendor/bin/phpunit` chạy tuần tự với `APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php`; ghi test/assertion/log.
- Self-check: Job contract rõ ràng, no null dereference, no duplicate worker flow, lock/retry/failure logging giữ nguyên, no unrelated diff.

## 6. Execution evidence and self-check — 2026-10-09

- Docs-first amendment: PASS; `crs-api-docs` build and `git diff --check` passed; commits `5a87809ea62a418864b12ded2a3c65ea67067fae` and `5fd3dd77e1b4768e574d9afc195491ea63b28b2c` pushed to `origin/main`.
- Affected suites: PASS, 38 tests / 379 assertions.
- Full suite: PASS, 628 tests / 9,397 assertions, `APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php ./vendor/bin/phpunit`, log `/private/tmp/gap691-010-full.log`, 04:15.039, 137 MB.
- Syntax/diff checks: PHP lint passed for changed PHP files; `git diff --check` passed. `rg` confirms no `syncPermanentCandidate(` callers remain in `app` or `tests`.
- Self-check: `PermanentCandidateSyncData::$snapshot` and `$profile` are required typed fields; `PermanentCandidateExecutionData::$profile` is required; Job has no nullable branch/guard; standalone builder/contract are removed; submit and TestCommand build required data before dispatch; no route/schema/migration changes.
- Runtime deployment, worker availability and external MatchMaker delivery remain unverified.

Approval gate: [x] user approves original plan; [x] user requested required snapshot/profile types and removal of unused standalone path; [x] docs-first validation/commit/push PASS; [x] implementation/test audit PASS; [x] affected/full PHPUnit and self-check PASS.
