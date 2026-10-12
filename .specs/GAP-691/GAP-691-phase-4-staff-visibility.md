# SPEC: GAP-691 Phase 4 — Ẩn Permanent khỏi CRS staff surfaces

> **Trạng thái**: `SUPERSEDED BY GAP-691-permanent-filter-scope-adjustment.md`
> **Ngày tạo**: 2026-09-29
> **Author**: Codex

> Tài liệu này giữ lại thiết kế/lịch sử Phase 4 ban đầu. Phạm vi hiện hành đã được thu hẹp theo amendment được duyệt tại [GAP-691-permanent-filter-scope-adjustment.md](GAP-691-permanent-filter-scope-adjustment.md): chỉ Candidate list/filter tiếp tục loại Permanent; ID lookups và các luồng không phải list filter không bị lọc chỉ bởi `is_permanent`.

## 1. Tổng quan

Phase 4 bảo đảm Candidate có `is_permanent=true` không xuất hiện hoặc bị truy cập qua các bề mặt CRS dành cho Consultant, Compliance và Admin, gồm list/search, chi tiết theo ID, selector/nested payload, thao tác hồ sơ, export và report phía nhân viên. Việc lọc phải theo query boundary hoặc authorization phù hợp; không thêm global model scope để Candidate self-service và luồng đồng bộ nội bộ vẫn hoạt động.

**Yêu cầu gốc**: Thực hiện Phase 4 của [GAP-691 implementation plan](GAP-691-implementation-plan.md), sau Phase 1. Phase 2/3 không phải prerequisite; khi tích hợp phải tránh sửa trùng file và giữ nguyên các ngoại lệ đã nêu trong plan tổng.

## 2. Database Design

N/A. Phase 4 dùng cột `candidates.is_permanent` do Phase 1 tạo; không thêm migration/schema.

## 3. API Contract

Không thêm endpoint hoặc thay đổi payload của Candidate thường.

- Các staff list/search/selector chỉ trả Candidate có `is_permanent=false`.
- Direct staff lookup/action trên Permanent Candidate trả not-found theo policy ẩn danh hiện có.
- Nested Candidate payload và export/report phía staff không được chứa Permanent Candidate.
- Không trả `is_permanent` như một cách thay thế cho filtering.
- `/api/candidate/me*`, signup/auth, job attachment, Permanent config/click/submit/CV upload và queue/background MatchMaker/status processing tiếp tục truy cập Candidate Permanent.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý

1. Trace các route staff và operation/report surfaces trong inventory Phase 4 của plan tổng tới controller, service, repository/query và resource/export.
2. Với mỗi query trả Candidate hoặc dữ liệu có Candidate lồng bên trong, thêm điều kiện loại `is_permanent=true` tại query boundary phù hợp với authorization/branch scope hiện hữu.
3. Với direct ID endpoints, áp dụng cùng policy not-found trước khi đọc hoặc mutate hồ sơ liên quan.
4. Giữ nguyên Candidate thường, quyền/branch scope, pagination, ordering và side effects.
5. Không áp dụng filter vào self-service, queue hoặc background sync/maintenance.

### 4.2. Phạm vi bắt buộc

- Consultant và Compliance Candidate list/search/detail cùng các routes/actions lồng dưới candidate ID.
- Admin Candidate email search/detail/delete và các Candidate-bound actions/files.
- Appointments, escalated issues, SMS estimate/campaign recipient selection và các selector/operation trả hoặc nhận Candidate IDs.
- Compliance MatchMaker export, `candidates:export-signed`, Right-to-Work reports/emails và các Candidate-based report/export phía staff.
- Progress, files, history, questions/answers, notes, snapshots, missing requests, welfare/face-match và contact-log surfaces.

Mỗi action phải được trace thực tế trước khi sửa; không coi route declaration là bằng chứng duy nhất rằng payload có Candidate.

### 4.3. Quy tắc

- Không thêm global Eloquent scope.
- Không thay đổi logic authorization/branch filtering ngoài điều kiện ẩn Permanent.
- Không đặt business branching trong Repository; repository chỉ nhận/thực hiện điều kiện truy vấn data access.
- Không chạy query trong loop; không đưa GET queries vào transaction.
- Các helper nội bộ mới phải là `private`; không dùng magic string/value.

## 5. Data Origin & Call Chain

