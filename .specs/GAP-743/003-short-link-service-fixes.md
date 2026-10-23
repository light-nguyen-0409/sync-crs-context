# SPEC: GAP-743 — ShortLinkService Fixes & Refinements

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-23
> **Author**: Antigravity
> **Nguồn yêu cầu**: Review & phản hồi comment về ShortLink (GAP-743)
> **Quyết định đã chốt với User**: Lựa chọn 2 — Bỏ hoàn toàn cột `expires_at` khỏi migration, Model, Service và Test.
> **Template**: [.specs/SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md)

---

## 1. Tổng quan

Kế hoạch này giải quyết các vấn đề được phát hiện trong quá trình rà soát và review code của module `ShortLink` (theo GAP-743):
1. **Sửa lỗi trích xuất href nháy đơn/không nháy**: `ShortLinkService::extractHref()` gặp lỗi với regex capture group khi thẻ `<a>` dùng nháy đơn (`<a href='...'>`) hoặc không nháy, khiến link bị bỏ qua và không được rút gọn (silent failure).
2. **Xử lý ngoại lệ giải mã (Decryption Error Handling)**: `ShortLinkService::resolve()` ném unhandled `DecryptException` (HTTP 500) khi dữ liệu destination bị hỏng hoặc key xoay vòng; cần bắt và chuyển thành HTTP 404 (`ShortLinkNotFoundException`).
3. **Bỏ hoàn toàn `expires_at` (Lựa chọn 2 đã được phê duyệt)**:
   - Xóa cột `expires_at` khỏi migration [`database/migrations/2026_10_16_120000_create_short_links_table.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/database/migrations/2026_10_16_120000_create_short_links_table.php) (do branch `GAP-743-bug-invitation-link-breaking` chưa merge vào `develop`).
   - Xóa `expires_at` khỏi `$fillable` và `$casts` trong [`ShortLink.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Models/ShortLink.php).
   - Xóa `'expires_at' => null` khỏi [`ShortLinkService::shortenRenderedBody()`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ShortLinkService.php).
   - Xóa logic kiểm tra `expires_at` trong [`ShortLinkService::resolve()`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ShortLinkService.php).
4. **Kiến trúc Link Reuse & Batch Insert**:
   - Giữ nguyên cơ chế batch `insert` trong `ShortLinkRepository::createMany()` (tuân thủ quy tắc "No Database Queries in Loops").
   - Giữ cơ chế sinh token ngẫu nhiên độc lập cho mỗi link gửi đi.

---

## 2. Database Design

### 2.1. Bảng `short_links`

Sửa trực tiếp migration tạo bảng: `database/migrations/2026_10_16_120000_create_short_links_table.php`.

```
Tên bảng: short_links
```

| Cột | Kiểu | Nullable | Default | Mô tả |
|-----|------|----------|---------|-------|
| `id` | bigIncrements | NO | — | Primary key |
| `token_hash` | string(64) | NO | — | SHA-256 hash của token public; unique index |
| `destination_url` | text | NO | — | URL gốc đã mã hóa bằng model cast encrypted |
| `created_at` | timestampTz | YES | null | Laravel timestamp |
| `updated_at` | timestampTz | YES | null | Laravel timestamp |

*(Cột `expires_at` bị xóa bỏ hoàn toàn).*

---

## 3. API Contract & Pre-Deployment Assessment

### 3.1. Đánh giá API Contract / API Docs

- **Endpoint**: `GET /api/r/{token}`
- **Kết quả đánh giá**: `N/A — no API contract/API docs change`.
  - Route, tham số `token`, HTTP status (302 Found khi thành công, 404 Not Found khi thất bại) không thay đổi so với tài liệu hiện hành tại `crs-api-docs` (`docs/api/general/get-r-token.md`).
  - Lỗi giải mã destination URL trả về 404 theo đúng contract đã tài liệu hóa: *"404 Not Found: Token does not exist, has been invalidated, or cannot be resolved."*

---

## 4. Business Logic (Service Layer)

### 4.1. Sửa lỗi `extractHref()` trong [`ShortLinkService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ShortLinkService.php)

