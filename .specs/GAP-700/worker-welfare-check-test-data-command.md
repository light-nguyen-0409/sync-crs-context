# SPEC: Worker Welfare Check Test Data Command

> **Trạng thái**: `DRAFT`
> **Ngày tạo**: 2026-09-22
> **Author**: Codex

---

## 1. Tổng quan

Tạo một Artisan command để dựng nhanh dữ liệu local/STG cho luồng Worker Welfare Check mà không gọi MatchMaker hoặc GBG. Candidate được tạo trong một job thuộc branch với trạng thái `MATCHMAKER` và MM status `LIVE`, để Consultant Candidate Detail trả `can_complete_worker_welfare_check = true`.

**Yêu cầu gốc**: Sau khi kiểm tra ba commit gần nhất của GAP-700, cần có test data để kiểm tra cờ cho phép quét và chạy welfare face check.

**Ba commit đã kiểm tra**:

- `d9263c06`: route/controller/model/repository/resource cho welfare check.
- `f13f3f84`: `WorkerWelfareCheckService`, certificate job, MatchMaker sync và failed email.
- `0d47ebeb`: feature/unit tests cho flow welfare check và file service.

## 2. Database Design

Không tạo migration và không thay đổi schema.

Command chỉ ghi vào các bảng hiện có:

- `jobs` nếu không truyền `--job-id`.
- `candidates` với `match_maker_status = Candidate::MM_STATUS_LIVE`.
- `candidate_jobs` với `status = CandidateJob::STATUS_MATCHMAKER`.
- `files` chỉ khi truyền image path tùy chọn.

Command không tạo trực tiếp `candidate_welfare_checks`, face-matching rate hoặc certificate; các record này phải được tạo bởi API/service/job thật.

## 3. API Contract

N/A — không thêm hoặc sửa HTTP endpoint.

Các endpoint dùng để verify sau khi chạy command:

```text
GET  /api/consultant/candidates/{candidateId}
POST /api/consultant/candidates/{candidateId}/worker_welfare_check
```

## 4. Business Logic (Command Layer)

### 4.1. Signature dự kiến

```text
php artisan worker-welfare-check:generate-test-data {branchId} {--job-id=} {--email=} {--interview-image=} {--welfare-image=}
```

### 4.2. Luồng xử lý

1. Kiểm tra branch tồn tại.
2. Nếu có `--job-id`, kiểm tra job tồn tại và thuộc branch; nếu không có thì tạo một test job mới trong branch.
3. Validate email chưa được dùng nếu caller truyền `--email`; nếu không thì sinh email unique.
4. Validate các image path tùy chọn trước khi ghi dữ liệu.
5. Ghi candidate và candidate job trong transaction write-only:
   - candidate `match_maker_status = Candidate::MM_STATUS_LIVE`;
   - candidate job `status = CandidateJob::STATUS_MATCHMAKER`.
6. Nếu có image path, dùng `FileServiceInterface::createFile()` để lưu vào storage và tạo file metadata:
   - `--interview-image` → `File::TYPE_CAPTURERD_CANDIDATE_FACE_IMAGE`;
   - `--welfare-image` → `File::TYPE_WELFARE_IMAGE`.
7. In ra candidate ID, job ID, email, status và file IDs (nếu có), kèm hướng dẫn gọi API.

Command mặc định không set `match_maker_people_number`, không gọi external MatchMaker và không dispatch welfare check. Như vậy certificate job sẽ không phát sinh external side effect ngoài lúc tester chủ động gọi API.

### 4.3. Điều kiện/giới hạn

- Cờ ở detail API chỉ phụ thuộc hai status trên (`Candidate::canCompleteWorkerWelfareCheck()`).
- Để gọi thành công welfare check, vẫn phải có interview face image và welfare image vật lý trong storage; service hiện tại kiểm tra cả hai trước khi gọi GBG.
- Nếu không truyền image path, command vẫn tạo candidate đủ điều kiện hiển thị cờ nhưng tester phải upload/capture ảnh qua flow hiện có trước khi POST welfare check.
- Không query trong loop; command chỉ tạo một fixture và chỉ đọc branch/job/email trước transaction.

## 5. Data Origin & Call Chain

```text
Artisan command
  → BranchRepositoryInterface / JobRepositoryInterface (validate hoặc resolve job)
  → CandidateRepositoryInterface::create
  → CandidateJobRepositoryInterface::create
  → FileServiceInterface::createFile (chỉ khi có image option)
  → GET CandidateController@get
    → CandidateDetail::toArray
      → Candidate::canCompleteWorkerWelfareCheck()
  → POST CandidateController@performWorkerWelfareCheck
    → WorkerWelfareCheckService::performCheck
      → fetch welfare/interview files
      → GBG face match
      → create welfare check + dispatch certificate job
```

| Biến / dữ liệu | Nguồn | Xác nhận |
|---|---|---|
| `branchId` | command argument | ✅ |
| `jobId` | `--job-id` hoặc job mới tạo trong branch | ✅ |
| `candidateId` | kết quả `CandidateRepositoryInterface::create()` | ✅ |
| `welfareImageFileId` | kết quả `FileServiceInterface::createFile()` hoặc upload API | ✅ |
| `consultantUserId`/`consultantName` | authenticated user trong `CandidateController` | ✅ |

## 6. Constants & Enums

Dùng constants hiện có, không tạo lại magic value:

```php
Candidate::MM_STATUS_LIVE
CandidateJob::STATUS_MATCHMAKER
File::TYPE_CAPTURERD_CANDIDATE_FACE_IMAGE
File::TYPE_WELFARE_IMAGE
```

Các giá trị fixture cố định như command name và test job title sẽ là `public const` trong command.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Mô tả |
|---|---|
| `app/Console/Commands/GenerateWorkerWelfareCheckTestData.php` | Artisan command dựng candidate/job/status và optional image metadata |

### 7.2. Files sửa

| File | Thay đổi |
|---|---|
| `.business-spec/backend-business-flow-spec.md` | Bổ sung command fixture vào command inventory |

Không sửa các thay đổi đang tồn tại trong working tree, đặc biệt `app/Services/WorkerWelfareCheckService.php` và untracked `app/Console/Commands/TestCommand.php`.

## 8. Test Cases

Theo exception trong `AGENTS.md`, đây là test-data/fixture-only Artisan command nên không tạo unit/feature test và không chạy PHPUnit cho command này. Vẫn thực hiện kiểm tra thủ công sau triển khai: command output, DB state, detail flag và các file option (nếu truyền).

## 9. Living-spec deviation audit

- **CODE**: `CandidateDetail` chỉ lấy flag từ status; image existence không nằm trong `canCompleteWorkerWelfareCheck()` mà được validate muộn hơn trong `WorkerWelfareCheckService`.
- **DATA**: Không có thay đổi schema; command chỉ dựng prerequisite data, không giả lập kết quả GBG/certificate.
- **CONFIG**: Không thêm config/env.
- **EXTERNAL**: Command không gọi GBG/MatchMaker; các external call chỉ xảy ra khi tester gọi welfare API và queue job xử lý.
- **INFRASTRUCTURE**: Không đổi queue/supervisor; muốn thấy certificate cần worker hiện có chạy được.
