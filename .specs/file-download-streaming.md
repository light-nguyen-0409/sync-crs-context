# SPEC: Stream File Download To Temporary File

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

## 1. Tổng quan

Tối ưu `FileService::downloadToTemp()` bằng cách đọc file dạng stream trực tiếp
từ filesystem adapter và ghi thẳng vào local temporary file. Mục tiêu là tránh
load toàn bộ nội dung ảnh vào memory, đồng thời không tạo thêm request kiểm tra
`tồn tại` trước khi đọc file.

**Yêu cầu gốc**: Áp dụng phương án `readStream()` để tối ưu download ảnh phục vụ
GBG/PDF.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

N/A — Không thay đổi request, response hoặc endpoint.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. Giữ nguyên cách xác định extension và temporary path hiện tại.
2. Gọi `Storage::readStream($url)` trực tiếp, không gọi `Storage::exists()`.
3. Mở temporary file ở chế độ binary write.
4. Dùng `stream_copy_to_stream()` để copy dữ liệu từ storage stream xuống local file.
5. Đóng source stream và destination handle trong mọi nhánh xử lý.
6. Nếu không mở được stream/file hoặc copy thất bại/không ghi được dữ liệu, xóa
   temporary file nếu đã tạo và ném `APIErrorException` hiện có.
7. Trả về local temporary path như contract hiện tại để không ảnh hưởng GBG,
   PDF và cleanup flow.

### 4.2. Business Rules

- Không thay đổi file gốc trên storage.
- Không thay đổi tên method, return type hoặc format local path.
- Không sử dụng `temporaryUrl()` trong implementation này; service vẫn cần local
  path để gửi multipart cho GBG.
- Không giữ toàn bộ nội dung file trong memory.
- Giữ nguyên thông báo lỗi `notFound` hiện tại cho lỗi retrieve file.

## 5. Data Origin & Call Chain

    WorkerWelfareCheckService::performCheck()
      → FileService::downloadToTemp(File $file)
      → File::url làm storage path
      → Storage::readStream($url)
      → local temporary file path
      → GbgFaceMatchApi::compareTwoImages() hoặc PDF processing

    BaseIdentificationCheckService::getFaceImage()
      → File::url tạo temporaryUrl và download riêng qua HTTP sink
      → GBGIdentificationCheckService::checkFaceMatchingRateBetweenTwoImages()

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$file->url` | `FileService::downloadToTemp()` | `File` model được caller truyền vào | ✅ |
| `$tempPath` | GBG/PDF và cleanup | `downloadToTemp()` trả về | ✅ |
| `$sourceStream` | Copy xuống local file | `Storage::readStream($file->url)` | ✅ |

## 6. Constants & Enums

N/A — Không thêm magic value mới. Chế độ mở file binary write là implementation
detail của stream handling.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `app/Services/FileService.php` | Thay `Storage::exists()` + `Storage::get()` + `file_put_contents()` bằng `Storage::readStream()` và `stream_copy_to_stream()`, kèm đóng handle và xử lý lỗi |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| Test hiện có của `FileService` | Existing download scenarios | Đảm bảo method vẫn trả về local file có nội dung đúng |
| Test mới/điều chỉnh cho `FileService::downloadToTemp()` | stream success | Mock storage stream, kiểm tra file tạm được ghi và đọc đúng content |
| Test mới/điều chỉnh cho `FileService::downloadToTemp()` | stream failure | Kiểm tra lỗi retrieve file dùng đúng `APIErrorException` và không để lại temp file |

Sau khi code sẽ rà soát toàn bộ test case liên quan, chạy test bị ảnh hưởng và
toàn bộ `./vendor/bin/phpunit` theo quy định workspace.

## 9. Checklist trước khi Approve

- [x] Không thay đổi database.
- [x] Không thay đổi API contract.
- [x] Không dùng `temporaryUrl()` cho flow cần local path.
- [x] Không load toàn bộ file vào memory.
- [x] Có cleanup stream/file handle ở cả success và failure.
- [x] Có test success và failure cho streaming.
- [x] User approve plan.
