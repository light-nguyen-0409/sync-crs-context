# Plan: Email Template Links & RichText Fixes

> **Trạng thái**: `DONE`  
> **Task Key**: `GAP-744`  
> **Plan Sequence**: `003`  
> **File**: `.specs/GAP-744/003-email-template-links-and-richtext-fixes.md`  
> **Author**: Antigravity  
> **Ngày tạo**: 2026-10-27  

---

## 1. Tổng quan & Bối cảnh

### 1.1. Bối cảnh
Khi giải quyết yêu cầu chuyển đổi URL trong email thành dạng thẻ bấm (`Click here` / `here`), việc chuyển đổi cờ `$emailTemplate->isRichText = true` ra ngoài khối `if ($custom)` đã gây ra các tác dụng phụ lớn:
1. Ép toàn bộ ~480 Master Template cũ (vốn là plain text có ký tự xuống dòng `\n`) chạy qua luồng Rich Text, dẫn đến mất tính năng ngắt dòng (`\n` bị email client gom thành 1 dòng duy nhất).
2. Khi template chạy qua `RichTextMailProcessor`, các placeholder chứa mã HTML sẵn (như Google Map `<br><a...><img...></a>` trong `AppointmentService` hay button styled `<a... style="...">Login</a>`) bị hàm `htmlspecialchars` mã hóa thành chuỗi thô (`&lt;a...&gt;`), làm hỏng giao diện hiển thị.
3. Ở luồng Master Template cũ (không có `EmailCustom`), các đường link URL hiện tại vẫn đang hiển thị dưới dạng raw URL (`<a href="https://...">https://...</a>`) thay vì văn bản thân thiện (`Click here` / `here`).

### 1.2. Mục tiêu kỹ thuật
1. **Khôi phục vị trí cờ `isRichText`**: Đưa `$emailTemplate->isRichText = true;` trở lại bên trong `if ($custom)` trong `EmailTemplateService::applyCustom`. Chỉ template nào có bản ghi tùy biến (`EmailCustom`) mới chạy theo pipeline Rich Text.
2. **Hỗ trợ an toàn các placeholder chứa HTML (Google Map, Button)**: Trong `RichTextMailProcessor::injectData`, nếu dữ liệu placeholder chứa thẻ HTML, sử dụng `Purify::clean($value)` để lọc whitelist tag/thuộc tính an toàn (giữ lại `<a>`, `<img>`, `<br>`, `style`), thay vì dùng `htmlspecialchars` làm hỏng thẻ.
3. **Chuyển đổi URL thành "Click here" / "here" cho cả luồng Master Template (Legacy)**: Trong `MailSenderAccessor::processContentTemplate`, nâng cấp regex URL replacement để tự động chuyển URL thành `<a href="...">Click here</a>` (hoặc `here` nếu trước đó có từ "click") thay vì in ra raw URL.
4. **Dọn dẹp code debug**: Xóa câu lệnh `dump($key);` trong `RichTextMailProcessor.php`.
5. **Cập nhật bộ test**: Đảm bảo toàn bộ Feature & Unit Test (đặc biệt là `MailSenderIntegrationTest`) đạt 100% PASS.

---

## 2. API Contract & Docs Assessment Gate

> [!IMPORTANT]
> **API Contract / API Docs Assessment**:
> Thay đổi này chỉ liên quan đến logic xử lý template và render nội dung email nội bộ (`EmailTemplateService`, `RichTextMailProcessor`, `MailSenderAccessor`).
> **Kết luận**: `N/A — no API contract/API docs change`.

---

## 3. Thiết kế giải pháp chi tiết

