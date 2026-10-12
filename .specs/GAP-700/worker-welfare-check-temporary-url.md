# SPEC: Worker Welfare Check Temporary File URLs

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

## 1. Tổng quan

Đảm bảo API worker welfare check không trả trực tiếp storage/S3 URL gốc của
ảnh welfare, ảnh interview hoặc certificate. Resource sẽ tạo signed
`Storage::temporaryUrl()` có thời hạn 10 phút cho các file liên quan.

**Yêu cầu gốc**: Áp dụng temporary URL cho API `worker_welfare_check` thay vì
trả URL S3 gốc.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

### 3.1. Endpoint

Các endpoint hiện tại vẫn giữ nguyên:

```text
POST /api/consultant/candidates/{id}/worker_welfare_check
GET  /api/consultant/candidates/{id}/worker_welfare_checks
```

### 3.2. Response

Không đổi tên hoặc cấu trúc các field:

```json
{
    "welfare_image_file_id": 12,
    "welfare_image_url": "https://signed-s3-url...",
    "interview_image_url": "https://signed-s3-url...",
    "certificate_url": "https://signed-s3-url..."
}
```

Các URL có file sẽ là signed URL hết hạn sau 10 phút; các field không có file
vẫn trả chuỗi rỗng như hiện tại.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. Controller gọi `WorkerWelfareCheckService` như hiện tại.
2. Service/repository eager-load `welfareImageFile`, `interviewImageFile` và
   `certificateFile`.
3. `CandidateWelfareCheck` Resource lấy storage path từ từng `File` model.
4. Resource gọi `Storage::temporaryUrl($file->url, now()->addMinutes(10))` cho
   từng file có dữ liệu.
5. Resource không passthrough URL gốc từ S3 trong response.

### 4.2. Business Rules

- Không thay đổi `file_id`, dữ liệu database hoặc quan hệ file.
- Không public hóa bucket/object.
- Không lưu temporary URL vào database.
- Không thay đổi response fields hoặc thời hạn hiện tại 10 phút.
- `File.url` được coi là storage key do `Storage::putFileAs()` tạo ra; không
  truyền URL HTTP đầy đủ vào `Storage::temporaryUrl()`.

## 5. Data Origin & Call Chain

    GET/POST consultant worker welfare endpoint
      → CandidateController::getWorkerWelfareChecks() /
        performWorkerWelfareCheck()
      → WorkerWelfareCheckService
      → CandidateWelfareCheckRepository::getByCandidateId() hoặc created check
      → eager-loaded File relations
      → CandidateWelfareCheck Resource::toArray()
      → Storage::temporaryUrl(File.url)
      → JSON response

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$check` | Controller/Resource | WorkerWelfareCheckService | ✅ |
| `welfareImageFile` | Resource | `welfareImageFile` relation từ repository/service | ✅ |
| `interviewImageFile` | Resource | `interviewImageFile` relation từ repository/service | ✅ |
| `certificateFile` | Resource | `certificateFile` relation từ repository/service | ✅ |
| `File.url` | `Storage::temporaryUrl()` | `Storage::putFileAs()` result lưu trong DB | ✅ |

## 6. Constants & Enums

Không thêm constant mới; giữ thời hạn temporary URL 10 phút đang được sử dụng
trong các Resource liên quan.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `../../app/Http/Resources/Api/Consultant/CandidateWelfareCheck.php` | Luôn tạo temporary URL cho welfare image, interview image và certificate thay vì trả passthrough URL |
| `tests/Unit/Http/Resources/CandidateWelfareCheckResourceTest.php` | Mock temporary URL và xác nhận response không trả raw storage URL |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `tests/Unit/Http/Resources/CandidateWelfareCheckResourceTest.php` | existing resource transformation | Xác nhận ba URL trong response là temporary URLs được tạo từ storage paths |
| `tests/Unit/Http/Resources/CandidateWelfareCheckResourceTest.php` | empty file relations | Xác nhận field không có file vẫn trả chuỗi rỗng |
| `../../tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | existing endpoint validation | Đảm bảo thay đổi Resource không ảnh hưởng endpoint contract hiện tại |

Sau khi code sẽ chạy test Resource, test Feature liên quan và toàn bộ
`./vendor/bin/phpunit`.

## 9. Checklist trước khi Approve

- [x] Không thay đổi database.
- [x] Không thay đổi tên hoặc cấu trúc response fields.
- [x] Không trả raw S3 URL từ worker welfare Resource.
- [x] Temporary URL không được lưu vào database.
- [x] Đã rà soát nguồn dữ liệu của các file relations.
- [x] Test Resource và toàn bộ PHPUnit pass.
- [x] User approve plan.
