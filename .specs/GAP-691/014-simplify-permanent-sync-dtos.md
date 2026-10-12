# SPEC: Simplify Permanent Candidate Sync DTOs

> **Trạng thái**: `IMPLEMENTED`
> **Ngày tạo**: 2026-10-09
> **Author**: Codex

## 1. Tổng quan

Rà soát flow hiện tại cho thấy `PermanentCandidateSyncData` vẫn giữ các field và DTO được tạo từ flow chuẩn bị dữ liệu cũ, trong khi service/job hiện tại đã quay lại flow scalar và chỉ truyền snapshot cùng các định danh file cần thiết. Plan này dọn các field không còn consumer production, đồng bộ `TestCommand` và test fixture, đồng thời giữ nguyên cấu trúc snapshot đang tham gia tạo fingerprint và PDF.

**Yêu cầu gốc**: Sau khi rollback flow service dùng DTO, kiểm tra DTO hiện tại có field thừa và cập nhật để DTO phản ánh đúng job payload thực tế.

## 2. Database Design

N/A — không thay đổi database, migration hoặc model.

## 3. API Contract

N/A — không thay đổi route, request/response schema, error contract hoặc API documentation. `~/projects/crs-api-docs` không cần cập nhật.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. `PermanentCandidateIntakeService` tạo `PermanentCandidateSyncData` với candidate/job/file IDs và `PermanentCandidateFormSnapshotData`.
2. `SyncPermanentCandidateToMatchMakerJob` nhận DTO và dùng các field cần thiết để generate form, sync MatchMaker và hoàn tất candidate.
3. Job ghi log failure bằng các định danh có trong payload hoặc form vừa tạo.

### 4.2. Business Rules

- Giữ lại trong `PermanentCandidateSyncData` các field đang được job/service sử dụng: `candidateId`, `jobId`, `cvFileId`, `snapshot`, `agreementFileId`.
- Loại bỏ `profile`, `answers` và `loadedQuestionCategories` vì không còn được đọc trong production flow.
- Loại bỏ `permanentFormFileId` khỏi DTO nếu log failure có thể dùng `generatedFormFileId`; không thay đổi behavior tạo/reuse form.
- Giữ nguyên toàn bộ field của `PermanentCandidateFormSnapshotData`, bao gồm file IDs, vì `toArray()` và fingerprint hiện phụ thuộc vào chúng.
- Xóa các DTO chuẩn bị dữ liệu MatchMaker nếu sau khi dọn DTO không còn production consumer.

### 4.3. Side Effects

Không có side effect mới. Job dispatch, upload MatchMaker và trạng thái candidate giữ nguyên.

## 5. Data Origin & Call Chain

```text
PermanentCandidateIntakeService::submit()
  → new PermanentCandidateSyncData(...)
  → SyncPermanentCandidateToMatchMakerJob
    → PermanentCandidateIntakeService::generatePermanentCandidateForm($data)
    → MatchMakerService::syncPermanentCandidate(...)
    → PermanentCandidateIntakeService::completePermanentCandidate(...)
```

| Field / DTO | Nguồn | Consumer đã xác nhận |
|-------------|-------|---------------------|
| `candidateId`, `jobId`, `cvFileId`, `agreementFileId` | `PermanentCandidateIntakeService::submit()` | Job và MatchMaker sync |
| `snapshot` | Payload submit → `PermanentCandidateFormSnapshotData::fromArray()` | Generate PDF, fingerprint, form reuse |
| `profile`, `answers`, `loadedQuestionCategories` | TestCommand/test fixture của flow cũ | Không có production consumer |
| `permanentFormFileId` | Chỉ fixture/failure-log fallback | Không được set trong production dispatch |
| `PreparedMatchMakerProfile`, `PreparedMatchMakerAnswer` | TestCommand/test fixture cũ | Không có production consumer |

## 6. Constants & Enums

N/A — không thêm magic value hoặc thay đổi constant.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa/xóa

| File | Thay đổi |
|------|----------|
| `app/Dto/PermanentCandidateSyncData.php` | Giảm constructor về các field cần cho job hiện tại. |
| `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php` | Cập nhật failure log nếu bỏ `permanentFormFileId` khỏi DTO. |
| `app/Console/Commands/TestCommand.php` | Bỏ build/import profile không còn được job sử dụng. |
| `tests/Unit/Services/MatchMakerPermanentSyncTest.php` | Cập nhật fixture và assertion theo DTO mới; không tạo dữ liệu prepared thừa. |
| `app/Dto/PreparedMatchMakerProfile.php` | Đã xóa; không còn reference. |
| `app/Dto/PreparedMatchMakerAnswer.php` | Đã xóa; không còn reference. |

## 8. Test Cases

- Cập nhật các test đang khởi tạo `PermanentCandidateSyncData` với field đã loại bỏ.
- Giữ coverage cho job generate form, upload MatchMaker, retry/failure logging và idempotent form reuse.
- Chạy kiểm tra reference để bảo đảm không còn import hoặc call tới hai DTO prepared đã xóa.
- Chạy `./vendor/bin/phpunit` và yêu cầu toàn bộ test pass.
- Chạy `git diff --check` và PHP lint cho các file PHP đã sửa.

**Kết quả thực hiện**:

- `PermanentCandidateSyncData` còn `candidateId`, `jobId`, `cvFileId`, `snapshot` và `agreementFileId`.
- Job failure log dùng `generatedFormFileId`, không còn đọc field `permanentFormFileId`.
- `TestCommand` không còn query/build profile prepared.
- Không còn reference tới `PreparedMatchMakerProfile`, `PreparedMatchMakerAnswer`, `profile`, `answers`, `loadedQuestionCategories` hoặc `permanentFormFileId` trong DTO flow.
- PHP lint và `git diff --check` đều pass.
- Affected tests: 105 pass.
- Full suite: `OK (612 tests, 9281 assertions)`.

## 9. Acceptance Criteria

- `PermanentCandidateSyncData` chỉ còn payload cần thiết cho flow production hiện tại.
- Không còn DTO/field prepared data cũ được tham chiếu trong `app` hoặc `tests`.
- Snapshot PDF, fingerprint, file reuse và MatchMaker sync không đổi behavior.
- TestCommand vẫn chạy được với cùng input CLI.
- Full PHPUnit pass và không có whitespace error.

## 10. Checklist trước khi triển khai

- [x] Đã trace call chain từ service → job → MatchMaker.
- [x] Đã xác nhận không có API contract/API docs thay đổi.
- [x] User approve plan này.
- [x] Cập nhật code sau khi plan được approve.
- [x] Cập nhật test và chạy full PHPUnit.
