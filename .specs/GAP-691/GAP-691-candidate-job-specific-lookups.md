# SPEC: GAP-691 — CandidateJob repository specific lookups

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex

## 1. Tổng quan

Rà soát các thay đổi của GAP-691 để loại bỏ việc gọi generic
`CandidateJobRepository::firstByFilter()` cho lookup theo cặp
`candidate_id`/`job_id`. Thay bằng method có tên và contract cụ thể, giúp thể
hiện rõ lookup một bản ghi và giữ đúng phân lớp Repository.

**Yêu cầu gốc**: Không dùng `candidateJobRepository->firstByFilter([...])` trong
code GAP-691; dùng `findBy...` cho một bản ghi và các method `getBy...` hiện có
cho collection.

## 2. Database Design

N/A. Không thay đổi schema, migration, index hoặc relationship.

## 3. API Contract

N/A. Không thay đổi route, request, response, status code hoặc validation.

## 4. Business Logic (Service/Repository Layer)

### 4.1. Phạm vi lookup

- Thêm `CandidateJobRepositoryInterface::findByCandidateIdAndJobId(int $candidateId, int $jobId): ?Model`.
- Implement method trong `CandidateJobRepository` bằng query trực tiếp trên
  `candidate_jobs`, với hai điều kiện `candidate_id` và `job_id`, rồi lấy một
  record đầu tiên.
- Không implement method cụ thể bằng cách gọi ngược lại `firstByFilter()`.
- Giữ `getByCandidateIdAndBranchId()` hiện có cho các use case trả nhiều
  `CandidateJob`; không thêm method `getByCandidateIdAndJobId()` nếu không có
  caller GAP-691 cần collection, tránh thêm contract không được sử dụng.

### 4.2. Call sites cần thay

- `PermanentCandidateIntakeService::getOwnedCandidateJob()` dùng
  `findByCandidateIdAndJobId()`.
- `MatchMakerService::syncPermanentCandidate()` dùng
  `findByCandidateIdAndJobId()`.
- Không thay các `firstByFilter()` thuộc domain khác hoặc các flow cũ ngoài
  phạm vi GAP-691.

### 4.3. Business rules/invariants

- Lookup phải giữ nguyên ownership condition: candidate và job phải cùng nằm
  trên một `candidate_job` record.
- Không đổi exception/error response khi record không tồn tại.
- Method lookup một bản ghi trong contract và implementation phải dùng return
  type `?Illuminate\Database\Eloquent\Model` theo convention của project.
- Repository chỉ chứa query data access; không đưa business rule vào method mới.

### 4.4. Rule kiến trúc áp dụng cho các thay đổi sau này

- Khi điều kiện query là tổ hợp field cố định, có ý nghĩa nghiệp vụ và được
  gọi lặp lại, Repository Contract/Implementation phải expose method có tên cụ
  thể thay vì để Service gọi `firstByFilter()`/`getByFilter()` trực tiếp.
- Dùng tiền tố `findBy...` cho lookup một bản ghi (semantics `first`) và
  `getBy...` cho lookup nhiều bản ghi (semantics collection).
- Generic `firstByFilter()`/`getByFilter()` chỉ giữ cho filter động hoặc use
  case không có điều kiện truy vấn ổn định; không dùng cho lookup cố định đã có
  thể đặt tên.
- Rule này sẽ được bổ sung vào `AGENTS.md` để áp dụng cho các task backend sau
  này, không chỉ GAP-691.

## 5. Data Origin & Call Chain

```
POST /api/candidate/me/permanent-intake
  → PermanentCandidateIntakeController::submit()
    → PermanentCandidateIntakeRequest::validated()
    → PermanentCandidateIntakeService::submit()
      → getOwnedCandidateJob()
        → CandidateJobRepositoryInterface::findByCandidateIdAndJobId()

PermanentCandidateSubmittedEvent
  → SyncPermanentCandidateToMatchMakerListener
    → MatchMakerService::syncPermanentCandidate()
      → CandidateJobRepositoryInterface::findByCandidateIdAndJobId()
```

