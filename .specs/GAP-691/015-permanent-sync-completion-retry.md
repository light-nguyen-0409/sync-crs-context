# SPEC: Permanent Sync Completion Retry and Duplicate Prevention

> **Trạng thái**: `IMPLEMENTED`
> **Ngày tạo**: 2026-10-09
> **Author**: Codex
> **Related**: [012 — Direct permanent sync validation](012-direct-permanent-sync-validation.md), [013 — Permanent sync test coverage](013-permanent-sync-test-coverage.md)

## 1. Tổng quan

Sau khi `MatchMakerService::syncPermanentCandidate()` hoàn tất, Job mới gọi `completePermanentCandidate()` để set `candidates.is_permanent`. Nếu completion ném `PermanentCandidateSyncStateException`, Job hiện tại gọi `$this->fail()` ngay. MatchMaker đã có candidate và local `match_maker_status` đã là `perm`, nhưng `is_permanent` vẫn `false`; candidate có thể submit lại và tạo thêm side effects bên MatchMaker.

Plan này tách rõ trạng thái “đã sync MatchMaker, cần hoàn tất local state” khỏi nhánh sync ban đầu, cho phép retry completion mà không gọi lại MatchMaker, đồng thời chặn submit mới khi local MatchMaker marker đã ở trạng thái permanent.

**Yêu cầu gốc**: Review comment về việc `completePermanentCandidate()` thất bại sau MatchMaker sync thành công làm Job fail vĩnh viễn và cho phép duplicate submission.

## 2. Database Design

N/A — không thêm bảng, cột hoặc migration. Tận dụng các field hiện có:

- `candidates.match_maker_status`
- `candidates.match_maker_people_number`
- `candidates.is_permanent`

Không tạo `permanent_candidate_submissions` hoặc bảng sync-state mới.

## 3. API Contract

### 3.1. Đánh giá ảnh hưởng contract

Endpoint bị ảnh hưởng về business guard:

- `POST /api/candidate/me/permanent-intake`

Không thay đổi route, request fields, response schema, HTTP 202 pending response hoặc error key hiện có. Candidate có `match_maker_status = Candidate::MM_STATUS_PERM` và `match_maker_people_number` sẽ nhận lại lỗi conflict hiện có giống candidate đã `is_permanent`.

`~/projects/crs-api-docs`: **N/A — không thay đổi public API contract hoặc API documentation**.

## 4. Business Logic (Service/Job Layer)

### 4.1. Flow sau thay đổi

1. Job acquire candidate lock.
2. Nếu `is_permanent = true`, kết thúc như hiện tại.
3. Nếu candidate đã có local MatchMaker permanent marker (`match_maker_status = perm` và có `match_maker_people_number`), bỏ qua generate form và MatchMaker sync; chỉ chạy completion.
4. Nếu chưa có marker, generate/reuse form, sync MatchMaker và trong cùng lần `handle()` gọi tiếp `completePermanentCandidate()`; đây không phải queue state mới.
5. `completePermanentCandidate()` set `is_permanent = true`.
6. Nếu completion thất bại sau khi MatchMaker marker đã tồn tại, exception được để queue worker retry; ở lần `handle()` kế tiếp, Job đọc marker bền vững trong Candidate và chỉ chạy completion, không gọi lại MatchMaker.
7. Nếu lỗi xảy ra trước khi MatchMaker sync hoàn tất, giữ policy terminal hiện tại cho lỗi state/non-retryable tương ứng.
8. Submit từ chối candidate đã có `is_permanent` hoặc MatchMaker permanent marker bằng error conflict hiện có.

### 4.2. Retry và failure classification

- Không gọi `$this->fail()` cho lỗi completion khi MatchMaker đã sync thành công; để exception thoát ra để queue retry theo `maxExceptions` và `retryUntil` hiện tại.
- Lỗi generate/ownership/file state trước MatchMaker sync tiếp tục fail theo policy hiện tại.
- Lỗi MatchMaker non-retryable tiếp tục fail ngay.
- Candidate/job không còn trong completion path được retry theo policy queue nhưng không tạo thêm MatchMaker side effect; sau khi vượt retry limit sẽ có failure log để manual reconciliation.
- Phải rà soát riêng failure boundary cuối `MatchMakerService::syncPermanentCandidate()`: external calls đã hoàn thành nhưng local MM status update thất bại cũng là partial-sync risk. Nếu không thể giải quyết trong scope không có sync-state table, ghi rõ limitation và không tuyên bố exactly-once.

### 4.3. Submit guard

Tạo private/service helper dùng chung cho Job và submit hoặc named Service method phù hợp để xác định MatchMaker permanent marker, tránh copy điều kiện status/people number ở nhiều nơi. Helper không được query trong loop và phải dùng constant `Candidate::MM_STATUS_PERM`.

## 5. Data Origin & Call Chain

```text
POST /api/candidate/me/permanent-intake
  → PermanentCandidateIntakeController::submit()
  → PermanentCandidateIntakeService::submit()
    → existing is_permanent guard
    → new MatchMaker permanent marker guard
    → dispatch SyncPermanentCandidateToMatchMakerJob

SyncPermanentCandidateToMatchMakerJob::handle()
  → isPermanentCandidate()
  → isMatchMakerPermanentMarker()
  → [generate form + sync MatchMaker] only when marker is absent
  → completePermanentCandidate()
```

