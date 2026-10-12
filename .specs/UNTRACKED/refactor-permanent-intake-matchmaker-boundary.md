# SPEC: Refactor Permanent Candidate Intake MatchMaker dependency boundary

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex

## 1. Tổng quan

`PermanentCandidateIntakeService` hiện inject `MatchMakerServiceInterface`, trái
với rule hiện tại: Service không được inject một Service/ServiceInterface khác.
Mục tiêu là loại bỏ dependency này nhưng giữ nguyên business behavior của GAP-691:
GAP commit trước, đồng bộ MatchMaker đồng bộ ngay sau commit, thành công trả `200`,
lỗi MatchMaker trả `502`, không dispatch queue fallback.

**Yêu cầu gốc**: Refactor `PermanentCandidateIntakeService` để tuân thủ rule
Service không inject Service.

**Phạm vi**: Chỉ refactor dependency boundary và cập nhật test/spec tương ứng.
Không thay đổi schema, payload, route, error contract hoặc MatchMaker mapping.

## 2. Database Design

N/A. Không tạo migration, không đổi bảng, cột, index, relationship hoặc transaction
boundary hiện tại.

## 3. API Contract

Không thay đổi API contract. Các endpoint sau chỉ được regression-test lại:

```text
GET  /api/candidate/me/permanent-intake/config?job_id={jobId}
POST /api/candidate/me/permanent-intake
POST /api/candidate/me/jobs/{jobId}/work_finder_agreement/click
```

### 3.1. Submit behavior phải giữ nguyên

- `PermanentCandidateIntakeRequest::validated()` tiếp tục cung cấp `$data` cho
  `PermanentCandidateIntakeService::submit()`.
- Profile, address, answers và `is_permanent` được ghi trong transaction hiện tại.
- Sau commit, MatchMaker được gọi một lần theo `candidate_id`, internal `job_id`
  và CV `file_id` đã được xác minh.
- Thành công trả payload hiện tại với `submission_status = submitted`.
- `MatchMakerTransientException` hoặc `MatchMakerNonRetryableException` tiếp tục
  được log và map thành `permanentMatchMakerSyncFailed` (`502`).
- Không dispatch `SyncPermanentCandidateToMatchMakerJob` từ submit flow.

## 4. Business Logic (Service Layer)

### 4.1. Phương án được chọn: synchronous event boundary

Call chain sau refactor:

```text
PermanentCandidateIntakeController::submit()
  → PermanentCandidateIntakeRequest::validated()
  → PermanentCandidateIntakeService::submit()
      → preload/validate reads
      → transaction: GAP writes only
      → Event::dispatch(PermanentCandidateSubmittedEvent)
          → SyncPermanentCandidateToMatchMakerListener
              → MatchMakerServiceInterface::syncPermanentCandidate()
      → return success hoặc map MatchMaker exception thành API error
```

Chi tiết:

1. Tạo `PermanentCandidateSubmittedEvent` chứa ba primitive đã có nguồn gốc rõ
   ràng: `candidateId`, `jobId`, `fileId`.
2. `PermanentCandidateIntakeService` dispatch event sau khi transaction hoàn tất.
   Service không còn import hoặc inject `MatchMakerServiceInterface`.
3. Đăng ký `SyncPermanentCandidateToMatchMakerListener` trong
   `App\Events\EventRegister`, theo convention event hiện tại của project.
4. Listener inject `MatchMakerServiceInterface` và gọi đúng một lần
   `syncPermanentCandidate($candidateId, $jobId, $fileId)`.
5. Listener chạy synchronous, không implement `ShouldQueue`, để exception từ
   MatchMaker bubble ngược về `PermanentCandidateIntakeService::submit()` và giữ
   nguyên response `502`.
6. Job `SyncPermanentCandidateToMatchMakerJob` vẫn được giữ nguyên cho queued
   payload/legacy worker; submit flow không dispatch job.

### 4.2. Các phương án không chọn

- **Gọi trực tiếp `MatchMakerApiInterface` từ PermanentCandidateIntakeService**:
  không chọn vì phải di chuyển hoặc nhân bản logic mapping, validation, upload CV
  và cập nhật MM status đang nằm trong `MatchMakerService`, làm diff lớn và tăng
  nguy cơ lệch behavior.
- **Chuyển submit sang queue/job bất đồng bộ**: không chọn vì thay đổi contract
  hiện tại từ direct `200/502` sang queued response và không còn trả kết quả lỗi
  MatchMaker ngay trong request.
- **Tạo Service trung gian rồi inject vào PermanentCandidateIntakeService**:
  không hợp lệ vì vẫn vi phạm rule Service không inject Service.

