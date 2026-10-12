# SPEC: GAP-691 — Trả kết quả ngay khi đồng bộ Candidate Permanent với MatchMaker lỗi

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex

## 1. Tổng quan

Thay đổi luồng Permanent intake để không tự dispatch queue job khi direct MatchMaker sync lỗi. Sau khi dữ liệu đã commit, hệ thống chỉ gọi MatchMaker một lần và trả thông báo/kết quả lỗi ngay cho client.

**Yêu cầu hiện tại**: Khi submit đã lưu GAP nhưng sync Candidate Permanent với MatchMaker lỗi, bỏ qua fallback job và trả error hiện tại `permanentMatchMakerSyncFailed` (`502`). Không thêm API resync hoặc retry flow mới trong scope này.

### 1.1. Phạm vi cần user xác nhận

- Không thêm endpoint resync/manual retry trong task này; yêu cầu trước về input `candidate_id` + `job_id` không còn áp dụng cho implementation hiện tại.
- Job class hiện tại không bị xóa; chỉ loại bỏ runtime dispatch khỏi submit để không phá queued payload/worker đang tồn tại.
- Persistence vẫn hoàn tất trước khi gọi MatchMaker; lỗi sync không rollback dữ liệu đã lưu.

## 2. Database Design

N/A. Không tạo migration, bảng sync state, retry history hoặc cột mới. Dùng các bảng và cột hiện có.

## 3. API Contract

### 3.1. Existing submit behavior

`POST /api/candidate/me/permanent-intake` giữ nguyên request và persistence contract.

- GAP data vẫn commit trước khi gọi MatchMaker.
- Direct sync success vẫn trả `200`.
- MatchMaker transient/non-retryable failure không dispatch queue; service log rồi throw Candidate `APIErrorException` với key `permanentMatchMakerSyncFailed` (`502`), framework render Candidate `Status`.
- Không còn trả `202 queued` hoặc `503 queue_failed` từ flow này.
- Không có endpoint resync mới; client nhận ngay kết quả của lần gọi hiện tại.

## 4. Business Logic (Service Layer)

### 4.1. Submit flow sau thay đổi

1. Candidate submit được validate và persistence như hiện tại.
2. Sau commit, gọi `MatchMakerService::syncPermanentCandidate()` trực tiếp.
3. Nếu lỗi MatchMaker, ghi error log chứa Candidate/job/file IDs và throw Candidate API error `permanentMatchMakerSyncFailed`.
4. Không gọi `SyncPermanentCandidateToMatchMakerJob::dispatch()`.
5. Candidate exception renderer trả `permanentMatchMakerSyncFailed` ngay.

### 4.2. Business rules

- Không tạo transaction mới và không gọi external API trong transaction.
- Không tự retry lồng nhau, không dispatch queue và không thêm resync API.
- Không thay đổi payload hoặc mapping của MatchMaker.

### 4.3. Side effects

| Loại | Trigger | Mô tả |
|---|---|---|
| MatchMaker | Submit success path | Register/update Candidate Permanent và upload CV theo flow hiện có |
| Database | MatchMaker success | `MatchMakerService` cập nhật `match_maker_people_number` và `match_maker_status = PERM` |
| Log | Sync failure | Ghi Candidate/job/file IDs và lỗi MatchMaker |

## 5. Data Origin & Call Chain

### 5.1. Submit

```
POST /api/candidate/me/permanent-intake
  → PermanentCandidateIntakeController::submit()
    → PermanentCandidateIntakeRequest::validated()
    → PermanentCandidateIntakeService::submit()
      → DB writes
      → MatchMakerService::syncPermanentCandidate()
      → Candidate API error `permanentMatchMakerSyncFailed`; không dispatch job
```

| Biến / Key | Nguồn cung cấp |
|---|---|
| `candidateId` | Candidate hiện tại từ authenticated user |
| `jobId` | `job_id` đã validate trong submit request |
| `fileId` | CV đã resolve trong submit flow |

## 6. Constants & Enums

Không thêm magic status/type. Reuse:

- Existing `MatchMakerTransientException` và `MatchMakerNonRetryableException`
- Existing API error key `permanentMatchMakerSyncFailed`

## 7. Files cần sửa

| File | Thay đổi |
|---|---|
| `app/Services/PermanentCandidateIntakeService.php` | Bỏ import/dispatch `SyncPermanentCandidateToMatchMakerJob`; khi MatchMaker lỗi throw Candidate API error ngay |
| `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php` | Bỏ response branch `queue_failed` nếu không còn được service trả về |
| `config/api.php` | Bỏ error key `permanentMatchMakerQueueFailed` vì submit không còn queue failure response |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật SPEC-039: không còn queue fallback hoặc resync API; submit trả lỗi ngay khi sync thất bại |
| `.business-spec/backend-api-route-inventory.md` | Xác nhận không thêm route mới và cập nhật response behavior của Permanent intake nếu inventory đang mô tả queue fallback |
| `.specs/GAP-691/GAP-691-implementation-plan.md` | Ghi amendment thay đổi từ queue fallback sang trả kết quả ngay |
| `documents/Gap-API-Candidate.yaml` | Bỏ response `202/503` và trạng thái `queued` khỏi contract Permanent intake |
| Tests liên quan | Cập nhật submit failure expectation: không dispatch job, trả `502` |

Không tạo controller/FormRequest/route mới. Không sửa `MatchMakerService` payload/mapping hoặc xóa `SyncPermanentCandidateToMatchMakerJob.php` trong scope này.

## 8. Test Cases

- Submit transient MatchMaker failure: GAP data đã lưu, không dispatch job, trả `502`.
- Submit non-retryable MatchMaker failure: GAP data đã lưu, không dispatch job, trả `502`.
- Submit success: gọi MatchMaker một lần và trả `200` như hiện tại.
- Existing validation, conflict và persistence cases tiếp tục pass.

## 9. Checklist hoàn tất

- [x] Không thêm endpoint resync/manual retry.
- [x] Submit không còn dispatch queue fallback.
- [x] MatchMaker failure được trả ngay bằng `permanentMatchMakerSyncFailed` (`502`).
- [x] Job class chỉ bị bỏ dispatch, không bị xóa.
- [x] Business specs và master plan được cập nhật sau implementation.
