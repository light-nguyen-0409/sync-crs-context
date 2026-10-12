# SPEC: Async Worker Welfare Check Post-Processing

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

## 1. Tổng quan

Tách phần xử lý sau khi face match khỏi request Worker Welfare Check. API chỉ
thực hiện validation, download/compare ảnh và lưu kết quả match; phần render PDF,
lưu certificate, sync MatchMaker và gửi email failure sẽ chạy trong queue job.

**Yêu cầu gốc**: API trả kết quả match nhanh; xuất PDF và sync MatchMaker được
đẩy vào queue.

## 2. Database Design

N/A — Không cần migration mới. `candidate_welfare_checks.certificate_file_id`
đã nullable, dùng `null` trong thời gian job hậu xử lý chưa hoàn tất.

## 3. API Contract

### 3.1. Endpoint

```text
POST /api/consultant/candidates/{id}/worker_welfare_check
```

Endpoint, request và validation giữ nguyên.

### 3.2. Response

Giữ `CandidateWelfareCheckResource` và các field hiện tại để tránh breaking
change. API trả ngay sau khi lưu score:

- `facematch_score`: kết quả match đã hoàn tất.
- `is_passed`: tính từ score.
- `welfare_image_url` và `interview_image_url`: temporary URLs như hiện tại.
- `certificate_url`: chuỗi rỗng nếu queue job chưa tạo xong certificate.

Client có thể gọi `GET /api/consultant/candidates/{id}/worker_welfare_checks`
để lấy certificate sau khi job hoàn tất.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính trong request

1. Load candidate và kiểm tra candidate đủ điều kiện.
2. Load welfare image và interview image metadata.
3. Download hai ảnh về temp local và gọi GBG face match.
4. Lưu `CandidateFaceMatchingRate`.
5. Tạo `CandidateWelfareCheck` ngay với:
   - candidate/consultant/image file IDs;
   - `facematch_score`;
   - `certificate_file_id = null`.
6. Dispatch `GenerateWorkerWelfareCheckCertificateJob` với các scalar values cần thiết:
   `welfareCheckId`, `candidateId`, `consultantName`, `branchId`.
7. Load các relation cần cho Resource và trả response.
8. Cleanup temp files của request.

### 4.2. Luồng xử lý trong queue job

1. Load welfare check, candidate, các file ảnh và branch từ repository/service.
2. Download lại ảnh từ storage về temp local của worker.
3. Compress ảnh phục vụ PDF.
4. Render certificate PDF.
5. Upload PDF và tạo `File` record.
6. Update `candidate_welfare_checks.certificate_file_id` bằng certificate file ID.
7. Sync contact log và PDF attachment sang MatchMaker.
8. Nếu score không đạt threshold, queue failure email hiện có.
9. Cleanup toàn bộ temp files trong `finally`.

Job chỉ truyền ID/string, không truyền local temp path vì temp path của request
không còn tồn tại khi worker xử lý.

### 4.3. Business Rules

- Face matching vẫn hoàn tất đồng bộ trước khi API trả response.
- PDF, certificate file và MatchMaker sync không được chặn response API.
- Welfare check record phải tồn tại trước khi dispatch job để API trả score và job
  có ID ổn định để update certificate.
- Nếu job chưa chạy hoặc thất bại, `certificate_file_id` giữ `null` và
  `certificate_url` trả chuỗi rỗng.
- Không thay đổi score, threshold, dữ liệu face matching rate hoặc file IDs ảnh.
- Queue phải dùng backend bất đồng bộ (`database`, `redis`, `sqs`, ...) và có worker;
  `QUEUE_CONNECTION=sync` chỉ phù hợp local/test và vẫn chạy inline.
- Failure email được gửi trong `GenerateWorkerWelfareCheckCertificateJob` và
  dùng recipient từ config hiện có; không queue thêm một mail job riêng.
- Loại bỏ `dd()` trong catch gửi email để không làm worker/request dừng đột ngột.

### 4.4. Side Effects

| Loại | Trigger | Mô tả |
|------|---------|-------|
| Database write | Sau face match | Tạo welfare check với `certificate_file_id = null` |
| Queue Job | Sau khi tạo welfare check | Process PDF, certificate và MatchMaker |
| File storage | Job thành công | Lưu certificate PDF và file record |
| Database update | Job tạo certificate | Cập nhật `certificate_file_id` |
| MatchMaker API | Job có PDF | Tạo contact log và upload certificate |
| Email queue | Score dưới threshold | Gửi failure email kèm PDF |

