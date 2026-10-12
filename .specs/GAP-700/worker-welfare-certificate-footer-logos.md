# SPEC: Worker Welfare Certificate Footer Logos

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-23
> **Author**: Codex

## 1. Tổng quan

Thêm dải logo footer cho Worker Welfare Check Certificate theo cách trình bày của Proof of Address Report: các logo thương hiệu được xếp cùng hàng và căn giữa ở cuối nội dung chứng chỉ. Các logo footer được khai báo cố định trong Blade, không bổ sung tham số từ Service. Giữ nguyên logo hiện tại ở header, nội dung chứng chỉ, bố cục khác và quy trình sinh PDF.

**Yêu cầu gốc**: Người dùng muốn Worker Welfare có footer logos như Proof of Address Report.

## 2. Database Design

N/A — không có thay đổi database.

## 3. API Contract

N/A — không có thay đổi API.

## 4. Business Logic (Service Layer)

Không thay đổi nghiệp vụ hoặc luồng tạo chứng chỉ. Blade tự tham chiếu trực tiếp các file logo tĩnh trong `storage/logos/` (Gap Personnel, Driving Force và Gap Technical); không thêm biến/parameter cho `generateCertificatePdf()`. Logo nào không có file hợp lệ thì không render. Dải logo đặt dưới phần chữ footer và căn giữa; style/kích thước theo Proof of Address Report.

## 5. Data Origin & Call Chain

```text
Worker welfare check completion
  → WorkerWelfareCheckService::generateCertificatePdf()
    → resources/views/pdf/worker_welfare_check_certificate.blade.php
      → tham chiếu các file logo tĩnh dưới storage/logos/
      → render hàng logo cuối trang
    → Dompdf render PDF
```

| Biến / dữ liệu | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|---|---|---|---|
| Logo Gap Personnel, Driving Force, Gap Technical | Footer Blade | File tĩnh `storage/logos/gap_personnel.png`, `storage/logos/driving_force.png`, `storage/logos/gap_technical.png` | ✅ Các file hiện có trong workspace; cần xác nhận khả năng truy cập phù hợp với Dompdf khi triển khai |
| Logo hiện tại ở header | Header Blade | `generateCertificatePdf()` truyền `logoBase64` hiện tại | ✅ |

## 6. Constants & Enums

Không thêm hằng số; dùng cấu hình logo hiện hữu và CSS pattern hiện có của Proof of Address Report.

## 7. Files cần tạo/sửa

### 7.1. Files mới

Không có.

### 7.2. Files sửa đổi

| File | Mô tả |
|---|---|
| `resources/views/pdf/worker_welfare_check_certificate.blade.php` | Thêm style và markup hàng logo căn giữa ở cuối certificate, tham chiếu trực tiếp các file logo tĩnh; không đổi header hiện tại. |
| Unit test liên quan tới render Worker Welfare Check Certificate | Bổ sung/cập nhật kiểm tra markup footer và các logo tĩnh nếu có test phù hợp; không cần thay đổi tham số/service mock cho logo. |

## 8. Test Plan

- Chạy các unit test hiện hữu liên quan `WorkerWelfareCheckService`.
- Unit test render Blade xác nhận hàng footer và ba logo asset hiện có được xuất ra dạng data URI.
- Điều kiện `file_exists` bỏ qua asset thiếu; đã giữ nguyên kiểm tra này trong Blade.
- Chạy toàn bộ PHPUnit theo yêu cầu workspace sau khi triển khai.

**Kết quả**: Unit test view (1 test), `WorkerWelfareCheckServiceTest` (7 tests) và toàn bộ PHPUnit (478 tests, 2086 assertions) đều pass.

## 9. Rủi ro / Ghi chú

- Blade sẽ truy cập file tĩnh dưới `storage/logos/`; cần dùng cách đọc ảnh tương thích với Dompdf và kiểm tra an toàn khi file không tồn tại.
- Không thay đổi nguồn, kích thước hoặc vị trí logo header của Worker Welfare.