Các biến dùng để quyết định lọc phải bắt nguồn từ cột `candidates.is_permanent` trên Candidate do query/relation hiện tại tải. Từng call chain sẽ được xác nhận trong lúc implement:

```text
Staff route → Controller/action → Service hoặc pure-read Repository
  → Candidate query / related query → Resource, selector, export hoặc report
```

| Dữ liệu | Nơi dùng | Nguồn | Xác minh |
|---|---|---|---|
| `is_permanent` | Staff Candidate queries | Candidate model/database, Phase 1 | Có cột trong model; xác minh từng query trong Phase 4 |
| Candidate ID trong direct route | Staff controller/service | Route parameter | Trace lookup và bảo đảm Permanent trả not-found trước side effect |
| Candidate trong nested/export payload | Operation/report query | Candidate relation/query cụ thể | Trace từng payload/export trước khi sửa |

## 6. Constants & Enums

Không dự kiến thêm constant. Dùng field/contract Phase 1 hiện có; không hardcode status thay cho cờ `is_permanent`.

## 7. Files cần tạo/sửa

### 7.1. Files mới

Không dự kiến thêm runtime files. Có thể cần test cases mới trong các test files hiện có.

### 7.2. Files sửa

Danh sách cuối chốt sau khi trace từng call chain; phạm vi dự kiến:

| Khu vực | Files dự kiến | Thay đổi |
|---|---|---|
| Shared candidate query | `app/Services/CandidateService.php`, `app/Repositories/CandidateRepository.php` và contract nếu cần | Filter query list/search hoặc common query phù hợp; không dùng global scope |
| Staff API | Controllers/services/repositories/resources cho Consultant, Compliance, Admin Candidate actions | Loại Permanent ở list, direct lookup, nested payload và selector |
| Operations | Appointment, escalated issue, SMS/selector query surfaces | Loại Permanent khỏi staff-facing Candidate result/recipient sets |
| Exports/reports | Compliance MatchMaker export, signed Candidate export, RTW/candidate reports | Loại Permanent khỏi staff-facing output |
| Tests | Affected `tests/Feature/Api/**`, export/report suites và service/repository tests | Bao phủ không lộ Permanent và không đổi hành vi Candidate thường |

Không sửa Phase 2 files (`MatchMakerService`, MatchMaker job/contracts) hoặc Phase 3 self-service routes/services trừ khi phát hiện yêu cầu tích hợp không thể tránh; nếu phát sinh shared-file dependency, cập nhật plan để review trước khi mở rộng scope.

## 8. Test Cases

| Khu vực | Acceptance |
|---|---|
| Consultant/Compliance/Admin list và search | Permanent không xuất hiện; Candidate thường và branch scope giữ nguyên |
| Direct ID detail/actions | Permanent trả not-found; không phát sinh side effects |
| Nested payload, selector, appointment, escalated issue, SMS recipient | Không lộ hoặc chọn Permanent; Candidate thường vẫn dùng được |
| Files/progress/profile subroutes | Direct lookup chặn Permanent nhất quán |
| Export/report/email | Permanent không nằm trong staff-facing output |
| Self-service và internal sync | Vẫn truy cập được Permanent; không bị ảnh hưởng bởi filter staff |
| Regression | Chạy các suite bị ảnh hưởng và `./vendor/bin/phpunit` theo workspace rules sau khi code được duyệt và hoàn tất |

## 9. Checklist trước khi Approve

- [x] Route/query inventory được trace tới caller và response/export thực tế.
- [x] Direct ID access có not-found policy rõ ràng trước side effects.
- [x] Không có global scope; self-service và background processing được miễn lọc.
- [x] Test matrix bao phủ list/search/detail, appointment, escalated issue, SMS, report/export; Candidate thường giữ nguyên.
- [x] File ownership không xung đột với Phase 2/3.

## 10. Implementation evidence

- Shared staff Candidate queries loại `is_permanent=true`; thêm staff-only Candidate ID lookup, không đổi lookup chung cho self-service/background.
- Direct Candidate actions, nested operation lookups, appointment actions, escalated issue details, welfare checks, MatchMaker no-account selector, SMS recipients/reports, RTW summaries, MatchMaker CSV export và signed Candidate export đã lọc Permanent.
- Không thêm global model scope hoặc schema change.
- `LOG_CHANNEL=single ./vendor/bin/phpunit`: 508 tests, 2,195 assertions passed (2026-09-29).
