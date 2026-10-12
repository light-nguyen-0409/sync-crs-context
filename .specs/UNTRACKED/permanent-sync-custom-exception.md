# SPEC: Replace ServerSideException in Permanent MatchMaker sync

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex

> **Superseded follow-up**: Plan `permanent-flag-after-matchmaker-success.md` thay đổi riêng precondition `is_permanent=true` của Permanent intake: candidate pending được phép sync, và chỉ được set cờ sau khi MatchMaker thành công. Exception taxonomy và các local state guards còn lại của plan này vẫn giữ nguyên.

## 1. Tổng quan

Trước thay đổi, `MatchMakerService::syncPermanentCandidate()` ném `ServerSideException` cho
các lỗi local state/precondition của Permanent candidate. Exception này không được
`PermanentCandidateIntakeService` bắt và không đi qua Candidate API error contract;
đồng thời queued job cũng không phân loại được để dừng retry.

Mục tiêu là thay bằng custom `PermanentCandidateSyncStateException`, giữ nguyên
business behavior và response contract, nhưng phân loại rõ local state failure là
lỗi non-retryable.

**Yêu cầu gốc**: Không dùng `ServerSideException` cho lỗi nghiệp vụ/state trong
`syncPermanentCandidate`; sử dụng custom exception.

**Phạm vi**: Exception classification, API mapping, queue retry classification,
tests và living business spec. Không thay đổi payload MatchMaker, route, schema,
transaction order hoặc event boundary đã refactor trước đó.

## 2. Database Design

N/A. Không tạo migration, không đổi bảng, cột, index hoặc relationship.

## 3. API Contract

Không thay đổi request/route/success payload. Regression scope:

```text
POST /api/candidate/me/permanent-intake
```

**Auth/Middleware**: Giữ nguyên route hiện tại: Candidate authentication,
profile-lock check và response normalization.

### 3.1. Error behavior

- Local Permanent sync state failure xảy ra sau khi GAP đã commit.
- `PermanentCandidateIntakeService` bắt `PermanentCandidateSyncStateException`
  cùng nhóm sync failures hiện tại.
- API tiếp tục trả `permanentMatchMakerSyncFailed` với HTTP `502`, không leak
  internal exception/message ra client và không rollback dữ liệu GAP đã commit.
- MatchMaker 4xx tiếp tục dùng `MatchMakerNonRetryableException`.
- MatchMaker timeout/network/5xx tiếp tục dùng `MatchMakerTransientException`.

## 4. Business Logic (Service Layer)

### 4.1. Exception taxonomy sau thay đổi

| Nhóm lỗi | Exception | Retry? | API result |
|---|---|---:|---|
| Candidate/job/candidate-job/file/address/branch state không hợp lệ hoặc local status update không thành công | `PermanentCandidateSyncStateException` | Không | `502 permanentMatchMakerSyncFailed` |
| MatchMaker từ chối request (4xx) | `MatchMakerNonRetryableException` | Không | `502 permanentMatchMakerSyncFailed` |
| MatchMaker/network/5xx failure | `MatchMakerTransientException` | Có trong legacy job; direct submit vẫn trả ngay | `502 permanentMatchMakerSyncFailed` |

### 4.2. Luồng xử lý

```text
POST /candidate/me/permanent-intake
  → PermanentCandidateIntakeService::submit()
  → dispatch PermanentCandidateSubmittedEvent (synchronous, sau commit)
  → SyncPermanentCandidateToMatchMakerListener
  → MatchMakerService::syncPermanentCandidate()
      → local state failure: PermanentCandidateSyncStateException
      → external 4xx: MatchMakerNonRetryableException
      → external transient/5xx: MatchMakerTransientException
  → listener bubble exception
  → intake service maps all sync failure classes to existing Candidate API 502
```

Các guard hiện đang dùng `ServerSideException` tại
`MatchMakerService::syncPermanentCandidate()` sẽ đổi sang custom exception:

- Candidate/job/candidate-job record không tồn tại.
- Candidate chưa có `is_permanent`.
- CV không tồn tại, sai owner hoặc sai type.
- Job branch thiếu legal entity.
- Candidate address không tồn tại.
- Không cập nhật được local MatchMaker identity/status sau sync.

`ServerSideException` ở các method khác của `MatchMakerService` không thuộc scope
và không được refactor lan sang task này.

### 4.3. Queue behavior

`SyncPermanentCandidateToMatchMakerJob` phải bắt `PermanentCandidateSyncStateException`
cùng `MatchMakerNonRetryableException` và gọi `$this->fail($exception)`, để local
state failure không bị queue retry. `MatchMakerTransientException` tiếp tục bubble
để queue retry theo behavior hiện tại.

