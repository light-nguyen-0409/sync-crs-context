# SPEC: Local HTML mail preview

> **Trạng thái**: `DRAFT`
> **Ngày tạo**: 2026-09-23
> **Author**: Codex

---

## 1. Tổng quan

Ở local/dev, thay vì gửi email ra ngoài hoặc ghi MIME/HTML vào log text, Laravel sẽ lưu HTML email đã render thành file để mở trực tiếp trong browser. Staging và production giữ nguyên mailer hiện tại.

**Yêu cầu gốc**: Không gửi email ra ngoài; tạo file HTML để xem nội dung.

**Điều tra hiện trạng**:

- `.env` hiện có `APP_ENV=local`, `MAIL_MAILER=log`, `LOG_CHANNEL=stack`; không có config cache trong workspace.
- `config/mail.php` có `log` transport nhưng chưa có HTML-file transport. Default mailer đọc `MAIL_MAILER`.
- `LOG_CHANNEL=stack` trỏ tới `storage/logs/laravel.log`; mailer `log` ghi message dạng log text, không tạo file HTML.
- `MailSenderAccessor` ở local gọi `Mail::send()`, nên có thể chuyển qua custom local transport.
- `OnepayService::sendMailToOnepay()` return sớm ở `APP_ENV=local`, nên luồng OnePay hiện không gọi mailer và không tạo preview.
- PHPUnit đặt `APP_ENV=testing`, `MAIL_MAILER=array`; nhánh `MailSenderAccessor`/OnePay khi testing còn ghi mock JSON vào thư mục temp. Vì vậy `.env` `MAIL_MAILER=log` không áp dụng cho lệnh PHPUnit.
- Không đọc credentials trong `.env`. `php artisan tinker` không boot được trên host do không resolve được DB host `pgsql`, nên runtime Laravel config chưa xác minh độc lập với file `.env`.

---

## 2. Database Design

N/A — không đổi schema hoặc lưu email vào database.

---

## 3. Mail Preview Contract

### 3.1. Môi trường và transport

- Local/dev dùng mailer `html_preview`, đăng ký qua Laravel `Mail::extend()`.
- Transport chỉ ghi file, không kết nối SMTP/provider.
- File được lưu dưới `storage/app/mail-previews/` (hoặc path riêng cấu hình qua `MAIL_PREVIEW_PATH`).
- Mỗi email có tên file riêng gồm timestamp, subject slug an toàn và UUID để không ghi đè email trước.
- Mở file `.html` trực tiếp bằng browser để xem body đã render. File chỉ gồm nội dung HTML của email; attachment không được nhúng/copy kèm.
- PHPUnit tiếp tục dùng `array` mailer/fake, không tạo hàng loạt file preview khi chạy toàn bộ test.

### 3.2. API

N/A — không đổi API route/request/response.

---

## 4. Business Logic / Configuration

### 4.1. Cách triển khai đề xuất

1. Tạo Symfony/Laravel mail transport `HtmlFileTransport` nhận message đã render, lấy HTML body và ghi file vào preview directory. Nếu message không có HTML body, render plain text thành `<pre>` an toàn.
2. Đăng ký transport bằng `Mail::extend('html_preview', ...)` trong provider và khai báo mailer/path trong `config/mail.php`.
3. Đặt `MAIL_MAILER=html_preview` và `MAIL_PREVIEW_PATH=storage/app/mail-previews` cho local; đổi `.env.example` để môi trường local mới dùng preview.
4. `MailSenderAccessor` và lời gọi `Mail::send()` trực tiếp sẽ dùng default transport nên không đi ra ngoài.
5. Sửa nhánh local trong `OnepayService::sendMailToOnepay()` để gọi Mailable qua preview transport rồi return; không ghi log như thể OnePay đã nhận mail.
6. Giữ nguyên nhánh `testing` và mailer của staging/production.
7. Xóa config cache local nếu có, gửi một email mẫu, và kiểm tra file mới trong preview directory.

### 4.2. Business Rules

- Chỉ local/dev mới chọn `html_preview`; deployment khác giữ cấu hình riêng.
- Preview transport không có fallback sang SMTP, để không thể gửi nhầm email ra ngoài khi local đang preview.
- Không thay nội dung template hoặc rule recipient; không đưa recipient vào filename.
- Không thay `testing` mock, vốn được cấu hình riêng trong `phpunit.xml`.

