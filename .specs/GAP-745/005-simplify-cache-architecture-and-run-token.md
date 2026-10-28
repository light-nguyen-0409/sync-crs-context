# SPEC: GAP-745 — Radically Simplified Campaign Email Architecture (No Per-Candidate Keys, No RunToken)

- **Date:** 2026-10-28
- **Task:** GAP-745 — Bulk SMS: Allow Email Communication Alongside SMS
- **Status:** Completed (Verified 28/28 tests passing)
- **Related Specs:**
  - [`.specs/GAP-745/001-bulk-sms-allow-email-communication.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/001-bulk-sms-allow-email-communication.md)
  - [`.specs/GAP-745/002-fix-code-review-findings.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/002-fix-code-review-findings.md)
  - [`.specs/GAP-745/003-master-child-bulk-email-jobs.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/003-master-child-bulk-email-jobs.md)
  - [`.specs/GAP-745/004-service-orchestrated-campaign-email-and-review-fixes.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-745/004-service-orchestrated-campaign-email-and-review-fixes.md)

---

## 1. Objective & Implemented Simplifications

1. **Bỏ validate recipient khi có `$preloadedBranchInfo` trong `MailSenderAccessor`**:
   - `MailSenderAccessor::sendCustomContent()` kiểm tra `if (empty($preloadedBranchInfo) && !$this->validateRecipient($to))`.
   - Khi có `$preloadedBranchInfo` (luồng bulk email đã được lọc trước ở Service layer), bỏ qua bước query DB `candidateRepository->findByEmail($to['address'])`.
2. **Loại bỏ toàn bộ Cache Keys per-candidate và loại bỏ luôn `runToken`**:
   - Không dùng `completedKey`, `sentKey`, `processedKey`, hay `runToken`.
   - Không còn bất kỳ vòng lặp `foreach` `Cache::forget` nào.
3. **Chỉ dùng duy nhất 1 Cache Key: `sms_campaign:{$campaignId}:pending_count`**:
   - Trong `SmsService::dispatchCampaignEmails()`:
     `Cache::put(SendSingleCampaignEmailJob::getPendingCountCacheKey($campaign->id), $validCandidates->count(), SendSingleCampaignEmailJob::CACHE_TTL_SECONDS);`
   - Mỗi child job khi hoàn tất (hoặc fail hết retries) chỉ thực hiện:
     `SendSingleCampaignEmailJob::decrementPending($this->campaignId, $smsCampaignRepository);`
   - Khi `remaining <= 0`: luôn cập nhật `$campaign->email_sent_at = Carbon::now()->toDateTimeString();` và xóa `pending_count`.
4. **Loại bỏ 2 Test Case trùng lặp / dư thừa trong `SmsCampaignTest.php`**:
   - Xóa `testSendSmsCampaignDispatchesSingleEmailJobWhenSendEmailIsTrue` (đã được bao quát bởi `testSendSmsCampaignDispatchesSingleJobsOnlyForValidCandidates`).
   - Xóa `testSendSingleCampaignEmailJobCatchesActivityLogExceptionWithoutFailingJob`.

---

## 2. API Contract / API Docs Assessment

- **Status:** `N/A — no API contract/API docs change`

---

## 3. Verification
- Chạy: `./vendor/bin/phpunit tests/Feature/Api/Consultant/SmsCampaignTest.php`
- Kết quả: `OK (28 tests, 77 assertions)` — 100% PASS (thời gian chạy ~7.4s).
