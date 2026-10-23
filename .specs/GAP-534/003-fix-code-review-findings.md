# SPEC: GAP-534 — Fix Code Review Findings (Profile Deletion Guard, Storage Cleanup, Repository Architecture)

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-20
> **Author**: Antigravity
> **Jira**: [GAP-534](https://gappersonnel.atlassian.net/browse/GAP-534), "Consultant - Multi Candidate Selection for Bulk Archive & Auto Communicate"
> **Kế thừa & Liên kết**: Kế thừa trực tiếp từ [.specs/GAP-534/001-bulk-archive-auto-communicate.md](001-bulk-archive-auto-communicate.md) và [.specs/GAP-534/002-scope-document-reset-by-job-ids.md](002-scope-document-reset-by-job-ids.md). Spec `003` xử lý trọn gói 4 vấn đề được phát hiện trong đợt Code Review.
> **Template**: [.specs/SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md)

---

## 1. Tổng quan

Đợt Code Review cho task GAP-534 đã phát hiện 4 vấn đề cần xử lý:
1. **[High] Lỗi cú pháp/Ràng buộc NOT NULL trong `SmsPreCampaignRepository`**: Theo quyết định của user, **bỏ hoàn toàn** việc xử lý xóa candidate trong `sms_pre_campaigns` vì đây chỉ là bảng draft tạm thời (TTL 24h), không phải bảng quan hệ nghiệp vụ lâu dài của candidate.
2. **[High] Guard kiểm tra xóa profile quá lỏng lẻo (`isAvailableForProfileDeletion`)**: Điều kiện hiện tại chỉ check `$candidate->candidateJobs->contains(STATUS_ARCHIVED)`. Nếu ứng viên có 1 job bị archive ở Branch A nhưng đang có job đi làm (`STATUS_APPROVED`, `STATUS_PLACED`) ở Branch B hoặc đang `LIVE`/`PERM` bên MatchMaker, việc click link xóa từ email cũ sẽ xóa sạch toàn bộ tài khoản và công việc đang hoạt động của ứng viên.
3. **[Medium] Cảnh báo giả và gọi thừa Storage API khi xóa file `'EMPTY'` / `'nothing'` trong `deleteCandidate()`**: Các file không phải Word-to-PDF có cột `converted_file_url` mang giá trị mặc định là `'nothing'` (`FileUtility::S3_EMPTY_CONVERTED_URL`) hoặc `'EMPTY'`. Gọi `Storage::delete()` cho các chuỗi này gây thừa API call và spam `Log::warning(...)`.
4. **[Medium] Vi phạm kiến trúc phân tầng trong `CandidateRepository`**: `CandidateRepository` đang chứa `archiveCandidateJobsByBranch()` (thao tác trực tiếp trên `CandidateJob`) và `removeStarsForUserByCandidateIds()` (thao tác trực tiếp trên `StarredCandidate`), vi phạm nguyên tắc Repository chỉ thao tác trên Model đại diện của chính nó.

---

## 2. Database Design

Không có thay đổi về database schema:
- Không tạo bảng mới hoặc migration mới.
- Các cột và index hiện hữu đáp ứng đầy đủ yêu cầu.

---

## 3. API Contract & Docs Assessment

- **Đánh giá API Contract / API Docs**: `N/A — no API contract/API docs change`.
- Lý do: Toàn bộ thay đổi nằm ở tầng nội bộ Repository, Service guard validation, và dọn dẹp file storage. Routes (`/api/v1/consultant/candidates/bulk-archive`, `/api/v1/candidate/profile_deletion`), request/response payload, HTTP status codes và error contract giữ nguyên 100%.

---

## 4. Chi tiết giải pháp kỹ thuật

### 4.1. Vấn đề 1: Bỏ xử lý `sms_pre_campaigns` trong `CandidateService::deleteCandidate()`

- **Bản chất**: Bảng `sms_pre_campaigns` là bảng tạm thời cho các chiến dịch SMS nháp với TTL chỉ 24 giờ và tự động được dọn dẹp bởi `SmsService::removeExpiredPreCampaigns()` khi hết hạn. Candidate không có quan hệ Foreign Key với bảng này.
- **Thực hiện**:
  1. Trong `CandidateService`:
     - Bỏ inject `SmsPreCampaignRepositoryInterface $smsPreCampaignRepository` khỏi constructor và thuộc tính class.
     - Trong `deleteCandidate()`: Bỏ query `$smsPreCampaignRows = $this->smsPreCampaignRepository->getContainingCandidate($id)...` và bỏ gọi `$this->smsPreCampaignRepository->removeCandidateFromReceiverIds(...)`.
  2. Trong `SmsPreCampaignRepositoryInterface` & `SmsPreCampaignRepository`:
     - Xóa các method `getContainingCandidate()` và `removeCandidateFromReceiverIds()`, cùng private helper `getDatabaseDriver()` (vì không còn method nào khác dùng đến).

### 4.2. Vấn đề 2: Siết chặt Guard `isAvailableForProfileDeletion()`

- **Bản chất**: Chỉ cho phép xóa vĩnh viễn hồ sơ khi ứng viên **đã được archive trên toàn bộ các công việc** và **không đang hoạt động bên MatchMaker**.
- **Thực hiện**:
  Trong `CandidateService.php`, cập nhật method `isAvailableForProfileDeletion()`:
  ```php
  private function isAvailableForProfileDeletion(?Candidate $candidate, int $candidateId, string $token): bool
  {
      $cachedToken = Cache::get(self::ARCHIVE_PROFILE_DELETION_TOKEN_CACHE_KEY_PREFIX . $candidateId);

      return $candidate instanceof Candidate
          && $candidate->id === $candidateId
          && !empty($cachedToken)
          && \is_string($cachedToken)
          && hash_equals($cachedToken, $token)
          && $this->isAlreadyArchivedCandidate($candidate)
          && !in_array($candidate->match_maker_status, [Candidate::MM_STATUS_LIVE, Candidate::MM_STATUS_PERM], true);
  }
  ```
  - `$this->isAlreadyArchivedCandidate($candidate)`: Đảm bảo toàn bộ `candidateJobs` (trừ matchmaker) đều có `status === STATUS_ARCHIVED`. Nếu candidate có bất kỳ job nào ở branch khác đang active (`STATUS_APPROVED`, `STATUS_PLACED`, `STATUS_INTERVIEW`, v.v.), điều kiện này sẽ trả về `false`.
  - `!in_array(..., [Candidate::MM_STATUS_LIVE, Candidate::MM_STATUS_PERM], true)`: Đảm bảo ứng viên không đang là lao động hoạt động (LIVE/PERM) bên MatchMaker.

### 4.3. Vấn đề 3: Bỏ qua file placeholder `'EMPTY'` / `'nothing'` trong Storage Cleanup

- **Bản chất**: Tránh gửi request vô nghĩa đến Storage và tránh sinh log cảnh báo giả.
- **Thực hiện**:
  Trong `CandidateService::deleteCandidate()`:
  ```php
  foreach ($filePaths as $filePath) {
      foreach ([$filePath->url, $filePath->converted_file_url] as $storagePath) {
          if (empty($storagePath)
              || $storagePath === FileUtility::S3_EMPTY_CONVERTED_URL
              || $storagePath === 'EMPTY'
              || !FileUtility::deleteFile($storagePath, false)
          ) {
              continue;
          }

          Log::warning('Candidate profile storage file could not be deleted after database purge.', [
              'candidate_id' => $id,
              'path' => $storagePath,
          ]);
      }
  }
  ```
  - Tái sử dụng `FileUtility::deleteFile($storagePath, false)`: Hàm này đã có sẵn kiểm tra `if (!Storage::exists($url)) return true;`, đảm bảo an toàn tuyệt đối và không phát sinh warning giả khi file không tồn tại.

### 4.4. Vấn đề 4: Tách method về đúng Model Repository

- **Bản chất**: Tuân thủ nguyên tắc Single Responsibility: `CandidateRepository` chỉ truy cập model `Candidate`. Các truy vấn trên `CandidateJob` và `StarredCandidate` phải thuộc về repository chuyên trách của chúng.
- **Thực hiện**:
  1. Chuyển method `archiveCandidateJobsByBranch(...)`:
     - Xóa khỏi `CandidateRepositoryInterface` và `CandidateRepository`.
     - Thêm vào `CandidateJobRepositoryInterface` và `CandidateJobRepository`:
       ```php
       public function archiveCandidateJobsByBranch(array $candidateIds, int $branchId, string $archivedStatus, Carbon $archivedAt): int;
       ```
  2. Chuyển method `removeStarsForUserByCandidateIds(...)`:
     - Xóa khỏi `CandidateRepositoryInterface` và `CandidateRepository`.
     - Thêm vào `StarredCandidateRepositoryInterface` và `StarredCandidateRepository`:
       ```php
       public function removeStarsForUserByCandidateIds(array $candidateIds, int $userId): int;
       ```
  3. Trong `CandidateService`:
     - Tại `updateCandidateJobStatus()` và `archiveBulkCandidatesAtomically()`: Thay `$this->candidateRepository->archiveCandidateJobsByBranch(...)` thành `$this->candidateJobRepository->archiveCandidateJobsByBranch(...)`.
     - Tại `archiveBulkCandidatesAtomically()`: Thay `$this->candidateRepository->removeStarsForUserByCandidateIds(...)` thành `$this->starredCandidateRepository->removeStarsForUserByCandidateIds(...)`.

---

## 5. Danh sách Files cần sửa đổi

| File | Thay đổi |
|---|---|
| `app/Contracts/Repositories/SmsPreCampaignRepositoryInterface.php` | Xóa `getContainingCandidate()` và `removeCandidateFromReceiverIds()` |
| `app/Repositories/SmsPreCampaignRepository.php` | Xóa `getContainingCandidate()`, `removeCandidateFromReceiverIds()`, `getDatabaseDriver()` |
| `app/Contracts/Repositories/CandidateRepositoryInterface.php` | Xóa `archiveCandidateJobsByBranch()`, `removeStarsForUserByCandidateIds()` |
| `app/Repositories/CandidateRepository.php` | Xóa `archiveCandidateJobsByBranch()`, `removeStarsForUserByCandidateIds()` |
| `app/Contracts/Repositories/CandidateJobRepositoryInterface.php` | Thêm `archiveCandidateJobsByBranch(...)` |
| `app/Repositories/CandidateJobRepository.php` | Implement `archiveCandidateJobsByBranch(...)` |
| `app/Contracts/Repositories/StarredCandidateRepositoryInterface.php` | Thêm `removeStarsForUserByCandidateIds(...)` |
| `app/Repositories/StarredCandidateRepository.php` | Implement `removeStarsForUserByCandidateIds(...)` |
| `app/Services/CandidateService.php` | - Bỏ inject `smsPreCampaignRepository`<br>- Bỏ cleanup sms pre-campaign trong `deleteCandidate()`<br>- Cập nhật guard `isAvailableForProfileDeletion()`<br>- Cập nhật storage cleanup dùng `FileUtility::deleteFile` và bỏ qua placeholder<br>- Đổi gọi sang `candidateJobRepository` và `starredCandidateRepository` |
| `tests/Feature/Api/Consultant/CandidateArchiveTest.php` | Thêm test case cho guard chặn xóa profile khi candidate còn job active hoặc matchmaker LIVE |

---

## 6. Test Cases & Verification Plan

### 6.1. Test Cases

1. **Test kiểm chứng Guard Profile Deletion từ chối khi candidate còn job active**:
   - `testProfileDeletionRejectsCandidateWithActiveJobOnOtherBranch`:
     + Candidate có Job 1 (Archived trên Branch 1) và Job 2 (`STATUS_APPROVED` trên Branch 2).
     + Gọi `GET /api/candidate/profile_deletion?id=...&token=...` -> Trả về `can_delete: false`.
     + Gọi `POST /api/candidate/profile_deletion` -> Bị reject với lỗi `profileDeletionTokenInvalid` (400).
     + Candidate và Job 2 trên Branch 2 không bị xóa.
2. **Test kiểm chứng Guard Profile Deletion từ chối khi candidate có match_maker_status LIVE**:
   - `testProfileDeletionRejectsCandidateWithMatchMakerStatusLive`:
     + Candidate có Job (Archived) nhưng `match_maker_status = Candidate::MM_STATUS_LIVE`.
     + Gọi `GET` -> `can_delete: false`.
     + Gọi `POST` -> Bị reject với lỗi `profileDeletionTokenInvalid` (400).
3. **Test hồi quy toàn bộ luồng Bulk Archive & Profile Deletion**:
   - Tất cả các test cases hiện tại trong `tests/Feature/Api/Consultant/CandidateArchiveTest.php` phải tiếp tục PASS 100%.

### 6.2. Verification Checklist

- [x] `php -l` toàn bộ file thay đổi (PASS).
- [x] `git diff --check` không có whitespace/formatting error (PASS).
- [x] Chạy Feature test suite: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit tests/Feature/Api/Consultant/CandidateArchiveTest.php` (PASS: 11 tests, 67 assertions).
- [x] Chạy full PHPUnit test suite: `APP_CONFIG_CACHE=/private/tmp/gap-534-config-test.php ./vendor/bin/phpunit` (PASS: 636 tests, 9,388 assertions).

#### Implementation Evidence (2026-10-20)

- **Vấn đề 1**: Đã loại bỏ hoàn toàn việc gọi `smsPreCampaignRepository` trong `CandidateService::deleteCandidate()`. Đã xóa các method không cần thiết `getContainingCandidate()` và `removeCandidateFromReceiverIds()` trong `SmsPreCampaignRepositoryInterface` và `SmsPreCampaignRepository`.
- **Vấn đề 2**: Đã siết chặt guard `CandidateService::isAvailableForProfileDeletion()`: yêu cầu `$this->isAlreadyArchivedCandidate($candidate)` (toàn bộ candidate jobs trừ matchmaker phải là `STATUS_ARCHIVED`) và `match_maker_status` không thuộc `[MM_STATUS_LIVE, MM_STATUS_PERM]`.
- **Vấn đề 3**: Đã cập nhật storage cleanup trong `deleteCandidate()`: bỏ qua các chuỗi rỗng và placeholder (`FileUtility::S3_EMPTY_CONVERTED_URL`, `'EMPTY'`), đồng thời sử dụng `FileUtility::deleteFile($storagePath, false)` để kiểm tra file tồn tại trước khi xóa, loại bỏ warning giả.
- **Vấn đề 4**: Đã chuyển `archiveCandidateJobsByBranch()` sang `CandidateJobRepository` và `removeStarsForUserByCandidateIds()` sang `StarredCandidateRepository`. Cập nhật `CandidateService` gọi đúng các repository đại diện cho Model.
- **Verification**:
  - `php -l`: All files PASS.
  - `git diff --check`: PASS (clean).
  - Feature test: `tests/Feature/Api/Consultant/CandidateArchiveTest.php` PASS (11 tests, 67 assertions).
  - Full PHPUnit: PASS (636 tests, 9,388 assertions, 0 failures, 0 errors).
- **Status: PASS.**
