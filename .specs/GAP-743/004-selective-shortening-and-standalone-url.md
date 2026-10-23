# SPEC: GAP-743 — Selective Shortening & Standalone URL Shortener

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-23
> **Author**: Antigravity
> **Nguồn yêu cầu**: Áp dụng Giải pháp 2 (loại bỏ rút gọn thừa) & mở rộng hàm `shortenUrl` cho các module khác (GAP-743).
> **Template**: [.specs/SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md)

---

## 1. Tổng quan

Kế hoạch này thực hiện 2 mục tiêu chính theo yêu cầu của dự án:
1. **Áp dụng Giải pháp 2 — Rút gọn có chọn lọc (Selective Shortening)**:
   - Khắc phục sự thừa thãi tài nguyên khi lưu database cho các link ngắn/tĩnh ở footer hoặc trong nội dung đã có nhãn người đọc (human-readable label).
   - Chỉ quét và rút gọn link trong HTML email khi thỏa mãn 1 trong 2 điều kiện:
     - Nhãn hiển thị chính là URL (`$label === $href`): Rút gọn để tránh vỡ dòng và làm đẹp giao diện người dùng.
     - HOẶC URL gốc quá dài (`strlen($href) > 100` ký tự): Rút gọn `href` ngầm để tránh lỗi email server/client chèn ngắt dòng làm hỏng token (MIME Quoted-Printable line wrapping).
   - Các link ngắn ($\le 100$ ký tự) đã có sẵn nhãn hoặc nút bấm (ví dụ: `<a href="https://gap-personnel.com/privacy-policy">Chính sách</a>`) được **giữ nguyên 100%**, không tốn bản ghi trong bảng `short_links`.
2. **Hỗ trợ rút gọn URL đơn lẻ (Standalone URL Shortening)**:
   - Bổ sung `shortenUrl(string $url): string` và `shortenUrls(array $urls): array` vào [`ShortLinkServiceInterface`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Contracts/Services/ShortLinkServiceInterface.php).
   - Tách phần core logic tạo token, mã hóa và batch insert thành `shortenUrls()`, giúp bất kỳ module nào (SMS, thông báo, plain-text email, API, webhook...) đều có thể tái sử dụng trực tiếp mà không cần bọc trong thẻ HTML `<a>`.

---

## 2. Database Design

Không thay đổi database schema. Tận dụng bảng `short_links` hiện tại:
- `token_hash`: string(64), unique.
- `destination_url`: text, encrypted.
- `created_at`, `updated_at`: timestampsTz.

---

## 3. API Contract & Pre-Deployment Assessment

### 3.1. Đánh giá API Contract / API Docs

- **Endpoint**: `GET /api/r/{token}`
- **Kết quả đánh giá**: `N/A — no API contract/API docs change`.
  - Không thay đổi route, tham số, mã HTTP response hay cấu trúc dữ liệu của API public redirect.
  - Các thay đổi hoàn toàn nằm ở tầng Service (`ShortLinkServiceInterface`) và luồng tiền xử lý nội dung.

---

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

#### A. Luồng rút gọn URL đơn lẻ (`shortenUrl`)
```text
Caller (SMS, Notification, API...)
  → ShortLinkService::shortenUrl($url)
    → Gọi ShortLinkService::shortenUrls([$url])
      → Validate URL scheme (http/https) và format
      → Sinh random token 10 ký tự, hash SHA-256
      → Batch insert vào short_links (Single query)
      → Trả về map [$url => $shortUrl]
    → Trả về $shortUrl (hoặc $url gốc nếu thất bại)
```

#### B. Luồng rút gọn email HTML rich-text (`shortenRenderedBody`)
```text
MailSenderAccessor::send()
  → ShortLinkService::shortenRenderedBody($content)
    → extractDestinations($content):
        Quét các thẻ <a href="...">...</a>
        Lấy $href và $label (strip tags, decode entity)
        Điều kiện Giải pháp 2:
          - Nếu ($label === $href) HOẶC (strlen($href) > 100): Gom vào $destinations
          - Ngược lại: BỎ QUA (giữ nguyên thẻ <a> gốc)
    → Gọi shortenUrls($destinations) theo batch
    → replaceDestinations($content, $shortUrls):
        Thay href cũ thành short URL
        Nếu ($label === $href), thay luôn text hiển thị thành short URL
        Nếu ($label !== $href), giữ nguyên nhãn hiển thị cũ
  → Trả về HTML đã được rewrite
```

### 4.2. Business Rules

1. **Ngưỡng độ dài an toàn (`SAFE_URL_LENGTH_THRESHOLD = 100`)**:
   - Khai báo hằng số `public const SAFE_URL_LENGTH_THRESHOLD = 100;`.
   - Một URL có độ dài $\le 100$ ký tự được coi là an toàn trước hiện tượng email client soft-wrapping, trừ khi URL đó được in trần ra màn hình làm nhãn hiển thị.
2. **Nguyên tắc Fail-safe**:
   - Nếu việc tạo short link thất bại (lỗi DB, invalid base URL, exception), luôn trả về URL gốc ban đầu để không làm gián đoạn luồng nghiệp vụ của caller.
3. **Tuân thủ quy tắc Batch Insert**:
   - Phương thức `shortenUrls(array $urls)` gom toàn bộ records và gọi `ShortLinkRepository::createMany()` một lần duy nhất, tuyệt đối không query/insert trong vòng lặp.
4. **Bảo toàn Nhãn Người Đọc (Human-readable Label Preservation)**:
   - Với các link dài được rút gọn mà có nhãn người đọc (ví dụ: `<a href="https://long-url...">Đăng ký ngay</a>`), chỉ có thuộc tính `href` được đổi thành short URL, text hiển thị `Đăng ký ngay` được giữ nguyên.

