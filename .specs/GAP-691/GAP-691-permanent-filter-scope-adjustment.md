# SPEC: GAP-691 — Thu hẹp phạm vi lọc Candidate Permanent

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-29
> **Author**: Codex

## 1. Tổng quan

Điều chỉnh rule ẩn Candidate Permanent: chỉ loại Permanent khỏi các API/bộ lọc trả về danh sách Candidate theo tiêu chí tìm kiếm. Các luồng truy cập trực tiếp theo ID và các luồng nghiệp vụ khác không được tự động loại Candidate chỉ vì `is_permanent = true`.

**Yêu cầu gốc**: “trước mắt chỉ lọc cho bộ lọc trả về, còn các luồng khác where theo id thì k cần thêm điều kiện này”. Đây là thay đổi phạm vi so với Phase 4 GAP-691 đã triển khai.

## 2. Database Design

N/A — không thay đổi schema.

## 3. API Contract

Không đổi route, request hoặc response schema.

- API trả danh sách Candidate qua bộ lọc/search tiếp tục loại `is_permanent = true`.
- API/detail/action truy cập Candidate hoặc Escalated Issue theo ID không lọc theo `is_permanent`.

## 4. Business Logic

### 4.1. Quy tắc sau điều chỉnh

1. Giữ điều kiện `is_permanent = false` tại query trả về candidate collections từ các bộ lọc/search hiện hữu: Candidate list/search, Escalated Issue candidate list, Appointment list và danh sách ứng viên đủ điều kiện được trả về cho bộ lọc người nhận SMS.
2. Bỏ điều kiện Permanent khỏi lookup theo ID, bao gồm Candidate lookup đơn, Candidate lookup kèm relations, lookup theo danh sách ID và Escalated Issue lookup theo ID. Các controller/service dùng những lookup này không được trả not-found chỉ do Candidate là Permanent.
3. Bỏ các điều kiện Permanent khỏi những luồng không phải candidate-list filter, như aggregate/count, report, export và xử lý campaign đã tạo. Không mở rộng yêu cầu này sang hành vi riêng của Permanent intake hoặc MatchMaker sync.
4. Không thêm global Eloquent scope. Không đổi xác thực, ownership, branch authorization hay các điều kiện nghiệp vụ khác.

### 4.2. Khôi phục API lookup gốc

Các API/method chuyên biệt được thêm chỉ để gắn điều kiện `is_permanent = false` phải được xóa, không giữ lại dưới dạng wrapper không lọc:

| API thêm riêng để lọc | Caller dùng API có sẵn sau khi khôi phục |
|------------------------|------------------------------------------|
| `CandidateRepository::getStaffCandidateById()` và `CandidateService::getStaffCandidateById()` | `CandidateRepository::find()` hoặc `CandidateService::getById()` theo layer hiện hữu |
| `CandidateRepository::getStaffCandidateWithAllRelations()` | `CandidateRepository::getCandidateWithAllRelations()` |
| `CandidateRepository::getStaffCandidatesByIds()` | `CandidateRepository::getByIds()` |
| `EscalatedIssueRepository::findForStaffById()` | `EscalatedIssueRepository::find()`; `EscalatedIssueService::getById()` tiếp tục làm API service hiện hữu |

Xóa khai báo tương ứng khỏi repository/service contracts và implementation; cập nhật toàn bộ caller để dùng API gốc. Không đổi query/filter ở các method list/search. Nếu một caller cần relations khác với method gốc, dùng API gốc rồi load quan hệ như flow hiện có; không tạo lại một `Staff*`/`*ForStaff*` lookup wrapper.

### 4.3. Call chain và phạm vi source đã rà

`routes/*` → Candidate/Appointment/EscalatedIssue controllers → service → repositories. Các candidate list/search đi qua:

- `CandidateRepository::searchCandidateWithDetailAndJob()` / `buildCandidateQueryFromFilter()`
- `CandidateRepository::searchCandidateWithEscalatedIssue()`
- `CandidateRepository::getCandidatesByEmail()`
- `AppointmentRepository::searchAppointmentsWithCandidatesAndJob()`
- SMS candidate filter endpoint → `SmsService::filterPotentialReceiversFromCandidateCollection()`

Lookup theo ID được gọi rộng rãi bởi Consultant, Compliance, Admin và các thao tác Candidate cụ thể. `EscalatedIssueService` dùng `EscalatedIssueRepository::findForStaffById()` cho detail/action theo issue ID.

## 5. Data Origin & Call Chain

`routes/consultant.php`, `routes/compliance.php`, `routes/admin.php` → controller → service/repository. Candidate IDs đến từ route parameter, request đã xác thực hoặc record đã được truy vấn trước đó. Việc bỏ cờ lọc Permanent khỏi lookup không bỏ qua authorization/branch checks đang có trong các middleware/controller/services.