| Dữ liệu | Nguồn | Cách dùng |
|---------|-------|-----------|
| `candidate.is_permanent` | Candidate repository | Skip Job hoặc reject submit khi đã hoàn tất local |
| `candidate.match_maker_status` | Candidate repository | Marker đã đăng ký permanent ở MatchMaker |
| `candidate.match_maker_people_number` | Candidate repository | Xác nhận marker có định danh MM thực tế |
| `candidate_id`, `job_id` | Existing Job DTO | Scope ownership, form, completion |
| `PermanentCandidateSyncData::snapshot` | Submit payload | Chỉ generate/reuse form khi cần; không thay đổi snapshot |

## 6. Constants & Enums

- Reuse `Candidate::MM_STATUS_PERM`.
- Reuse existing permanent intake conflict, completion failure, sync-state và Job retry constants.
- Không thêm magic status string hoặc retry duration mới.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A — không tạo class mới nếu helper có thể đặt private trong Service/Job theo contract hiện tại.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `app/Jobs/SyncPermanentCandidateToMatchMakerJob.php` | Tách nhánh sync và completion; nhận diện marker; retry completion mà không gọi lại MatchMaker; giữ terminal handling cho lỗi trước sync. |
| `app/Services/PermanentCandidateIntakeService.php` | Thêm/reuse helper xác định MatchMaker permanent marker và áp dụng guard submit. |
| `app/Contracts/Services/PermanentCandidateIntakeServiceInterface.php` | Cập nhật contract nếu helper được gọi từ Job qua interface. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Assert submit bị chặn khi local MM marker đã permanent nhưng `is_permanent=false`. |
| `tests/Feature/Api/Candidate/PermanentCandidateFormTest.php` | Cover Job completion retry: lần đầu completion fail sau MM sync, lần sau chỉ completion và cuối cùng set `is_permanent`. |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | N/A — marker behavior is covered through the Feature submit boundary; repository/unit tests are not added for this change. |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật async failure/retry boundary và marker behavior sau khi implementation pass. |

## 8. Test Cases

- MM sync thành công, completion ném `PermanentCandidateSyncStateException`, Job không gọi `fail()` ngay.
- Retry sau completion failure không gọi lại `generatePermanentCandidateForm()` hoặc `syncPermanentCandidate()` khi candidate đã có MM marker.
- Completion retry thành công set `is_permanent=true`.
- Submit bị từ chối khi `is_permanent=false` nhưng `match_maker_status=perm` và `match_maker_people_number` có giá trị.
- Candidate đã `is_permanent=true` tiếp tục skip Job như hiện tại.
- Generate/ownership/file state failure trước MM sync vẫn theo terminal policy hiện tại.
- MatchMaker non-retryable rejection vẫn không chạy completion.
- Lock release và failure log vẫn giữ đúng identifiers.
- Test phải bắt đầu từ queued DTO/real submit boundary hoặc verified Job fixture; không gọi MatchMaker thật.
- Chạy affected suites và full `./vendor/bin/phpunit`.

## 9. Acceptance Criteria

- Completion failure sau MM sync không làm mất cơ hội retry local completion.
- Retry không đăng ký candidate/upload CV, Agreement hoặc form lần thứ hai.
- Candidate không thể submit lại trong khoảng local `is_permanent=false` nhưng MM marker đã permanent.
- Các lỗi trước MM sync và MM non-retryable không bị biến thành retry vô hạn.
- Không thêm bảng/migration/API field mới.
- Business spec phản ánh đúng failure boundary và không tuyên bố exactly-once vượt quá khả năng hiện tại.
- Full PHPUnit pass.

## 10. Checklist trước khi triển khai

- [x] Đã trace Job → MatchMaker sync → completion → submit guard.
- [x] Đã xác nhận không thay đổi public API schema/docs.
- [x] User approve plan này.
- [x] Implement retry/marker flow.
- [x] Cập nhật tests và business spec.
- [x] Chạy affected tests và full PHPUnit.

## 11. Implementation Record

- **Code**: `SyncPermanentCandidateToMatchMakerJob` now keeps terminal handling around the pre-sync stage only. Completion exceptions escape to the queue retry path; an existing Candidate MatchMaker permanent marker makes later attempts completion-only.
- **Guard**: `PermanentCandidateIntakeService::submit` rejects both `is_permanent` and the existing MatchMaker permanent marker with the current conflict error.
- **Tests**: Affected Permanent Candidate suites pass 102 tests. Full `vendor/bin/phpunit --no-coverage` passes **614 tests / 9,303 assertions**. The suite logs expected offline `api.pwnedpasswords.com` connection errors from existing password-validation tests but remains green.
- **API/docs**: No route, request/response schema, or API documentation change; `~/projects/crs-api-docs` is N/A.
- **Residual limitation**: If external MatchMaker calls succeed but the final local MatchMaker marker update inside `syncPermanentCandidate()` fails, the existing fields cannot prove the external post-state. This remains a partial-sync/manual-reconciliation risk because this scope intentionally adds no durable submission-state table.
