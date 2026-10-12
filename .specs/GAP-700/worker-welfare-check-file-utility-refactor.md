# SPEC: Worker Welfare Check File Utility Refactor

> **Trạng thái**: `IMPLEMENTED`
> **Ngày tạo**: 2026-09-23
> **Author**: Codex

## 1. Tổng quan

Task này cập nhật GAP-700 theo review kiến trúc: Service không được inject một
Service khác. `WorkerWelfareCheckService` hiện đang inject
`FileServiceInterface` để dùng các thao tác file; dependency này sẽ được loại
bỏ bằng cách tách phần technical/stateless sang `App\Utilities\FileUtility`.

Đồng thời rà soát `FileService` để tách các helper thuần filesystem, storage,
temporary-file và image/PDF có thể tái sử dụng, nhưng giữ lại trong Service các
method có repository query, persistence hoặc business workflow.

**Yêu cầu gốc**: Review GAP-700 yêu cầu bổ sung rule chung “Service không inject
Service”, chuyển các function `WorkerWelfareCheckService` đang dùng từ
`FileService` sang Utilities và refactor các function thuần tiện ích trong
`app/Services/FileService.php`.

**Phạm vi không đổi**: Không thay đổi API endpoint, score rule, queue flow,
MatchMaker sync, email behavior, database schema hoặc storage contract.

## 2. Database Design

N/A — Không thêm/sửa migration, table, column hoặc relationship. Các record
`files` vẫn được tạo qua `FileRepositoryInterface`; chỉ thay đổi nơi điều phối
technical upload trong Worker Welfare Check.

## 3. API Contract

N/A — Không thay đổi endpoint hoặc validation/response contract.

Các endpoint hiện tại vẫn giữ nguyên:

- `POST /api/consultant/candidates/{id}/worker_welfare_check`
- `GET /api/consultant/candidates/{id}/worker_welfare_checks`

## 4. Business Logic (Service Layer)

### 4.1. Rule kiến trúc mới

Bổ sung vào `AGENTS.md`:

- Service MUST NOT inject một Service hoặc `ServiceInterface` khác.
- Shared stateless technical helpers phải nằm trong `App\Utilities\*Utility`;
  Utility không được query database hoặc chứa business workflow.
- Khi cần persistence, Service dùng Repository Interface trực tiếp; khi cần
  external integration, dùng External contract trực tiếp.
- Nếu hai Service cần cùng business workflow, không giải quyết bằng cách
  inject Service vào Service; phải gom workflow vào một Service phù hợp hoặc
  tách phần stateless thực sự dùng chung thành Utility.

### 4.2. Phân loại method trong `FileService`

| Method/nhóm hiện tại | Quyết định | Lý do |
|---|---|---|
| `downloadToTemp()` | Chuyển sang `FileUtility` | Đọc stream từ storage và tạo temp file, không cần Repository/business state |
| `compressImageForPdf()` | Chuyển sang `FileUtility` | Image transformation thuần kỹ thuật; các giới hạn ảnh chuyển thành constants của Utility |
| `cleanupTempFile()` | Chuyển sang `FileUtility` | Cleanup filesystem thuần kỹ thuật |
| Phần tính path/name và upload storage dùng chung của `createFile()` | Tách helper kỹ thuật vào `FileUtility`; `createFile()` vẫn ở `FileService` | Upload file record cần Service phối hợp Storage + Repository và xử lý contract conversion |
| `generateFilePath()`, `generateFileName()` | Dùng implementation từ `FileUtility`; giữ compatibility nếu cần cho các subclass hiện tại | Đây là formatting/path helper; phải bảo toàn naming override của `DocumentService`, `MedicalQuestionnaireService`, `ApplicationPackService` |
| `deleteFile()` | Chuyển implementation sang `FileUtility` | Chỉ thao tác Storage; các method public delete và rule welfare-check vẫn ở `FileService` |
| `convertWordToPDF()`, `downloadFile()`, `resizePng()` | Đánh giá/tách phần kỹ thuật sang `FileUtility` với tham số rõ ràng | Không chứa query/business rule; phải giữ nguyên behavior của contract/document flows và subclass callers |
| `getFilesByType()`, `getFileById()`, `getFileByJobIdAndId()` | Giữ ở Service/Repository boundary | Có database query; `getFilesByType()` còn enrich `CandidateTiming` cho loại contract |
| `createFile()`, status/expiry methods, delete workflow, tracking, candidate RTW reset | Giữ ở Service | Có persistence, authorization/business branching, side effect hoặc workflow coordination |
| `signWithContractDocument()` | Giữ ở `FileService` | Contract-specific workflow, không phải helper dùng chung |

`FileUtility` không được nhận hoặc gọi Repository. Với các helper cần
repository, Service vẫn là nơi phối hợp và Repository là nơi persistence.

### 4.3. Refactor `WorkerWelfareCheckService`

