# SPEC: Worker Welfare Check Failure Email Configuration

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

## 1. Tổng quan

Loại bỏ recipient email hardcode khỏi `FailedWorkerWelfareCheckMail` và đưa
recipient vào cấu hình mail để có thể thay đổi theo môi trường mà không sửa code.
Giữ nguyên việc gửi email qua queue và không thay đổi subject, nội dung hoặc
attachment PDF.

**Yêu cầu gốc**: Chuyển email nhận thông báo khi Worker Welfare Check không đạt
match score từ constant sang config.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

N/A — Không thay đổi request, response hoặc endpoint.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. `WorkerWelfareCheckService::performCheck()` kiểm tra score dưới threshold.
2. Service lấy recipient từ `config('mail.worker_welfare_check_failure_email')`.
3. Service gửi `FailedWorkerWelfareCheckMail` qua flow queue hiện tại.
4. Giá trị config lấy từ `MAIL_WORKER_WELFARE_CHECK_FAILURE_EMAIL`, có fallback
   là recipient hiện tại để không làm môi trường thiếu biến bị mất email.

### 4.2. Business Rules

- Không giữ recipient email trong constant của Mailable.
- Không thay đổi điều kiện gửi email.
- Không thay đổi subject, view hoặc PDF attachment.
- Không lưu recipient vào database.
- Môi trường triển khai có thể override recipient bằng biến môi trường.

### 4.3. Side Effects

| Loại | Trigger | Mô tả |
|------|---------|-------|
| Queue Job | Score dưới threshold | Queue `FailedWorkerWelfareCheckMail` tới email trong config |
| Email | Queue worker xử lý | Gửi thông báo failure kèm PDF |

## 5. Data Origin & Call Chain

    WorkerWelfareCheckService::performCheck()
      → scorePercent < CandidateWelfareCheck::PASS_SCORE_THRESHOLD
      → config('mail.worker_welfare_check_failure_email')
      → Mail::to($configuredRecipient)
      → FailedWorkerWelfareCheckMail implements ShouldQueue

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$recipient` | `Mail::to()` | `config('mail.worker_welfare_check_failure_email')` | ✅ |
| `MAIL_WORKER_WELFARE_CHECK_FAILURE_EMAIL` | `../../config/mail.php` | Environment configuration | ✅ |
| `$pdfOutput` | Mailable attachment | `generateCertificatePdf()` | ✅ |

## 6. Constants & Enums

- Xóa `FailedWorkerWelfareCheckMail::DEFAULT_TO_EMAIL`.
- Giữ `FailedWorkerWelfareCheckMail::SUBJECT`.
- Config fallback giữ giá trị recipient hiện tại: `compliance@gap-personnel.com`.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `../../config/mail.php` | Thêm key recipient failure email đọc từ env với fallback hiện tại |
| `../../.env.example` | Thêm biến `MAIL_WORKER_WELFARE_CHECK_FAILURE_EMAIL` |
| `.env_test.example` | Thêm biến cấu hình cho test environment |
| `../../app/Mail/FailedWorkerWelfareCheckMail.php` | Xóa constant recipient không còn sử dụng |
| `../../app/Services/WorkerWelfareCheckService.php` | Dùng recipient từ config khi gọi `Mail::to()` |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Assert recipient theo config thay vì constant |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | failed score email scenario | Xác nhận email được queue tới recipient trong config |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | failed score email scenario | Xác nhận subject và attachment flow không đổi |
| Config smoke check | existing service test | Xác nhận fallback config vẫn là recipient hiện tại khi env chưa override |

Sau khi code sẽ chạy test service liên quan và toàn bộ
`./vendor/bin/phpunit`.

## 9. Checklist trước khi Approve

- [x] Recipient không còn hardcode trong Mailable constant.
- [x] Có config key và env example tương ứng.
- [x] Service lấy recipient từ config.
- [x] Queue flow, subject, view và attachment không thay đổi.
- [x] Test cập nhật theo config.
- [x] Toàn bộ PHPUnit pass.
- [x] User approve plan.
