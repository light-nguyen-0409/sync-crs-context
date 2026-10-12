# SPEC: GAP-691 — Roll back typed DTO/context flow for Permanent sync

> **Trạng thái**: `DRAFT` — chờ user duyệt trước khi rollback code
> **Ngày tạo**: 2026-10-09
> **Author**: Codex
> **Related**: [007 — Permanent form/MM Job](007-backend-generated-permanent-form-in-mm-job.md), [009 — Reuse Service data in Permanent sync Job](009-reuse-service-data-in-permanent-sync-job.md), [010 — Remove CV-only Job branch](010-remove-cv-only-job-branch.md)

## 1. Mục tiêu và phạm vi

User muốn giảm phạm vi thay đổi hiện tại bằng cách rollback typed DTO/runtime-context refactor của GAP-691, đưa Permanent sync về flow truyền scalar IDs và Service tự build dữ liệu khi Job chạy.

Phạm vi đề xuất:

- Job không nhận `PermanentCandidateSyncData` hoặc `PermanentCandidateExecutionData`.
- Job nhận các scalar IDs cần thiết (`candidateId`, `jobId`, `cvFileId`, `agreementFileId`, `permanentFormFileId`) và snapshot payload cần cho PDF theo contract hiện tại đã có trước DTO refactor.
- Service xử lý lại việc query/build dữ liệu từ các scalar IDs trong worker; không truyền Eloquent model hoặc runtime context qua queue.
- Giữ BE generate `permanent_candidate_form`, Redis/default worker, lock/retry, MM upload order, completion và TestCommand.
- Không tạo bảng submission/retry, không đổi route/request/response public, không đổi schema.

Không rollback các thay đổi nghiệp vụ độc lập đã được yêu cầu trước đó: PDF certificate layout, header/footer/logo, click metadata, DB label resolution, upload compatibility, queue default routing và event/listener removal nếu chúng không phụ thuộc trực tiếp vào DTO.

## 2. Điểm cần chốt trước khi code

“Không dùng DTO” được hiểu là bỏ các DTO typed của queue/context (`PermanentCandidateSyncData`, `PermanentCandidateExecutionData`, prepared profile/answer value objects). Snapshot PDF vẫn phải có nguồn dữ liệu immutable; plan này giữ snapshot ở Job dưới dạng payload tương thích flow cũ. Nếu user muốn bỏ luôn snapshot và chỉ query DB, cần plan khác vì payload submit hiện chưa được persist đủ để tái tạo toàn bộ PDF.

## 3. API contract/docs assessment

Public endpoint `/api/candidate/me/permanent-intake` không đổi route, request, response hoặc error contract. `~/projects/crs-api-docs` chỉ quản lý API contract nên task này không cập nhật repo đó: **N/A — no API contract/API docs change**. Queue flow và business logic chỉ cập nhật trong `.business-spec/` của backend sau khi source được trace lại.

## 4. Phase 2 — Backend implementation

### Job and service boundary

- `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php`: đổi constructor/serialized properties về scalar IDs + snapshot payload; bỏ dependency vào typed DTO/context; giữ routing, lock, retry/failure logging.
- `app/Services/PermanentCandidateIntakeService.php`: khôi phục method signatures nhận scalar arguments/snapshot cho form generation và worker preparation; dispatch Job bằng scalar payload.
- `app/Services/MatchMakerService.php`: khôi phục một Service method nhận scalar IDs để tự query/build dữ liệu trước `syncPermanentCandidateFromContext` hoặc flow tương đương; không queue DTO.
- `app/Contracts/Services/MatchMakerServiceInterface.php` và `PermanentCandidateIntakeServiceInterface.php`: đồng bộ lại scalar signatures.
- `app/Console/Commands/TestCommand.php`: dispatch scalar Job payload theo command flow.

### DTO cleanup

- Xóa hoặc ngừng sử dụng các DTO chỉ phục vụ typed queue/context: `PermanentCandidateSyncData`, `PermanentCandidateExecutionData`, `PreparedMatchMakerProfile`, `PreparedMatchMakerAnswer` và các helper DTO chỉ còn caller trong flow này.
- Chỉ xóa file nào sau khi `rg` xác nhận không còn caller ngoài scope; không xóa DTO dùng ở flow khác.
- Không truyền Eloquent model, Request hoặc Service instance vào queue.

### Tests and documentation

- Cập nhật Feature tests để assert scalar Job serialization, worker rebuild/query behavior, PDF/MM/completion ordering và retry/lock.
- Cập nhật Unit tests chỉ cho Service logic; loại bỏ assertions dành riêng cho typed DTO/context.
- Cập nhật ba living specs trong `.business-spec/` sau khi source được trace lại.

## 5. Data origin and call chain

Submit route → `PermanentCandidateIntakeController` → validated `PermanentCandidateIntakeRequest` → `PermanentCandidateIntakeService::submit` persists candidate/address/answers → dispatches scalar Job with immutable PDF snapshot and file IDs → Job resolves candidate/job/branch/address/answers/files/questions through repositories → Service validates ownership/state → generates/reuses PDF → MatchMaker uploads CV/Agreement/form → completion updates `is_permanent`.

The worker must not infer missing payload keys. Scalar IDs and snapshot keys must be documented in the Job constructor/PHPDoc and covered by feature tests from the real submit caller and TestCommand caller.

## 6. Acceptance criteria

- No `PermanentCandidateSyncData`/`PermanentCandidateExecutionData` crosses the queue boundary or is required by Job/Service contracts.
- `rg` shows no queue dispatch/Job constructor using typed runtime DTOs.
- Submit still returns HTTP 202 pending; no public API schema change.
- PDF remains deterministic and uses the immutable submit snapshot; MM uses current records loaded during worker attempt.
- No database query runs inside loops or write transactions.
- Affected tests and full `./vendor/bin/phpunit` pass; plan records counts/log.
- Backend code is not committed/pushed by Codex; no external API docs commit is required because the contract is unchanged.

## 7. Files expected to change

- `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php`
- `app/Services/PermanentCandidateIntakeService.php`
- `app/Services/MatchMakerService.php`
- `app/Contracts/Services/MatchMakerServiceInterface.php`
- `app/Contracts/Services/PermanentCandidateIntakeServiceInterface.php`
- `app/Console/Commands/TestCommand.php`
- Relevant Feature/Service tests under `tests/Feature/Api/Candidate/` and `tests/Unit/Services/`
- `.business-spec/backend-business-flow-spec.md`
- `.business-spec/backend-api-route-inventory.md`
- `.business-spec/backend-database-relationship.md`

Approval gate: [ ] user confirms “không dùng DTO” means the scalar Job + immutable snapshot design above; [x] API docs assessment N/A — no contract change; [ ] backend rollback; [ ] affected/full test audit.