### 4.3. Business rules và side effects

- Giữ nguyên ownership/file validation, transaction chỉ bao quanh writes và không
  gọi external API trong transaction.
- Event chỉ là boundary tách orchestration giữa hai service; không thêm retry,
  idempotency hoặc sync state mới.
- Không thay đổi exception class, error key, log level hoặc MatchMaker payload.

## 5. Data Origin & Call Chain

| Biến / Key | Nguồn cung cấp | Nơi sử dụng | Confirmed? |
|---|---|---|---|
| `$candidate->id` | Candidate hiện tại từ `auth()->user()` truyền vào Controller/Service | Event `candidateId` | ✅ |
| `$data['job_id']` | `PermanentCandidateIntakeRequest::validated()` | Service ownership lookup và event `jobId` | ✅ |
| `$cvFile->id` | `files[]` đã batch-load từ `FileRepositoryInterface::allByIds()` và kiểm tra ownership/type | Event `fileId` | ✅ |
| Event payload | `PermanentCandidateSubmittedEvent` | Listener | ✅ |
| MatchMaker dependency | Container resolve `MatchMakerServiceInterface` tại listener | `syncPermanentCandidate()` | ✅ |

Không thêm query trong event/listener và không đưa read query vào transaction.

## 6. Constants & Enums

N/A. Refactor sử dụng các ID runtime đã có; không thêm status/type/magic value.
Các constant hiện tại của `PermanentCandidateIntakeService` và
`MatchMakerService` được giữ nguyên.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|---|---|---|
| `app/Events/Definitions/PermanentCandidateSubmittedEvent.php` | `App\Events\Definitions` | Event synchronous mang candidate/job/CV IDs đã xác minh |
| `app/Events/Listeners/SyncPermanentCandidateToMatchMakerListener.php` | `App\Events\Listeners` | Listener inject `MatchMakerServiceInterface` và delegate sync |
| `tests/Unit/Events/Listeners/SyncPermanentCandidateToMatchMakerListenerTest.php` | `Tests\Unit\Events\Listeners` | Kiểm tra listener delegate đúng IDs và propagate exceptions |

### 7.2. Files sửa

| File | Thay đổi |
|---|---|
| `app/Services/PermanentCandidateIntakeService.php` | Bỏ `MatchMakerServiceInterface` khỏi constructor; dispatch event sau commit |
| `app/Events/EventRegister.php` | Register event/listener mới |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Cập nhật constructor/mocks; kiểm tra event dispatch và lỗi từ event vẫn map đúng |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Regression success, persistence-before-sync, `502`, no queue và response contract |
| `.business-spec/backend-business-flow-spec.md` | Ghi nhận synchronous event boundary và source listener trong SPEC-039; cập nhật event inventory nếu cần |
| `.business-spec/crs-matchmaker-crm-current-state.md` | Cập nhật call-chain reference nếu nội dung hiện tại còn mô tả Service gọi trực tiếp MatchMaker Service |

Không sửa `MatchMakerService`/`MatchMakerServiceInterface` hoặc payload/mapping của
MatchMaker trong scope refactor này.

## 8. Test Cases

| Test File | Test Method/Scope | Mô tả |
|---|---|---|
| `tests/Unit/Events/Listeners/SyncPermanentCandidateToMatchMakerListenerTest.php` | delegate | Listener gọi `syncPermanentCandidate()` đúng ba ID |
| same | exception propagation | Transient/non-retryable exception không bị nuốt |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | submit success | Event được dispatch sau persistence với đúng candidate/job/CV IDs |
| same | sync failure mapping | Exception phát ra từ event boundary vẫn log và map thành `APIErrorException` hiện tại |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | existing regression cases | Success, `502`, candidate đã được lưu trước lỗi MM, không enqueue job |
| `tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php` | legacy job regression | Job hiện tại vẫn delegate và retry/fail như trước |

Sau khi code được approve và hoàn tất, chạy các test bị ảnh hưởng rồi chạy toàn bộ:

```text
./vendor/bin/phpunit
```

## 9. Checklist trước khi Approve

- [x] `PermanentCandidateIntakeService` không còn inject Service/ServiceInterface.
- [x] Event listener là synchronous và không thêm queue/retry ngoài contract.
- [x] Controller/FormRequest/API response không đổi.
- [x] Transaction không chứa read query hoặc external call.
- [x] Không có query trong loop mới.
- [x] Existing job behavior không bị phá vỡ.
- [x] Business spec phản ánh đúng call chain mới.
- [x] Unit/feature tests được audit và toàn bộ PHPUnit pass với `LOG_CHANNEL=single`.
- [x] Self-check code cuối cùng đối chiếu từng mục của plan.
