# SPEC: GAP-691 — Permanent intake nhận danh sách files

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-29
> **Author**: Codex

## 1. Tổng quan

Thay field `file_id` trên `POST /api/candidate/me/permanent-intake` bằng mảng `files` chứa `{file_id,type}`. Candidate upload file qua endpoint file hiện có trước submit; intake xác minh các file đã tồn tại, đúng Candidate và đúng type. CV luôn bắt buộc; file `other` tùy chọn và không phụ thuộc `journey_type`.

**Yêu cầu gốc**: User muốn submit gửi danh sách `files` gồm CV và file `other` cho journey Others, thay cho một `file_id` đơn.

## 2. Database Design

Không dự kiến thay đổi schema hoặc tạo bảng liên kết mới. Các file đã được upload và persist trong `files` qua `POST /api/candidate/me/files/{type}` (`type=cv` hoặc `type=other`); submit chỉ nhận IDs và xác minh ownership/type. File records tiếp tục gắn Candidate qua `candidate_id`.

## 3. API Contract

```http
POST /api/candidate/me/permanent-intake
```

Thay request field `file_id` bằng:

```json
{
  "files": [
    { "file_id": 123, "type": "cv" },
    { "file_id": 456, "type": "other" }
  ]
}
```

Rules đề xuất:

- `files` là array; mỗi item có integer `file_id` và `type` chỉ nhận `cv` hoặc `other`.
- Mỗi type xuất hiện tối đa một lần; file ID phải thuộc Candidate đang đăng nhập và DB file `type` phải khớp request type.
- Phải có đúng một file `cv` cho mọi `journey_type`.
- File `other` là tùy chọn với mọi `journey_type`; tạm thời không kiểm tra việc có/không có file này dựa trên `journey_type`.
- Response, persisted Candidate fields, double-submit behavior và HTTP status không đổi.

## 4. Business Logic (Service Layer)

1. FormRequest validate shape, allowed types, unique type và yêu cầu CV; không ràng buộc `other` theo `journey_type`.
2. Service batch-load toàn bộ file IDs trước khi ghi Candidate; không query DB trong loop. Tạo in-memory map theo ID rồi xác minh `candidate_id`, `File::TYPE_CV` / `File::TYPE_OTHER` khớp từng item.
3. Thiếu, sai type hoặc foreign-owned file giữ not-found/validation policy hiện có cho CV; dùng cùng policy không tiết lộ file của Candidate khác cho cả `other`.
4. Permanent persistence không tạo thêm file row vì các file được upload và lưu trước submit. Chỉ CV ID tiếp tục đi vào `MatchMakerService::syncPermanentCandidate` và `SyncPermanentCandidateToMatchMakerJob`; file `other` được giữ ở GAP trên Candidate hiện tại.
5. Không upload `other` sang MatchMaker trong thay đổi này. **Decision cần review**: nếu “lưu cả file” có nghĩa gửi supporting file lên MatchMaker, phải mở rộng sync method/job/API attachment flow và cập nhật plan này trước khi code.

## 5. Data Origin & Call Chain

```text
Candidate uploads each file
  → POST /api/candidate/me/files/cv|other
  → FileService persists storage object + `files` row owned by Candidate
  → FE sends [{file_id,type}] to permanent-intake submit
  → FormRequest validates array contract
  → PermanentCandidateIntakeService batch-loads/validates submitted File records
  → Candidate/profile/answers persist; only CV ID goes to direct MM sync or queue
```

`file_id` is sourced from the existing upload response; `type` is checked against the DB row and is not treated as authoritative client data.

## 6. Constants & Enums

Use `File::TYPE_CV`, `File::TYPE_OTHER`, and `Candidate::JOURNEY_TYPE_OTHERS`; no new magic values.

## 7. Files cần sửa

| File | Thay đổi |
|---|---|
| `app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php` | Validate `files` array and conditional required item types |
| `app/Services/PermanentCandidateIntakeService.php` | Batch lookup and ownership/type checks; keep CV as MM sync file |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Cover CV-only journey, Others with both uploads, and invalid/missing/foreign files |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Cover batched file lookup and sync CV ID selection |
| `.specs/GAP-691/GAP-691-implementation-plan.md` | Update approved API contract and tests after implementation |
| `.business-spec/backend-business-flow-spec.md` | Update SPEC-039 request and file flow after implementation |

Không dự kiến sửa MatchMaker sync method/job contract hoặc schema nếu `other` chỉ được giữ ở GAP.

## 8. Test Cases / Acceptance

- Any journey type may submit one `cv` with or without one `other`; direct sync/queued job receives only the CV ID.
- Missing CV, duplicate types, unsupported type, mismatched row type, missing ID, and foreign Candidate file are rejected without persisting Permanent profile data.
- Neither file ID nor type supplied by FE can reference a different Candidate's file.
- MatchMaker API contract remains CV-only unless expanded plan is approved.
- Run affected feature/service tests and full `LOG_CHANNEL=single ./vendor/bin/phpunit` after implementation.

## 9. Checklist trước khi duyệt

- [x] User approved array contract and optional `other` file behavior (not conditional on journey type).
- [x] `other` remains stored in GAP and is not uploaded to MatchMaker.

## 10. Implementation evidence

- Request accepts `files[]`; validates one CV plus an optional distinct Other item, supported type and distinct IDs.
- Service batch-loads the submitted file IDs, checks each row's `candidate_id` and persisted type, and selects CV only for direct/queued MatchMaker sync.
- Feature coverage verifies CV+Other upload/submit, Other remains optional with `journey_type=others`, foreign file rejection and required CV. Service test verifies fallback receives only CV ID.
- Affected intake feature/service tests passed (4 tests, 27 assertions); full PHPUnit passed (508 tests, 2,201 assertions).
- No schema change or new MatchMaker job payload field.
