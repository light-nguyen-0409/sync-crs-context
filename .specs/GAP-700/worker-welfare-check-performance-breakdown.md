# SPEC: Worker Welfare Check Performance Breakdown Logging

> **Trạng thái**: RETIRED
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

> **Ghi chú hiện tại**: Phase timing instrumentation được mô tả trong spec này
> đã được gỡ khỏi `WorkerWelfareCheckService.php`. Timing log tổng ở
> `TestCommand` vẫn được giữ theo spec `worker-welfare-check-performance-logging.md`.

## 1. Tổng quan

Bổ sung structured log theo từng phase trong
WorkerWelfareCheckService::performCheck() để đối chiếu với tổng thời gian đã
được ghi ở TestCommand. Mục tiêu là xác định chính xác thời gian tiêu tốn ở
download ảnh, GBG face matching, render PDF, lưu file, database và MatchMaker.

**Yêu cầu gốc**: Bổ sung log thời gian ở các thành phần khác để đo từng phần
trong flow Worker Welfare Check.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

N/A — Không thay đổi API contract.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. Giữ nguyên log tổng thời gian ở TestCommand.
2. WorkerWelfareCheckService ghi timestamp trước mỗi phase cần đo.
3. Ghi structured log sau khi phase hoàn tất với:
   - phase name;
   - duration_ms;
   - candidate_id;
   - welfare_image_file_id.
4. Các phase được đo:
   - tìm file interview và welfare;
   - download interview image;
   - download welfare image;
   - gọi GBG compareTwoImages;
   - lưu face matching rate;
   - tìm branch;
   - chuẩn bị ảnh/base64 cho PDF;
   - render Blade HTML cho PDF;
   - render/output certificate bằng Dompdf;
   - lưu/upload certificate file;
   - lưu candidate welfare check;
   - sync MatchMaker;
   - gửi failure email nếu có;
   - cleanup temporary files.
5. Không thay đổi thứ tự xử lý, dữ liệu, response hoặc exception behavior.

### 4.2. Business Rules

- Log chỉ chứa metadata hiệu năng và identifier; không log nội dung ảnh, token
  hoặc PDF binary.
- Nếu một phase throw exception, các phase sau không log completed; exception vẫn
  được giữ nguyên.
- Không thêm unit test theo yêu cầu hiện tại; chỉ kiểm tra syntax và giữ nguyên
  test behavior hiện có.

## 5. Data Origin & Call Chain

    TestCommand::handle()
      → WorkerWelfareCheckService::performCheck()
        → fetch file metadata
        → downloadToTemp()
        → compareTwoImages()
        → generateCertificatePdf()
        → createFile()
        → welfareCheckRepository->create()
        → syncToMatchMaker()
        → Mail::send() khi fail
        → cleanupTempFile()

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| candidate_id | Mọi phase log | performCheck() argument | ✅ |
| welfare_image_file_id | Mọi phase log | performCheck() argument | ✅ |
| phase | Structured log | Tên phase cố định trong service | ✅ |
| duration_ms | Structured log | hrtime(true) start/end | ✅ |

## 6. Constants & Enums

N/A — Không thêm business constant. Các phase name là metadata của log.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| app/Services/WorkerWelfareCheckService.php | Thêm structured timing logs cho từng phase trong performCheck() |

TestCommand đã có log tổng thời gian và không cần sửa thêm.

## 8. Test Cases

N/A — Theo yêu cầu hiện tại không thêm hoặc cập nhật unit test cho instrumentation.

Verification:

- Chạy php -l app/Services/WorkerWelfareCheckService.php.
- Chạy TestCommand và đối chiếu các phase duration với tổng duration trong
  TestCommand.

## 9. Checklist trước khi Approve

- [x] Không thay đổi database.
- [x] Không thay đổi API contract.
- [x] Đã liệt kê đầy đủ phase cần đo.
- [x] Đã trace nguồn dữ liệu cho các field log.
- [x] Không log dữ liệu nhạy cảm.
- [x] Đã giữ nguyên business behavior.
- [x] User approve plan.