## 6. Constants & Enums

N/A.

## 7. Files dự kiến sửa

| File | Thay đổi |
|------|----------|
| `app/Repositories/CandidateRepository.php` | Giữ lọc trong các method list/search; bỏ khỏi lookup theo ID/IDs; bỏ khỏi query export nếu không phải list-filter endpoint |
| `app/Contracts/Repositories/CandidateRepositoryInterface.php`, `app/Contracts/Services/CandidateServiceInterface.php` | Xóa các khai báo API `getStaff*` được tạo chỉ để lọc Permanent |
| `app/Repositories/EscalatedIssueRepository.php`, `app/Contracts/Repositories/EscalatedIssueRepositoryInterface.php` | Xóa `findForStaffById()`; service quay lại dùng repository `find()` |
| `app/Services/CandidateService.php`, `app/Services/EscalatedIssueService.php`, các caller Controller/Service | Xóa service wrapper chỉ phục vụ lọc Permanent; chuyển caller về API lookup gốc tương ứng |
| `app/Repositories/CandidateJobRepository.php` | Bỏ lọc khỏi aggregate/count không phải list filter |
| `app/Repositories/AppointmentRepository.php` | Giữ lọc Permanent trong Appointment list/search |
| `app/Services/CandidateService.php` | Bỏ lọc khỏi báo cáo RTW không phải list filter |
| `app/Services/SmsService.php`, `app/Http/Controllers/Api/Consultant/SmsController.php` | Chỉ giữ lọc ở endpoint trả danh sách ứng viên theo bộ lọc; bỏ khỏi report/luồng xử lý theo Candidate IDs hoặc campaign đã tạo |
| `app/Console/Commands/ExportSignedCandidates.php` | Bỏ lọc Permanent khỏi export không phải API candidate-list filter |
| Test liên quan | Đổi kỳ vọng: list/search vẫn ẩn Permanent; lookup/detail theo ID có thể trả Permanent khi quyền truy cập hợp lệ; kiểm tra luồng report/export không bị lọc ngoài yêu cầu |
| `.specs/GAP-691/GAP-691-implementation-plan.md` | Điều chỉnh mô tả Phase 4 khỏi “ẩn khỏi mọi staff surface”, ghi rõ phạm vi mới |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật SPEC-039 thành hành vi hiện tại và ghi deviation so với quyết định Phase 4 trước đó |

> Trước khi sửa implementation, đối chiếu lại toàn bộ `where('is_permanent', false)` trong source và phân loại từng occurrence theo đúng hai nhóm: Candidate collection filter giữ; các nhóm còn lại bỏ. Không sửa `MatchMakerService` guard hoặc Permanent intake duplicate-submit guard.

## 8. Test Cases

| Test File | Kiểm tra |
|-----------|----------|
| `tests/Feature/Api/Consultant/CandidatesTest.php` | Permanent không xuất hiện trong list filter; detail bằng ID không bị chặn chỉ vì Permanent |
| `tests/Feature/Api/Compliance/CandidatesTest.php` | Tương tự cho Compliance list/detail |
| `tests/Feature/Api/Consultant/AppointmentsTest.php` | Appointment list filter vẫn loại Permanent |
| `tests/Feature/Api/Consultant/CandidateEscalatedIssuesTest.php` | Escalated Issue candidate list vẫn loại Permanent; issue detail theo ID không bị chặn riêng bởi cờ Permanent |
| Test SMS và các test report/export/count có liên quan | Xác nhận chỉ candidate filter endpoint áp dụng cờ; luồng ID/report/export không bị ảnh hưởng ngoài yêu cầu |
| Full suite | `LOG_CHANNEL=single ./vendor/bin/phpunit` |

## 9. Checklist triển khai

- [x] Phân loại các occurrence hiện có: list/search filter hay lookup/luồng khác
- [x] Giữ lọc ở Candidate/Appointment/SMS candidate-list filters
- [x] Gỡ lọc khỏi lookup ID/IDs và các luồng non-filter đã inventory
- [x] Xóa API `getStaffCandidateById`, `getStaffCandidateWithAllRelations`, `getStaffCandidatesByIds`, `findForStaffById` cùng contract; chuyển caller sang API gốc
- [x] Cập nhật/kiểm tra toàn bộ test bị ảnh hưởng
- [x] Chạy full PHPUnit: `508 tests, 2,201 assertions`
- [x] Self-check diff và source: chỉ các list/filter query cần thiết còn loại Permanent; API lookup chuyên biệt đã xóa