- **Nguyên nhân**: Pattern `HREF_PATTERN = "/(\\bhref\\s*=\\s*)(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))/i"` có 3 nhánh capture group. Khi href là nháy đơn hoặc không nháy, PHP PCRE vẫn set `$matches[2] = ""` khiến `isset($matches[2])` là true và return `""`.
- **Giải pháp**: Kiểm tra `isset($matches[$index]) && $matches[$index] !== ''`.

```php
foreach ([2, 3, 4] as $index) {
    if (isset($matches[$index]) && $matches[$index] !== '') {
        return html_entity_decode($matches[$index], ENT_QUOTES | ENT_HTML5, 'UTF-8');
    }
}
```

### 4.2. Xử lý `DecryptException` trong `resolve()`

- **Giải pháp**: Bọc trong `try ... catch (\Illuminate\Contracts\Encryption\DecryptException)` và throw `ShortLinkNotFoundException()`.

```php
try {
    $destination = (string) $shortLink->destination_url;
} catch (\Illuminate\Contracts\Encryption\DecryptException) {
    throw new ShortLinkNotFoundException();
}
```

### 4.3. Bỏ hoàn toàn `expires_at`

- Trong `ShortLinkService::shortenRenderedBody()`: Bỏ `'expires_at' => null` trong mảng `$records`.
- Trong `ShortLinkService::resolve()`: Xóa bỏ kiểm tra `$shortLink->expires_at`.
- Trong `ShortLink.php`: Bỏ `'expires_at'` trong `$fillable` và `$casts`.

### 4.4. Quyết định kiến trúc: Link Reuse & Batch Insert

1. **Batch Insert trong `ShortLinkRepository`**:
   - Giữ nguyên `ShortLinkRepository::createMany` sử dụng `forceFill` để kích hoạt encryption và Query Builder `insert()` để gom thành 1 câu SQL duy nhất.
   - Không chuyển sang `foreach` + `create()` để tránh N+1 write queries và vi phạm workspace rule.
2. **Tái sử dụng link cũ (Link Reuse)**:
   - Giữ cơ chế sinh token ngẫu nhiên độc lập cho mỗi link gửi đi, tránh xung đột và đảm bảo an toàn.

---

## 5. Files cần tạo/sửa

| File | Thay đổi |
|---|---|
| [`database/migrations/2026_10_16_120000_create_short_links_table.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/database/migrations/2026_10_16_120000_create_short_links_table.php) | Xóa dòng `$table->timestampTz('expires_at')->nullable()->index();` |
| [`app/Models/ShortLink.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Models/ShortLink.php) | Xóa `'expires_at'` khỏi `$fillable` và `$casts` |
| [`app/Services/ShortLinkService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ShortLinkService.php) | 1. Sửa `extractHref()` kiểm tra capture group khác rỗng.<br>2. Bọc `destination_url` với `catch (DecryptException)`.<br>3. Bỏ `'expires_at' => null` và bỏ logic kiểm tra `expires_at`. |
| [`.business-spec/backend-business-flow-spec.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.business-spec/backend-business-flow-spec.md) | Cập nhật SPEC-040: Ghi nhận không có expiry tại short-link redirect layer. |
| [`.business-spec/backend-database-relationship.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.business-spec/backend-database-relationship.md) | Cập nhật bảng `SHORT_LINKS`: Xóa cột `expires_at`. |
| [`tests/Unit/Services/ShortLinkServiceTest.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/tests/Unit/Services/ShortLinkServiceTest.php) | Thêm test case cho href dùng nháy đơn `'...'` và không nháy; cập nhật assert không có `expires_at`. |
| [`tests/Feature/Api/General/PublicShortLinkTest.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/tests/Feature/Api/General/PublicShortLinkTest.php) | Thêm test case decrypt lỗi trả về 404 thay vì 500. |

---

## 6. Test Impact & Verification Plan

### 6.1. Test Execution Gate

- Chạy test suites liên quan:
  ```bash
  ./vendor/bin/phpunit tests/Unit/Services/ShortLinkServiceTest.php
  ./vendor/bin/phpunit tests/Feature/Api/General/PublicShortLinkTest.php
  ./vendor/bin/phpunit tests/Feature/Api/General/RichTextMailShortLinkTest.php
  ```
- Toàn bộ 100% test assertions phải PASS.
