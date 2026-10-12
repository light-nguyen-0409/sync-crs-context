# SPEC: Worker Welfare Check dùng Email Template hiện tại

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-23
> **Author**: Codex

---

## 1. Tổng quan

Thay thế luồng gửi email thất bại của Worker Welfare Check đang dùng
`FailedWorkerWelfareCheckMail` và Blade view riêng bằng luồng gửi email chuẩn
`MailSender`, dùng master/custom template trong bảng `email_templates`.

**Yêu cầu gốc**: GAP-700 — theo review, không dùng
`resources/views/mails/failed_worker_welfare_check.blade.php`; bổ sung template
tương ứng vào `database/seeders/data/email_templates.csv` và gửi qua email
template flow hiện tại.

Business-spec baseline đã mô tả flow mong muốn tại `SPEC-020` và
`SPEC-028`. Deviation hiện tại là `CODE`: `WorkerWelfareCheckService` vẫn gọi
Laravel `Mail` trực tiếp với Mailable/Blade riêng.

Phạm vi không thay đổi: điều kiện score `< 75`, nội dung nghiệp vụ cảnh báo,
recipient từ config, PDF certificate, queue job, MatchMaker sync và cơ chế log
khi gửi mail lỗi.

---

## 2. Database Design

Không thay đổi schema, migration, relationship hoặc column. Chỉ bổ sung một
master email-template row vào CSV seed data; `EmailTemplateSeeder` hiện có cơ
chế chỉ thêm các row có `id` lớn hơn ID lớn nhất trong database.

### 2.1. Bảng mới

N/A.

### 2.2. Bảng sửa đổi

```text
Bảng: `email_templates`
Nguồn seed: `database/seeders/data/email_templates.csv`
```

| Thay đổi | Cột | Mô tả |
|----------|-----|-------|
| ADD data row | `id`, `name`, `title`, `type`, `content`, `last_update_user_id` | Master template cho email cảnh báo Worker Welfare Check không đạt |

Template dự kiến dùng `id` tiếp theo trong CSV hiện tại, type cố định
`compliance_failed_worker_welfare_check`, title `Failed Worker Welfare Check`,
và giữ nội dung nghiệp vụ tương đương mail hiện tại. Không tạo `email_customs`
seed row; custom theo legal entity/branch vẫn do flow Compliance quản lý.

### 2.3. Eloquent Relationships

N/A — giữ nguyên quan hệ `EmailTemplate` → `EmailCustom`.

---

## 3. API Contract

N/A — không thêm hoặc thay đổi endpoint, request validation hay response.

---

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

```text
1. Consultant gọi POST /api/consultant/candidates/{id}/worker_welfare_check.
2. CandidateController → WorkerWelfareCheckService::performCheck() thực hiện
   face match, lưu score/check và dispatch certificate job như hiện tại.
3. GenerateWorkerWelfareCheckCertificateJob gọi
   WorkerWelfareCheckService::processPostCheck().
4. Service tạo/lưu PDF certificate và sync MatchMaker như hiện tại.
5. Nếu facematch_score < CandidateWelfareCheck::PASS_SCORE_THRESHOLD:
   a. Dùng EmailTemplate::TYPE_TO_COMPLIANCE_FAILED_WORKER_WELFARE_CHECK.
   b. Gọi MailSender::send() với branch scope toàn cục, recipient từ
      config('mail.worker_welfare_check_failure_email'), payload không có
      placeholder và đường dẫn PDF tạm làm attachment.
   c. MailSender resolve master/custom template, render base mail template,
      attach PDF và ghi activity log theo flow hiện tại.
6. Sau khi flow xử lý xong, finally hiện tại cleanup file tạm.
```

### 4.2. Business Rules

- Chỉ score dưới `CandidateWelfareCheck::PASS_SCORE_THRESHOLD` mới gửi email.
- Subject, nội dung cảnh báo, recipient và PDF attachment phải giữ tương đương
  hành vi hiện tại; title của master template là nguồn subject trong flow mới.
- Dùng `MailSender` để template có thể resolve master/custom theo cơ chế hiện
  tại; branch ID toàn cục không resolve branch-specific custom.
- PDF phải còn tồn tại trong lúc `MailSender::send()` thực hiện việc attach;
  cleanup chỉ diễn ra sau khi lời gọi gửi mail kết thúc.
- Không dùng lại `FailedWorkerWelfareCheckMail` hoặc
  `mails.failed_worker_welfare_check` sau thay đổi.
- Không thay đổi queue/job, certificate persistence, MatchMaker contact-log
  sync hoặc cách swallow/log lỗi gửi mail trong `processPostCheck`.

### 4.3. Side Effects

| Loại | Trigger | Mô tả |
|------|---------|-------|
| Email | `facematch_score < 75` | Gửi template `compliance_failed_worker_welfare_check` tới email Compliance kèm PDF |
| Activity log | Khi `MailSender` xử lý gửi | Ghi email event theo flow chuẩn, gắn `candidate_id` |
| File cleanup | Sau xử lý certificate/email | Xóa PDF tạm sau khi attachment đã được dùng |

