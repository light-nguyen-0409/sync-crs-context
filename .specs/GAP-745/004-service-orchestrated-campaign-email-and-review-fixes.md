# SPEC: GAP-745 — Service-Orchestrated Campaign Email Dispatch & Code Review Fixes

- **Date:** 2026-04-20
- **Task:** GAP-745 — Bulk SMS: Allow Email Communication Alongside SMS
- **Status:** Completed (Verified with 34/34 passing tests)
- **Related Specs:**
  - [`.specs/GAP-745/001-bulk-sms-allow-email-communication.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/001-bulk-sms-allow-email-communication.md)
  - [`.specs/GAP-745/002-fix-code-review-findings.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/002-fix-code-review-findings.md)
  - [`.specs/GAP-745/003-master-child-bulk-email-jobs.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/003-master-child-bulk-email-jobs.md)

---

## 1. Objective & Scope

This specification addresses the architectural simplification and code review findings for **GAP-745**:

1. **Remove Master Job (`SendBulkCampaignEmailJob`) & Move Orchestration to `SmsService`**:
   - Eliminate `app/Jobs/SendBulkCampaignEmailJob.php` so we do not maintain a nested Master Job -> Child Job queue hop.
   - Orchestrate candidate filtering, placeholder personalization (`{candidate_first_name}`, `{candidate_full_name}`), disclaimer rendering, Redis tracking counter initialization, and `SendSingleCampaignEmailJob` dispatch directly inside `SmsService::sendCampaign()` via a private helper `dispatchCampaignEmails()`.
   - Reuse the already-loaded `$candidates = $campaign->candidates` collection in `SmsService::sendCampaign()` to avoid duplicate DB queries.
2. **Fix Finding 1 (`[High]` — HTML Sanitizer Mismatch)**:
   - Inject `RichTextMailProcessor` into `SmsService` and use `$this->richTextProcessor->sanitize(...)` instead of `HtmlUtility::purify(...)` in both `SmsService::createCandidateCampaign()` and `SmsService::resumeCampaign()`.
   - This preserves rich-text inline CSS styles (`style="..."`), text alignment, images (`<img>`), horizontal rules (`<hr>`), and restores URL-encoded placeholders (`%7Bcandidate_first_name%7D` -> `{candidate_first_name}`) inside `<a href="...">` tags.
3. **Fix Comment 1 (`[High]` — `resumeCampaign()` Does Not Reset `email_sent_at`)**:
   - In `SmsService::resumeCampaign()`, reset `$campaign->email_sent_at = null` whenever a campaign is resumed so subsequent execution of `SmsService::sendCampaign()` does not skip email dispatch.
   - In `SmsService::dispatchCampaignEmails()`, clear any stale per-candidate Redis markers (`email_sent`, `completed`) and reset `pending_count` / `sent_count` before dispatching child jobs for the campaign.
4. **Fix Finding 2 (`[High]` — Double `Cache::decrement` & Unguarded `ActivityLog::create`)**:
   - Inject `ActivityLogRepositoryInterface` into `SendSingleCampaignEmailJob::handle()` (replacing direct `ActivityLog::create()` model call) and wrap activity log creation in a `try ... catch (\Throwable $e)` block with structured `Log::error` (including `'message' => $e->getMessage()`), ensuring activity log failure after a sent email never triggers job failure/retry or duplicate emails.
   - Guard per-candidate completion decrement with `Cache::add($completedMarkerKey, true, self::CACHE_TTL_SECONDS)` so each candidate decrements `pending_count` **at most once** across `handle()`, queue retries, `failed()`, and dispatch-failure `catch` blocks (including under `QUEUE_CONNECTION=sync`).
5. **Fix Finding 3 (`[Medium]` — False-Positive `email_sent_at` When All Emails Fail)**:
   - Track `sms_campaign:{$campaignId}:sent_count` in Redis whenever an email is sent (or was already marked sent).
   - Only update `$campaign->email_sent_at` when `pending_count <= 0` **AND** `sent_count > 0` (or immediately in `SmsService::dispatchCampaignEmails()` when `$validCandidates` is initially empty so there are no recipients to send to).

---

## 2. API Contract / API Docs Assessment

- **Status:** `N/A — no API contract/API docs change`
- **Reasoning:** All routes, request validation rules, response resource structures (`SmsCampaign` resource), and error contracts remain unchanged and match the already-committed documentation in `~/projects/crs-api-docs` (`a2b86d8` / `e8117dc`).

---

## 3. Detailed Design & File Changes

### 3.1. Delete `app/Jobs/SendBulkCampaignEmailJob.php`
- Remove `app/Jobs/SendBulkCampaignEmailJob.php` completely.

### 3.2. Update `app/Models/SmsCampaign.php`
- Add view constant for the campaign email disclaimer partial (no magic strings):
  ```php
  public const DISCLAIMER_VIEW = 'mails.partials.campaign_disclaimer';
  ```

### 3.3. Update `app/Jobs/SendSingleCampaignEmailJob.php`
- **Constants** (no magic numbers/strings):
  ```php
  public const CACHE_TTL_SECONDS = 86400;
  public const CACHE_KEY_PENDING_COUNT = 'sms_campaign:%d:pending_count';
  public const CACHE_KEY_SENT_COUNT = 'sms_campaign:%d:sent_count';
  public const CACHE_KEY_CANDIDATE_SENT = 'sms_campaign:%d:candidate:%d:email_sent';
  public const CACHE_KEY_CANDIDATE_COMPLETED = 'sms_campaign:%d:candidate:%d:completed';
  ```
- **Helper Methods for Cache Keys**:
  - `public static function getPendingCountCacheKey(int $campaignId): string`
  - `public static function getSentCountCacheKey(int $campaignId): string`
  - `public static function getCandidateSentCacheKey(int $campaignId, int $candidateId): string`
  - `public static function getCandidateCompletedCacheKey(int $campaignId, int $candidateId): string`
- **`handle(ActivityLogRepositoryInterface $activityLogRepository): void`**:
  1. Check idempotency marker `$sentMarkerKey = self::getCandidateSentCacheKey($this->campaignId, $this->candidateId)`. If `Cache::has($sentMarkerKey)` is true, call `self::recordCandidateCompletion($this->campaignId, $this->candidateId, $smsCampaignRepository)` and return.
  2. Call `MailSender::sendCustomContent($this->finalHtml, [$this->recipientEmail], $this->subject, $this->senderEmail, $this->senderName)`.
  3. On success:
     - Set `Cache::put($sentMarkerKey, true, self::CACHE_TTL_SECONDS)`.
     - Increment `Cache::increment(self::getSentCountCacheKey($this->campaignId))`.
     - Wrap `$activityLogRepository->create([...])` inside `try ... catch (\Throwable $e)` and log any exception with `Log::error('SendSingleCampaignEmailJob activity log failed', ['campaign_id' => $this->campaignId, 'candidate_id' => $this->candidateId, 'exception' => $e::class, 'message' => $e->getMessage()])`.
     - Call `self::recordCandidateCompletion($this->campaignId, $this->candidateId, $smsCampaignRepository)`.
  4. On `ServerSideException $e`:
     - Log error with `campaign_id`, `candidate_id`, `exception`, and `'message' => $e->getMessage()`, then rethrow `$e` so the queue worker can retry up to `$tries = 3`.
- **`failed(\Throwable $exception): void`**:
  - Log permanent failure with `campaign_id`, `candidate_id`, `exception`, and `'message' => $exception->getMessage()`.
  - Resolve `SmsCampaignRepositoryInterface` and call `self::recordCandidateCompletion($this->campaignId, $this->candidateId, $smsCampaignRepository)`.
- **Idempotent Completion & `email_sent_at` Guard (`recordCandidateCompletion`)**:
  ```php
  public static function recordCandidateCompletion(
      int $campaignId,
      int $candidateId,
      SmsCampaignRepositoryInterface $smsCampaignRepository
  ): void {
      $completedKey = self::getCandidateCompletedCacheKey($campaignId, $candidateId);
      if (!Cache::add($completedKey, true, self::CACHE_TTL_SECONDS)) {
          return;
      }

      $pendingKey = self::getPendingCountCacheKey($campaignId);
      $remaining = Cache::decrement($pendingKey);

      if ($remaining <= 0) {
          $sentCount = (int) Cache::get(self::getSentCountCacheKey($campaignId), 0);
          if ($sentCount > 0) {
              try {
                  /** @var SmsCampaign|null $campaign */
                  $campaign = $smsCampaignRepository->find($campaignId);
                  if ($campaign && $campaign->email_sent_at === null) {
                      $campaign->email_sent_at = Carbon::now()->toDateTimeString();
                      $smsCampaignRepository->save($campaign);
                  }
              } catch (\Throwable $e) {
                  Log::error('SendSingleCampaignEmailJob completion update failed', [
                      'campaign_id' => $campaignId,
                      'exception' => $e::class,
                      'message' => $e->getMessage(),
                  ]);
              }
          }
          Cache::forget($pendingKey);
          Cache::forget(self::getSentCountCacheKey($campaignId));
      }
  }
  ```

### 3.4. Update `app/Services/SmsService.php`
- **Constructor Injection**:
  - Inject `RichTextMailProcessor $richTextProcessor` into `SmsService::__construct(...)`.
- **`createCandidateCampaign(array $message, array $candidateIds)`**:
  - Replace `HtmlUtility::purify($message['email_content'])` with `$this->richTextProcessor->sanitize($message['email_content'])`.
- **`resumeCampaign(int $campaignId, array $data = [])`**:
  - Reset `$campaign->email_sent_at = null;` when resuming the campaign.
  - When `$campaign->send_email` is true and `!empty($data['email_content'])`, sanitize with `$this->richTextProcessor->sanitize($data['email_content'])`.
- **`sendCampaign(SmsCampaign $campaign)`**:
  - After saving `$savedCampaign = $this->smsCampaignRepository->save($campaign);`, check:
    ```php
    if ($smsResult->isSuccess() && $savedCampaign->send_email && empty($savedCampaign->email_sent_at)) {
        try {
            $this->dispatchCampaignEmails($savedCampaign, $candidates);
        } catch (\Throwable $e) {
            Log::error('SmsService::dispatchCampaignEmails failed', [
                'campaign_id' => $savedCampaign->id,
                'exception' => $e::class,
                'message' => $e->getMessage(),
            ]);
        }
    }
    ```
- **`private function dispatchCampaignEmails(SmsCampaign $campaign, Collection $candidates): void`**:
  1. Filter `$validCandidates` from `$candidates`: non-DNU (`!$candidate->dnu`) and non-empty `trim((string) $candidate->email)`.
  2. If `$validCandidates->isEmpty()`:
     - Set `$campaign->email_sent_at = Carbon::now()->toDateTimeString();` and save via `$this->smsCampaignRepository->save($campaign)` so campaigns with 0 valid email recipients do not remain in a perpetually pending email state.
     - Return early.
  3. Resolve sender info once before the loop:
     - Eager-load `consultant.branch` if not loaded (`$campaign->loadMissing(['consultant.branch'])`).
     - `$branch = $campaign->consultant?->branch;`
     - `$senderEmail = $branch?->email ?: config('mail.from.address');`
     - `$senderName = $branch?->title ?: config('mail.from.name');`
     - Render disclaimer once: `$disclaimerHtml = view(SmsCampaign::DISCLAIMER_VIEW)->render();`
  4. Initialize Redis state for `$campaign->id`:
     - `Cache::put(SendSingleCampaignEmailJob::getPendingCountCacheKey($campaign->id), $validCandidates->count(), SendSingleCampaignEmailJob::CACHE_TTL_SECONDS);`
     - `Cache::put(SendSingleCampaignEmailJob::getSentCountCacheKey($campaign->id), 0, SendSingleCampaignEmailJob::CACHE_TTL_SECONDS);`
     - For each `$candidate` in `$validCandidates`, `Cache::forget` any stale `getCandidateSentCacheKey` and `getCandidateCompletedCacheKey` markers (ensuring resumed campaigns can send emails cleanly).
  5. Loop over `$validCandidates` (no DB queries inside loop):
     - Build `$candidateData` (`candidate_first_name`, `candidate_full_name`).
     - Personalize content using `$personalizedBody = $this->richTextProcessor->injectData((string) $campaign->email_content, $candidateData);`.
     - Append `$finalHtml = $personalizedBody . $disclaimerHtml;`.
     - Dispatch `SendSingleCampaignEmailJob::dispatch(...)` inside `try ... catch (\Throwable $e)`:
       - On exception, log error (`campaign_id`, `candidate_id`, `exception`, `'message' => $e->getMessage()`) and call `SendSingleCampaignEmailJob::recordCandidateCompletion($campaign->id, (int) $candidate->id, $this->smsCampaignRepository)`.
  6. Refresh `$campaign->email_sent_at` from DB (`$updatedCampaign = $this->smsCampaignRepository->find($campaign->id)`) if completed synchronously so the returned `$savedCampaign` reflects the updated `email_sent_at` timestamp when running with `sync` queue.

---

## 4. Test Impact & Verification Plan

### Affected Test Files
- [`tests/Feature/Api/Consultant/SmsCampaignTest.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/tests/Feature/Api/Consultant/SmsCampaignTest.php)

