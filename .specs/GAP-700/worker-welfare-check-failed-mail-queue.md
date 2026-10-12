# SPEC: Queue Failed Worker Welfare Check Email

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

## 1. Tổng quan

Đưa email thông báo Worker Welfare Check không đạt tiêu chuẩn vào Laravel queue
để request không phải chờ quá trình gửi email hoàn tất. Mailable sẽ implement
`ShouldQueue`; lời gọi `Mail::to(...)->send()` hiện tại được Laravel chuyển sang
queue khi mailable thực hiện contract này.

**Yêu cầu gốc**: Implement `ShouldQueue` cho email failure của Worker Welfare
Check.

## 2. Database Design

N/A — Không thay đổi database hoặc queue backend.

## 3. API Contract

N/A — Không thay đổi request, response hoặc endpoint.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. `WorkerWelfareCheckService::performCheck()` tính `scorePercent`.
2. Nếu score thấp hơn `CandidateWelfareCheck::PASS_SCORE_THRESHOLD`, service
   tạo `FailedWorkerWelfareCheckMail` với PDF content và filename hiện có.
3. Laravel nhận diện mailable implement `ShouldQueue` và dispatch email vào queue.
4. Queue worker thực hiện render view, attach PDF và gửi email.
5. Request Worker Welfare Check không chờ SMTP gửi xong, trừ trường hợp môi
   trường dùng `QUEUE_CONNECTION=sync`.

### 4.2. Business Rules

- Không thay đổi điều kiện gửi email hoặc người nhận.
- Không thay đổi subject, nội dung view hoặc file PDF attachment.
- Không đổi lời gọi service sang API khác; chỉ thay đổi queue contract của mailable.
- Giữ nguyên cấu hình môi trường hiện tại; `QUEUE_CONNECTION=sync` vẫn chạy đồng
  bộ cho local/test cho tới khi môi trường triển khai dùng backend queue thật và
  có worker.
- PDF hiện truyền dưới dạng content string, nên job payload có thể lớn; không mở
  rộng sang thay đổi storage/file reference trong task này.

### 4.3. Side Effects

| Loại | Trigger | Mô tả |
|------|---------|-------|
| Queue Job | Score dưới threshold | Queue email `FailedWorkerWelfareCheckMail` |
| Email | Queue worker xử lý job | Gửi tới `FailedWorkerWelfareCheckMail::DEFAULT_TO_EMAIL` |

## 5. Data Origin & Call Chain

    POST /api/consultant/candidates/{id}/worker_welfare_check
      → CandidateController::performWorkerWelfareCheck()
      → WorkerWelfareCheckService::performCheck()
      → generateCertificatePdf() trả `$pdfOutput`
      → tạo `$pdfFileName`
      → Mail::to(...)->send(new FailedWorkerWelfareCheckMail(...))
      → Laravel Mailer queue mailable vì `ShouldQueue`

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$scorePercent` | Điều kiện gửi mail | GBG response trong `performCheck()` | ✅ |
| `$pdfOutput` | Mailable attachment | `generateCertificatePdf()` | ✅ |
| `$pdfFileName` | Attachment filename | `performCheck()` | ✅ |
| `DEFAULT_TO_EMAIL` | Recipient | `FailedWorkerWelfareCheckMail` constant | ✅ |

## 6. Constants & Enums

Không thêm constant mới. Giữ các constant hiện có:

- `CandidateWelfareCheck::PASS_SCORE_THRESHOLD`
- `FailedWorkerWelfareCheckMail::DEFAULT_TO_EMAIL`
- `FailedWorkerWelfareCheckMail::SUBJECT`

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `../../app/Mail/FailedWorkerWelfareCheckMail.php` | Implement `Illuminate\Contracts\Queue\ShouldQueue` |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Đổi assertion email failure từ `assertSent` sang `assertQueued` và giữ kiểm tra recipient/subject |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | failed score email scenario | Xác nhận mailable được queue khi score dưới threshold |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | failed score email scenario | Xác nhận recipient và subject không đổi |
| `../../tests/Unit/Mail/FailedWorkerWelfareCheckMailTest.php` hoặc assertion hiện có | queue contract | Xác nhận mailable implement `ShouldQueue` |

Sau khi code sẽ chạy test mail/service liên quan và toàn bộ
`./vendor/bin/phpunit`.

## 9. Checklist trước khi Approve

- [x] Mailable implement `ShouldQueue`.
- [x] Test chuyển sang `assertQueued` và vẫn kiểm tra recipient/subject.
- [x] Không thay đổi điều kiện, nội dung hoặc attachment email.
- [x] Đã ghi rõ `QUEUE_CONNECTION=sync` vẫn không tạo async processing.
- [x] Toàn bộ PHPUnit pass.
- [x] User approve plan.
