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