### 3.1. Revert `isRichText` về vị trí đúng trong `EmailTemplateService`
* **File**: [`app/Services/EmailTemplateService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/EmailTemplateService.php)
* **Phương thức**: `applyCustom()`
* **Logic**:
  ```php
  private function applyCustom(EmailTemplate $emailTemplate, ?EmailCustom $custom, ?int $legalEntityId, ?int $branchId): EmailTemplate
  {
      $emailTemplate->placeholders = $this->richTextProcessor->extractPlaceholders($emailTemplate->content ?? '');
      $emailTemplate->include_header = $custom?->include_header ?? true;
      $emailTemplate->include_footer = $custom?->include_footer ?? true;

      if ($custom) {
          if ($custom->title !== null) {
              $emailTemplate->title = $custom->title;
          }
          $emailTemplate->content = $custom->content;
          $emailTemplate->previous_content = $custom->previous_content;
          $emailTemplate->last_update_user_id = $custom->last_update_user_id;
          $emailTemplate->setRelation('last_update_user', $custom->last_update_user);
          $emailTemplate->updated_at = $custom->updated_at;
          $emailTemplate->isRichText = true; // <-- Chỉ set true khi có $custom
          $emailTemplate->legal_entity_id = $custom->legal_entity_id;
          $emailTemplate->branch_id = $custom->branch_id;
      }

      return $emailTemplate;
  }
  ```

---

### 3.2. Hỗ trợ HTML Placeholders bằng `Purify::clean()` trong `RichTextMailProcessor`
* **File**: [`app/Services/Mail/RichTextMailProcessor.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/Mail/RichTextMailProcessor.php)
* **Phương thức**: `injectData()` & `isHtmlPlaceholder()`
* **Logic**:
  1. Xóa bỏ dòng `dump($key);`.
  2. Tại bước replace placeholder:
     - Nếu là Link Placeholder dạng URL thuần (`isValidHttpUrl($value)`): Tiếp tục logic tự bọc thẻ `<a>` với contextual label (`Click here` hoặc `here`).
     - Nếu là HTML Placeholder hợp lệ (`isHtmlPlaceholder($key, $value)`):
       Chạy qua `Purify::clean((string) $value)`. Điều này cho phép Google Map (`<br><a...><img.../></a>`) và nút bấm (`<a... style="...">Login</a>`) được giữ nguyên hiển thị và lọc sạch các script nguy hại.
       Để ngăn ngừa lỗ hổng XSS/HTML Injection khi người dùng nhập thẻ HTML trong thông tin cá nhân (`candidate_name`, `address`), hàm `isHtmlPlaceholder` áp dụng kiểm tra nghiêm ngặt chỉ dựa trên whitelist tường minh:
       - Thuộc danh sách key HTML cố định sinh ra từ backend: `interview_location_map`, `map_link`, `login_to_gap_profile_button`, `complete_registration_button_link_to_right_to_work`. (Các trường free-text như `request_missing_information`, `request_documents` bị loại bỏ để chống phishing/content-spoofing).
       - Hoặc key `candidate_registration_link` khi giá trị bắt đầu bằng thẻ styled anchor `<a\b`.
       - Loại bỏ hoàn toàn regex hậu tố (`_map`, `_button`, `_html`) để tránh nguy cơ bypass khi phát triển tính năng mới.
       - Mọi trường dữ liệu khác (`candidate_name`, `request_missing_information`, `request_documents`, `notes_html`, v.v.) tuyệt đối không được coi là HTML và luôn đi qua `htmlspecialchars()`.
     - Nếu là Text thông thường: Dùng `htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8')`.

---

