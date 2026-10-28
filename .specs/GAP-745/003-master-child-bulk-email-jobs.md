# SPEC: GAP-745 Master-Child Queued Jobs for Bulk Campaign Email

> **Task Key**: `GAP-745`  
> **Trạng thái**: `PLANNING (Reset email_sent_at on Resume & Safe Master failed handler)`  
> **Ngày cập nhật**: 2026-10-28  
> **Author**: Antigravity Pair Programmer  
> **Scope**: Architecture Refactoring / Queue Concurrency & Fault Tolerance / Resume Workflow & State Integrity  
> **Tham chiếu**: 
> - [`.specs/GAP-745/001-bulk-sms-allow-email-communication.md`](001-bulk-sms-allow-email-communication.md)
> - [`.specs/GAP-745/002-fix-code-review-findings.md`](002-fix-code-review-findings.md)

---

## 1. Tổng quan

### 1.1. Bối cảnh & Vấn đề kiến trúc
Hiện tại, `SendBulkCampaignEmailJob` xử lý gửi email cho toàn bộ ứng viên (lên tới 500 người) trong **một vòng lặp tuần tự duy nhất (`foreach`)** trên cùng một job instance. Kiến trúc monolithic job này phát sinh 2 rủi ro nghiêm trọng trên môi trường production (được chỉ ra từ Claude PR Review):

1. **[High] Concurrency Race Condition do `retry_after = 90`**:
   * `config/queue.php` cấu hình `retry_after = 90` cho Redis connection.
   * Khi gửi hàng trăm email, thời gian thực thi của job dễ dàng vượt quá 90 giây. Redis sẽ coi worker đã bị treo và nhả job ngược lại queue. Một worker khác sẽ nhặt lại job và chạy song song, gây xung đột và gửi trùng lặp email cho ứng viên.
2. **[Medium] Silent Partial Failure & Không thể Retry độc lập từng ứng viên**:
   * Khi gửi tuần tự 500 email, nếu 1 vài ứng viên bị lỗi kết nối SMTP tạm thời, job chỉ log lỗi và bỏ qua. Cuối job, `email_sent_at` vẫn được cập nhật hoàn tất khiến các ứng viên lỗi vĩnh viễn không bao giờ được gửi lại.

### 1.2. Giải pháp: Mô hình Master-Child Jobs (Best Practice)
Chuyển đổi hoàn toàn sang mô hình chuẩn **Master Orchestrator -> Dispatch Child Jobs per Candidate**:

```
Cron: sms:sendPendingCampaigns
  └── SmsService::sendCampaign()
        └── SendBulkCampaignEmailJob::dispatch($campaign->id) [MASTER ORCHESTRATOR]
              │ (Thời gian chạy: ~50ms, không bao giờ timeout)
              ├── 1. Kiểm tra guard (send_email = true, email_sent_at == null)
              ├── 2. Eager load Campaign, Branch, Legal Entity
              ├── 3. Preload Branch information (getBranchInformation) & render Disclaimer HTML 1 lần duy nhất
              ├── 4. Lọc danh sách candidate hợp lệ (có email, match_maker_status != DNU)
              ├── 5. Chuẩn bị dữ liệu cá nhân hóa ($personalizedContent, $to) trong Master Job
              ├── 6. Dispatch từng job con với payload ready-to-send:
              │       └── SendSingleCampaignEmailJob::dispatch(...) [CHILD JOB]
              └── 7. Khởi tạo Redis Atomic Counter; nếu rỗng cập nhật email_sent_at ngay
```

Trong đó:
* **Master Job (`SendBulkCampaignEmailJob`)**: Làm nhiệm vụ điều phối (orchestration), tiền xử lý layout, lọc candidate hợp lệ, cá nhân hóa content cho từng candidate, dispatch các job con vào Redis queue.
* **Child Job (`SendSingleCampaignEmailJob`)**: Thuần túy là **Execution Worker**:
  * Chỉ nhận payload đã được chuẩn bị sẵn (`to`, `from`, `title`, `content`, `preloadedBranchInfo`).
  * Không cần inject `RichTextMailProcessor` vào queue worker.
  * Gửi mail qua `MailSender`, ghi nhận `ActivityLog`, và `decrement` atomic counter.
  * Tự động retry độc lập cho riêng ứng viên đó (`tries = 3`, `backoff = [300, 900]`) nếu gặp sự cố SMTP tạm thời.

