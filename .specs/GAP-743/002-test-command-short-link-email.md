# SPEC: GAP-743 — TestCommand Function to Send Email with Shortened Link

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-23
> **Author**: Antigravity
> **Nguồn yêu cầu**: [GAP-743](https://gappersonnel.atlassian.net/browse/GAP-743) / User Request: "trong TestCommand thêm function để test gửi email dùng template có url để test shorten link task 743"
> **Template**: [SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md)
> **Liên kết liên quan**: [.specs/GAP-743/001-email-short-link-redirect.md](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-743/001-email-short-link-redirect.md)

---

## 1. Tổng quan

Mục tiêu của task là bổ sung function vào [`TestCommand`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Console/Commands/TestCommand.php) (`app/Console/Commands/TestCommand.php`) để gửi email thử nghiệm sử dụng rich-text email template có chứa URL/link nhằm kiểm tra thực tế tính năng tự động rút gọn link (Shorten Links in Email Bodies) đã phát triển ở task GAP-743.

### Bối cảnh nghiệp vụ & kỹ thuật (Task GAP-743)
- Ở task GAP-743, [`MailSenderAccessor::send()`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Facades/MailSenderAccessor.php#L63-L92) đã tích hợp: khi một email template là rich text (`$emailTemplate->isRichText === true`), nội dung sau khi render placeholder qua [`RichTextMailProcessor`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/Mail/RichTextMailProcessor.php) sẽ được đưa qua [`ShortLinkServiceInterface::shortenRenderedBody()`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ShortLinkService.php#L31-L87).
- Cơ chế rút gọn: Tất cả các thẻ `<a href="...">` có link HTTP/HTTPS sẽ được tự động chuyển đổi thành short URL dạng `{base_url}/api/r/{token}` (10 ký tự token ngẫu nhiên), đồng thời lưu bản ghi được mã hóa vào bảng `short_links`. Nếu nhãn của link trùng với destination URL, nhãn cũng được đổi thành short URL.
- Để `$emailTemplate->isRichText` có giá trị `true`, template phải có bản ghi custom tương ứng trong bảng `email_customs` (theo logic của [`EmailTemplateService::resolveTemplateForSending()`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/EmailTemplateService.php#L234-L268)).

---

## 2. Database Design

*N/A — Không thay đổi cấu trúc Database (sử dụng các bảng hiện có: `email_templates`, `email_customs`, `branches`, `short_links`).*

---

## 3. API Contract & API Docs Pre-Deployment Gate

*N/A — no API contract/API docs change.*

Thay đổi chỉ nằm trong Artisan console command nội bộ phục vụ việc test cục bộ của developer ([`app/Console/Commands/TestCommand.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Console/Commands/TestCommand.php)); không thêm, sửa hoặc xóa bất kỳ API route hay HTTP contract nào.

---

## 4. Thiết kế chi tiết cho TestCommand

### 4.1. Cập nhật Command Signature & Options
Cập nhật signature của [`TestCommand`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Console/Commands/TestCommand.php#L47):
```php
protected $signature = 'cmd:test
    {--action= : Action to run (e.g. short-link-mail, permanent-sync)}
    {--branch-id=1 : Branch ID to use}
    {--email= : Target recipient email}
    {--candidate-id=}
    {--job-id=}
    {--cv-file-id=}
    {--agreement-file-id=}';
```

### 4.2. Logic Function `sendShortLinkMailTest()`
Thêm function `public function sendShortLinkMailTest(?string $recipientEmail = null, ?int $branchId = null): int` vào [`TestCommand`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Console/Commands/TestCommand.php):

1. **Xác định tham số gửi mail**:
   - `branchId`: lấy từ option `--branch-id` (mặc định = 1, chi nhánh Flint có sẵn trong DB).
   - `recipient`: lấy từ option `--email`, nếu không truyền thì dùng constant `self::RECIPIENT_EMAIL` (`light.nguyen@nexusfrontier.tech`).

2. **Chuẩn bị Template Rich-Text có URLs**:
   - Sử dụng template type: `EmailTemplate::TYPE_TO_CANDIDATE_INVITATION_LINK_SENT` (`candidate_registration_invitation_link_sent` - ID 25, template mời đăng ký ứng viên của task 743).
   - Đảm bảo tồn tại bản ghi rich-text trong `email_customs` cho template này gắn với `branch_id = $branchId` (hoặc tạo/cập nhật qua `EmailCustom::updateOrCreate`) với nội dung HTML chứa các trường hợp link:
     - **Link trần có nhãn là placeholder/URL**: `<a href="{registration_link}">{registration_link}</a>` (để kiểm tra xem cả `href` lẫn label hiển thị đều được rút gọn).
     - **Named anchor link**: `<a href="https://apply.gap-personnel.com/downloads/complaints-policy.pdf">GAP Complaints Policy</a>` (để kiểm tra `href` được rút gọn nhưng nhãn hiển thị vẫn giữ nguyên).
   - Xóa cache resolved template (`EmailTemplateService::CACHE_KEY_RESOLVED_PREFIX`) để đảm bảo template mới nhất với `$isRichText = true` được load.

3. **Gửi Email qua MailSender**:
   - Chuẩn bị dữ liệu placeholder:
     - `{candidate_name}`: `Test Candidate`
     - `{registration_link}`: `https://frontend.example/#/welcome?job_id=42&utm_source=email&token=sample-very-long-registration-token-for-gap-743`
     - `{branch_name}`: Tên của chi nhánh (ví dụ: `Flint Branch`)
   - Gọi [`MailSender::send(...)`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Facades/MailSenderAccessor.php#L63-L92):
     ```php
     MailSender::send(
         $branchId,
         null,
         ['address' => $recipientEmail, 'name' => self::RECIPIENT_NAME],
         EmailTemplate::TYPE_TO_CANDIDATE_INVITATION_LINK_SENT,
         $data
     );
     ```

4. **Kiểm tra và hiển thị kết quả (Console Output)**:
   - Truy vấn các bản ghi `short_links` vừa được tạo gần nhất (trong vòng 1 phút).
   - In thông báo gửi mail thành công kèm bảng kết quả chứa:
     - `Token Hash` (hoặc 10 ký tự rút gọn)
     - `Short URL` (`config('app.url') . '/api/r/{token}'`)
     - `Destination URL` (URL gốc sau khi giải mã)
   - Cho phép click thử nghiệm hoặc in hướng dẫn kiểm tra link redirect.

### 4.3. Cập nhật `handle()` trong TestCommand
Trong `handle()`:
- Nếu `--action=short-link-mail` hoặc `--action=send-short-link-mail`: gọi trực tiếp `$this->sendShortLinkMailTest()` và trả về mã exit code tương ứng mà không bắt buộc truyền các option của job `permanent-sync` (`candidate-id`, `job-id`, v.v.).
- Nếu không có `--action` hoặc chạy action mặc định: dọn dẹp đoạn code nháp tạm thời (`dd($matches)`) và khôi phục xử lý hợp lệ hoặc hiển thị hướng dẫn các action khả dụng.

---

## 5. Data Origin & Call Chain

```
Artisan CLI: php artisan cmd:test --action=short-link-mail
  → TestCommand::handle()
    → TestCommand::sendShortLinkMailTest()
      → EmailTemplate::where('type', 'candidate_registration_invitation_link_sent')->first()
      → EmailCustom::updateOrCreate(..., [content => rich-text HTML with <a href="...">])
      → MailSender::send($branchId, null, $recipient, $templateType, $placeholders)
        → MailSenderAccessor::send()
          → EmailTemplateService::resolveTemplateForSending() (returns EmailTemplate with $isRichText = true)
          → RichTextMailProcessor::process() (replaces placeholders with long URLs)
          → ShortLinkService::shortenRenderedBody() (extracts URLs, inserts short_links, replaces hrefs)
          → Mail::send('mails.richtext_base', ...)
      → Output short links to console
```

---

## 6. Constants & Options

Khai báo bổ sung trong [`TestCommand`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Console/Commands/TestCommand.php):
```php
public const ACTION_SHORT_LINK_MAIL = 'short-link-mail';
public const ACTION_PERMANENT_SYNC = 'permanent-sync';
public const SAMPLE_LONG_REGISTRATION_URL = 'https://frontend.example/#/welcome?job_id=42&utm_source=email&token=sample-very-long-registration-token-for-gap-743';
```

---

## 7. Files cần sửa / tạo

| File | Thay đổi |
|---|---|
| [`app/Console/Commands/TestCommand.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Console/Commands/TestCommand.php) | Thêm constants, bổ sung option `{--action=}` và `{--email=}` vào `$signature`, cập nhật `handle()`, thêm method `sendShortLinkMailTest()` |

*Lưu ý: Không tạo thêm Controller, Service hay Repository mới vì đây là hàm test command nội bộ; tuân thủ quy tắc Minimal Git Diff và Test Placement Policy.*

---

## 8. Test Cases & Verification

### 8.1. Kiểm tra trực tiếp qua Artisan Command
- Chạy command kiểm tra:
  ```bash
  docker exec gap-web-backend-laravel.test-1 php artisan cmd:test --action=short-link-mail
  ```
- Kỳ vọng:
  1. Email được gửi thành công (qua mail transport hiện hành, trong môi trường local sẽ ghi log/mock hoặc gửi qua SMTP tester tùy cấu hình `.env`).
  2. Bảng `short_links` có thêm 2 bản ghi mới tương ứng với các URL trong nội dung email.
  3. Console in ra danh sách Short URLs được tạo và URL đích.
  4. Gửi request GET tới endpoint redirect `/api/r/{token}` để xác nhận response HTTP 302 Redirect về URL đích chính xác.

### 8.2. Miễn trừ Unit Test
- Theo Workspace Rules mục 3 (*"Exception — test-data/fixture-only Artisan commands"*): `TestCommand` là command phục vụ kiểm thử cục bộ/test fixture của developer (đã nằm trong `.gitignore`), không can thiệp logic runtime sản phẩm, nên được miễn thêm unit test trong `tests/Unit/Services/`.

---

## 9. Checklist trước khi Implementation

- [x] Đã khảo sát hiện trạng `TestCommand.php` và logic GAP-743 (`ShortLinkService`, `MailSenderAccessor`, `RichTextMailProcessor`).
- [x] Đã đánh giá cổng API Contract / Docs (`N/A`).
- [x] Kế hoạch tuân thủ kiến trúc phân lớp, nguyên tắc không dùng magic value, kiểm tra nguồn dữ liệu.
- [x] Đã lưu plan tại đúng đường dẫn quy định `.specs/GAP-743/002-test-command-short-link-email.md`.
