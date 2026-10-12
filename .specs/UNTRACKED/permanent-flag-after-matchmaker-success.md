# SPEC: Mark Permanent candidate only after MatchMaker success

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex

## 1. Tổng quan

Hiện tại `PermanentCandidateIntakeService::submit()` set
`candidates.is_permanent = true` bên trong transaction lưu profile, trước khi
dispatch `PermanentCandidateSubmittedEvent` và gọi MatchMaker. Vì event listener
đang chạy đồng bộ, nếu MatchMaker lỗi thì API trả `502` nhưng cờ đã bị lưu là
`true`.

Mục tiêu là chỉ set `is_permanent = true` sau khi toàn bộ MatchMaker sync trong
cùng request hoàn tất thành công. Khi MatchMaker thất bại, profile/address/answers
vẫn giữ behavior đã thống nhất, nhưng `is_permanent` phải vẫn là `false`.

**Yêu cầu gốc**: Candidate chỉ được đánh dấu Permanent sau khi call MatchMaker
thành công.

**Phạm vi**: Thứ tự cập nhật cờ, precondition của Permanent sync, tests và living
business spec. Không đổi route, request payload, success response, database schema
hoặc event boundary synchronous hiện tại.

## 2. Database Design

Không có migration hoặc thay đổi schema. Chỉ thay đổi thời điểm ghi cột hiện có
`candidates.is_permanent`.

## 3. API Contract

### 3.1. Endpoint

```text
POST /api/candidate/me/permanent-intake
```

Giữ nguyên authentication, middleware, request validation và success payload.

### 3.2. Error behavior

| Tình huống | HTTP/API behavior | `is_permanent` sau request |
|---|---|---:|
| Profile save và MatchMaker sync thành công | Success response hiện tại | `true` |
| MatchMaker/local sync failure sau khi profile đã commit | `502 permanentMatchMakerSyncFailed` hiện tại | `false` |
| Candidate đã Permanent trước khi submit lại | Conflict error hiện tại | Giữ nguyên `true` |

Internal MatchMaker exception/message không được leak ra response.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý sau thay đổi

```text
POST /candidate/me/permanent-intake
  → PermanentCandidateIntakeService::submit()
  → transaction lưu profile/address/answers, không set is_permanent
  → dispatch PermanentCandidateSubmittedEvent (synchronous)
  → SyncPermanentCandidateToMatchMakerListener
  → MatchMakerService::syncPermanentCandidate()
      → register candidate
      → create contact log
      → upload CV
      → update MatchMaker identity/status local
  → Event::dispatch() hoàn tất không exception
  → PermanentCandidateIntakeService set is_permanent = true
  → trả success response
```

### 4.2. Business rules

- `is_permanent` không được ghi `true` trong transaction profile ban đầu.
- `syncPermanentCandidate()` phải cho phép candidate đang ở trạng thái pending
  (`is_permanent = false`) vì đây là trạng thái hợp lệ trước khi MM sync hoàn tất.
- Chỉ sau khi listener trả về thành công mới gọi repository update để set
  `is_permanent = true`.
- Nếu listener ném một trong các custom sync exceptions, intake giữ mapping `502`
  hiện tại và không thực hiện bước set cờ.
- Nếu local update set cờ thất bại sau khi MM đã thành công, ném
  `PermanentCandidateSyncStateException` để dùng mapping lỗi hiện tại; không giả
  định candidate đã Permanent.
- Không dùng queue/asynchronous result để quyết định thời điểm set cờ; event
  boundary hiện tại vẫn synchronous.

### 4.3. Side effects

| Loại | Trigger | Behavior |
|---|---|---|
| Database write | Initial transaction | Profile/address/answers; không set `is_permanent` |
| External API | Synchronous event listener | MatchMaker registration/contact log/CV |
| Database write | Sau khi event thành công | Set `candidates.is_permanent = true` |
| API error/log | Sync failure | Log và trả `502`; cờ vẫn `false` |

## 5. Data Origin & Call Chain

