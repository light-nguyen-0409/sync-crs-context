# SPEC: Worker Welfare Check Service Deduplication

> **Trạng thái**: `IMPLEMENTING`
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

## 1. Tổng quan

Rà soát và loại bỏ code bị lặp giữa `performCheck()` và
`processPostCheck()` trong `WorkerWelfareCheckService`. Các đoạn download
hai ảnh và cleanup temp files đang có cùng mục đích, cần chuyển thành private
helper dùng chung để giảm rủi ro hai flow bị lệch behavior.

**Yêu cầu gốc**: Khi phát hiện duplicate code trong service, tạo function
chung; bổ sung workspace rule để không tiếp tục copy-paste logic.

## 2. Database Design

N/A — Chỉ refactor service và cập nhật rule, không thay đổi database.

## 3. API Contract

N/A — Không thay đổi endpoint, request hoặc response contract.

## 4. Business Logic (Service Layer)

### 4.1. Phạm vi duplication

Các đoạn trùng cần gom lại:

1. Download `interviewFile` và `welfareImageFile` bằng
   `FileService::downloadToTemp()`.
2. Thêm các temp paths vào danh sách cleanup.
3. Ghi log cho hai phase download.
4. Cleanup danh sách temp files trong `finally` và ghi log cleanup.

### 4.2. Thiết kế helper

Thêm các internal helper `private` trong
`WorkerWelfareCheckService`:

- Helper download một cặp ảnh, trả về hai local paths và danh sách temp files
  để caller tiếp tục xử lý face match hoặc PDF.
- Helper cleanup temp files và log phase cleanup dùng chung cho cả request và
  queue job.

Giữ nguyên thứ tự xử lý, phase log, exception behavior và danh sách file được
   cleanup. Không đưa business logic vào Repository và không tạo abstraction
   dùng chung ngoài service khi chưa cần thiết.

### 4.3. Rule DRY trong workspace

Bổ sung vào `../../AGENTS.md` một rule trong phần coding conventions:

- Không copy-paste cùng một business logic ở nhiều method/file.
- Khi logic lặp từ hai nơi trở lên, phải tạo helper/service dùng chung với
  phạm vi phù hợp; helper nội bộ phải là `private`.
- Chỉ abstract phần logic thực sự giống nhau, tránh gom các đoạn chỉ giống
  hình thức nhưng khác business behavior.

## 5. Data Origin & Call Chain

```text
POST worker welfare check
  → CandidateController::performWorkerWelfareCheck()
  → WorkerWelfareCheckService::performCheck()
  → shared image-download helper
  → GBG compare
  → shared cleanup helper

Queue worker
  → GenerateWorkerWelfareCheckCertificateJob::handle()
  → WorkerWelfareCheckService::processPostCheck()
  → shared image-download helper
  → PDF/MatchMaker processing
  → shared cleanup helper
```

| Biến | Nguồn | Mục đích | Confirmed? |
|------|-------|---------|------------|
| `$interviewFile` | `fetchInterviewImage()` hoặc `candidate_welfare_checks.interviewImageFile` | File ảnh interview để download | ✅ |
| `$welfareImageFile` | `fetchWelfareImageFile()` hoặc `candidate_welfare_checks.welfareImageFile` | File welfare image để download | ✅ |
| `$candidateId` | Route/service hoặc queue job payload | Log và định danh candidate | ✅ |
| `$welfareImageFileId` | Request file ID hoặc persisted welfare check | Log phase | ✅ |

## 6. Constants & Enums

Không thêm constant mới. Các phase log và giới hạn ảnh hiện tại được giữ
nguyên.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `../../app/Services/WorkerWelfareCheckService.php` | Tạo private helper cho download image pair và cleanup temp files; thay thế các đoạn duplicate trong hai flow |
| `../../AGENTS.md` | Bổ sung rule DRY/no duplicate business logic |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Rà soát và bổ sung regression coverage cho hai flow sau refactor |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Existing `performCheck` success/failure cases | Đảm bảo flow đồng bộ vẫn download đủ hai ảnh, dispatch job và cleanup |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Post-processing regression case | Đảm bảo flow queue dùng helper chung, tiếp tục download và cleanup đúng |
| Toàn bộ test suite | `./vendor/bin/phpunit` | Đảm bảo refactor không thay đổi behavior hiện tại |

## 9. Checklist trước khi Approve

- [x] Đã xác định đầy đủ duplicate logic trong service.
- [x] Helper dùng chung giữ nguyên behavior và phase logs.
- [x] Helper nội bộ có visibility `private`.
- [x] Rule DRY được bổ sung vào `../../AGENTS.md`.
- [x] Test impact đã được rà soát.
- [ ] Toàn bộ PHPUnit pass — hiện còn lỗi pre-existing ở `CandidateWelfareCheck` resource do working tree thiếu `certificate_url`.
- [x] User approve plan.