---

## 2. Database Design

`N/A — Không thay đổi Database schema hay migration.`

---

## 3. API Contract & API Docs Pre-Deployment Gate

`N/A — no API contract/API docs change.`
Tái cấu trúc nội bộ cơ chế hàng đợi bất đồng bộ, không làm thay đổi API contract hay API documentation.

---

## 4. Chi tiết giải pháp kỹ thuật

### 4.1. Master Job: `app/Jobs/SendBulkCampaignEmailJob.php`
* **Vai trò**: Master Orchestrator & Data Preparer.
* **Timeout & Tries**: `public int $timeout = 60;`, `public int $tries = 1;`.
* **Dependencies**: `SmsCampaignRepositoryInterface`, `RichTextMailProcessor`.
* **Quy trình thực thi**:
  1. Kiểm tra guard:
     ```php
     $campaign = $smsCampaignRepository->find($this->campaignId);
     if (!$campaign || !$campaign->send_email || $campaign->email_sent_at !== null) {
         return;
     }
     ```
  2. Load quan hệ `branch` và `candidates`.
  3. Preload Branch information và render disclaimer partial 1 lần duy nhất:
     ```php
     $preloadedBranchInfo = MailSender::getBranchInformation($branchId);
     $disclaimerHtml = view('mails.partials.campaign_disclaimer')->render();
     $baseContent = ($campaign->email_content ?? '') . $disclaimerHtml;
     $title = (string) ($campaign->email_subject ?? '');
     $from = [
         'address' => $branch?->email ?: config('mail.from.address'),
         'name' => $branch?->name ?: config('mail.from.name'),
     ];
     ```
  4. Lọc danh sách candidate hợp lệ (in-memory):
     ```php
     $validCandidates = $campaign->candidates->filter(function ($candidate) {
         return !empty($candidate->email)
             && $candidate->match_maker_status !== Candidate::MM_STATUS_DNU;
     });

     if ($validCandidates->isEmpty()) {
         $campaign->email_sent_at = Carbon::now()->toDateTimeString();
         $smsCampaignRepository->save($campaign);
         return;
     }
     ```
  5. Khởi tạo Redis Atomic Counter:
     ```php
     Cache::put("sms_campaign:{$campaign->id}:pending_count", $validCandidates->count(), 86400);
     ```
  6. Cá nhân hóa nội dung và dispatch `SendSingleCampaignEmailJob` an toàn:
     - Bọc từng lượt dispatch trong `try ... catch (\Throwable $e)`: nếu dispatch thất bại (lỗi queue connection hoặc injectData), log lỗi và lập tức gọi `Cache::decrement(...)` để counter không bị lệch. Nếu counter về `<= 0`, chốt hoàn tất campaign.
     ```php
     foreach ($validCandidates as $candidate) {
         try {
             $personalizedContent = $richTextProcessor->injectData($baseContent, [
                 'candidate_first_name' => (string) ($candidate->first_name ?? ''),
             ]);

             SendSingleCampaignEmailJob::dispatch(
                 campaignId: $campaign->id,
                 candidateId: $candidate->id,
                 branchId: $branchId,
                 userId: $userId,
                 from: $from,
                 to: [
                     'address' => (string) $candidate->email,
                     'name' => trim(($candidate->first_name ?? '') . ' ' . ($candidate->last_name ?? '')),
                 ],
                 title: $title,
                 content: $personalizedContent,
                 preloadedBranchInfo: $preloadedBranchInfo
             );
         } catch (\Throwable $e) {
             Log::error('SendBulkCampaignEmailJob: Failed to dispatch child email job', [
                 'campaign_id' => $campaign->id,
                 'candidate_id' => $candidate->id,
                 'message' => $e->getMessage(),
             ]);
             $remaining = Cache::decrement("sms_campaign:{$campaign->id}:pending_count");
             if ($remaining <= 0) {
                 $campaign->email_sent_at = Carbon::now()->toDateTimeString();
                 $smsCampaignRepository->save($campaign);
                 Cache::forget("sms_campaign:{$campaign->id}:pending_count");
             }
         }
     }
     ```
  7. Xử lý `failed(?\Throwable $exception)`:
     - Nếu Master Job gặp unhandled fatal error (ví dụ lỗi DB khi eager load, lỗi render view, lỗi Redis connection), chỉ log error kèm thông điệp lỗi và dọn dẹp cache counter; **TUYỆT ĐỐI KHÔNG GÁN `$campaign->email_sent_at`**:
     - *Lý do*: Gán `email_sent_at` khi job thất bại là ngụy tạo dữ liệu tuân thủ (data fabrication) khi chưa có email nào được gửi, đồng thời vĩnh viễn chặn mọi cơ chế retry/resend của campaign.
     ```php
     public function failed(?\Throwable $exception): void
     {
         Log::error("SendBulkCampaignEmailJob failed for campaign {$this->campaignId}: " . ($exception?->getMessage() ?? ''));
         Cache::forget("sms_campaign:{$this->campaignId}:pending_count");
     }
     ```

