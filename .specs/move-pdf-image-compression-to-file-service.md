# SPEC: Move PDF Image Compression To FileService

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-22
> **Author**: Codex

---

## 1. Tổng quan

Di chuyển `compressImageForPdf()` khỏi `WorkerWelfareCheckService` sang
`FileService`, vì đây là thao tác đọc/biến đổi file tạm. Worker Welfare Check
Service chỉ orchestration flow và gọi qua `FileServiceInterface`.

**Yêu cầu gốc**: Chuyển function `compressImageForPdf` vào `FileService`.

---

## 2. Database Design

N/A — Không thay đổi schema, migration hoặc query behavior.

---

## 3. API Contract

N/A — Không thay đổi endpoint, request, response hoặc status code.

---

## 4. Architecture & Business Logic

### 4.1. Thay đổi kiến trúc

- Thêm `compressImageForPdf(string $sourcePath): string` vào
  `FileServiceInterface` và implement trong `FileService`.
- Chuyển các constants liên quan đến resize/compression sang `FileService`.
- `WorkerWelfareCheckService::processPostCheck()` gọi:
  `FileServiceInterface::compressImageForPdf()` cho interview/welfare image.
- Xóa private helper và các constants tương ứng khỏi
  `WorkerWelfareCheckService`.

### 4.2. Behavior giữ nguyên

- GD không khả dụng, file rỗng/không hợp lệ hoặc compression thất bại đều
  fallback về source path.
- Giữ tỷ lệ ảnh, cạnh dài tối đa 800px, JPEG quality 80 và nền trắng.
- Không overwrite ảnh gốc; file compressed thành file tạm mới.
- File compressed vẫn được thêm vào cleanup list nếu path khác source path.
- Không thay đổi GBG input, PDF output, database hoặc exception behavior.

---

## 5. Data Origin & Call Chain

```text
WorkerWelfareCheckService::processPostCheck()
  → FileService::downloadToTemp() trả source path
  → FileServiceInterface::compressImageForPdf() trả compressed/source path
  → generateCertificatePdf() đọc path kết quả
  → cleanupTempFile() xóa các file tạm
```

| Biến / Key | Nguồn | Nơi dùng | Confirmed? |
|------------|-------|----------|------------|
| `$interviewTempPath` | `FileService::downloadToTemp()` | GBG + compression | ✅ |
| `$welfareTempPath` | `FileService::downloadToTemp()` | GBG + compression | ✅ |
| compressed path | `FileService::compressImageForPdf()` | PDF + cleanup | ✅ |

---

## 6. Files cần sửa

| File | Thay đổi |
|------|----------|
| `app/Contracts/Services/FileServiceInterface.php` | Khai báo method compression |
| `app/Services/FileService.php` | Nhận constants và implement compression helper |
| `app/Services/WorkerWelfareCheckService.php` | Gọi FileService, xóa helper/constants |
| `tests/Unit/Services/FileServiceTest.php` | Test compression success/fallback behavior |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Mock method mới trong post-check flow |
| `specs/worker-welfare-check-pdf-image-compression.md` | Cập nhật owner/call chain/constants |

---

## 7. Test Cases

- FileService nén ảnh hợp lệ, giữ tỷ lệ và giới hạn cạnh dài 800px.
- FileService fallback về source path khi file không phải ảnh hoặc GD không
  xử lý được.
- Worker Welfare Check post-processing truyền path kết quả vào PDF flow và vẫn
  cleanup file tạm.
- Chạy `php -l` cho các file PHP sửa.
- Chạy toàn bộ `./vendor/bin/phpunit` và đảm bảo pass.

Không chạy formatter/linter tự động.

---

## 8. Checklist trước khi Approve

- [x] Đã xác nhận function hiện tại chỉ xử lý file/image transformation.
- [x] Đã trace call chain từ Worker Welfare Check đến cleanup.
- [x] Đã xác định contract, implementation và test impact.
- [x] User approve plan.
- [x] Implementation hoàn tất.
- [x] Test suite pass.
