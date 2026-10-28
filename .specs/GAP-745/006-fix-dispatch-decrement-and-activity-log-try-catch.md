# SPEC: GAP-745 — Fix Dispatch Decrement & ActivityLog Exception Handling

- **Date:** 2026-10-28
- **Task:** GAP-745 — Bulk SMS: Allow Email Communication Alongside SMS
- **Status:** Draft (Pending User Approval)
- **Related Specs:**
  - [`.specs/GAP-745/001-bulk-sms-allow-email-communication.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/001-bulk-sms-allow-email-communication.md)
  - [`.specs/GAP-745/002-fix-code-review-findings.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/002-fix-code-review-findings.md)
  - [`.specs/GAP-745/003-master-child-bulk-email-jobs.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/003-master-child-bulk-email-jobs.md)
  - [`.specs/GAP-745/004-service-orchestrated-campaign-email-and-review-fixes.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/004-service-orchestrated-campaign-email-and-review-fixes.md)
  - [`.specs/GAP-745/005-simplify-cache-architecture-and-run-token.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/005-simplify-cache-architecture-and-run-token.md)

---

## 1. Analysis of Review Comments

### Comment 1 `[Medium]` — Missing counter decrement on dispatch failure in `SmsService`
- **Location:** [`app/Services/SmsService.php:533-540`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/SmsService.php#L533-L540)
- **Root Cause:**
  Counter `pending_count` được khởi tạo bằng `$validCandidates->count()`. Khi loop dispatch `SendSingleCampaignEmailJob`, nếu lệnh `dispatch()` bị lỗi (do queue connection timeout hoặc driver error), block `catch (\Throwable $e)` chỉ ghi log mà không gọi `SendSingleCampaignEmailJob::decrementPending(...)`.
- **Impact:**
  Những candidate bị lỗi dispatch sẽ không bao giờ chạy, dẫn tới `pending_count` không bao giờ giảm về `0`, campaign bị kẹt vĩnh viễn ở trạng thái `email_sent_at = null` dù các candidate khác đã gửi thành công.
- **Fix:**
  Trong block `catch (\Throwable $e)` của `SmsService::dispatchCampaignEmails()`, gọi `SendSingleCampaignEmailJob::decrementPending($campaign->id, $this->smsCampaignRepository);`.

---

### Comment 2 `[Medium]` — Missing `try ... catch` around `ActivityLog::create` in `SendSingleCampaignEmailJob`
- **Location:** [`app/Jobs/SendSingleCampaignEmailJob.php:78-86`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Jobs/SendSingleCampaignEmailJob.php#L78-L86)
- **Root Cause:**
  Sau khi `MailSender::sendCustomContent(...)` đã gửi email thành công cho ứng viên ở bước 1, nếu việc ghi `ActivityLog` ở bước 2 gặp lỗi DB (transient DB error / lock), exception không được bắt sẽ làm crash `handle()`. Queue worker sẽ retry job này (tối đa 3 lần). Ở mỗi lần retry, `MailSender::sendCustomContent(...)` lại được gọi tiếp, khiến ứng viên nhận email trùng lặp 2–3 lần. Đồng thời, `decrementPending` bị bỏ qua cho tới khi hết retry.
- **Impact:**
  Gửi trùng lặp marketing email cho ứng viên do lỗi phụ ở bước ghi log.
- **Fix:**
  Bọc lời gọi `$activityLogRepository->create(...)` trong `try ... catch (\Throwable $e)` kèm `Log::error(...)` ghi đầy đủ context và `'message' => $e->getMessage()`.

---

## 2. API Contract / API Docs Assessment

- **Status:** `N/A — no API contract/API docs change`
- **Reasoning:** Sửa lỗi xử lý ngoại lệ nội bộ trong Service và Queue Job, không ảnh hưởng route hay API contract.

---

## 3. Detailed Changes

### 3.1. `app/Services/SmsService.php`
- Cập nhật catch block trong `dispatchCampaignEmails`:
  ```php
  } catch (\Throwable $e) {
      Log::error('SmsService: Failed to dispatch child email job', [
          'campaign_id' => $campaign->id,
          'candidate_id' => $candidate->id,
          'exception' => $e::class,
          'message' => $e->getMessage(),
      ]);
      SendSingleCampaignEmailJob::decrementPending(
          $campaign->id,
          $this->smsCampaignRepository
      );
  }
  ```

### 3.2. `app/Jobs/SendSingleCampaignEmailJob.php`
- Bọc `$activityLogRepository->create(...)` trong `try-catch`:
  ```php
  // 2. Record ActivityLog for this candidate (wrap in try-catch so failure does not re-trigger email send)
  $candidateEmail = (string) ($this->to['address'] ?? '');
  try {
      $activityLogRepository->create([
          'user_id' => $this->userId ?: null,
          'candidate_id' => $this->candidateId,
          'job_id' => null,
          'type' => ActivityLog::TYPE_EMAIL,
          'content' => 'Email Sent : Title : ' . $this->title . ' Content : ' . $this->content . ' Email Address : ' . $candidateEmail,
          'posted_at' => Carbon::now()->getTimestamp(),
      ]);
  } catch (\Throwable $e) {
      Log::error('SendSingleCampaignEmailJob: Failed to record ActivityLog', [
          'campaign_id' => $this->campaignId,
          'candidate_id' => $this->candidateId,
          'exception' => $e::class,
          'message' => $e->getMessage(),
      ]);
  }
  ```

### 3.3. `tests/Feature/Api/Consultant/SmsCampaignTest.php`
- Bổ sung test case kiểm chứng:
  1. `testSendSingleCampaignEmailJobCatchesActivityLogExceptionWithoutFailingJob`: Verify rằng khi `$activityLogRepository->create` throw exception, exception được log lại, job không bị fail, `decrementPending` vẫn được gọi và `$campaign->email_sent_at` vẫn được cập nhật.
  2. Test verify `dispatch` catch block gọi `decrementPending`.

---

## 4. Verification Plan
- Chạy: `./vendor/bin/phpunit tests/Feature/Api/Consultant/SmsCampaignTest.php`
- Đảm bảo 100% tests pass.