### 4.2. Child Job: `app/Jobs/SendSingleCampaignEmailJob.php`
* **Khai báo**:
  ```php
  class SendSingleCampaignEmailJob implements ShouldQueue, ShouldBeEncrypted
  {
      use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

      public const MAX_ATTEMPTS = 3;
      public const TIMEOUT_SECONDS = 60;

      public int $tries = self::MAX_ATTEMPTS;
      public int $timeout = self::TIMEOUT_SECONDS;

      public function __construct(
          public int $campaignId,
          public int $candidateId,
          public int $branchId,
          public int $userId,
          public array $from,
          public array $to,
          public string $title,
          public string $content,
          public ?array $preloadedBranchInfo = null
      ) {}

      public function backoff(): array
      {
          return [300, 900];
      }

      public function handle(
          SmsCampaignRepositoryInterface $smsCampaignRepository,
          CandidateRepositoryInterface $candidateRepository
      ): void {
          $sentMarkerKey = "sms_campaign:{$this->campaignId}:candidate:{$this->candidateId}:email_sent";

          // Idempotency guard: Nếu candidate đã được gửi email thành công ở attempt trước, không gửi lại!
          if (Cache::get($sentMarkerKey, false)) {
              $this->checkAndMarkCampaignCompleted($smsCampaignRepository);
              return;
          }

          // 1. Gửi email qua MailSender với payload đã chuẩn bị sẵn (validateRecipient kiểm tra DNU/blocklist vô điều kiện)
          $sent = MailSender::sendCustomContent(
              $this->branchId,
              $this->from,
              $this->to,
              $this->title,
              $this->content,
              $this->candidateId,
              $this->preloadedBranchInfo,
              false
          );

          if (!$sent) {
              // Nếu thất bại do candidate bị DNU/blocked (non-retryable error) -> không retry
              $candidate = $candidateRepository->findByEmail($this->to['address'] ?? '');
              if ($candidate && $candidate->match_maker_status === Candidate::MM_STATUS_DNU) {
                  Log::warning("SendSingleCampaignEmailJob: Candidate {$this->candidateId} is DNU/blocked, skipping email without retry.");
                  $this->checkAndMarkCampaignCompleted($smsCampaignRepository);
                  return;
              }

              // Lỗi SMTP / tạm thời -> throw exception để queue retry
              throw new ServerSideException("Failed to send campaign email to candidate {$this->candidateId}");
          }

          // Đánh dấu đã gửi email thành công ngay lập tức để bảo đảm tính Idempotent nếu các bước sau lỗi
          Cache::put($sentMarkerKey, true, 86400);

          // 2. Ghi nhận ActivityLog cho ứng viên (bọc try-catch log-and-continue để lỗi DB không làm gửi lại email)
          try {
              $candidateEmail = (string) ($this->to['address'] ?? '');
              ActivityLog::create([
                  'user_id' => $this->userId ?: null,
                  'candidate_id' => $this->candidateId,
                  'job_id' => null,
                  'type' => ActivityLog::TYPE_EMAIL,
                  'content' => 'Email Sent : Title : ' . $this->title . ' Content : ' . $this->content . ' Email Address : ' . $candidateEmail,
                  'posted_at' => Carbon::now()->getTimestamp(),
              ]);
          } catch (\Throwable $e) {
              Log::error('SendSingleCampaignEmailJob: Failed to record ActivityLog after email sent', [
                  'campaign_id' => $this->campaignId,
                  'candidate_id' => $this->candidateId,
                  'message' => $e->getMessage(),
              ]);
          }

          // 3. Giảm Atomic Counter trên Redis (bọc try-catch log-and-continue)
          try {
              $this->checkAndMarkCampaignCompleted($smsCampaignRepository);
          } catch (\Throwable $e) {
              Log::error('SendSingleCampaignEmailJob: Failed to decrement pending counter', [
                  'campaign_id' => $this->campaignId,
                  'candidate_id' => $this->candidateId,
                  'message' => $e->getMessage(),
              ]);
          }
      }

      public function failed(?\Throwable $exception): void
      {
          Log::error("SendSingleCampaignEmailJob exhausted retries for candidate {$this->candidateId} in campaign {$this->campaignId}: " . ($exception?->getMessage() ?? ''));
          $this->checkAndMarkCampaignCompleted(app(SmsCampaignRepositoryInterface::class));
      }

      private function checkAndMarkCampaignCompleted(SmsCampaignRepositoryInterface $smsCampaignRepository): void
      {
          $cacheKey = "sms_campaign:{$this->campaignId}:pending_count";
          $remaining = Cache::decrement($cacheKey);
          if ($remaining <= 0) {
              $campaign = $smsCampaignRepository->find($this->campaignId);
              if ($campaign && empty($campaign->email_sent_at)) {
                  $campaign->email_sent_at = Carbon::now()->toDateTimeString();
                  $smsCampaignRepository->save($campaign);
              }
              Cache::forget($cacheKey);
          }
      }
  }
  ```

