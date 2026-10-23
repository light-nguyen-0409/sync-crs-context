# SPEC: GAP-534 — Scope Candidate Document Reset by Job IDs

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-20
> **Author**: Antigravity
> **Jira**: [GAP-534](https://gappersonnel.atlassian.net/browse/GAP-534), "Consultant - Multi Candidate Selection for Bulk Archive & Auto Communicate"
> **Kế thừa & Liên kết**: Kế thừa trực tiếp từ [.specs/GAP-534/001-bulk-archive-auto-communicate.md](001-bulk-archive-auto-communicate.md). Tạo spec mới `002` theo quy tắc sequence của dự án nhằm xử lý code review comment [High] về việc reset/delete file hợp đồng bị mất dữ liệu chéo chi nhánh.
> **Template**: [.specs/SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md)

---

## 1. Tổng quan

Khi thực hiện tính năng **Bulk Archive** ứng viên tại một Chi nhánh (Branch), hệ thống thực hiện reset tiến trình hợp đồng và xóa các file hợp đồng đã ký (`work_contract`, `work_contract_signature`, `medical_contract`, `medical_contract_signature`) của công việc bị archive để nếu sau này ứng viên được kích hoạt lại thì sẽ ký lại hợp đồng mới.

Tuy nhiên, implementation hiện tại tại `CandidateService::prepareCandidateJobDocumentResetData()` gọi `FileRepository::getByCandidateIdsAndTypes()` chỉ lọc theo `candidate_id` và `type`, hoàn toàn bỏ qua `job_id`. Nếu một ứng viên có công việc tại Chi nhánh A (đang bị archive) và đồng thời có công việc đang hoạt động tại Chi nhánh B, hành vi bulk archive ở Chi nhánh A sẽ vô tình lấy và xóa vĩnh viễn (cả file vật lý trên S3/disk và record trong DB) các file hợp đồng thuộc Chi nhánh B.

Mục tiêu của spec này là giới hạn phạm vi truy vấn và xóa file hợp đồng chính xác theo các cặp `(candidate_id, job_id)` đang được archive tại chi nhánh hiện tại, loại bỏ hoàn toàn nguy cơ mất dữ liệu chéo chi nhánh (Permanent Cross-Branch Data Loss).

---

## 2. Database Design

Không có thay đổi về schema database:
- Bảng `files` đã có sẵn cột `candidate_id` (indexed) và `job_id` (indexed).
- Không cần tạo bảng mới hoặc migration mới.

---

## 3. API Contract & Docs Assessment

- **Đánh giá API Contract / API Docs**: `N/A — no API contract/API docs change`.
- Lý do: Thay đổi này hoàn toàn nằm ở tầng nội bộ Data Access (`FileRepository`) và Business Logic (`CandidateService`). Route, request payload, response payload, HTTP status code và error contract của API `POST /api/v1/consultant/candidates/bulk-archive` giữ nguyên 100%.

---

## 4. Business Logic & Solution Design

### 4.1. Phân tích nguyên nhân gốc (Root Cause)

Trong `app/Services/CandidateService.php`:
```php
// prepareCandidateJobDocumentResetData():
$resetDocumentFiles = $this->fileRepository->getByCandidateIdsAndTypes(
    array_values(array_unique($documentResetCandidateIds)),
    [
        FileModel::TYPE_WORK_CONTRACT,
        FileModel::TYPE_WORK_CONTRACT_SIGNATURE,
        FileModel::TYPE_MEDICAL_CONTRACT,
        FileModel::TYPE_MEDICAL_CONTRACT_SIGNATURE,
    ]
);
```
Query sinh ra:
```sql
SELECT * FROM files
WHERE candidate_id IN (?)
  AND type IN ('work_contract', 'work_contract_signature', 'medical_contract', 'medical_contract_signature');
```
Do không có điều kiện `job_id`, tất cả các file hợp đồng của candidate trên mọi branch/job đều bị trả về và sau đó bị `deleteResetDocumentFiles()` xóa vĩnh viễn.

### 4.2. Giải pháp kỹ thuật

1. **Thay thế `getByCandidateIdsAndTypes()` bằng `getByCandidateJobKeysAndTypes()`**:
   - `FileRepositoryInterface`:
     ```php
     /**
      * @param array<int, array{candidate_id: int, job_id: int}> $candidateJobKeys
      * @param array<int, string> $types
      */
     public function getByCandidateJobKeysAndTypes(array $candidateJobKeys, array $types): SupportCollection;
     ```
   - Xóa method `getByCandidateIdsAndTypes()` khỏi Interface và Repository vì method này mới được tạo cho GAP-534 và không có bất kỳ caller nào khác trong codebase.

2. **Implementation trong `FileRepository`**:
   - Tối ưu hóa truy vấn kết hợp Index và điều kiện chính xác:
     ```php
     public function getByCandidateJobKeysAndTypes(array $candidateJobKeys, array $types): SupportCollection
     {
         if ([] === $candidateJobKeys || [] === $types) {
             return collect();
         }

         $candidateIds = array_values(array_unique(array_column($candidateJobKeys, 'candidate_id')));
         $jobIds = array_values(array_unique(array_column($candidateJobKeys, 'job_id')));

         return $this->getBaseQuery()
             ->whereIn('type', $types)
             ->whereIn('candidate_id', $candidateIds)
             ->whereIn('job_id', $jobIds)
             ->where(function ($query) use ($candidateJobKeys): void {
                 foreach ($candidateJobKeys as $key) {
                     $query->orWhere(function ($subQuery) use ($key): void {
                         $subQuery->where('candidate_id', $key['candidate_id'])
                             ->where('job_id', $key['job_id']);
                     });
                 }
             })
             ->get();
     }
     ```
   - *Lợi ích hiệu năng*:
     + `whereIn('candidate_id', $candidateIds)` và `whereIn('job_id', $jobIds)` tận dụng trực tiếp 2 index sẵn có trên bảng `files` để thu hẹp phạm vi quét dữ liệu ở mức tối đa trước khi duyệt các cặp OR.
     + Nhóm `orWhere` đảm bảo tính toàn vẹn 100%: chỉ lấy file khớp chính xác cặp `candidate_id` và `job_id` được chỉ định.
     + Tương thích hoàn toàn với cả MySQL và SQLite (`:memory:` trong PHPUnit tests).

3. **Cập nhật `CandidateService::prepareCandidateJobDocumentResetData()`**:
   - Tái sử dụng danh sách `$documentResetTimingKeys` (vốn đã chứa chính xác các cặp `['candidate_id' => ..., 'job_id' => ...]`) hoặc gán biến rõ nghĩa `$documentResetCandidateJobKeys`.
   - Gọi `$this->fileRepository->getByCandidateJobKeysAndTypes($documentResetCandidateJobKeys, [...types...])`.
   - Giữ nguyên luồng kiểm tra `$referencedResetFileIds` qua `candidateWelfareCheckRepository->getReferencedFileIds(...)` và hàm xóa `$this->deleteResetDocumentFiles(...)`.

---

## 5. Data Origin & Call Chain Verification

```
POST /api/consultant/candidates/bulk_archive
  → ConsultantCandidateController::bulkArchive
    → CandidateService::bulkArchive(candidateIds, sendEmail, branchId, archiveUserId)
      → CandidateRepository::getCandidatesForBulkArchive(candidateIds, branchId)
        (Chỉ lấy candidateJobs thuộc branchId)
      → CandidateService::prepareCandidateJobDocumentResetData(archiveJobs)
        (Lọc các job có contract_document_status >= SIGNED_SERVICES_AND_TERMS_OF_ENGAGEMENT)
        → $documentResetCandidateJobKeys = [['candidate_id' => ..., 'job_id' => ...]]
        → FileRepository::getByCandidateJobKeysAndTypes($documentResetCandidateJobKeys, $types)
          → Files trả về CHỈ thuộc các candidate_id VÀ job_id đang được archive ở branchId
      → CandidateService::deleteResetDocumentFiles($resetData['files'], $resetData['referenced_file_ids'])
        → CHỈ xóa file hợp đồng của các jobs ở branch hiện tại. Files của branch khác được bảo vệ nguyên vẹn.
```

**Biến cần verify**:
| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|---|---|---|---|
| `$candidateJob->candidate_id` | `prepareCandidateJobDocumentResetData` | `CandidateJob` model từ `getCandidatesForBulkArchive` | ✅ |
| `$candidateJob->job_id` | `prepareCandidateJobDocumentResetData` | `CandidateJob` model từ `getCandidatesForBulkArchive` | ✅ |
| `candidate_id`, `job_id` | `FileRepository::getByCandidateJobKeysAndTypes` | Mảng `$candidateJobKeys` từ Service | ✅ |

---

## 6. Files cần sửa đổi

| File | Thay đổi |
|---|---|
| `app/Contracts/Repositories/FileRepositoryInterface.php` | Thay `getByCandidateIdsAndTypes` bằng `getByCandidateJobKeysAndTypes(array $candidateJobKeys, array $types): SupportCollection` |
| `app/Repositories/FileRepository.php` | Implement `getByCandidateJobKeysAndTypes` với scoping `candidate_id` và `job_id` |
| `app/Services/CandidateService.php` | Cập nhật `prepareCandidateJobDocumentResetData` truyền các cặp `(candidate_id, job_id)` sang `fileRepository->getByCandidateJobKeysAndTypes` |
| `tests/Feature/Api/Consultant/CandidateArchiveTest.php` | Thêm Feature test case kiểm chứng: Candidate có 2 job ở 2 branch khác nhau, khi bulk archive branch A thì file hợp đồng ở branch B không bị xóa |

---

## 7. Test Cases & Verification Plan

### 7.1. Test Cases

1. **Test hồi quy hiện tại**:
   - `testBulkArchiveUpdatesCandidateJobsAndDoesNotCreateArchiveLog`: Đảm bảo job được archive ở branch hiện tại vẫn được reset contract và xóa file hợp đồng đúng như trước.
2. **Test case mới chống Data Loss chéo Branch**:
   - **Tên test**: `testBulkArchiveOnlyDeletesContractFilesForArchivedBranchAndPreservesOtherBranchFiles`
   - **Kịch bản**:
     - Tạo Candidate X.
     - Tạo Job 1 thuộc Branch 1 (với file hợp đồng A).
     - Tạo Job 2 thuộc Branch 2 (với file hợp đồng B).
     - Gọi `bulk_archive` trên Branch 1 với candidate X.
     - **Assert**:
       + Job 1 đổi status sang `STATUS_ARCHIVED`, contract status reset về `WATCHED_KEY_INFORMATION_DOCUMENT`.
       + File A của Job 1 bị xóa khỏi storage và DB.
       + Job 2 ở Branch 2 giữ nguyên status (không bị archive).
       + File B của Job 2 ở Branch 2 **vẫn tồn tại trên storage và database**.

### 7.2. Verification Checklist

- [x] `php -l` toàn bộ file thay đổi (PASS).
- [x] `git diff --check` không có whitespace/formatting error (PASS).
- [x] Chạy Feature test suite: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit tests/Feature/Api/Consultant/CandidateArchiveTest.php` (PASS: 8 tests, 54 assertions).
- [x] Chạy full PHPUnit test suite: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` (PASS: 633 tests, 9,375 assertions).

#### Implementation Evidence (2026-10-20)

- Đã thay thế `getByCandidateIdsAndTypes()` bằng `getByCandidateJobKeysAndTypes(array $candidateJobKeys, array $types): SupportCollection` trong `FileRepositoryInterface` và `FileRepository`.
- Đã tối ưu hóa query trong `FileRepository::getByCandidateJobKeysAndTypes()`: kết hợp `whereIn('type', $types)->whereIn('candidate_id', ...)->whereIn('job_id', ...)` cùng nhóm điều kiện `orWhere` theo từng cặp `(candidate_id, job_id)`.
- Đã cập nhật `CandidateService::prepareCandidateJobDocumentResetData()`: truyền danh sách `$documentResetTimingKeys` (chứa các cặp `['candidate_id' => ..., 'job_id' => ...]`) vào `getByCandidateJobKeysAndTypes()`.
- Đã thêm Feature test `testBulkArchiveOnlyDeletesContractFilesForArchivedBranchAndPreservesOtherBranchFiles` trong `CandidateArchiveTest.php` xác minh: Khi candidate có Job 1 (Branch 1) và Job 2 (Branch 2), hành vi bulk archive trên Branch 1 chỉ xóa file hợp đồng của Job 1 và giữ nguyên vẹn file hợp đồng của Job 2.
- Kết quả test:
  - Feature test: 8/8 tests PASS.
  - Full PHPUnit: 633/633 tests PASS (0 failures, 0 errors).
- **Status: PASS.**
