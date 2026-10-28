# SPEC: [GAP-744] Make Links Clickable in Generated Application Pack PDFs (Descriptive Link Text & English Comments)

> **Trạng thái**: `DONE`  
> **Ngày cập nhật**: 2026-10-27  
> **Task Key**: `GAP-744`  
> **Author**: Antigravity  

---

## 1. Tổng quan & Đánh giá thay đổi

### 1.1. Đánh giá thay đổi `$kidLinkHtml` ("Click here")
Thay đổi:
```php
$kidLinkHtml = !empty($kidLink) ? '<a href="' . $kidLink . '" target="_blank" style="color: #1a5490; text-decoration: underline;">Click here</a>' : '';
```

- **Tính đúng đắn và mục tiêu Jira**:
  - Ticket Jira GAP-744 có tiêu đề: *"[Bug/Enhancement] Make Links Clickable and Shorten URLs in Generated PDFs"*.
  - Technical Notes trong Jira yêu cầu: *"Prefer descriptive link text where appropriate to avoid introducing additional dependencies or redirect management."*
  - URL của KID document (issuu link) thường rất dài (hơn 100 ký tự), làm vỡ/tràn dòng trong bảng Timing Log table. Việc thay thế nội dung hiển thị thành `"Click here"` hoàn toàn đáp ứng yêu cầu rút gọn link và giữ layout trang PDF sạch đẹp, đồng thời vẫn giữ nguyên clickable link trỏ tới URL gốc.
  - Về mặt bảo mật: URL vẫn được escape an toàn bằng `htmlspecialchars($timing->kid_link, ENT_QUOTES)`.
- **Lưu ý / Trade-off**:
  - Với PDF in ấn ra giấy vật lý (hard copy printout): Người đọc bản in trên giấy sẽ thấy chữ "Click here" và không thể gõ thủ công URL. Tuy nhiên đây là trade-off đã được chấp thuận trong requirement của Jira ticket.
- **Tình trạng Test Case hiện tại**:
  - **KHÔNG PASS (1 failure)**: Test case `test_timing_html_wraps_kid_link_in_anchor_tag_and_preserves_url_text` trong `tests/Unit/Services/ApplicationPackServiceTest.php` đang assert URL đầy đủ xuất hiện bên trong thẻ `<a>...</a>`. Do đó test bị fail khi so khớp chuỗi HTML.
  - Cần cập nhật lại test assertion thành `'Click here'` và cập nhật tên/docblock của test case cho đúng với hành vi mới.

### 1.2. API Contract & API Docs Pre-Deployment Gate
- **Đánh giá**: Thay đổi này thuộc nội bộ logic sinh file PDF trong `ApplicationPackService`, không thay đổi route, request/response schema, endpoint documentation hay error contract của bất kỳ API nào.
- **Kết luận**: `N/A — no API contract/API docs change`.

---

## 2. Chi tiết thay đổi Code (Implementation Plan)

### 2.1. File `app/Services/ApplicationPackService.php`

1. **Bổ sung English comments cho toàn bộ thay đổi thuộc Task 744**:
   - Tại `generateApplicationPack()`: Comment giải thích việc thu hẹp `$allowedLinkFiles` chỉ cho phép `$tempTimingPdfFilePath` (ngăn chặn trích xuất link annotation từ tài liệu do ứng viên upload hoặc không đáng tin cậy).
   - Tại `margePdfFiles()`: Comment giải thích việc lazy instantiate `StreamReader`/`PdfParser`/`PdfReader` chỉ đối với các file nằm trong allowlist để tối ưu hiệu năng và đảm bảo an toàn.
   - Tại `copyPageLinkAnnotations()`: Bổ sung PHPDoc và inline comments chi tiết bằng tiếng Anh:
     - Mục đích: Trích xuất và bảo toàn các hyperlink annotations từ trang PDF được import sang TcpdfFpdi.
     - Inner try-catch: Cô lập lỗi ở từng annotation để tránh việc 1 link lỗi làm hỏng các link hợp lệ khác trên trang.
     - Scheme allowlist: Chỉ cho phép `http`, `https`, `mailto`.
     - Rect validation & coordinate normalization: Chuẩn hóa toạ độ `min()/max()` theo chuẩn ISO 32000-1 để tránh toạ độ âm khi Dompdf đảo ngược y-coordinates.
     - Scale factor & coordinate transformation: Chuyển đổi toạ độ từ điểm PDF sang toạ độ TCPDF.
   - Tại `getCandidateTimingHtml()`:
     - Comment giải thích việc escape tên ứng viên (`htmlspecialchars`).
     - Comment giải thích việc render KID link dưới dạng clickable anchor với descriptive text `"Click here"` nhằm đáp ứng yêu cầu rút gọn URL của GAP-744 và tránh tràn bảng.

### 2.2. File `tests/Unit/Services/ApplicationPackServiceTest.php`

1. **Cập nhật Test Case**:
   - Cập nhật test case `test_timing_html_wraps_kid_link_in_anchor_tag_and_preserves_url_text` (hoặc đổi tên thành `test_timing_html_renders_kid_link_as_clickable_anchor_with_descriptive_text`):
     - Kỳ vọng thẻ `<a>` chứa text `Click here`:
       ```php
       $expectedAnchor = '<a href="' . htmlspecialchars($kidUrl, ENT_QUOTES) . '" target="_blank" style="color: #1a5490; text-decoration: underline;">Click here</a>';
       $this->assertStringContainsString($expectedAnchor, $html);
       ```
   - Bổ sung English comments giải thích mục đích và assertions của test case.

---

## 3. Kế hoạch kiểm thử (Verification Plan)

1. **Unit Test mục tiêu**:
   `./vendor/bin/phpunit tests/Unit/Services/ApplicationPackServiceTest.php`
   -> Kỳ vọng 100% PASS (5 tests, 15 assertions).
2. **Toàn bộ Unit Service Tests**:
   `./vendor/bin/phpunit tests/Unit/Services/`
   -> Kỳ vọng 100% PASS (81 tests, 533 assertions).
3. **Feature Test liên quan**:
   `./vendor/bin/phpunit tests/Feature/Api/Consultant/CandidateTest.php tests/Feature/Api/Consultant/CandidatesTest.php`
   -> Kỳ vọng 100% PASS.