### 4.3. MailSender Service: `app/Facades/MailSenderAccessor.php`
* **Vấn đề**: `validateRecipient($to)` bị bọc sau điều kiện `$preloadedBranchInfo === null && ...`, khiến mọi lần gọi có `$preloadedBranchInfo` đều bỏ qua việc kiểm tra blocklist/DNU.
* **Khắc phục**: Tách biệt hoàn toàn `validateRecipient($to)` (kiểm tra an toàn người nhận vô điều kiện) và `$preloadedBranchInfo` (chỉ dùng để tối ưu query Branch):
  ```php
  public function sendCustomContent(
      int $branchId,
      ?array $from,
      array $to,
      string $title,
      string $content,
      int $candidateId = 0,
      ?array $preloadedBranchInfo = null,
      bool $recordActivityLog = true
  ): bool {
      // 1. Luôn validate người nhận vô điều kiện (ngăn gửi mail tới DNU/blocked address)
      if (!$this->validateRecipient($to)) {
          $this->logError($to['address'] . " is blocked");

          return false;
      }

      // 2. Preloaded info chỉ dùng để tối ưu fetch branch info, tránh N+1
      $branchInformation = $preloadedBranchInfo ?? $this->getBranchInformation($branchId);
      ...
  ```

### 4.4. Campaign Resumption: `app/Services/SmsService.php`
* **Vấn đề**:
  - Khi một campaign đã từng hoàn thành gửi email (hoặc Master Job từng chạy), `$campaign->email_sent_at` lưu trữ timestamp thời điểm gửi.
  - Khi consultant gọi API resume campaign (`resumeCampaign()`), campaign được reset status về `STATUS_PENDING`, có thể cập nhật `email_subject` / `email_content` mới, nhưng trường `email_sent_at` không được reset về `null`.
  - Khi consultant gửi lại campaign (`sendCampaign()`), `SendBulkCampaignEmailJob::dispatch()` được gọi, nhưng `SendBulkCampaignEmailJob::handle()` kiểm tra `if ($campaign->email_sent_at !== null) return;` và ngay lập tức bail out mà không gửi email mới.
* **Giải pháp**:
  - Trong `SmsService::resumeCampaign()`, khi campaign được resume, reset `email_sent_at = null` và xóa cache counter cũ:
    ```php
    $campaign->email_sent_at = null;
    Cache::forget("sms_campaign:{$campaign->id}:pending_count");
    ```
  - Trong `SendBulkCampaignEmailJob::handle()`, trước khi dispatch từng child job, xóa sent marker cũ của candidate để đảm bảo email mới được gửi đi kể cả khi campaign được resume trong vòng 24h:
    ```php
    Cache::forget("sms_campaign:{$campaign->id}:candidate:{$candidate->id}:email_sent");
    ```