| Biến/điều kiện | Nguồn | Confirmed? |
|---|---|---|
| `$candidateId` | Candidate token trong intake service hoặc event payload | ✅ |
| `$jobId` | `PermanentCandidateIntakeRequest::validated()` hoặc event payload | ✅ |
| CandidateJob ownership | `candidate_jobs.candidate_id` + `candidate_jobs.job_id` | ✅ |
| Collection lookup theo branch | `CandidateJobRepository::getByCandidateIdAndBranchId()` hiện có | ✅ |

## 6. Constants & Enums

N/A. Không thêm magic value hoặc enum.

## 7. Files cần sửa

| File | Thay đổi |
|---|---|
| `app/Contracts/Repositories/CandidateJobRepositoryInterface.php` | Khai báo `findByCandidateIdAndJobId()` với return type `?Model`. |
| `app/Repositories/CandidateJobRepository.php` | Implement lookup cụ thể bằng query `where(...)->where(...)->first()`. |
| `app/Services/PermanentCandidateIntakeService.php` | Thay call `firstByFilter()` tại helper ownership. Giữ nguyên business behavior. |
| `app/Services/MatchMakerService.php` | Thay call `firstByFilter()` trong Permanent sync. Giữ nguyên failure mapping. |
| `AGENTS.md` | Bổ sung rule dùng method Repository cụ thể: `findBy...` cho một record và `getBy...` cho collection; giới hạn dùng generic filter methods. |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Cập nhật mock expectation sang method cụ thể; bổ sung coverage cho candidate-job lookup failure nếu cần theo test hiện tại. |
| `tests/Unit/Services/MatchMakerPermanentSyncTest.php` | Cập nhật mock expectation sang method cụ thể. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Đồng bộ expectation thiếu CV với error contract hiện tại (`404`), không đổi runtime behavior. |

## 8. Test Cases

- Permanent intake service gọi `findByCandidateIdAndJobId()` với đúng
  `candidate_id`/`job_id` và vẫn trả lỗi hiện tại khi không tìm thấy.
- MatchMaker Permanent sync gọi cùng method cụ thể và giữ nguyên payload,
  exception mapping, `PERM` status.
- Không còn call site GAP-691 nào dùng
  `candidateJobRepository->firstByFilter([...])`.
- Chạy test bị ảnh hưởng và toàn bộ `./vendor/bin/phpunit` sau khi code xong.

## 9. Self-check trước khi hoàn thành

- [x] Contract và implementation có method cụ thể, đúng return type single-record.
- [x] Rule lookup cụ thể đã được ghi vào `AGENTS.md`.
- [x] Không thêm query vào loop hoặc transaction read.
- [x] Không thay đổi API/business behavior ngoài lookup.
- [x] Không sửa các thay đổi không liên quan trong working tree.
- [x] Test audit đã cập nhật các caller/test liên quan.
- [x] Affected suites pass; kết quả full suite và failure ngoài phạm vi được ghi nhận bên dưới.

## 10. Implementation evidence

- Đã thêm `findByCandidateIdAndJobId()` vào Contract/Repository với return type
  `?Model`, và thay hai call site GAP-691 đang dùng `firstByFilter()`.
- Đã bổ sung rule named query vào `AGENTS.md`: `findBy...` cho một record,
  `getBy...` cho collection; giữ nguyên các rule hiện hành khác.
- Không thay đổi schema, API runtime, transaction boundary hoặc business
  behavior ngoài cách gọi lookup.
- Affected tests pass: `PermanentCandidateIntakeServiceTest` (4 tests/60
  assertions), `MatchMakerPermanentSyncTest` (1/13),
  `PermanentCandidateIntakeTest` (8/118).
- Full `./vendor/bin/phpunit` với `LOG_CHANNEL=single`: 518 tests, 2341
  assertions; còn 1 failure ngoài phạm vi lookup tại
  `SyncPermanentCandidateToMatchMakerJobTest::testHandleLetsSyncFailureEscapeSoQueueRetriesIt`.
  Test này đang kỳ vọng exception thoát ra, trong khi implementation hiện tại
  của job gọi `$this->fail($exception)`; không phát sinh từ thay đổi này.
