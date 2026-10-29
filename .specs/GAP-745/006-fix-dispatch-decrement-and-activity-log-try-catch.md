# SPEC: GAP-745 — Fix Batch Collision (RunToken), Dispatch Decrement, and ActivityLog Exception Handling

- **Date:** 2026-10-29
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

### Issue 1 `[Medium]` — Batch collision on `pending_count` when campaign is resumed
- **Location:** [`app/Jobs/SendSingleCampaignEmailJob.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Jobs/SendSingleCampaignEmailJob.php) & [`app/Services/SmsService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/SmsService.php)
- **Root Cause:**
  Khi `pending_count` chỉ được scope theo `campaign_id` (`sms_campaign:{$campaignId}:pending_count`), nếu một campaign được resume và gửi lại trong khi các job của đợt gửi trước vẫn đang trong hàng đợi hoặc đang retry (backoff lên tới 900s), đợt gửi mới sẽ ghi đè `Cache::put()`. Sau đó, các job đến muộn từ đợt cũ sẽ gọi `decrementPending()` làm giảm trừ nhầm bộ đếm của đợt mới, khiến `email_sent_at` bị đánh dấu sớm trước khi tất cả email đợt mới thực sự được gửi xong, hoặc bộ đếm bị âm/bất đồng bộ.
- **Fix:**
  Đưa lại `$runToken` (sinh bằng `(string) Str::uuid()`) vào key `sms_campaign:{$campaignId}:{$runToken}:pending_count` và truyền vào `SendSingleCampaignEmailJob`. Các job đợt cũ chỉ tác động vào key của đợt cũ, hoàn toàn độc lập với đợt gửi mới.

---

### Issue 2 `[Medium]` — Missing counter decrement on dispatch failure in `SmsService`
- **Location:** [`app/Services/SmsService.php:533-540`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/SmsService.php#L533-L540)
- **Root Cause:**
  Khi `pending_count` được khởi tạo, nếu `SendSingleCampaignEmailJob::dispatch(...)` bị lỗi kết nối hàng đợi (Redis down/timeout ở môi trường Async), block `catch` chỉ log mà không decrement bù, khiến `pending_count` không bao giờ về `0` và `email_sent_at` bị kẹt mãi mãi.
- **Fix:**
  Trong block `catch (\Throwable $e)` của `dispatchCampaignEmails()`, kiểm tra `if (config('queue.default') !== 'sync')` để decrement bù khi lỗi xảy ra ở môi trường async (tránh trừ đúp khi ở môi trường sync).

---

### Issue 3 `[Medium]` — Missing `try ... catch` around `ActivityLog::create` in `SendSingleCampaignEmailJob`
- **Location:** [`app/Jobs/SendSingleCampaignEmailJob.php:78-86`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Jobs/SendSingleCampaignEmailJob.php#L78-L86)
- **Root Cause:**
  Sau khi gửi email thành công, nếu ghi `ActivityLog` bị lỗi DB, exception làm crash `handle()` và worker retry job. Ở các lần retry, email bị gửi lại cho cùng ứng viên (gửi lặp 2–3 lần).
- **Fix:**
  Bọc lời gọi `$activityLogRepository->create(...)` trong `try ... catch (\Throwable $e)` kèm `Log::error(...)` ghi đầy đủ `'message' => $e->getMessage()`.

---

## 2. API Contract / API Docs Assessment

- **Status:** `N/A — no API contract/API docs change`

---

## 3. Detailed Changes

### 3.1. `app/Jobs/SendSingleCampaignEmailJob.php`
- Bổ sung `runToken` vào cache key & constructor:
  ```php
  public const CACHE_KEY_PENDING_COUNT = 'sms_campaign:%d:%s:pending_count';

  public function __construct(
      public int $campaignId,
      public string $runToken,
      public int $candidateId,
      public int $branchId,
      public int $userId,
      public array $from,
      public array $to,
      public string $title,
      public string $content,
      public ?array $preloadedBranchInfo = null
  ) {}

  public static function getPendingCountCacheKey(int $campaignId, string $runToken): string
  {
      return sprintf(self::CACHE_KEY_PENDING_COUNT, $campaignId, $runToken);
  }
  ```
- Bọc `ActivityLog::create` trong `try ... catch (\Throwable $e)`:
  ```php
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
- Cập nhật `decrementPending(int $campaignId, string $runToken, SmsCampaignRepositoryInterface $smsCampaignRepository)`.

### 3.2. `app/Services/SmsService.php`
- Trong `dispatchCampaignEmails()`:
  - Sinh `$runToken = (string) Str::uuid();`.
  - Khởi tạo `Cache::put(SendSingleCampaignEmailJob::getPendingCountCacheKey($campaign->id, $runToken), $validCandidates->count(), SendSingleCampaignEmailJob::CACHE_TTL_SECONDS);`.
  - Dispatch job truyền `$runToken`.
  - Trong block `catch (\Throwable $e)`:
    ```php
    } catch (\Throwable $e) {
        Log::error('SmsService: Failed to dispatch child email job', [
            'campaign_id' => $campaign->id,
            'candidate_id' => $candidate->id,
            'exception' => $e::class,
            'message' => $e->getMessage(),
        ]);

        if (config('queue.default') !== 'sync') {
            SendSingleCampaignEmailJob::decrementPending(
                $campaign->id,
                $runToken,
                $this->smsCampaignRepository
            );
        }
    }
    ```

### 3.3. `tests/Feature/Api/Consultant/SmsCampaignTest.php`
- Cập nhật các test case truyền `$runToken` vào `SendSingleCampaignEmailJob`.
- Bổ sung test kiểm tra `ActivityLog` throw exception vẫn được bọc an toàn và hoàn tất job.

---

## 4. Verification Plan
- Chạy: `./vendor/bin/phpunit tests/Feature/Api/Consultant/SmsCampaignTest.php`