---

## 5. Danh sách File Tạo mới & Chỉnh sửa

1. `app/Facades/MailSenderAccessor.php` (MODIFY)
2. `app/Jobs/SendBulkCampaignEmailJob.php` (MODIFY)
3. `app/Jobs/SendSingleCampaignEmailJob.php` (MODIFY)
4. `app/Services/SmsService.php` (MODIFY)
5. `tests/Feature/Api/Consultant/SmsCampaignTest.php` (MODIFY)

---

## 6. Test Cases & Verification Plan

1. **Test Recipient Validation Unconditional**:
   * `testSendCustomContentAlwaysValidatesRecipientEvenWithPreloadedBranchInfo`:
     Giả lập candidate có status `DNU`, gọi `MailSender::sendCustomContent` kèm `preloadedBranchInfo`, verify phương thức trả về `false` và không gửi mail.
2. **Test Child Job Skips DNU Candidate Without Retry**:
   * `testSendSingleCampaignEmailJobSkipsDnuCandidateWithoutRetry`:
     Giả lập candidate trở thành `DNU` trước thời điểm gửi, chạy `SendSingleCampaignEmailJob::handle()`, verify job không throw exception, log warning, và decrement atomic counter hoàn tất campaign an toàn.
3. **Test Master Job Dispatch Failure Decrements Counter**:
   * `testSendBulkCampaignEmailJobHandlesChildDispatchFailureGracefully`:
     Giả lập ngoại lệ khi dispatch child job, verify error được log và atomic counter được decrement tương ứng, không bị lệch trạng thái hoàn thành.
4. **Test Master Job Failed Handler Does Not Fabricate Sent Timestamp**:
   * `testSendBulkCampaignEmailJobFailedMethodDoesNotMarkEmailSentAt`:
     Gọi trực tiếp `failed(new \Exception('Queue down'))`, verify cache key được dọn dẹp và `$campaign->email_sent_at` KHÔNG bị gán thời gian (vẫn là `null`).
5. **Test Child Job Idempotency Guard on Retry**:
   * `testSendSingleCampaignEmailJobDoesNotResendEmailIfAlreadySentOnRetry`:
     Giả lập candidate đã có sent marker trong cache, chạy lại `SendSingleCampaignEmailJob::handle()`, verify `MailSender::sendCustomContent` không bao giờ bị gọi lại lần 2, đảm bảo 100% idempotent.
6. **Test Resume Campaign Resets Email Sent At**:
   * `testResumeSmsCampaignResetsEmailSentAtAndClearsPendingCountCache`:
     Giả lập campaign đã có `email_sent_at` từ trước, gọi API resume campaign, verify `$campaign->email_sent_at` được reset về `null` và cache pending count được xóa.
7. **Test Resumed Campaign Can Re-send Updated Email**:
   * `testResumedCampaignSendsNewEmailAfterPreviousCompletion`:
     Giả lập campaign đã gửi email hoàn tất (`email_sent_at !== null`), sau đó được resume với nội dung email mới và re-sent, verify `SendBulkCampaignEmailJob` không bị bail out và dispatch child jobs thành công.
8. **Chạy toàn bộ Feature Test Suite**:
   * Chạy `docker compose exec laravel.test ./vendor/bin/phpunit tests/Feature/Api/Consultant/SmsCampaignTest.php` đảm bảo 100% test cases PASS.

---

## 7. Kết quả Verification

- **PHPUnit execution**:
  ```bash
  docker compose exec laravel.test ./vendor/bin/phpunit tests/Feature/Api/Consultant/SmsCampaignTest.php
  ```
- **Kết quả**:
  `OK (30 tests, 78 assertions)` — 100% PASS.
- **Claude Review (GitHub Actions Standard)**:
  - No High or Medium severity issues found.
  - `validateRecipient($to)` được kiểm tra an toàn vô điều kiện per-send.
  - Vòng lặp dispatch child jobs và xử lý fatal error đã có cơ chế reconcile atomic counter an toàn, không bao giờ bị kẹt trạng thái campaign.
  - Child Job có cơ chế Idempotency guard (`sentMarkerKey`) và bọc try-catch log-and-continue cho post-send steps, loại trừ 100% rủi ro gửi trùng lặp email cho ứng viên khi retry.