### 4.3. Side Effects

Local tạo file HTML trong storage. Không có SMTP/provider call, DB schema write hoặc email gửi thật.

---

## 5. Data Origin & Call Chain

| Giá trị | Nơi dùng | Nguồn cung cấp | Xác minh |
|---|---|---|---|
| Environment | Chọn nhánh mailer/mock | `APP_ENV` | `.env` là local; PHPUnit override thành testing |
| Mailer | Chọn transport | `MAIL_MAILER` → `config/mail.php` | `.env` là log; runtime Laravel chưa đọc được do DB bootstrap lỗi |
| Rendered HTML/text | Custom transport | Symfony `Email` sau khi Laravel render Mailable/View | Chưa có implementation |
| Preview path | Custom transport | `MAIL_PREVIEW_PATH`, mặc định `storage/app/mail-previews` | Đề xuất mới |
| Subject | File name | Message đã render | Sẽ chuẩn hóa ký tự trước khi tạo tên file |

---

## 6. Constants & Enums

- Dùng transport key và path trong config thay vì hardcode rải rác.
- Filename suffix dùng UUID; định dạng timestamp/path khai báo tập trung trong transport/config.

---

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|---|---|---|
| `app/Mail/Transports/HtmlFileTransport.php` | `App\Mail\Transports` | Ghi HTML body của Symfony email vào file local; không gửi network |

### 7.2. Files sửa

| File | Thay đổi |
|---|---|
| `app/Providers/AppServiceProvider.php` | Đăng ký custom mail transport; giữ nguyên các thay đổi đang có trong working tree |
| `config/mail.php` | Khai báo `html_preview` mailer và preview path |
| `.env` (local, ignored) | Đổi `MAIL_MAILER=html_preview`, đặt path; giữ nguyên các giá trị khác |
| `.env.example` | Đặt local default `MAIL_MAILER=html_preview`, thêm `MAIL_PREVIEW_PATH` |
| `app/Services/OnepayService.php` | Cho phép local OnePay Mailable đi qua preview transport thay vì return trước khi render; tránh ghi nhận như gửi ra OnePay |
| `tests/Unit/Mail/HtmlFileTransportTest.php` | Kiểm tra file HTML, nội dung render, tên file an toàn/duy nhất và không có network send |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật mail configuration behavior nếu sau triển khai trở thành hành vi chuẩn của local flow |

`MailSenderAccessor` không cần đổi cho local vì đã gọi default `Mail::send()`. Không đổi `phpunit.xml`; test runner tiếp tục dùng array/fake.

---

## 8. Verification

| Check | Kỳ vọng |
|---|---|
| Unit test custom transport với HTML body | Ghi đúng body vào file `.html` |
| Unit test custom transport với text-only body | Ghi nội dung text thành HTML an toàn |
| Gửi email qua `MailSenderAccessor` trong local | Tạo file HTML; không ghi mail MIME vào Laravel log và không gọi SMTP/provider |
| Gửi email qua `Mail::send()` trực tiếp trong local | Tạo file HTML qua cùng transport |
| Chạy nhánh OnePay local | Tạo preview file; không tạo external-send success log |
| Chạy PHPUnit hiện hữu | Vẫn dùng `MAIL_MAILER=array` và mock; không phát sinh preview file ngoài ý muốn |
| Kiểm tra staging/production config | Vẫn dùng mailer được deployment cấu hình |

Sau khi plan được duyệt và code hoàn tất, chạy test suite bị ảnh hưởng theo repository instructions. Lượt lập plan này không sửa code và không chạy test.

---

## 9. Checklist trước khi Approve

- [ ] Xác nhận scope là local/dev; PHPUnit vẫn giữ mock hiện tại và không cần lưu HTML files.
- [ ] Duyệt thư mục output `storage/app/mail-previews/`.
- [ ] Chấp nhận preview file gồm HTML body; attachment không được copy/nhúng vào preview.
- [ ] Duyệt thay đổi local OnePay guard để mail preview được tạo mà không ghi nhận gửi thành công ra OnePay.
- [ ] Đồng ý cập nhật `.env.example`; staging/production không đổi.