1. Xóa property/constructor dependency `FileServiceInterface`.
2. Thay các call sau bằng `FileUtility`:
   - `downloadToTemp()` trong `downloadCheckImages()`;
   - `compressImageForPdf()` khi tạo certificate;
   - `cleanupTempFile()` trong hai nhánh `finally`.
3. Thay `getFilesByType()` bằng query đọc trực tiếp qua
   `FileRepositoryInterface`, giữ đúng filter candidate-level, type và thứ tự
   file mới nhất. Không đưa query vào Utility.
4. Thay `createFile()` bằng một private helper của Worker để:
   - dùng helper upload/path của `FileUtility`;
   - tạo metadata record qua `$fileRepository->create()`;
   - giữ `File::TYPE_WORKER_WELFARE_CHECK_CERTIFICATE`, status uploaded,
     `uploaded_at`, candidate ID, job ID và `converted_file_url` hiện tại.
5. Giữ nguyên thứ tự: face match → lưu score/check → dispatch job; queue job
   vẫn tạo certificate → update `certificate_file_id` → sync MatchMaker → gửi
   failure email khi score dưới threshold.
6. Không tạo query trong loop, không thêm transaction cho các read hiện tại,
   không đổi custom exception hoặc side-effect behavior.

### 4.4. Behavior invariants cần giữ

- `downloadToTemp()` vẫn lấy extension từ `original_file_name`, fallback URL,
  reject storage stream rỗng và ném `APIErrorException` hiện tại.
- `compressImageForPdf()` vẫn fallback về source khi GD/image content không
  hợp lệ, giới hạn max dimension `800` và JPEG quality `80`.
- Cleanup vẫn chạy trong `finally` cho cả synchronous request và queue job.
- Certificate vẫn là candidate-level file với `job_id = 0`.
- `candidate_face_matching_rates.score` vẫn lưu tỷ lệ 0–1; welfare check score
  vẫn lưu phần trăm 0–100.

## 5. Data Origin & Call Chain

### 5.1. Synchronous face-match flow

```text
POST /api/consultant/candidates/{id}/worker_welfare_check
  → CandidateController::performWorkerWelfareCheck()
    → WorkerWelfareCheckService::performCheck()
      → CandidateRepositoryInterface::find($candidateId)
      → FileRepositoryInterface::firstByFilter($welfareImageFileId, $candidateId, type, job_id)
      → FileRepositoryInterface::allByFilter(interview image filter)
      → FileUtility::downloadToTemp(File)
      → GbgFaceMatchApi::compareTwoImages()
      → CandidateFaceMatchingRateRepositoryInterface::create()
      → CandidateWelfareCheckRepositoryInterface::create()
      → GenerateWorkerWelfareCheckCertificateJob::dispatch()
      → FileUtility::cleanupTempFile($tempFiles)
```

### 5.2. Queue certificate flow

```text
GenerateWorkerWelfareCheckCertificateJob::handle()
  → WorkerWelfareCheckService::processPostCheck()
    → CandidateWelfareCheckRepositoryInterface::find()
    → CandidateWelfareCheck relations: candidate/interviewImageFile/welfareImageFile
    → BranchRepositoryInterface::find($branchId)
    → FileUtility::downloadToTemp(File)
    → FileUtility::compressImageForPdf($tempPath)
    → render PDF
    → FileUtility upload/path helper
    → FileRepositoryInterface::create($fileData)
    → CandidateWelfareCheckRepositoryInterface::update(certificate_file_id)
    → MatchMakerApiInterface + Mail
    → FileUtility::cleanupTempFile($tempFiles)
```

| Biến / dữ liệu | Nguồn cung cấp | Nơi sử dụng | Confirmed? |
|---|---|---|---|
| `$candidateId` | Route parameter / queued job payload | Candidate/file scope, welfare record, logs | ✅ |
| `$welfareImageFileId` | `WorkerWelfareCheckRequest` validated input | FileRepository filter | ✅ |
| `$interviewFile` | FileRepository query theo candidate-level captured face image | GBG, PDF, welfare record | ✅ |
| `$welfareImageFile` | FileRepository query theo ID + candidate + welfare type + job 0 | GBG, PDF, welfare record | ✅ |
| `$tempFiles` | Worker local flow state | `finally` cleanup | ✅ |
| `$certificateFile` | FileRepository create sau storage upload | `certificate_file_id` update | ✅ |

Không giả định thêm request key, relation hoặc resource variable mới.

## 6. Constants & Enums

- Đưa các constants chỉ phục vụ image/PDF utility về `FileUtility`, gồm max
  dimension, JPEG quality, background color và default extension nếu cần.
- Giữ và tái sử dụng constants file type/status từ `App\Models\File`.
- Nếu cần biểu diễn candidate-level file scope, dùng một constant chung trong
  `File` thay vì thêm literal `0` ở flow mới.
- Không thay đổi `CandidateWelfareCheck::PASS_SCORE_THRESHOLD` hoặc các
  `CandidateFaceMatchingRate`/`File` type constants hiện có.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|---|---|---|