## 5. Data Origin & Call Chain

| Biến / Key | Nguồn cung cấp | Nơi sử dụng | Confirmed? |
|---|---|---|---|
| `$candidateId` | `PermanentCandidateSubmittedEvent` từ authenticated Candidate trong intake flow, hoặc payload legacy job | `MatchMakerService::syncPermanentCandidate()` | ✅ |
| `$jobId` | Validated internal `jobs.id` trong request, hoặc payload legacy job | Job/candidate-job/branch lookup | ✅ |
| `$fileId` | CV row đã batch-validated trong intake, hoặc payload legacy job | CV lookup/ownership/type check | ✅ |
| Local state checks | Repository results trong `MatchMakerService` | Throw `PermanentCandidateSyncStateException` | ✅ |
| Direct API exception mapping | Event listener bubble → `PermanentCandidateIntakeService::submit()` | Candidate `APIErrorException` 502 | ✅ |
| Queue exception mapping | Job `handle()` receives service exception | `fail()` hoặc retry | ✅ |

Không thêm query trong loop, không thêm read query vào transaction và không gọi
external API trong transaction.

## 6. Constants & Enums

N/A. Không thêm status/type/magic value. Exception class chỉ thay đổi loại lỗi;
giữ nguyên error key/message public hiện tại của Candidate intake.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|---|---|---|
| `app/Exceptions/Services/PermanentCandidateSyncStateException.php` | `App\Exceptions\Services` | Custom non-retryable exception cho local Permanent sync state/precondition failure |

### 7.2. Files sửa

| File | Thay đổi |
|---|---|
| `app/Services/MatchMakerService.php` | Thay các `ServerSideException` trong `syncPermanentCandidate()` bằng custom exception; giữ nguyên các method khác |
| `app/Contracts/Services/MatchMakerServiceInterface.php` | Bổ sung PHPDoc `@throws` cho Permanent sync contract nếu cần để mô tả exception taxonomy |
| `app/Services/PermanentCandidateIntakeService.php` | Catch custom state exception cùng hai MatchMaker sync exceptions và giữ mapping `502` hiện tại |
| `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php` | Phân loại custom state exception là non-retryable và gọi `fail()` |
| `tests/Unit/Services/MatchMakerPermanentSyncTest.php` | Kiểm tra local state guards ném đúng custom exception |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Kiểm tra custom exception từ event boundary được map thành Candidate API error |
| `tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php` | Kiểm tra custom state failure không retry và được mark failed |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Regression HTTP `502`, GAP đã commit và không queue khi custom state exception xảy ra |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật SPEC-039 exception taxonomy và ghi rõ local state failure là non-retryable |
| `.business-spec/crs-matchmaker-crm-current-state.md` | Cập nhật Permanent flow/error classification nếu còn mô tả `ServerSideException`/queue behavior cũ |

Không sửa event/listener boundary, MatchMaker payload/mapping hoặc database schema.

## 8. Test Cases

| Test File | Scope | Mô tả |
|---|---|---|
| `tests/Unit/Services/MatchMakerPermanentSyncTest.php` | Local state guard (trước follow-up) | Các local guard dùng `PermanentCandidateSyncStateException`; precondition candidate chưa Permanent được supersede bởi plan pending-state mới |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | API mapping | Custom state exception sau commit trả `APIErrorException` với message/error key hiện tại |
| `tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php` | No retry | Custom state exception gọi `fail()` và không bubble để retry |
| same | Existing retry behavior | Transient exception vẫn bubble; MatchMaker non-retryable vẫn fail như trước |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | HTTP contract | `502`, candidate vẫn Permanent, không dispatch queue |

Sau khi implementation được approve:

```text
LOG_CHANNEL=single ./vendor/bin/phpunit
```

## 9. Checklist trước khi Approve

- [x] `syncPermanentCandidate()` không còn dùng `ServerSideException` cho local state guards.
- [x] Custom exception nằm dưới `App\Exceptions\Services`.
- [x] Direct API flow vẫn trả `502 permanentMatchMakerSyncFailed` sau commit.
- [x] Legacy job không retry local state failure.
- [x] Transient MatchMaker failure vẫn giữ retry behavior của job.
- [x] Không leak internal exception/message ra API response.
- [x] Không thay đổi MatchMaker payload/mapping hoặc event boundary.
- [x] Business spec phản ánh exception taxonomy mới.
- [x] Unit/feature tests được cập nhật và full PHPUnit pass.
- [x] Self-check code cuối cùng đối chiếu plan.