---

## 5. Data Origin & Call Chain

```text
POST /api/consultant/candidates/{id}/worker_welfare_check
  → CandidateController::performWorkerWelfareCheck()
    → WorkerWelfareCheckService::performCheck()
      → GenerateWorkerWelfareCheckCertificateJob::dispatch()
        → WorkerWelfareCheckService::processPostCheck()
          → generateCertificatePdf() trả $pdfOutput
          → file_put_contents() tạo $tempPdfPath
          → nếu score fail: MailSender::send(..., $tempPdfPath)
            → EmailTemplateService::resolveTemplateForSending()
            → EmailTemplateRepository/EmailCustomRepository
            → mails.base hoặc mails.richtext_base + attachment
```

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$welfareCheck->facematch_score` | Điều kiện gửi mail | `candidate_welfare_checks` được tạo trong `performCheck()` | ✅ |
| `$pdfOutput` | Nội dung ghi ra file tạm | `generateCertificatePdf()` trong `processPostCheck()` | ✅ |
| `$tempPdfPath` | Attachment argument của `MailSender` | `file_put_contents()` trước nhánh gửi mail; được thêm vào `$tempFiles` | ✅ |
| `$pdfFileName` | Tên file certificate/attachment | `processPostCheck()` | ✅ |
| `config('mail.worker_welfare_check_failure_email')` | Recipient address | `config/mail.php` và environment | ✅ |
| `EmailTemplate::TYPE_TO_COMPLIANCE_FAILED_WORKER_WELFARE_CHECK` | Template type | Constant mới trong `EmailTemplate` | ✅ |
| `$candidateId` | Activity log context | Job argument từ `performCheck()` | ✅ |
| `[]` template data | Placeholder replacement | Template mới không dùng placeholder động | ✅ |

---

## 6. Constants & Enums

Thêm constant cần thiết, không hardcode template type trong Service:

```php
// app/Models/EmailTemplate.php
public const TYPE_TO_COMPLIANCE_FAILED_WORKER_WELFARE_CHECK =
    'compliance_failed_worker_welfare_check';
```

Trong `WorkerWelfareCheckService`, dùng constant public cho các fixed context
mới nếu cần theo convention hiện tại (global branch scope và recipient display
name). Giữ nguyên:

- `CandidateWelfareCheck::PASS_SCORE_THRESHOLD`.
- `config('mail.worker_welfare_check_failure_email')`.

---

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `app/Models/EmailTemplate.php` | Khai báo constant cho template type mới |
| `app/Services/WorkerWelfareCheckService.php` | Thay direct Mailable bằng `MailSender::send()` và truyền PDF path làm attachment; giữ nguyên threshold/log/cleanup |
| `database/seeders/data/email_templates.csv` | Thêm master template tương ứng với subject/body cảnh báo |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Thêm assertion score fail gọi đúng template flow, recipient, candidate context và attachment path |

### 7.3. Files xóa vì không còn caller

| File | Lý do |
|------|-------|
| `app/Mail/FailedWorkerWelfareCheckMail.php` | Mailable riêng không còn được sử dụng |
| `resources/views/mails/failed_worker_welfare_check.blade.php` | Nội dung được chuyển vào `email_templates` và render qua base template |
| `tests/Unit/Mail/FailedWorkerWelfareCheckMailTest.php` | Test của Mailable đã bị loại bỏ; coverage chuyển sang service/template flow |

Không sửa `.business-spec/` vì `SPEC-020`/`SPEC-028` đã ghi nhận MailSender
và email-template resolution là baseline; thay đổi này làm source khớp baseline.

---

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | low-score post-check email case | Mock `MailSender` và xác nhận gọi type mới, global branch scope, recipient từ config, candidate ID và PDF path attachment |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | high-score post-check case | Xác nhận score đạt ngưỡng không gọi `MailSender` |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | cleanup case | Xác nhận PDF path vẫn được truyền trước khi cleanup và cleanup vẫn chạy |
| Existing `tests/Unit/Jobs/GenerateWorkerWelfareCheckCertificateJobTest.php` | regression | Xác nhận job vẫn delegate đúng `processPostCheck()` |
| Existing `tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | regression | Xác nhận API response/dispatch contract không đổi |
| Existing email-template tests | regression | Xác nhận resolution master/custom hiện tại không bị ảnh hưởng |

Sau khi được approve: chạy các test bị ảnh hưởng và toàn bộ
`./vendor/bin/phpunit`, không chạy formatter/linter tự động.

---

## 9. Checklist trước khi Approve

- [x] Đã xác nhận không cần migration/schema change.
- [x] Đã chốt template type/title/body và ID seed row.
- [x] Đã chốt attachment dùng $tempPdfPath trước cleanup.
- [x] Đã chốt xóa Mailable/Blade cũ và chuyển coverage sang service test.
- [x] Đã chốt không thay đổi threshold, recipient config, certificate hoặc MM flow.
- [x] Call chain và data origin đã trace về controller/job/service.
- [x] Test impact đã được liệt kê.
