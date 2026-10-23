# SPEC: 018 - Standardize Exception Logging & Error Traceability in Permanent Candidate Flow

> **Task**: GAP-691
> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-21
> **Author**: Antigravity

---

## 1. Tổng quan

### 1.1. Bối cảnh & Yêu cầu
Qua rà soát mã nguồn thuộc phạm vi task GAP-691 (Permanent Candidate Intake & MatchMaker Synchronization), phát hiện một số vị trí bắt ngoại lệ (`\Throwable`) nhưng:
1. Thiếu thông điệp chi tiết của ngoại lệ (`$exception->getMessage()`).
2. Ghi đè (shadowing) context key chuẩn `'exception'` của Monolog bằng chuỗi tên class (`$exception::class`), khiến Monolog không thể format file, line và stack trace theo chuẩn PSR-3.
3. Nuốt chửng ngoại lệ ngoài dự kiến (`silent swallow`) mà không ghi log trước khi re-throw ngoại lệ cấp cao hơn.

Kế hoạch này chuẩn hoá việc ghi log lỗi và bảo toàn vết tích ngoại lệ (traceability) trên toàn bộ các thành phần của GAP-691.

### 1.2. API Contract Pre-Deployment Gate
- **Đánh giá ảnh hưởng API Docs**: `N/A — no API contract/API docs change`.
- **Lý do**: Thay đổi chỉ thuộc tầng nội bộ (Service và Job logging), không thay đổi endpoints, request params, response payload, mã lỗi HTTP hay cấu trúc JSON trả về cho client.

---

## 2. Chi tiết các vị trí cần sửa đổi

### 2.1. Vị trí 1: `submit()` khi dispatch job thất bại
- **File**: [`app/Services/PermanentCandidateIntakeService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/PermanentCandidateIntakeService.php#L417-L424)
- **Hiện trạng**:
  ```php
  } catch (\Throwable $exception) {
      Log::error(self::MESSAGE_QUEUE_FAILED, [
          'candidate_id' => $candidate->id,
          'job_id' => $jobId,
          'exception' => $exception::class,
      ]);
      throw new APIErrorException(self::ERROR_MATCH_MAKER_SYNC_FAILED, self::MESSAGE_QUEUE_FAILED);
  }
  ```
- **Sửa đổi**: Bổ sung `error` message và truyền chính object `$exception` vào context:
  ```php
  } catch (\Throwable $exception) {
      Log::error(self::MESSAGE_QUEUE_FAILED, [
          'candidate_id' => $candidate->id,
          'job_id' => $jobId,
          'error' => $exception->getMessage(),
          'exception' => $exception,
      ]);
      throw new APIErrorException(self::ERROR_MATCH_MAKER_SYNC_FAILED, self::MESSAGE_QUEUE_FAILED);
  }
  ```

---

### 2.2. Vị trí 2: `failed()` của Job đồng bộ nền
- **File**: [`app/Jobs/SyncPermanentCandidateToMatchMakerJob.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Jobs/SyncPermanentCandidateToMatchMakerJob.php#L102-L113)
- **Hiện trạng**:
  ```php
  public function failed(Throwable $exception): void
  {
      Log::critical(self::FAILURE_LOG_MESSAGE, [
          'candidate_id' => $this->data->candidateId,
          'job_id' => $this->data->jobId,
          'file_id' => $this->data->cvFileId,
          'agreement_file_id' => $this->data->agreementFileId,
          'permanent_form_file_id' => $this->generatedFormFileId,
          'exception' => $exception::class,
          'error' => $exception->getMessage(),
      ]);
  }
  ```
- **Sửa đổi**: Thay `'exception' => $exception::class` bằng `'exception' => $exception` để Monolog ghi nhận full stack trace, file và line:
  ```php
  public function failed(Throwable $exception): void
  {
      Log::critical(self::FAILURE_LOG_MESSAGE, [
          'candidate_id' => $this->data->candidateId,
          'job_id' => $this->data->jobId,
          'file_id' => $this->data->cvFileId,
          'agreement_file_id' => $this->data->agreementFileId,
          'permanent_form_file_id' => $this->generatedFormFileId,
          'error' => $exception->getMessage(),
          'exception' => $exception,
      ]);
  }
  ```

---

