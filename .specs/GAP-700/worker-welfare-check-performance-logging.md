# SPEC: Worker Welfare Check Performance Logging

> **Trạng thái**: DONE
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

## 1. Tổng quan

Thêm structured log để đo thời gian chạy lời gọi Worker Welfare Check trong
app/Console/Commands/TestCommand.php. Thay đổi chỉ phục vụ observability,
không thay đổi business logic, dữ liệu hoặc response.

**Yêu cầu gốc**: Đặt log đo thời gian thực thi tại
app/Console/Commands/TestCommand.php dòng gọi service và
WorkerWelfareCheckService được giữ nguyên.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

N/A — Không thay đổi API contract.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. TestCommand ghi timestamp trước khi gọi performCheck().
2. TestCommand ghi tổng duration sau khi service hoàn tất hoặc ném exception.

### 4.2. Business rules

- Chỉ thêm log, không thay đổi thứ tự xử lý hoặc dữ liệu nghiệp vụ.
- Duration dùng milliseconds với hrtime(true) để có độ chính xác phù hợp đo performance.
- Log chứa các identifier cần thiết (candidate_id, welfare_image_file_id) nhưng không log nội dung ảnh, token hoặc dữ liệu nhạy cảm.
- Giữ nguyên dd($data) hiện tại trong TestCommand.

## 5. Data Origin & Call Chain

    cmd:test
      → TestCommand::handle()
        → performance log bắt đầu
        → WorkerWelfareCheckService::performCheck(4244, 3305, 2, ..., 1)
        → performance log kết thúc

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| candidateId | TestCommand logs | performCheck() argument | ✅ |
| welfareImageFileId | TestCommand logs | performCheck() argument | ✅ |
| startedAt | Duration calculation | hrtime(true) before service call | ✅ |
| durationMs | Structured log | Difference between timestamps | ✅ |

## 6. Constants & Enums

N/A — Không thêm business constants. Đơn vị duration được ghi rõ là
duration_ms trong log context.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| app/Console/Commands/TestCommand.php | Thêm log bắt đầu/kết thúc và tổng duration quanh lời gọi performCheck() |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
N/A — Theo yêu cầu, không thêm hoặc cập nhật unit test cho instrumentation này.

Sau khi code xong sẽ chạy test liên quan và toàn bộ ./vendor/bin/phpunit.

## 9. Checklist trước khi Approve

- [x] Không thay đổi database.
- [x] Không thay đổi API contract.
- [x] Đã xác định điểm cần đo.
- [x] Đã trace nguồn dữ liệu cho các field log.
- [x] Không log dữ liệu nhạy cảm.
- [x] Đã liệt kê test impact.
- [x] User approve plan.