### Planned Test Updates & Additions
1. **Update Existing Dispatch Tests**:
   - Replace references to `SendBulkCampaignEmailJob` with `SendSingleCampaignEmailJob` assertions when `SmsService::sendCampaign()` is called.
2. **Add Test for RichTextMailProcessor Sanitization (Finding 1)**:
   - Verify `createCandidateCampaign` and `resumeCampaign` preserve inline CSS styles (`style="color: red; text-align: center;"`), `<hr>`, `<img>`, and restore `{candidate_first_name}` inside `<a href="https://example.com?name={candidate_first_name}">`.
3. **Add Test for `resumeCampaign()` Resetting `email_sent_at` (Comment 1)**:
   - Verify that a campaign that already had `email_sent_at` populated has `email_sent_at` reset to `null` upon `PUT /api/v1/consultant/sms/campaign/{id}/resume`, and dispatches `SendSingleCampaignEmailJob` again when `sendCampaign()` runs.
4. **Add Test for Single-Decrement Idempotency & All-Failed `email_sent_at` Guard (Findings 2 & 3)**:
   - Verify that when `MailSender::sendCustomContent` throws `ServerSideException`, `pending_count` is decremented only once per candidate (not double-decremented across `failed()` and `catch`), and when all emails fail (`sent_count === 0`), `email_sent_at` remains `null`.
   - Verify that when `ActivityLogRepositoryInterface::create` throws an exception after `MailSender::sendCustomContent` succeeds, the exception is caught and logged, `email_sent_at` is still updated, and no duplicate email is sent.

### Verification Command
- `./vendor/bin/phpunit tests/Feature/Api/Consultant/SmsCampaignTest.php`
