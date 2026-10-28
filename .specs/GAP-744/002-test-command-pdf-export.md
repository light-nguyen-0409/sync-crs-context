# SPEC: GAP-744 — TestCommand Function to Export Application Pack & Timing PDF

> **Trạng thái**: `DONE`  
> **Ngày tạo**: 2026-10-27  
> **Task Key**: `GAP-744`  
> **Author**: Antigravity  
> **Nguồn yêu cầu**: User Request: "tôi muốn test xuâst pdf (có thêr thêm function trong TestCommand.php) đêr check xem, hãy sưả TestCommand ddi"  
> **Template**: [.specs/SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md)  
> **Liên kết liên quan**: [.specs/GAP-744/001-clickable-hyperlinks-application-pack-pdf.md](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-744/001-clickable-hyperlinks-application-pack-pdf.md)  

---

## 1. Tổng quan

Mục tiêu của task là bổ sung action/function vào [`TestCommand`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Console/Commands/TestCommand.php) (`app/Console/Commands/TestCommand.php`) để lập trình viên có thể chạy câu lệnh Artisan CLI và xuất trực tiếp file PDF (Application Pack hoặc Timing Log PDF) ra thư mục local (`public/` hoặc `storage/`). Từ đó dễ dàng mở và kiểm tra trực quan liên kết KID clickable ("Click here") trên file PDF thực tế.

---

## 2. Database Design

*N/A — Không thay đổi schema Database (sử dụng các bảng hiện có: `candidates`, `candidate_timings`, `jobs`, `branches`, `files`).*

---

## 3. API Contract & API Docs Pre-Deployment Gate

*N/A — no API contract/API docs change.*

Thay đổi chỉ nằm trong Artisan console command nội bộ (`TestCommand.php` - file này đã được ignore trong `.gitignore`) phục vụ việc kiểm thử cục bộ của developer; không thay đổi bất kỳ API endpoint hay schema HTTP nào.

---

## 4. Thiết kế chi tiết cho TestCommand

### 4.1. Command Signature & Options
Cập nhật signature của [`TestCommand`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Console/Commands/TestCommand.php):
```php
protected $signature = 'cmd:test
    {--action= : Action to run (e.g. short-link-mail, permanent-sync, pdf-export)}
    {--branch-id=1 : Branch ID to use}
    {--email= : Target recipient email}
    {--candidate-id= : Candidate ID to export PDF for}
    {--job-id= : Job ID to use}
    {--only-timing : Only export the Timing Log page PDF with KID link}
    {--cv-file-id=}
    {--agreement-file-id=}';
```

### 4.2. Action Routing trong `handle()`
Thêm nhánh xử lý:
```php
public const ACTION_PDF_EXPORT = 'pdf-export';

// Trong handle():
if ($action === self::ACTION_PDF_EXPORT || $action === 'export-pdf' || $action === 'pdf') {
    return $this->exportPdfTest();
}
```

### 4.3. Logic Function `exportPdfTest()`
1. **Xác định Candidate & Job**:
   - Nhận `--candidate-id` từ option; nếu không truyền, tự động truy vấn bản ghi đầu tiên có `kid_link` trong bảng `candidate_timings` (ví dụ candidate ID `4220` hoặc `4219`).
   - Nhận `--job-id` từ option; nếu không truyền, lấy `job_id` tương ứng từ `candidate_timings`.
2. **Xuất PDF Timing Log (`--only-timing` hoặc chế độ mặc định)**:
   - Sử dụng Reflection để gọi `getCandidateTimingHtml($candidate, $job)` và logic render Dompdf -> import qua `TcpdfFpdi` với `copyPageLinkAnnotations`.
   - Lưu file PDF kết quả vào thư mục `public/temp_timing_candidate_{candidateId}.pdf`.
   - Phân tích nội dung nhị phân của file PDF: kiểm tra sự tồn tại của `/Subtype /Link` và destination URL.
   - In ra đường dẫn file tuyệt đối trên máy Mac và URL local (`http://localhost:8081/temp_timing_candidate_{candidateId}.pdf`) để developer mở ngay trên trình duyệt hoặc Preview.
3. **Xuất Full Application Pack (nếu không truyền `--only-timing`)**:
   - Gọi `ApplicationPackServiceInterface::generateApplicationPack($candidateId, $branchId, 'British', 'White', [])`.
   - Copy file kết quả ra `public/temp_app_pack_{candidateId}.pdf`.
   - Nếu dữ liệu hồ sơ candidate thiếu các bản ghi phụ (như hợp đồng, ngân hàng), catch exception và tự động fallback sang xuất Timing Log PDF để developer luôn có file PDF kiểm tra mà không bị chặn bởi dữ liệu thiếu.

---

## 5. Kế hoạch kiểm thử (Verification Plan)

1. **Chạy thử nghiệm Artisan Command**:
   - Chạy lệnh test xuất Timing PDF:
     ```bash
     docker exec gap-web-backend-laravel.test-1 php artisan cmd:test --action=pdf-export --only-timing
     ```
   - Chạy lệnh test xuất full Application Pack (fallback sang Timing PDF nếu thiếu relation):
     ```bash
     docker exec gap-web-backend-laravel.test-1 php artisan cmd:test --action=pdf-export --candidate-id=4220
     ```

2. **Kết quả kiểm thử thực tế**:
   - Command thực thi thành công (Exit Code 0).
   - File PDF được sinh tại: `public/temp_timing_candidate_4219.pdf` và `public/temp_timing_candidate_4220.pdf`.
   - HTTP Status: `200 OK` tại `http://localhost:8081/temp_timing_candidate_4220.pdf`.
   - Kiểm tra cấu trúc annotation trong PDF:
     ```
     <</Type /Annot /Subtype /Link /Rect [259.915100 507.868900 319.627100 523.233700] /P 7 0 R /NM (0001-0000) /M (D:20261027042534+00'00') /F 4 /Border [0 0 0] /A <</S /URI /URI (https://issuu.com/gappersonnel/docs/01._kid_gphl_-_paye_cfs_92d9c73df83ae4)>> /H /I>>
     ```
     Toạ độ Rect hợp lệ, không bị âm; URL target chính xác và text hiển thị là `"Click here"`.
