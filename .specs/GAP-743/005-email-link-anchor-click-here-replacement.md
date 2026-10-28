# SPEC: GAP-743 — Chuyển đổi Link Placeholder thành Thẻ Anchor với Nhãn Ngữ Cảnh trong RichTextMailProcessor

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-26
> **Author**: Antigravity
> **Nguồn yêu cầu**: [GAP-743](https://gappersonnel.atlassian.net/browse/GAP-743) & Yêu cầu cập nhật từ User: *"thêm comment cho dễ hiểu"* (tiếng Anh) trong `RichTextMailProcessor.php`.
> **Phase 1 (Docs-First)**: Đã hoàn tất, commit `ad8cc39` trên `~/projects/crs-api-docs` remote `main`.
> **Phase 2 (Implementation & Tests)**: Đã hoàn tất và 100% tests pass.
> **Template**: [.specs/SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md)

---

## 1. Tổng quan

### 1.1. Bối cảnh & Vấn đề gốc (GAP-743)
- **Vấn đề**: Các đường link lời mời đăng ký (`registration_link`) và các liên kết trong email gửi tới ứng viên có độ dài lớn (> 100 ký tự với nhiều query parameters). Khi mở trên thiết bị di động hoặc ứng dụng email (như Outlook/Apple Mail), URL dài thường bị ngắt dòng tự động (Quoted-Printable mime line wrapping / soft wrapping), khiến đường link bị vỡ khi ứng viên bấm vào.
- **Hiện trạng trên `develop`**: Nhánh `develop` hoàn toàn sạch, chưa từng chứa code của URL Shortener (không có bảng `short_links`, không có model hay route redirect).

### 1.2. Hướng tiếp cận thống nhất
1. **Chỉ áp dụng cho Rich-text Email (`$emailTemplate->isRichText = true`)**:
   - Nếu không phải rich-text (legacy template), giữ nguyên 100% luồng và logic cũ trong `processContentTemplate()`, không can thiệp.
   - `MailSenderAccessor.php` được giữ nguyên vẹn không chỉnh sửa.
2. **Không sử dụng URL Shortener**: Giữ nguyên URL đích gốc đầy đủ trong thuộc tính `href` của thẻ HTML `<a>`.
3. **Xử lý tận gốc tại `RichTextMailProcessor::injectData()`**:
   - Thay vì quét toàn bộ nội dung HTML sau khi đã render xong (dễ làm ảnh hưởng các URL tĩnh), việc định dạng link được thực hiện **ngay trong bước inject placeholder của RichTextMailProcessor**.
   - **Tự động bảo toàn URL tĩnh (Zero hardcode)**: Các URL tĩnh trong template (như 14 link YouTube/PDF trong `candidate_welcome` hay link do người dùng gõ vào) là text tĩnh, không phải placeholder nên **100% không bị ảnh hưởng**, không cần bất kỳ hardcode loại trừ template nào.
4. **Nhận diện biến Link qua tên placeholder**:
   - Chỉ các placeholder có tên kết thúc bằng `_link`, `_url` hoặc bắt đầu bằng `link_to_` (ví dụ: `{registration_link}`, `{login_link}`, `{candidate_rtw_link}`...) mới được kích hoạt cơ chế bọc thẻ `<a>`.
   - Các biến text thông thường (`{candidate_name}`, `{branch_name}`...) vẫn giữ nguyên cơ chế escape `htmlspecialchars()` chống XSS.
   - Các biến đã là mã HTML button sẵn (như `{login_to_gap_profile_button}`, `{complete_registration_button_...}`) được giữ nguyên định dạng HTML ban đầu.
5. **Nhãn ngữ cảnh thông minh (Contextual Label Detection)**:
   - Nếu placeholder đứng riêng 1 dòng: Gán nhãn **`Click here`** (nổi bật như một Call-To-Action).
   - Nếu từ đứng liền trước kết thúc bằng *"click"* / *"clicking"* / *"this link"*: Gán nhãn **`here`** (*"Please click [here]..."*, *"by clicking [here]..."* để tránh lặp từ).
   - Nếu từ đứng liền trước kết thúc bằng *"follow this"*: Gán nhãn **`link`** (*"Please follow this [link]..."*).
   - Nếu placeholder đang nằm trong thuộc tính `href="{registration_link}"` của một thẻ `<a>` sẵn có: Chỉ inject URL thô để bảo toàn nhãn do người soạn đã thiết lập.

---

## 2. Database Design
- **Không thay đổi Database**: Không tạo migration, không thêm bảng, không sửa cột.

---

## 3. API Contract & Docs-First Assessment (Pre-Deployment Gate)

### 3.1. Đánh giá API Contract / API Docs
- **Endpoint `GET /api/r/{token}`**: Từng được thêm vào repo [`crs-api-docs`](file:///Users/nexusfrontiertech/projects/crs-api-docs) với trạng thái `NOT YET DEPLOYED`.
- Vì phương án ShortLink bị hủy bỏ và không triển khai trên backend, tài liệu API cần được dọn dẹp để đồng bộ đúng thực tế.
- **Kế hoạch 2 Phase**:
  - **Phase 1 (Docs-First — Bắt buộc)**:
    1. Xóa file `docs/api/general/get-r-token.md` trên `crs-api-docs`.
    2. Xóa dòng `GET /api/r/{token}` trong bảng `docs/api/general/index.md`.
    3. Chạy `npm run build` trong `crs-api-docs` xác minh build thành công không lỗi link.
    4. Commit với message `docs(GAP-743): remove short-link redirect endpoint` và push lên `main` của `crs-api-docs`.
  - **Phase 2 (Backend Code Implementation)**:
    - Triển khai code trên backend theo đúng thiết kế tại `RichTextMailProcessor`.

---

## 4. Business Logic & Architecture

### 4.1. Nâng cấp `RichTextMailProcessor`
Chỉnh sửa file: [`app/Services/Mail/RichTextMailProcessor.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/Mail/RichTextMailProcessor.php).

#### Constants:
```php
public const LABEL_CLICK_HERE = 'Click here';
public const LABEL_HERE = 'here';
public const LABEL_LINK = 'link';
```

#### Thuật toán nhận diện nhãn ngữ cảnh (`detectLinkLabel`):
```php
    /**
     * Detect the appropriate display label for a link anchor based on the preceding text context.
     * Prevents awkward repetition (e.g. "Please click Click here") and creates natural phrasing.
     */
    private function detectLinkLabel(string $cleanBefore): string
    {
        // 1. Preceded by "click", "clicking", or "clicked" -> label is "here" (e.g. "Please click here")
        if (preg_match('/\b(click|clicking|clicked)\s*$/i', $cleanBefore)) {
            return self::LABEL_HERE;
        }

        // 2. Preceded by "this link" or "the link" -> label is "here" (e.g. "by following this link here")
        if (preg_match('/\b(?:this|the)\s+link\s*$/i', $cleanBefore)) {
            return self::LABEL_HERE;
        }

        // 3. Preceded by "follow this" -> label is "link" (e.g. "Please follow this link")
        if (preg_match('/\bfollow\s+this\s*$/i', $cleanBefore)) {
            return self::LABEL_LINK;
        }

        // 4. Default: standalone on a new line or generic context -> prominent CTA "Click here"
        return self::LABEL_CLICK_HERE;
    }
```

#### Kiểm tra biến Link (`isLinkPlaceholder`):
```php
    /**
     * Check if a placeholder key follows the link naming convention (*_link, *_url, link_to_*).
     * This avoids hardcoding template IDs/types while leaving static URLs untouched.
     */
    private function isLinkPlaceholder(string $key): bool
    {
        return (bool) preg_match('/(?:_link|_url|^link_to_)/i', $key);
    }
```

#### Xử lý inject dữ liệu (`injectData`):
Triển khai thực tế sử dụng `PREG_OFFSET_CAPTURE` với đầy đủ inline comments bằng tiếng Anh:
```php
    public function injectData(string $html, array $data): string
    {
        if (empty($data)) {
            return $html;
        }

        // Use PREG_OFFSET_CAPTURE to get the exact byte position of each placeholder in $html,
        // allowing inspection of preceding context for link label detection and tag attribute checks.
        return (string) preg_replace_callback(self::PLACEHOLDER_PATTERN, function (array $matches) use ($data, $html): string {
            $key = $matches[1][0];
            $offset = $matches[0][1];
            $legacyKey = '{' . $key . '}';
            if (\array_key_exists($key, $data) || \array_key_exists($legacyKey, $data)) {
                $dataKey = \array_key_exists($key, $data) ? $key : $legacyKey;
                $value = $data[$dataKey];
                if (\is_null($value)) {
                    return '';
                }

                // 1. Pre-rendered HTML buttons/anchors (e.g. login button HTML)
                // -> Preserve raw HTML markup as-is; do not escape or re-wrap with an <a> tag.
                if (str_starts_with((string) $value, '<a ')) {
                    return (string) $value;
                }

                // 2. Link placeholder (*_link, *_url, link_to_*) with a valid URL value
                if ($this->isLinkPlaceholder($key) && filter_var($value, FILTER_VALIDATE_URL) !== false) {
                    $before = substr($html, 0, $offset);

                    // Check if the placeholder is inside an HTML tag attribute
                    // (e.g. inside an existing attribute: <a href="{registration_link}"> or <img src="{...}">).
                    $lastOpen = strrpos($before, '<');
                    $lastClose = strrpos($before, '>');
                    $isInsideTag = ($lastOpen !== false && ($lastClose === false || $lastOpen > $lastClose));

                    // If inside a tag attribute, inject only the raw escaped URL to prevent broken HTML markup.
                    if ($isInsideTag) {
                        return htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
                    }

                    // Extract preceding clean text to detect the appropriate contextual label ('here', 'link', 'Click here').
                    $cleanBefore = trim(strip_tags($before));
                    $label = $this->detectLinkLabel($cleanBefore);

                    // Check if the placeholder is inner text inside an unclosed <a> anchor
                    // (e.g. template authored as: <a href="https://example.com">{registration_link}</a>).
                    preg_match_all('/<a\b[^>]*>/i', $before, $openA, PREG_OFFSET_CAPTURE);
                    preg_match_all('/<\/a\s*>/i', $before, $closeA, PREG_OFFSET_CAPTURE);
                    $lastOpenA = !empty($openA[0]) ? end($openA[0])[1] : -1;
                    $lastCloseA = !empty($closeA[0]) ? end($closeA[0])[1] : -1;
                    $isInsideAnchor = ($lastOpenA > $lastCloseA);

                    // If already inside an anchor tag, inject only the label to prevent invalid nested anchors (<a><a>...</a></a>).
                    if ($isInsideAnchor) {
                        return $label;
                    }

                    // Standalone link placeholder in body text -> wrap the URL in an <a> tag with contextual label.
                    return '<a href="' . htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8') . '">' . $label . '</a>';
                }

                // 3. Regular text placeholders -> escape HTML entities to prevent XSS.
                return htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
            }

            return $matches[0][0];
        }, $html, -1, $count, PREG_OFFSET_CAPTURE);
    }
```

### 4.2. Tích hợp trong Mail Sending Pipeline
- **Rich-text Email (`$emailTemplate->isRichText = true`)**:
  - `MailSenderAccessor::send()` gọi `$content = $this->richTextProcessor->process($emailTemplate->content, $data);` $\rightarrow$ Áp dụng logic chuyển đổi link placeholder thành thẻ `<a>` có nhãn ngữ cảnh.
- **Legacy Plain-text Email (`$emailTemplate->isRichText = false`)**:
  - `MailSenderAccessor::send()` gọi `$this->processContentTemplate($emailTemplate->content, $data)` $\rightarrow$ **Giữ nguyên 100% logic cũ**, không thay đổi `MailSenderAccessor.php`.

---

## 5. Data Origin & Call Chain Verification

| Biến / Dữ liệu | Nguồn cung cấp | Nơi sử dụng | Đã xác minh? |
|---|---|---|---|
| `$html` | Template HTML từ seeder hoặc `EmailCustom` | `RichTextMailProcessor::injectData()` | ✅ |
| `$data` | Mảng tham số truyền từ caller (`CandidateService`, `AppointmentService`...) | `RichTextMailProcessor::injectData()` | ✅ |
| `$key` | Tên biến trích xuất từ regex `{...}` | `isLinkPlaceholder($key)` | ✅ |
| `$value` | Giá trị URL thật sự trong `$data` (ví dụ registration link) | Thuộc tính `href` của thẻ `<a>` | ✅ |
| `$textBefore` | Đoạn HTML đứng trước vị trí match | `detectLinkLabel($textBefore)` | ✅ |

---

## 6. Files cần sửa đổi / tạo mới

### 6.1. Files Sửa đổi
| File | Thay đổi |
|---|---|
| [`app/Services/Mail/RichTextMailProcessor.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/Mail/RichTextMailProcessor.php) | Thêm constants, logic `detectLinkLabel`, `isLinkPlaceholder`, cập nhật `injectData` và bổ sung inline comments tiếng Anh chi tiết cho toàn bộ thuật toán. |
| [`app/Facades/MailSenderAccessor.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Facades/MailSenderAccessor.php) | **Giữ nguyên 100%** (không sửa đổi vì chỉ áp dụng cho rich-text email, legacy email giữ nguyên). |
| [`app/Http/Middleware/AutoLogout.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Http/Middleware/AutoLogout.php) | Áp dụng fix trả về 401 khi sign out trên nhánh mới. |

### 6.2. Files Tạo mới
| File | Mục đích |
|---|---|
| `tests/Unit/Services/Mail/RichTextMailProcessorTest.php` | Test Unit bao phủ toàn bộ các kịch bản inject placeholder link, label detection, và bảo toàn URL tĩnh. |
| `tests/Feature/Mail/MailSenderIntegrationTest.php` | Test Feature tích hợp qua `MailSenderAccessor::send()`. |

---

## 7. Test Impact & Verification Plan

### 7.1. Test Cases cần viết
1. `testRegistrationLinkPlaceholderGetsWrappedWithClickHere()`:
   - Template: `<p>Please follow link below:</p><p>{registration_link}</p>`
   - Assert: `<p><a href="https://example.com/register">Click here</a></p>`
2. `testPrecedingClickWordAssignsHereLabel()`:
   - Template: `<p>Please click {login_link} to continue</p>`
   - Assert: `<p>Please click <a href="https://example.com/login">here</a> to continue</p>`
3. `testPrecedingFollowThisLinkAssignsHereLabel()`:
   - Template: `<p>Please follow this link {candidate_rtw_link} to renew</p>`
   - Assert: `<p>Please follow this link <a href="https://example.com/rtw">here</a> to renew</p>`
4. `testPrecedingFollowThisAssignsLinkLabel()`:
   - Template: `<p>Please follow this {link_to_candidate_rtw} to see</p>`
   - Assert: `<p>Please follow this <a href="https://example.com/rtw">link</a> to see</p>`
5. `testStaticUrlsInTemplateAreNotModified()`:
   - Template: `<p>Review Complaints Policy <https://apply.gap-personnel.com/downloads/policy.pdf></p>`
   - Assert: Giữ nguyên vẹn URL tĩnh, không bị bọc hay đổi label.
6. `testExistingAnchorWithPlaceholderInHref()`:
   - Template: `<p><a href="{registration_link}">Register Now</a></p>`
   - Assert: `<p><a href="https://example.com/register">Register Now</a></p>` (URL được inject vào `href`, label `Register Now` giữ nguyên).
7. `testHtmlButtonPlaceholderIsPreserved()`:
   - Value: `<a href="..." style="...">Login to gap profile</a>`
   - Assert: Giữ nguyên định dạng button HTML.
8. `testNonLinkPlaceholdersAreEscaped()`:
   - Value: `<script>alert(1)</script>` trong `{candidate_name}`
   - Assert: Được escape thành `&lt;script&gt;...`.

### 7.2. Verification Commands
- Chạy unit test: `./vendor/bin/phpunit tests/Unit/Services/Mail/RichTextMailProcessorTest.php`
- Chạy feature test: `./vendor/bin/phpunit tests/Feature/Mail/MailSenderIntegrationTest.php`
- Chạy full test suite: `./vendor/bin/phpunit`

---

## 8. Phased Execution Plan

- **Phase 1 (Docs-First — Bắt buộc)**:
  1. Cập nhật `~/projects/crs-api-docs`:
     - Xóa `docs/api/general/get-r-token.md`.
     - Xóa dòng `GET /api/r/{token}` trong `docs/api/general/index.md`.
  2. Chạy `cd ~/projects/crs-api-docs && npm run build` kiểm tra build PASS (0 broken links).
  3. Commit: `docs(GAP-743): remove short-link redirect endpoint` và push lên `origin/main`.
- **Phase 2 (Implementation & Verification)**:
  1. Checkout branch làm việc trên nền `develop`.
  2. Cập nhật `RichTextMailProcessor.php` và `MailSenderAccessor.php`.
  3. Viết test suite `RichTextMailProcessorTest.php`.
  4. Chạy PHPUnit và kiểm tra 100% test pass.

---

## 9. Security Hardening: Bổ sung Scheme Whitelist cho Link Placeholders (`isValidHttpUrl`)

### 9.1. Bối cảnh & Lỗ hổng bảo mật (Stored XSS)
- **Vấn đề**: `filter_var($value, FILTER_VALIDATE_URL)` chỉ kiểm tra cú pháp URL theo chuẩn RFC 2396, không giới hạn scheme. Các chuỗi nguy hiểm như `javascript://test%0Aalert(1)` hoặc `data://...` hoàn toàn vượt qua `filter_var()`.
- **Hậu quả**: Khi một placeholder biến link (ví dụ `{meeting_link}` trong `AppointmentService` lấy từ `appointmentData['meeting_url']` do consultant nhập) nhận giá trị `javascript://...`, hệ thống sẽ bọc thành `<a href="javascript://...">Click here</a>`. Hàm `htmlspecialchars()` chỉ escape ký tự `< > " ' &`, hoàn toàn không vô hiệu hóa được scheme `javascript:`, dẫn đến lỗ hổng Stored XSS khi ứng viên click vào link trong email.
- **Giải pháp**: Thay thế `filter_var` đơn thuần bằng helper `isValidHttpUrl($value)` bắt buộc scheme phải nằm trong whitelist an toàn: `['http', 'https']`.

### 9.2. API Contract & API Docs Pre-Deployment Gate
- **Đánh giá**: Thay đổi nội bộ trong thuật toán xử lý HTML email của `RichTextMailProcessor`, không thay đổi route, input/output payload, hoặc documentation của API.
- **Kết luận**: `N/A — no API contract/API docs change`.

### 9.3. Thiết kế chi tiết

#### Method `isValidHttpUrl` trong [`app/Services/Mail/RichTextMailProcessor.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/Mail/RichTextMailProcessor.php):
```php
    /**
     * Validate that a URL is syntactically valid and uses a safe web scheme (http/https).
     * Prevents Stored XSS via dangerous schemes such as javascript: or data:.
     */
    private function isValidHttpUrl(mixed $value): bool
    {
        if (!\is_string($value) || filter_var($value, FILTER_VALIDATE_URL) === false) {
            return false;
        }

        $scheme = strtolower((string) parse_url($value, PHP_URL_SCHEME));

        return \in_array($scheme, ['http', 'https'], true);
    }
```

#### Áp dụng trong `injectData()`:
```php
    // 2. Link placeholder (*_link, *_url, link_to_*) with a valid safe HTTP/HTTPS URL
    if ($this->isLinkPlaceholder($key) && $this->isValidHttpUrl($value)) {
        // ... logic bọc thẻ <a> giữ nguyên vẹn ...
    }
```
- Các URL có scheme không an toàn (`javascript:...`, `data:...`) hoặc không phải URL hợp lệ sẽ không được bọc thẻ `<a>`, mà rơi xuống bước 3 escape thành text trơ an toàn qua `htmlspecialchars()`.

### 9.4. Test Impact & Verification Plan

#### Test cases bổ sung trong [`tests/Unit/Services/RichTextMailProcessorTest.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/tests/Unit/Services/RichTextMailProcessorTest.php):
1. `testJavascriptSchemeUrlIsNotWrappedAsAnchorAndIsEscaped()`:
   - Input: `<p>Join meeting: {meeting_link}</p>`
   - Data: `['{meeting_link}' => 'javascript://test%0Aalert(1)']`
   - Expected Output: `<p>Join meeting: javascript://test%0Aalert(1)</p>` (text trơ, không có thẻ `<a>`).
2. `testDataSchemeUrlIsNotWrappedAsAnchorAndIsEscaped()`:
   - Input: `<p>Download: {download_url}</p>`
   - Data: `['{download_url}' => 'data://text/plain;base64,123']`
   - Expected Output: `<p>Download: data://text/plain;base64,123</p>` (text trơ, không có thẻ `<a>`).
3. `testHttpAndHttpsUrlsContinueToBeWrappedCorrectly()`:
   - Xác minh URL `http://` và `https://` vẫn được bọc thẻ `<a>` bình thường.

#### Verification Commands:
- `./vendor/bin/phpunit tests/Unit/Services/RichTextMailProcessorTest.php`
- `./vendor/bin/phpunit tests/Feature/Mail/MailSenderIntegrationTest.php`

