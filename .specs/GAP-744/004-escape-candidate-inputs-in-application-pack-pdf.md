# SPEC: [GAP-744] Output-Side Escaping for Candidate Inputs in Application Pack PDF

> **Trạng thái**: `DONE`  
> **Ngày tạo**: 2026-10-27  
> **Task Key**: `GAP-744`  
> **Author**: Antigravity  
> **Liên kết liên quan**: [001-clickable-hyperlinks-application-pack-pdf.md](001-clickable-hyperlinks-application-pack-pdf.md)  

---

## 1. Tổng quan

### 1.1. Bối cảnh & Vấn đề bảo mật
Trong commit `c7451940fc9` (`#744: fix old button click here not active`), biến `$tempMainPdfFilePath` được thêm vào `$allowedLinkFiles` trong [`ApplicationPackService::generateApplicationPack()`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ApplicationPackService.php#L214) để kích hoạt các link tĩnh trên trang chính (`48_hour.pdf`, privacy notice, email DPO).

Tuy nhiên, Claude Review đã phát hiện lỗ hổng bảo mật `[High]`:
- Trang Main PDF (`$tempMainPdfFilePath`) được xây dựng qua [`getHtml()`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ApplicationPackService.php#L730) chứa rất nhiều dữ liệu do ứng viên nhập (họ tên, địa chỉ, các câu trả lời tự do qua `getAnswerByCategory()`, lịch sử việc làm).
- Hiện tại, các hàm format HTML trong file này đang nối chuỗi thô mà không escape HTML đầu ra. Nếu ứng viên nhập các thẻ dạng `<a href="https://phishing.com">...</a>`, Dompdf sẽ sinh ra đối tượng PDF `/Subtype /Link`, và [`copyPageLinkAnnotations()`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ApplicationPackService.php#L605) sẽ sao chép toàn bộ các link này vào file PDF Application Pack chính thức được ký duyệt và gửi cho Consultant/Client.
- Việc chỉ dựa vào middleware `XssProtection` (`strip_tags`) ở tầng HTTP request là không đủ nguyên tắc phòng vệ chiều sâu (Defense-in-depth).

### 1.2. Mục tiêu xử lý
1. Áp dụng **Output-Side Escaping** toàn diện cho tất cả dữ liệu do ứng viên kiểm soát (Candidate-controlled inputs) trong [`ApplicationPackService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ApplicationPackService.php).
2. Sử dụng helper chuẩn và ngắn gọn `e($value)` của Laravel (tương đương `htmlspecialchars($value ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8')`), hoặc `StringUtility::escapeHtml($value)` nếu cần tính đóng gói trong Utility.
3. Giữ nguyên `$tempMainPdfFilePath` trong `$allowedLinkFiles` để các link tĩnh nội bộ (`48_hour.pdf`, privacy notice, mailto DPO) vẫn hoạt động bình thường, trong khi toàn bộ link injection tiềm ẩn từ dữ liệu ứng viên bị vô hiệu hóa hoàn toàn trước khi vào Dompdf.
4. Cập nhật comment giải thích kiến trúc tại `$allowedLinkFiles` cho chính xác.

### 1.3. API Contract / API Docs Pre-Deployment Gate
- **Đánh giá**: Thay đổi nội bộ thuật toán escape HTML khi render PDF trong `ApplicationPackService`. Không thay đổi route, request/response schema, error contract hay API documentation.
- **Kết luận**: `N/A — no API contract/API docs change`.

---

## 2. Chi tiết Thiết kế & Thay đổi Code

### 2.1. Lựa chọn Hàm Helper Escape HTML
Để thay thế cho chuỗi dài `htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8')`:
- **Giải pháp chính (Khuyến nghị)**: Sử dụng helper global chuẩn của Laravel: **`e($value)`**.
  - `e($value)` được Laravel định nghĩa: `htmlspecialchars($value ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8', false)`.
  - Có sẵn toàn cục trong framework, tự động xử lý an toàn giá trị `null`, ngắn gọn, trực quan và đúng chuẩn Laravel convention.
- **Giải pháp bổ trợ (tùy chọn)**: Khai báo thêm `StringUtility::escapeHtml(?string $value): string` trong [`App\Utilities\StringUtility`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Utilities/StringUtility.php) nếu muốn tập trung qua Utility.

*(Trong bản thiết kế này, chúng ta sẽ dùng `e($value)` cho ngắn gọn và sạch code).*

---

### 2.2. Các Vị trí Cụ thể Cần Sửa trong [`app/Services/ApplicationPackService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/ApplicationPackService.php)

#### Vị trí 1: `writeItemTitleAndValue` (Dòng 918 - 936)
Hàm này in hơn 30 trường dữ liệu cá nhân, ngân hàng, và câu trả lời tự do từ `getAnswerByCategory`:
```php
// BEFORE:
private function writeItemTitleAndValue(string $title, string $value, bool $withOutStrongForTitle = false): string
{
    $content = '';
    if ($withOutStrongForTitle) {
        $content = $title.': '.$value;
    } else {
        $content = '<strong>'.$title.'</strong>: '.$value;
    }
...

// AFTER:
private function writeItemTitleAndValue(string $title, string $value, bool $withOutStrongForTitle = false): string
{
    $safeValue = e($value);
    $content = '';
    if ($withOutStrongForTitle) {
        $content = $title.': '.$safeValue;
    } else {
        $content = '<strong>'.$title.'</strong>: '.$safeValue;
    }
...
```

#### Vị trí 2: `writeEmploymentAndEducationHistoryDetails` (Dòng 1305 - 1317)
Hàm này in các trường do ứng viên nhập trong lịch sử việc làm/học vấn (company_name, job_title, job_description, institution_name):
```php
// BEFORE:
private function writeEmploymentAndEducationHistoryDetails(string $title, string $value): string
{
    $html = '';
    $html .= $this->box(
        'box-3rd-level',
        $this->typography(
            'typography-subtitle2',
            '<strong>'.$title.'</strong>: '.$value,
        ),
    );

    return $html;
}

// AFTER:
private function writeEmploymentAndEducationHistoryDetails(string $title, string $value): string
{
    $html = '';
    $html .= $this->box(
        'box-3rd-level',
        $this->typography(
            'typography-subtitle2',
            '<strong>'.$title.'</strong>: '.e($value),
        ),
    );

    return $html;
}
```

#### Vị trí 3: Họ tên ứng viên & Tiêu đề trong Header / Agreement (Dòng 950 & 1603)
- Tại `getHeader` (Dòng 950):
  ```php
  // BEFORE:
  '<strong>'.$candidate->fullName().' - Application Pack</strong>',
  // AFTER:
  '<strong>'.e($candidate->fullName()).' - Application Pack</strong>',
  ```
- Tại `getAgreements` (Dòng 1603):
  ```php
  // BEFORE:
  $completedDate->format('d-m-Y @ H:i:s').' by '.$candidate->fullName(),
  // AFTER:
  $completedDate->format('d-m-Y @ H:i:s').' by '.e($candidate->fullName()),
  ```
- Tại `getOptInsAndDeclarations` (Dòng 1539 & 1556 - câu trả lời Data Protection & Marketing):
  ```php
  // BEFORE:
  $explanation.': '.$this->getAnswerByCategory($answers, Question::DATA_PROTECTION)
  $explanation.': '.$this->getAnswerByCategory($answers, Question::MARKETING)
  // AFTER:
  $explanation.': '.e($this->getAnswerByCategory($answers, Question::DATA_PROTECTION))
  $explanation.': '.e($this->getAnswerByCategory($answers, Question::MARKETING))
  ```

#### Vị trí 5: Cập nhật Security Comment tại `$allowedLinkFiles` (Dòng 212 - 216)
Cập nhật comment phản ánh đúng việc `$tempMainPdfFilePath` đã được bảo vệ bằng output-side escaping:
```php
// BEFORE:
// Restrict link preservation to trusted internal files (timing page) to prevent malicious or untrusted annotations
$allowedLinkFiles = array_values(array_filter([
    $tempMainPdfFilePath,
    !empty($timingHtml) ? $tempTimingPdfFilePath : null,
]));

// AFTER:
// Restrict link preservation to internal system templates (main details and timing page).
// Candidate-controlled inputs in the main template are escaped via e() to prevent untrusted link annotations.
$allowedLinkFiles = array_values(array_filter([
    $tempMainPdfFilePath,
    !empty($timingHtml) ? $tempTimingPdfFilePath : null,
]));
```

---

## 3. Kế hoạch Kiểm thử (Verification Plan)

### 3.1. Unit Test
1. Chạy test suite `ApplicationPackServiceTest`:
   ```bash
   docker exec gap-web-backend-laravel.test-1 ./vendor/bin/phpunit tests/Unit/Services/ApplicationPackServiceTest.php
   ```
2. Thêm test case xác minh:
   - Khi câu trả lời hoặc tên ứng viên chứa mã HTML (`<a href="https://malicious.example.com">Evil Link</a>`), chuỗi HTML được escape thành `&lt;a href=...&gt;` trong HTML và không tạo ra thẻ link DOM thực thụ.

### 3.2. Regression Tests
Chạy toàn bộ Service Unit Tests:
```bash
docker exec gap-web-backend-laravel.test-1 ./vendor/bin/phpunit tests/Unit/Services/
```

### 3.3. Test Xuất PDF Thực tế
Chạy lệnh `TestCommand`:
```bash
docker exec gap-web-backend-laravel.test-1 php artisan cmd:test --action=pdf-export
```
- Xác minh file `public/temp_app_pack_candidate_4231.pdf` được sinh bình thường.
- Kiểm tra các link tĩnh (`48_hour.pdf`, privacy notice, KID link) vẫn giữ nguyên clickable link annotations.
