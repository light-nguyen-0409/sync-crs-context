# SPEC: Worker Welfare Check Failure Mail Sync Inside Queue Job

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

## 1. Tổng quan

`FailedWorkerWelfareCheckMail` hiện implements `ShouldQueue` nhưng được gọi
từ `GenerateWorkerWelfareCheckCertificateJob`, vốn đã chạy trong queue.
Việc này tạo thêm một lớp queue không cần thiết cho email. Mailable sẽ được
gửi đồng bộ trong context của worker job hiện tại.

**Yêu cầu gốc**: Không queue riêng `FailedWorkerWelfareCheckMail` vì nó đã
được gọi bên trong queue job.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

N/A — Không thay đổi endpoint hoặc response.

## 4. Business Logic

### 4.1. Call chain hiện tại

```text
GenerateWorkerWelfareCheckCertificateJob::handle()
  → WorkerWelfareCheckService::processPostCheck()
  → Mail::to(...)->send(new FailedWorkerWelfareCheckMail(...))
```

### 4.2. Thay đổi

- Bỏ `ShouldQueue` khỏi `FailedWorkerWelfareCheckMail`.
- Bỏ các queue-specific imports/traits không còn cần thiết trong mailable.
- Giữ nguyên subject, Blade view, PDF attachment và recipient lấy từ config.
- Giữ nguyên `try/catch` trong service để lỗi gửi mail không làm mất các xử
  lý đã hoàn tất của job.
- Không thay đổi `GenerateWorkerWelfareCheckCertificateJob` hoặc cách gọi
  `Mail::send()`.

### 4.3. Expected behavior

Email được gửi trong cùng queue worker đang xử lý certificate job, không tạo
thêm queued mail job. Nếu `QUEUE_CONNECTION=sync`, behavior vẫn là gửi inline
như hiện tại.

## 5. Data Origin & Call Chain

| Biến / Key | Nguồn cung cấp | Nơi sử dụng | Confirmed? |
|------------|----------------|-------------|------------|
| `$pdfOutput` | `processPostCheck()` sau khi render PDF | Mailable body/attachment | ✅ |
| `$pdfFileName` | `processPostCheck()` | Tên file attachment | ✅ |
| Recipient | `config('mail.worker_welfare_check_failure_email')` | `Mail::to()` | ✅ |

## 6. Constants & Enums

Giữ nguyên `FailedWorkerWelfareCheckMail::SUBJECT`; không thêm constant mới.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|------|-----------|-------|
| `../../tests/Unit/Mail/FailedWorkerWelfareCheckMailTest.php` | `Tests\\Unit\\Mail` | Xác nhận mailable không implements `ShouldQueue` và giữ behavior build hiện tại |

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `../../app/Mail/FailedWorkerWelfareCheckMail.php` | Bỏ `ShouldQueue`, `Queueable` và `SerializesModels` vì mail được gửi bên trong queue job |
| `specs/worker-welfare-check-async-post-processing.md` | Cập nhật business rule từ “failure email dùng ShouldQueue” thành “failure email gửi trong certificate queue job” |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `../../tests/Unit/Mail/FailedWorkerWelfareCheckMailTest.php` | `testMailIsNotQueued` | Mailable không implements `ShouldQueue` |
| `../../tests/Unit/Mail/FailedWorkerWelfareCheckMailTest.php` | `testBuildsPdfAttachment` | Giữ subject, view và PDF attachment |
| Affected tests | — | Không thay đổi contract của worker welfare check job/service |
| Toàn bộ test suite | `./vendor/bin/phpunit` | Regression check |

## 9. Checklist trước khi Approve

- [x] Mailable không còn `ShouldQueue`.
- [x] Không còn queue-specific trait/import không cần thiết trong mailable.
- [x] Email vẫn được gọi từ `processPostCheck()` trong queue job.
- [x] Subject/view/attachment/recipient không đổi.
- [x] Test mailable được bổ sung.
- [x] Toàn bộ PHPUnit đã chạy; còn 2 error + 1 failure pre-existing ngoài scope ở Resource do thiếu `certificate_url`.
- [x] User approve plan.
