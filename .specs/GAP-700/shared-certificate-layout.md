# SPEC: Shared Certificate Layout

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-23
> **Author**: Codex

## 1. Tổng quan

Tạo một Blade layout dùng chung cho header và footer của certificate PDF, nhưng trong task này chỉ refactor và áp dụng cho Worker Welfare Check Certificate. Các certificate/report PDF cũ (bao gồm Proof of Address và Right to Work Journey Report) giữ nguyên; có thể refactor để dùng layout chung trong task riêng sau này.

**Yêu cầu gốc**: Tạo template certificate chung gồm header/footer, các template certificate khác inject phần content.

## 2. Database Design

N/A — không thay đổi database.

## 3. API Contract

N/A — không thay đổi API.

## 4. Business Logic (Service Layer)

### 4.1. Luồng render

```text
Certificate generator/service
  → truyền dữ liệu của certificate vào content view tương ứng
  → content view kế thừa shared certificate layout
  → layout render header + content section + footer
  → Dompdf render PDF
```

### 4.2. Business Rules / Presentation Contract

- Shared layout sở hữu markup/CSS của header và footer; content views không tự dựng lại hai vùng này.
- Shared layout sở hữu cấu trúc header/footer và CSS dùng chung. Content view cung cấp title/subtitle và phần nội dung riêng của Worker Welfare qua Blade sections.
- Giữ nguyên thiết kế header Worker Welfare hiện tại (tiêu đề bên trái, logo Gap Personnel bên phải); footer có hàng logo Gap Personnel, Driving Force và Gap Technical căn giữa, asset được tham chiếu cố định trong Blade.
- Câu disclaimer hiện có của Worker Welfare vẫn thuộc content certificate, không chuyển thành thông tin dùng chung trong footer.
- Không refactor hoặc thay đổi bất kỳ certificate/report PDF cũ nào trong task này; không thay đổi điều kiện tạo certificate, dữ liệu, file naming/storage, MatchMaker sync hoặc email flow.

### 4.3. Scope

- Bao gồm shared layout mới và Worker Welfare Check Certificate là consumer đầu tiên.
- Proof of Address Report và Right to Work Journey Report không được sửa trong task này; giữ nguyên output hiện tại. Việc chuyển các template đó sang layout chung là công việc refactor sau.

## 5. Data Origin & Call Chain

```text
Worker Welfare:
performWorkerWelfareCheck → WorkerWelfareCheckService::performCheck
  → GenerateWorkerWelfareCheckCertificateJob
  → processPostCheck → view('pdf.worker_welfare_check_certificate')
  → Dompdf

Các certificate/report cũ:
  → giữ nguyên generator/view hiện tại, không đổi call chain trong task này
```

| Dữ liệu | Nguồn | Nơi render | Confirmed? |
|---|---|---|---|
| Worker Welfare-specific fields | `WorkerWelfareCheckService::generateCertificatePdf()` view data | Worker Welfare content Blade | ✅ Existing call chain; verify variables during implementation |
| Header logo | `logoBase64` passed by `generateCertificatePdf()` | Shared layout header | ✅ Existing view data |
| Footer logos | Tracked files under `storage/logos/` | Shared layout Blade | ✅ Files exist in repository |
| Other certificate/report data and layouts | Existing generators/views | Existing PDFs | ✅ Out of scope; unchanged |

## 6. Constants & Enums

Không phát sinh business constants. Static logo paths và presentation CSS thuộc shared Blade layout.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Mô tả |
|---|---|
| `resources/views/pdf/layouts/certificate.blade.php` | Shared document shell, header, footer, common logo row, and content section. |
| `resources/views/pdf/worker_welfare_check_certificate_content.blade.php` | Worker Welfare content-only view kế thừa shared layout. |
| Unit test cho shared layout/content rendering | Xác nhận wrapper/header/footer và Worker Welfare content sections render đúng. |

### 7.2. Files sửa

| File | Thay đổi |
|---|---|
| `resources/views/pdf/worker_welfare_check_certificate.blade.php` | Render shared layout cùng Worker Welfare content view, hoặc giữ tên làm entry view và tách body sang content-only view; bỏ cấu trúc header/footer trùng. |
| `app/Services/WorkerWelfareCheckService.php` | Chỉ cập nhật view entry/data wiring nếu cần; giữ nguyên call chain, PDF rendering và các side effect. |
| `tests/Unit/Views/WorkerWelfareCheckCertificateViewTest.php` / `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Cập nhật test theo layout mới và xác nhận Worker Welfare data/content được render. |

## 8. Test Plan

- Test layout render header/footer chung, giữ vị trí logo header hiện tại, render footer logo assets và content sections.
- Test Worker Welfare variables/content vẫn render đúng và không lặp header/footer.
- Không cập nhật hoặc thay đổi expected output/test của Proof of Address hay Right to Work Journey Report trong task này.
- Chạy các test service/view liên quan và toàn bộ `./vendor/bin/phpunit`.
- Không chạy formatter/linters tự động.

**Kết quả**: Worker Welfare view test xác nhận header/footer và render PDF (1 test, 9 assertions); `WorkerWelfareCheckServiceTest` (7 tests, 11 assertions); toàn bộ PHPUnit pass (478 tests, 2089 assertions).

## 9. Checklist trước khi Approve

- [x] Chỉ áp dụng shared layout cho Worker Welfare Check trong task này.
- [x] Giữ nguyên các certificate/report cũ; có thể migrate sau.
- [x] Giữ nguyên bố cục header hiện tại của Worker Welfare; footer chung có hàng logo cố định.