### 3.3. Escape toàn bộ các câu trả lời của ứng viên trong `ApplicationPackService`
* **File**: [`app/Services/ApplicationPackService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ApplicationPackService.php)
* **Phương thức**: `getAgreements()` & `writeInterviewTopic()`
* **Logic**:
  - Khi khôi phục link annotation trên trang PDF chính (`$tempMainPdfFilePath` trong `$allowedLinkFiles`), toàn bộ các giá trị do ứng viên nhập phải được bọc `e()` để tránh PDF link injection.
  - Bọc `e(...)` cho toàn bộ các câu trả lời còn lại trong `getAgreements()`: `TIME_REGULATIONS_48_HOUR_OPT_OUT`, `HEALTH_DISABILITY`, và `DBS`.
  - Bọc `e(...)` cho `$value` trong `writeInterviewTopic()` để phòng thủ theo chiều sâu (defense-in-depth).

---

### 3.4. Tự động chuyển URL thành "Click here" / "here" trong `MailSenderAccessor` (Luồng Legacy)
* **File**: [`app/Facades/MailSenderAccessor.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Facades/MailSenderAccessor.php)
* **Phương thức**: `processContentTemplate()`
* **Logic**:
  Hiện tại luồng legacy dùng regex:
  ```php
  private const URL_REGEX = '/((?:https?|http):\/\/[-_.!~*\'()a-zA-Z0-9;\/?:@&=+$,%#]+)/';
  private const LINK_TAG = '<a href="$1">$1</a>';
  ```
  Nâng cấp thay thế regex để phân tích ngữ cảnh trước URL:
  - Nếu URL nằm ngay sau các từ như `click`, `clicking`, `click on`: bọc nhãn `here` (ví dụ `please click <a href="...">here</a>`).
  - Nếu là URL độc lập: bọc nhãn `Click here` (ví dụ `<a href="...">Click here</a>`).
  - Đảm bảo URL được escape an toàn qua `htmlspecialchars($url, ENT_QUOTES, 'UTF-8')` để ngăn ngừa HTML injection.
  - Tôn trọng cờ `urlPregReplace => false` nếu caller yêu cầu không thay thế URL.

---

### 3.4. Cập nhật và kiểm thử `MailSenderIntegrationTest`
* **File**: [`tests/Feature/Mail/MailSenderIntegrationTest.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/tests/Feature/Mail/MailSenderIntegrationTest.php)
* Cập nhật test case `testNonRichTextEmailPreservesLegacyRawUrlBehavior` để assert link được convert thành `Click here` / `here` phù hợp với yêu cầu mới, đồng thời kiểm tra chính xác URL đã escape `&amp;`.
* Chạy toàn bộ các test suite liên quan đến email và application pack.

---

## 4. Danh sách file thay đổi

| File | Hành động | Mục đích |
| :--- | :--- | :--- |
| [`app/Services/EmailTemplateService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/EmailTemplateService.php) | Sửa | Đưa `$emailTemplate->isRichText = true;` về lại trong khối `if ($custom)` |
| [`app/Services/Mail/RichTextMailProcessor.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/Mail/RichTextMailProcessor.php) | Sửa | Xóa `dump($key);`, dùng `Purify::clean()` cho placeholder chứa HTML |
| [`app/Facades/MailSenderAccessor.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Facades/MailSenderAccessor.php) | Sửa | Convert URL trong luồng Master Template thành `Click here` / `here` |
| [`tests/Feature/Mail/MailSenderIntegrationTest.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/tests/Feature/Mail/MailSenderIntegrationTest.php) | Sửa | Cập nhật assertion cho luồng gửi mail không có custom |

---

## 5. Kế hoạch kiểm thử (Test Plan)

1. **Unit Tests**:
   - `tests/Unit/Services/RichTextMailProcessorTest.php`
   - `tests/Unit/Services/EmailTemplateServiceTest.php`
   - `tests/Unit/Services/ApplicationPackServiceTest.php`
2. **Feature Tests**:
   - `tests/Feature/Mail/MailSenderIntegrationTest.php`
   - `tests/Feature/Api/Compliance/EmailTemplatesTest.php`
   - `tests/Feature/Api/Consultant/CandidateArchiveTest.php`
3. **Kiểm tra trực tiếp**:
   - Luồng có EmailCustom: Chứa Google Map, nút bấm styled HTML -> Không bị escape thành `&lt;a&gt;`.
   - Luồng không có EmailCustom (Master Template): Xuống dòng `\n` vẫn giữ nguyên dạng `<br/>`, URL được chuyển thành `Click here` / `here`.