```text
routes/candidate.php
  → PermanentCandidateIntakeController::submit()
  → PermanentCandidateIntakeRequest::validated()
  → PermanentCandidateIntakeService::submit($candidate, $data)
      → CandidateRepository::save() trong transaction
      → Event::dispatch(PermanentCandidateSubmittedEvent)
      → SyncPermanentCandidateToMatchMakerListener::handle()
      → MatchMakerService::syncPermanentCandidate()
      → CandidateRepository::update() set is_permanent=true
  → PermanentCandidateIntakeResult
```

| Biến / field | Nguồn | Nơi dùng | Confirmed? |
|---|---|---|---|
| `$candidate` | Authenticated candidate từ controller | Initial profile save và post-MM flag update | ✅ |
| `$data` | `PermanentCandidateIntakeRequest::validated()` | Profile/address/answers | ✅ |
| `$candidate->id` | Authenticated Candidate model | Event payload và repository update | ✅ |
| `$candidate->is_permanent` | Current DB/model state | Conflict check; pending state trước MM | ✅ |
| MM completion | Synchronous event listener return | Gate để set `is_permanent=true` | ✅ |

Không thêm query trong loop, không thêm read query vào transaction và không đổi
ownership của candidate/job/file.

## 6. Constants & Enums

Không thêm magic value hoặc enum. Dùng constant/error message hiện có cho
`permanentMatchMakerSyncFailed` và state exception hiện tại.

## 7. Files cần tạo/sửa

### 7.1. Files mới

Không tạo file production mới.

### 7.2. Files sửa

| File | Thay đổi |
|---|---|
| `app/Services/PermanentCandidateIntakeService.php` | Bỏ set cờ trong transaction; set `is_permanent=true` sau synchronous MM event thành công; map lỗi update bằng custom exception hiện có |
| `app/Services/MatchMakerService.php` | Bỏ guard yêu cầu `is_permanent=true` trước sync để hỗ trợ pending candidate; giữ MatchMaker/local identity update hiện tại |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Kiểm tra failure không set cờ và success set cờ sau event |
| `tests/Unit/Services/MatchMakerPermanentSyncTest.php` | Cập nhật test để pending candidate được phép sync; giữ coverage MatchMaker update |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Failure giữ `is_permanent=false`; success set `is_permanent=true` và giữ response hiện tại |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật SPEC-039 thứ tự set cờ sau MM success |
| `.business-spec/crs-matchmaker-crm-current-state.md` | Cập nhật flow Permanent Candidate và post-condition |

Không sửa route, FormRequest, event/listener boundary, queue payload hoặc schema.

## 8. Test Cases

| Test File | Scope | Mô tả |
|---|---|---|
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Success ordering | Event/MM thành công rồi mới update `is_permanent=true` |
| same | Failure ordering | Event ném transient/non-retryable/state exception thì không update cờ |
| `tests/Unit/Services/MatchMakerPermanentSyncTest.php` | Pending state | Candidate `is_permanent=false` vẫn được sync khi đi qua Permanent intake boundary |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | HTTP failure | MM failure trả `502`, candidate vẫn `is_permanent=false`, không queue |
| same | HTTP success | Success payload không đổi và candidate trở thành Permanent sau MM success |

Sau implementation:

```text
LOG_CHANNEL=single ./vendor/bin/phpunit
```

## 9. Checklist trước khi Approve

- [x] Xác nhận vị trí hiện tại của `is_permanent=true` và desired ordering.
- [x] Không set cờ trong transaction profile ban đầu.
- [x] Pending candidate được phép đi qua synchronous MM sync.
- [x] Chỉ set cờ sau khi event/listener hoàn tất thành công.
- [x] MM failure giữ `is_permanent=false` và mapping `502`.
- [x] Success response/route/request contract không đổi.
- [x] Tests unit/feature được cập nhật.
- [x] Business spec được cập nhật.
- [x] Full PHPUnit pass.
- [x] Self-check đối chiếu plan.