### 2.3. Vị trí 3: `generateWorkFinderAgreement()` khi render PDF hoặc upload gặp lỗi
- **File**: [`app/Services/PermanentCandidateIntakeService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/PermanentCandidateIntakeService.php#L285-L293)
- **Hiện trạng**: Nuốt ngoại lệ hoàn toàn, không có log.
  ```php
  } catch (\Throwable $exception) {
      if ($uploadedUrl) {
          Storage::delete($uploadedUrl);
      }

      throw new APIErrorException(self::ERROR_GENERATION_FAILED, self::MESSAGE_GENERATION_FAILED);
  }
  ```
- **Sửa đổi**: Ghi `Log::error` trước khi ném ngoại lệ để phục vụ điều tra lỗi render Dompdf / S3 upload:
  ```php
  } catch (\Throwable $exception) {
      if ($uploadedUrl) {
          Storage::delete($uploadedUrl);
      }

      Log::error('Work finder agreement generation failed: '.$exception->getMessage(), [
          'candidate_id' => $candidate->id,
          'job_id' => $jobId,
          'error' => $exception->getMessage(),
          'exception' => $exception,
      ]);

      throw new APIErrorException(self::ERROR_GENERATION_FAILED, self::MESSAGE_GENERATION_FAILED);
  }
  ```

---

### 2.4. Vị trí 4: `generatePermanentCandidateForm()` khi lưu metadata / upload form PDF thất bại
- **File**: [`app/Services/PermanentCandidateIntakeService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/PermanentCandidateIntakeService.php#L555-L560)
- **Hiện trạng**: Bắt ngoại lệ lưu file/metadata vào DB nhưng không log:
  ```php
  } catch (\Throwable $exception) {
      if ($uploadedUrl) {
          Storage::delete($uploadedUrl);
      }
      throw new MatchMakerTransientException(self::MESSAGE_FORM_GENERATION_FAILED);
  }
  ```
- **Sửa đổi**: Ghi `Log::error` trước khi throw `MatchMakerTransientException` (giữ nguyên error message để đảm bảo tương thích ngược với các assertion test hiện tại):
  ```php
  } catch (\Throwable $exception) {
      if ($uploadedUrl) {
          Storage::delete($uploadedUrl);
      }

      Log::error('Permanent candidate form generation or storage failed: '.$exception->getMessage(), [
          'candidate_id' => $candidateId,
          'job_id' => $jobId,
          'error' => $exception->getMessage(),
          'exception' => $exception,
      ]);

      throw new MatchMakerTransientException(self::MESSAGE_FORM_GENERATION_FAILED);
  }
  ```

---

## 3. Data Origin & Call Chain Verification

| Phương thức | Biến sử dụng trong Log | Nguồn gốc dữ liệu |
|---|---|---|
| `generateWorkFinderAgreement()` | `$candidate->id`, `$jobId`, `$exception` | Tham số `$candidate: Candidate`, biến cục bộ `$jobId` (đã validate dòng 231), biến catch `$exception: \Throwable`. |
| `submit()` | `$candidate->id`, `$jobId`, `$exception` | Tham số `$candidate: Candidate`, biến `$jobId` lấy từ request payload (dòng 315), biến catch `$exception: \Throwable`. |
| `generatePermanentCandidateForm()` | `$candidateId`, `$jobId`, `$exception` | Thuộc tính từ `$data->candidateId`, `$data->jobId` (dòng 480-481), biến catch `$exception: \Throwable`. |
| `SyncPermanentCandidateToMatchMakerJob::failed()` | `$this->data->candidateId`, `$this->data->jobId`, `$exception` | DTO `$this->data: PermanentCandidateSyncData`, tham số `$exception: Throwable`. |

Tất cả các biến đều được xác minh tồn tại trong phạm vi cục bộ tại thời điểm gọi log, không phụ thuộc vào giá trị giả định.

---

## 4. Test Impact Review & Verification Plan

### 4.1. Rà soát test hiện có
- `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php`:
  - `testPermanentIntakeQueuesSnapshotWithoutUpdatingPermanentFlag`: Có `Log::shouldReceive('error')->once();`. Cần cập nhật để assert rõ ràng context chứa `error` và `exception`.
- `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`:
  - `setUp()` định nghĩa `Log::shouldReceive('error')->zeroOrMoreTimes();` và `Log::shouldReceive('critical')->zeroOrMoreTimes();` -> Tiếp tục PASS.
- `tests/Feature/Api/Candidate/PermanentCandidateFormTest.php`:
  - `testMetadataWriteFailureDeletesUploadedFormAndRemainsRetryable`: Mock DB failure và assert `MatchMakerTransientException` -> Tiếp tục PASS vì exception message không đổi.

### 4.2. Kế hoạch kiểm thử tự động
1. Chạy Unit Test:
   ```bash
   ./vendor/bin/phpunit tests/Unit/Services/PermanentCandidateIntakeServiceTest.php
   ```
2. Chạy Feature Test liên quan đến GAP-691:
   ```bash
   ./vendor/bin/phpunit tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php
   ./vendor/bin/phpunit tests/Feature/Api/Candidate/PermanentCandidateFormTest.php
   ./vendor/bin/phpunit tests/Unit/Services/MatchMakerPermanentSyncTest.php
   ```
3. Chạy toàn bộ test suite để đảm bảo không có regression:
   ```bash
   ./vendor/bin/phpunit
   ```

---

## 5. Quy tắc thực thi (Workflow Compliance)
- Tuân thủ quy tắc **Minimal Git Diff**: Chỉ sửa chính xác các dòng trong khối catch/failed, không reformat các phương thức xung quanh.
- **DỪNG LẠI SAU KHI LẬP PLAN**: Đợi user duyệt bản kế hoạch trước khi tiến hành code.