## 5. Data Origin & Call Chain

    POST route
      → CandidateController::performWorkerWelfareCheck()
      → WorkerWelfareCheckService::performCheck()
      → GBG compare
      → CandidateWelfareCheckRepository::create()
      → GenerateWorkerWelfareCheckCertificateJob::dispatch($welfareCheckId, ...)
      → API returns CandidateWelfareCheckResource

    Queue worker
      → GenerateWorkerWelfareCheckCertificateJob::handle()
      → WorkerWelfareCheckService::processPostCheck()
      → FileService/download, PDF generation, FileService::createFile()
      → CandidateWelfareCheckRepository::update()
      → MatchMaker sync and failure mail

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$candidateId` | Request và job | Route parameter | ✅ |
| `$welfareImageFileId` | Request | FormRequest `file_id` | ✅ |
| `$consultantName` | Request và job | Authenticated consultant | ✅ |
| `$branchId` | Request và job | FormRequest `branch_id` | ✅ |
| `$scorePercent` | API response và DB | GBG response | ✅ |
| `$welfareCheckId` | Job update | Repository create result | ✅ |

## 6. Constants & Enums

Giữ các constant hiện có:

- `CandidateWelfareCheck::PASS_SCORE_THRESHOLD`
- Các phase log trong `WorkerWelfareCheckService`
- `File::TYPE_WORKER_WELFARE_CHECK_CERTIFICATE`

Không thêm status database trong scope này; `certificate_file_id = null` biểu thị
post-processing chưa hoàn tất.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|------|-----------|-------|
| `../../app/Jobs/GenerateWorkerWelfareCheckCertificateJob.php` | `App\Jobs` | Queue job điều phối hậu xử lý PDF/certificate/MatchMaker/email |

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `../../app/Services/WorkerWelfareCheckService.php` | Tách flow sync trước score và flow post-processing; dispatch job sau khi tạo welfare check; bỏ PDF/MatchMaker khỏi request |
| `../../app/Contracts/Services/WorkerWelfareCheckServiceInterface.php` | Thêm method service cho job hậu xử lý nếu cần theo contract |
| `../../app/Http/Resources/Api/Consultant/CandidateWelfareCheck.php` | Đã xác nhận behavior hiện tại: certificate thiếu trả URL rỗng và score trả được ngay; không cần sửa thêm |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Cập nhật expectation: API tạo record và dispatch job, không chạy PDF/MatchMaker inline |
| `../../tests/Unit/Jobs/GenerateWorkerWelfareCheckCertificateJobTest.php` | Test job gọi post-processing với đúng payload |
| `../../tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | Test response có score ngay và certificate có thể rỗng khi job chưa chạy |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | perform check success | Face match được lưu, welfare check được tạo và job được dispatch |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | perform check failed score | Score thấp vẫn trả response; email không gửi inline trong request |
| `../../tests/Unit/Jobs/GenerateWorkerWelfareCheckCertificateJobTest.php` | handle | Job delegate post-processing với đúng payload |
| `../../tests/Feature/Api/Consultant/WorkerWelfareCheckTest.php` | perform endpoint | API response trả `facematch_score` trước khi certificate job hoàn tất |
| Existing worker welfare tests | regression | Không thay đổi threshold, score conversion, relation/resource contract |

Sau khi code sẽ chạy test bị ảnh hưởng và toàn bộ `./vendor/bin/phpunit`.

## 9. Checklist trước khi Approve

- [x] API chỉ chờ tới face match và lưu score.
- [x] PDF/certificate/MatchMaker sync được đưa vào queue job.
- [x] Job không phụ thuộc temp path của request.
- [x] `certificate_file_id` nullable được dùng đúng cho trạng thái pending.
- [x] Failure email vẫn chạy qua queue/config hiện tại.
- [x] Không còn `dd()` trong flow worker.
- [x] Test service/job/feature đầy đủ.
- [x] Toàn bộ PHPUnit pass (`475 tests, 2062 assertions`).
- [x] User approve plan.