| `app/Utilities/FileUtility.php` | `App\Utilities` | Stateless storage/temp/image/path helpers được dùng bởi Worker và FileService |
| `tests/Unit/Utilities/FileUtilityTest.php` | `Tests\Unit\Utilities` | Test download, empty stream/error, compression, cleanup và upload/path helper |

### 7.2. Files sửa

| File | Thay đổi |
|---|---|
| `AGENTS.md` | Bổ sung rule Service không inject Service và ranh giới Utility/Repository |
| `app/Services/WorkerWelfareCheckService.php` | Bỏ `FileServiceInterface`; dùng FileUtility + FileRepository trực tiếp; giữ nguyên business flow |
| `app/Services/FileService.php` | Gọi FileUtility cho helper kỹ thuật; giữ các method có repository/business workflow |
| `app/Contracts/Services/FileServiceInterface.php` | Gỡ các public technical helper đã chuyển khỏi Service contract |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Bỏ FileService mock; cập nhật repository/storage fixtures và test certificate record/cleanup |
| `tests/Unit/Services/FileServiceTest.php` | Chuyển test technical helper sang FileUtility; giữ regression test cho delete business rule |
| `app/Services/DocumentService.php` | Chỉ sửa nếu cần để gọi FileUtility sau khi tách path/image helper, giữ naming override |
| `app/Services/MedicalQuestionnaireService.php` | Chỉ sửa nếu cần để gọi FileUtility sau khi tách path/image helper, giữ naming override |
| `app/Services/ApplicationPackService.php` | Chỉ sửa nếu cần để gọi FileUtility sau khi tách path helper, giữ behavior application pack |

Không sửa các thay đổi unrelated đang có trong working tree, đặc biệt phần
whitespace hiện tại của `WorkerWelfareCheckService.php`.

## 8. Test Cases

| Test File | Test Method/Scope | Mô tả |
|---|---|---|
| `tests/Unit/Utilities/FileUtilityTest.php` | Download success/error | Đọc file từ fake storage, reject empty/missing stream, cleanup temp path |
| `tests/Unit/Utilities/FileUtilityTest.php` | Image compression | Resize đúng max dimension/quality và fallback source với invalid image |
| `tests/Unit/Utilities/FileUtilityTest.php` | Upload/path helper | Giữ candidate-level job scope, filename và storage path behavior hiện tại |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Perform success/high score | Không còn mock `FileService`, vẫn dispatch job và cleanup |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Perform no interview image | Query trực tiếp FileRepository và giữ APIErrorException |
| `tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Post-check | Download/compress/create certificate/update record/cleanup theo đúng thứ tự |
| `tests/Unit/Services/FileServiceTest.php` | Delete referenced file | Rule không cho xóa file được welfare check tham chiếu vẫn giữ nguyên |
| Affected feature tests | Existing welfare endpoint coverage | Xác nhận container resolve Service mới và API contract không đổi |
| Toàn bộ test suite | `./vendor/bin/phpunit` | Bắt buộc pass 100% sau implementation |

## 9. Living-spec deviation audit

- **CODE**: Trước implementation, `WorkerWelfareCheckService` inject
  `FileServiceInterface` và gọi các helper file tại
  `app/Services/WorkerWelfareCheckService.php`; implementation đã loại bỏ
  deviation này. Business flow vẫn nằm trong `WorkerWelfareCheckService`
  và Repository/External boundary không đổi.
- **DATA**: Không đổi bảng/cột/quan hệ; file metadata và welfare score giữ
  format hiện tại.
- **CONFIG**: Không thêm config/env; các giới hạn image được chuyển thành
  constants kỹ thuật tương đương.
- **EXTERNAL**: GBG, MatchMaker và Mail không đổi endpoint/thứ tự/điều kiện.
- **INFRASTRUCTURE**: Queue sync/async phụ thuộc connection như hiện tại;
  temp file cleanup và storage driver behavior phải giữ nguyên.

## 10. Checklist trước khi Approve

- [x] Rule Service không inject Service đã được ghi rõ trong `AGENTS.md`.
- [x] Đã phân loại method FileService: technical helper tách khỏi DB/business workflow.
- [x] Call chain và data origin đã được trace từ route/job tới Repository/Utility.
- [x] Không thay đổi API, schema, score threshold, queue, MatchMaker hoặc email contract.
- [x] Test impact đã được liệt kê cho Worker, FileService và Utility mới.
- [x] User review và approve plan trước khi implementation.

## 11. Implementation Record

- `WorkerWelfareCheckService` không còn inject `FileServiceInterface`; các helper
  storage/temp/image dùng `FileUtility`, còn file query và persistence dùng
  `FileRepositoryInterface`.
- `FileService` giữ business workflow và repository coordination; các helper
  filesystem/storage/PDF/image đã được chuyển implementation sang `FileUtility`.
- Đã chạy affected tests và toàn bộ PHPUnit: `477 tests, 2080 assertions` pass.
