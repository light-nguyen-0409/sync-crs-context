# SPEC: Worker Welfare Check PDF Image Compression

> **Trạng thái**: DONE
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

## 1. Tổng quan

Giảm thời gian Dompdf render bằng cách resize và compress hai ảnh trước khi
nhúng vào certificate PDF. Logic biến đổi file nằm trong `FileService`; ảnh gốc
không bị thay đổi và tiếp tục được dùng cho GBG face matching.

**Yêu cầu gốc**: Áp dụng compress ảnh trước khi tạo Worker Welfare Check PDF.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

N/A — Không thay đổi request, response hoặc endpoint.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. Download ảnh gốc như flow hiện tại qua `FileService`.
2. Dùng GD tạo file JPEG tạm cho mỗi ảnh:
   - giữ đúng aspect ratio;
   - giới hạn cạnh dài tối đa 800px;
   - JPEG quality 80;
   - nền trắng cho ảnh có transparency.
3. Gọi `FileService::compressImageForPdf()` và dùng file tạm đã tối ưu để base64
   và render PDF.
4. Tiếp tục dùng file gốc cho GBG compare.
5. Thêm file ảnh tạm vào danh sách cleanup hiện tại.
6. Nếu GD không khả dụng, ảnh không hợp lệ hoặc compression thất bại, fallback về
   file gốc để không làm thay đổi behavior hiện tại.

### 4.2. Business Rules

- Không overwrite ảnh gốc trong storage.
- Không thay đổi score, dữ liệu database hoặc nội dung nghiệp vụ.
- Compression failure không làm request fail; PDF fallback dùng ảnh gốc.
- Các giới hạn 800px và quality 80 được khai báo thành constants trong service.

## 5. Data Origin & Call Chain

    WorkerWelfareCheckService::processPostCheck()
      → FileService::downloadToTemp() trả file ảnh gốc
      → FileService::compressImageForPdf() tạo file JPEG tạm
      → generateCertificatePdf() đọc file JPEG tạm
      → Dompdf render PDF
      → cleanupTempFile() xóa cả file gốc tạm và file compressed tạm

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| interviewTempPath | GBG và compression | FileService::downloadToTemp() | ✅ |
| welfareTempPath | GBG và compression | FileService::downloadToTemp() | ✅ |
| compressedImagePath | PDF và cleanup | compressImageForPdf() | ✅ |

## 6. Constants & Enums

Trong FileService:

    public const PDF_IMAGE_MAX_DIMENSION = 800;
    public const PDF_IMAGE_JPEG_QUALITY = 80;
    public const PDF_IMAGE_BACKGROUND_COLOR = [255, 255, 255];

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| app/Contracts/Services/FileServiceInterface.php | Khai báo `compressImageForPdf()` |
| app/Services/FileService.php | Compress ảnh tạm trước PDF và xử lý fallback |
| app/Services/WorkerWelfareCheckService.php | Gọi FileService cho ảnh PDF, dùng ảnh compressed và cleanup file tạm |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| tests/Unit/Services/FileServiceTest.php | compression success/fallback | Kiểm tra resize JPEG và fallback về source |
| tests/Unit/Services/WorkerWelfareCheckServiceTest.php | existing post-check scenario | Đảm bảo Service gọi FileService và vẫn cleanup file tạm |

Sau khi code sẽ chạy test service, test FileService và toàn bộ PHPUnit để kiểm tra
regression.

## 9. Checklist trước khi Approve

- [x] Không thay đổi database.
- [x] Không thay đổi API contract.
- [x] Đã xác nhận GD có sẵn trong project.
- [x] Ảnh gốc được giữ nguyên cho GBG.
- [x] File tạm compressed có cleanup.
- [x] Có fallback khi compression thất bại.
- [x] User approve plan.