---

## 5. Data Origin & Call Chain

| Biến / Dữ liệu | Nguồn cung cấp | Nơi sử dụng | Đã xác minh? |
|---|---|---|---|
| `$url` | Caller (SMS service, Job, API, Command...) | `ShortLinkService::shortenUrl()` | ✅ |
| `$urls` | Danh sách URL mảng từ Caller hoặc `extractDestinations()` | `ShortLinkService::shortenUrls()` | ✅ |
| `$content` | Rendered HTML từ `RichTextMailProcessor` qua `MailSenderAccessor` | `ShortLinkService::shortenRenderedBody()` | ✅ |
| `$href` | Trích xuất từ thuộc tính `href` của thẻ `<a>` | `extractDestinations` & `replaceDestinations` | ✅ |
| `$label` | `strip_tags($matches[2])` của thẻ `<a>` | So sánh `$label === $href` | ✅ |

---

## 6. Constants & Enums

Khai báo trong [`ShortLinkService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ShortLinkService.php) (hoặc Contract):

```php
public const SAFE_URL_LENGTH_THRESHOLD = 100;
```

---

## 7. Files cần tạo/sửa

### 7.1. Files sửa đổi

| File | Thay đổi |
|---|---|
| [`app/Contracts/Services/ShortLinkServiceInterface.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Contracts/Services/ShortLinkServiceInterface.php) | Khai báo 2 method mới: `shortenUrl(string $url): string` và `shortenUrls(array $urls): array`. |
| [`app/Services/ShortLinkService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ShortLinkService.php) | 1. Bổ sung const `SAFE_URL_LENGTH_THRESHOLD = 100`.<br>2. Thêm method `shortenUrls(array $urls): array` tách từ logic batch hiện tại.<br>3. Thêm method `shortenUrl(string $url): string` gọi `shortenUrls([$url])`.<br>4. Cập nhật `extractDestinations` theo Giải pháp 2 (chỉ lấy link có `$label === $href` hoặc `strlen > 100`).<br>5. Refactor `shortenRenderedBody` để tái sử dụng `shortenUrls`. |
| [`tests/Unit/Services/ShortLinkServiceTest.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/tests/Unit/Services/ShortLinkServiceTest.php) | Bổ sung Unit test cases cho: `shortenUrl`, `shortenUrls`, bỏ qua link ngắn có nhãn chữ, rút gọn link dài có nhãn chữ, rút gọn link ngắn nhưng có nhãn là URL trần. |

---

## 8. Test Impact & Verification Plan

### 8.1. Test Cases cần bổ sung trong `tests/Unit/Services/ShortLinkServiceTest.php`

1. `testShortenUrlReturnsShortUrlForValidDestination()`:
   - Gọi `shortenUrl('https://example.com/test')`.
   - Assert trả về đúng format `https://short.example/api/r/{token}` (10 ký tự token).
2. `testShortenUrlReturnsOriginalUrlWhenInvalidDestinationOrBaseUrl()`:
   - Gọi `shortenUrl('invalid-url')` hoặc `shortenUrl('ftp://example.com')`.
   - Assert trả về nguyên bản URL ban đầu (fail-safe).
3. `testShortenUrlsBatchesMultipleDestinations()`:
   - Truyền mảng 3 URL vào `shortenUrls()`.
   - Assert repository nhận 3 records trong 1 lượt `createMany()`, trả về mảng map 3 short URLs.
4. `testSelectiveShorteningSkipsShortLinksWithHumanReadableLabels()` (Giải pháp 2):
   - HTML: `<p><a href="https://example.com/short">Policy</a></p>`.
   - Vì độ dài URL $\le 100$ và nhãn không phải URL, assert repository `createMany` **KHÔNG** được gọi, HTML trả về nguyên vẹn không đổi.
5. `testSelectiveShorteningShortensLongLinksWithHumanReadableLabels()` (Giải pháp 2):
   - HTML: `<p><a href="https://example.com/very-long-url-path-that-exceeds-one-hundred-characters-in-total-length-for-email-testing-purposes-1234567890">Policy</a></p>`.
   - Vì URL dài > 100 ký tự, assert `href` được đổi thành short URL, nhưng nhãn hiển thị vẫn là `Policy`.
6. `testSelectiveShorteningShortensShortLinksWhenLabelIsRawUrl()` (Giải pháp 2):
   - HTML: `<p><a href="https://example.com/short">https://example.com/short</a></p>`.
   - Vì nhãn trùng với URL, assert cả `href` lẫn nhãn hiển thị đều được đổi thành short URL.

### 8.2. Verification Gate

Chạy toàn bộ test suites bị ảnh hưởng:
```bash
./vendor/bin/phpunit tests/Unit/Services/ShortLinkServiceTest.php
./vendor/bin/phpunit tests/Feature/Api/General/PublicShortLinkTest.php
./vendor/bin/phpunit tests/Feature/Api/General/RichTextMailShortLinkTest.php
```
Tất cả các assertions phải đạt 100% PASS.

---

## 9. Checklist trước khi Approve

- [x] Không thay đổi Database schema
- [x] Đánh giá API contract: `N/A — no API contract/API docs change`
- [x] Business rules rõ ràng (ngưỡng 100 ký tự, logic chọn lọc)
- [x] Tái sử dụng code sạch sẽ, tuân thủ DRY và không query trong loop
- [x] Call chain đã trace và xác minh
- [x] Đầy đủ file list theo kiến trúc phân lớp
- [x] Test cases bao phủ toàn diện cả use-case đơn lẻ lẫn Giải pháp 2
