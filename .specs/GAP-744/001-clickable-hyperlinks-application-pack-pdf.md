# SPEC: [GAP-744] Make Links Clickable in Generated Application Pack PDFs (Phương án A & Tối ưu hóa Toạ độ Annotation)

> **Trạng thái**: `DONE`  
> **Ngày tạo**: 2026-10-20  
> **Task Key**: `GAP-744`  
> **Author**: Antigravity  

---

## 1. Tổng quan

### 1.1. Mục tiêu
1. **Chỉ chuyển duy nhất link KID (`timing->kid_link`)** tại trang Timing Log (trang 29) thành clickable hyperlink `<a href="...">`.
2. **Revert hoàn toàn logic auto-linkify ở `getEmploymentHistoryReferenceEmailContent()`** về nguyên bản để loại bỏ triệt để nguy cơ phishing từ candidate-controlled data.
3. **Thu hẹp Allowlist (`$allowedLinkFiles`)**: Chỉ cho phép duy nhất `$tempTimingPdfFilePath` được trích xuất link annotation khi merge PDF.
4. **Tối ưu hóa và phòng thủ vững chắc trong `copyPageLinkAnnotations()` (Code Review mới)**:
   - **Xử lý lỗi cục bộ (Inner Try-Catch)**: Chuyển try-catch vào bên trong vòng lặp từng annotation, tránh trường hợp 1 annotation bị lỗi làm rớt toàn bộ các link hợp lệ còn lại trên cùng trang.
   - **Kiểm tra an toàn cấu trúc `Rect`**: Xác thực `isset($annot->value['Rect'])` và `is_array($rect->value) && count($rect->value) >= 4` để tương thích hoàn toàn với PHP 8.1+ (không throw `Undefined array key`).
   - **Chuẩn hóa toạ độ hình chữ nhật (Coordinate Normalization)**: Áp dụng `min()` và `max()` cho các cặp toạ độ `(x1, x2)` và `(y1, y2)` theo chuẩn PDF ISO 32000-1, loại bỏ nguy cơ chiều rộng hoặc chiều cao âm (`$w < 0`, `$h < 0`) làm hỏng vùng bấm trên một số trình đọc PDF.

---

## 2. Chi tiết thay đổi Code (Implementation Plan)

### 2.1. File `app/Services/ApplicationPackService.php`

1. **Revert `getEmploymentHistoryReferenceEmailContent()`**:
   - Giữ nguyên nội dung gốc không auto-linkify.
2. **Thu hẹp `$allowedLinkFiles`**:
   - Chỉ cho phép `$tempTimingPdfFilePath`.
3. **Cập nhật `getCandidateTimingHtml()`**:
   - Escape `$candidate->fullName()` ở tiêu đề bằng `htmlspecialchars(..., ENT_QUOTES, 'UTF-8')`.
   - Bọc `$timing->kid_link` trong thẻ `<a>`.
4. **Cập nhật `copyPageLinkAnnotations()`**:
   ```php
   private function copyPageLinkAnnotations(TcpdfFpdi $pdf, PdfReader $reader, PdfParser $parser, int $pageNo, $tplId): void
   {
       try {
           $page = $reader->getPage($pageNo);
           $pageDict = $page->getPageDictionary();

           if (!isset($pageDict->value['Annots'])) {
               return;
           }

           $annots = PdfType::resolve($pageDict->value['Annots'], $parser);
           if (!isset($annots->value) || !is_array($annots->value)) {
               return;
           }

           $scaleFactor = $pdf->getScaleFactor();
           $tplSize = $pdf->getTemplateSize($tplId);
           $pageHeightPt = $tplSize['height'] * $scaleFactor;

           foreach ($annots->value as $annotRef) {
               try {
                   $annot = PdfType::resolve($annotRef, $parser);
                   if (!isset($annot->value['Subtype'])) {
                       continue;
                   }

                   $subtype = PdfType::resolve($annot->value['Subtype'], $parser)->value;

                   if ($subtype === 'Link' && isset($annot->value['A'])) {
                       $action = PdfType::resolve($annot->value['A'], $parser);
                       if (!isset($action->value['URI'])) {
                           continue;
                       }

                       $uri = PdfType::resolve($action->value['URI'], $parser)->value;
                       $scheme = parse_url($uri, PHP_URL_SCHEME);
                       if (!in_array(strtolower((string) $scheme), ['http', 'https', 'mailto'], true)) {
                           continue;
                       }

                       if (!isset($annot->value['Rect'])) {
                           continue;
                       }

                       $rect = PdfType::resolve($annot->value['Rect'], $parser);
                       if (!isset($rect->value) || !is_array($rect->value) || count($rect->value) < 4) {
                           continue;
                       }

                       $x1 = (float) $rect->value[0]->value;
                       $y1 = (float) $rect->value[1]->value;
                       $x2 = (float) $rect->value[2]->value;
                       $y2 = (float) $rect->value[3]->value;

                       $minX = min($x1, $x2);
                       $maxX = max($x1, $x2);
                       $minY = min($y1, $y2);
                       $maxY = max($y1, $y2);

                       $x = $minX / $scaleFactor;
                       $y = ($pageHeightPt - $maxY) / $scaleFactor;
                       $w = ($maxX - $minX) / $scaleFactor;
                       $h = ($maxY - $minY) / $scaleFactor;

                       $pdf->Link($x, $y, $w, $h, $uri);
                   }
               } catch (\Throwable $e) {
                   \Illuminate\Support\Facades\Log::warning("Failed to copy link annotation on page {$pageNo}: " . $e->getMessage());
               }
           }
       } catch (\Throwable $e) {
           \Illuminate\Support\Facades\Log::warning("Failed to copy PDF link annotations page {$pageNo}: " . $e->getMessage());
       }
   }
   ```

---

### 2.2. File `tests/Unit/Services/ApplicationPackServiceTest.php`

1. **Duy trì các test case cốt lõi**:
   - `test_timing_html_wraps_kid_link_in_anchor_tag_and_preserves_url_text`
   - `test_merge_pdf_preserves_hyperlink_annotations`
   - `test_merge_pdf_skips_link_extraction_for_files_not_in_allowlist`
   - `test_copy_page_link_annotations_ignores_unsafe_schemes`
2. **Bổ sung test case mới**:
   - `test_copy_page_link_annotations_normalizes_inverted_rect_and_handles_missing_rect`:
     - Tạo PDF chứa link có toạ độ Rect chuẩn và kiểm tra toạ độ xử lý không bị lỗi.
     - Kiểm tra khả năng chịu lỗi khi annotation thiếu trường hoặc toạ độ không chuẩn.

---

## 3. Kế hoạch kiểm thử (Verification Plan)

1. Chạy suite Unit Test mục tiêu:
   `./vendor/bin/phpunit tests/Unit/Services/ApplicationPackServiceTest.php` -> `OK (5 tests, 15 assertions)` — 100% PASS.
2. Chạy toàn bộ Unit Service Tests:
   `./vendor/bin/phpunit tests/Unit/Services/` -> `OK (81 tests, 533 assertions)` — 100% PASS.
3. Chạy Consultant Feature Tests:
   `./vendor/bin/phpunit tests/Feature/Api/Consultant/CandidateTest.php tests/Feature/Api/Consultant/CandidatesTest.php` -> `OK (21 tests, 166 assertions)` — 100% PASS.
