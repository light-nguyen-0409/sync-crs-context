# SPEC: GAP-745 Fix Code Review Findings for Bulk SMS Email Communication

> **Task Key**: `GAP-745`  
> **Trạng thái**: `COMPLETED`  
> **Ngày tạo**: 2026-10-28  
> **Cập nhật**: 2026-10-28  
> **Author**: Antigravity Pair Programmer  
> **Scope**: Bugfix / Reliability / Review Remediation  
> **Tham chiếu**: [`.specs/GAP-745/001-bulk-sms-allow-email-communication.md`](001-bulk-sms-allow-email-communication.md)

---

## 1. Tổng quan

Sau khi rà soát toàn diện code change của task GAP-745 (commit `5dc7a564`) dựa trên GitHub Actions Claude Review protocol, hệ thống ghi nhận **4 vấn đề (2 High, 2 Medium)** cần được khắc phục:

1. **[High] Crash HTTP 500 (TypeError) tại Resource khi serialize campaign đã gửi email**:
   * *Hiện trạng*: Trong `SmsCampaign.php` (Model), `email_sent_at` được khai báo trong `$casts` kiểu `'datetime'`, trả về instance của `Carbon`. Trong khi đó, `SmsCampaign.php` (Resource) có `declare(strict_types=1);` và gọi `DateTimeUtility::formatToBstTimeFromGmt($this->resource->email_sent_at)`. Hàm utility yêu cầu typehint `string`, dẫn đến ném fatal `TypeError` và gây sập HTTP 500 khi gọi `GET /api/consultant/sms/candidate_campaigns`.
   * *Giải pháp*: Bỏ cast `'datetime'` của `email_sent_at` trong Model (đồng bộ với `sent_at`), đồng thời ép kiểu an toàn `(string)` trong Resource và bổ sung test case serialize.

2. **[High] Ghi đè mất cấu hình Email khi gọi `resumeCandidateCampaign` mà không truyền `send_email`**:
   * *Hiện trạng*: `ResumeCampaign` FormRequest cho phép `send_email` là `'sometimes|boolean'`. Tuy nhiên, `SmsController::resumeCandidateCampaign` luôn gán `'send_email' => $request->boolean('send_email')` (mặc định `false`), `'email_subject' => null`, `'email_content' => null`. Khi gọi `SmsService::resumeCampaign`, logic kiểm tra `array_key_exists('send_email', $message)` sẽ kích hoạt và xóa sạch toàn bộ nội dung email của campaign nếu consultant chỉ cập nhật nội dung tin nhắn SMS.
   * *Giải pháp*: Chỉ đưa các trường email vào `$campaignData` trong Controller khi `$request->has('send_email')`.

3. **[Medium] Thiếu Idempotency & Dedup Guard khi Retry Bulk Email Job**:
   * *Hiện trạng*: `SendBulkCampaignEmailJob` xử lý tối đa 500 ứng viên qua SMTP tuần tự, có cấu hình `tries = 3` và `timeout = 300`. Nếu job bị ngắt giữa chừng (do timeout hoặc sự cố mạng tạm thời ở ứng viên thứ N), queue worker sẽ retry lại từ đầu khiến các ứng viên từ 1 đến N bị nhận email trùng lặp.
   * *Giải pháp*: 
     - Bổ sung guard ở đầu `handle()`: kiểm tra nếu `$campaign->email_sent_at !== null` thì return ngay.
     - Dùng Redis Set (`Cache::sAdd` / `Cache::sIsMember`) để ghi nhận danh sách ứng viên đã gửi email thành công. Khi retry, tự động bỏ qua những ai đã nhận mail. Xóa cache key sau khi job hoàn thành.
     - Tăng timeout lên `timeout = 600` (10 phút) để đảm bảo đủ thời gian cho 500 email.

4. **[Medium] Dispatch Queue Job trước khi lưu trạng thái Campaign xuống Database**:
   * *Hiện trạng*: Trong `SmsService::sendCampaign()`, `SendBulkCampaignEmailJob::dispatch($campaign->id)` được gọi trước khi gọi `$this->smsCampaignRepository->save($campaign)`. Nếu save bị fail hoặc worker nhấc job ngay lập tức, worker sẽ đọc trạng thái campaign chưa được cập nhật trong DB.
   * *Giải pháp*: Persist trạng thái campaign (`STATUS_SENT`, `sent_at`) xuống database trước khi gọi `SendBulkCampaignEmailJob::dispatch()`.

---

## 2. Database Design

`N/A — Không thay đổi Database schema hay migration.`

---

## 3. API Contract & API Docs Pre-Deployment Gate

`N/A — no API contract/API docs change.`
Các thay đổi hoàn toàn mang tính sửa lỗi nội bộ (bugfix), gia cố độ ổn định (reliability) và bảo toàn tính toàn vẹn dữ liệu, không làm thay đổi request/response schema hay tài liệu API trong `~/projects/crs-api-docs`.

---

## 4. Chi tiết giải pháp kỹ thuật

### 4.1. Finding 1: Khắc phục TypeError trong `SmsCampaign` Resource

* **File 1**: [`app/Models/SmsCampaign.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Models/SmsCampaign.php)
  Loại bỏ `'email_sent_at' => 'datetime'` khỏi mảng `$casts`:
  ```php
  protected $casts = [
      'send_email' => 'boolean',
  ];
  ```
  *(Đồng bộ cách xử lý với trường `sent_at` vốn cũng là chuỗi raw timestamp trong DB).*

* **File 2**: [`app/Http/Resources/Api/Consultant/SmsCampaign.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Http/Resources/Api/Consultant/SmsCampaign.php)
  Ép kiểu an toàn sang chuỗi trước khi truyền vào `formatToBstTimeFromGmt`:
  ```php
  if (!empty($this->resource->email_sent_at)) {
      $result['email_sent_at'] = DateTimeUtility::formatToBstTimeFromGmt((string) $this->resource->email_sent_at);
  }
  ```

---

### 4.2. Finding 2: Bảo vệ cấu hình Email khi gọi `resumeCandidateCampaign`

* **File**: [`app/Http/Controllers/Api/Consultant/SmsController.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Http/Controllers/Api/Consultant/SmsController.php)
  Tại method `resumeCandidateCampaign`, chỉ thêm các trường email vào array truyền xuống Service khi request thực sự có truyền:
  ```php
  $campaignData = [
      'subject' => $subject,
      'content' => $content,
  ];

  if ($request->has('send_email')) {
      $campaignData['send_email'] = $request->boolean('send_email');
      $campaignData['email_subject'] = $request->input('email_subject');
      $campaignData['email_content'] = $request->input('email_content');
  }
  ```

---

### 4.3. Finding 3: Dedup Guard & Idempotency trong `SendBulkCampaignEmailJob`

* **File**: [`app/Jobs/SendBulkCampaignEmailJob.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Jobs/SendBulkCampaignEmailJob.php)
  1. Tăng timeout:
     ```php
     public const TIMEOUT_SECONDS = 600;
     ```
  2. Bổ sung guard ở đầu hàm `handle()`:
     ```php
     if (!$campaign || !$campaign->send_email || $campaign->email_sent_at !== null) {
         return;
     }
     ```
  3. Dùng Redis Set qua Facade `Cache` để track danh sách candidate đã nhận email:
     ```php
     $sentCacheKey = "sms_campaign:{$campaign->id}:sent_emails";

     foreach ($validCandidates as $candidate) {
         // Kiểm tra nếu candidate này đã gửi thành công ở attempt trước
         if (Cache::sIsMember($sentCacheKey, (string) $candidate->id)) {
             continue;
         }

         try {
             // ... gửi email ...
             if ($sent) {
                 Cache::sAdd($sentCacheKey, (string) $candidate->id);
                 Cache::expire($sentCacheKey, 86400); // 24h TTL
                 // gom ActivityLog ...
             }
         } catch (\Throwable $e) { ... }
     }
     ```
  4. Sau khi insert ActivityLog và cập nhật `email_sent_at`:
     ```php
     $campaign->email_sent_at = Carbon::now();
     $smsCampaignRepository->save($campaign);
     Cache::forget($sentCacheKey);
     ```

---

### 4.4. Finding 4: Điều chỉnh thứ tự dispatch trong `SmsService::sendCampaign`

* **File**: [`app/Services/SmsService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/SmsService.php)
  Lưu campaign trước khi dispatch queue job:
  ```php
  $campaign->sent_at = Carbon::now();
  $savedCampaign = $this->smsCampaignRepository->save($campaign);

  if ($smsResult->isSuccess() && $savedCampaign->send_email) {
      SendBulkCampaignEmailJob::dispatch($savedCampaign->id);
  }

  return $savedCampaign;
  ```

---

## 5. Danh sách File Chỉnh sửa & Test Cases

### File Code:
1. `app/Models/SmsCampaign.php` (MODIFY)
2. `app/Http/Resources/Api/Consultant/SmsCampaign.php` (MODIFY)
3. `app/Http/Controllers/Api/Consultant/SmsController.php` (MODIFY)
4. `app/Jobs/SendBulkCampaignEmailJob.php` (MODIFY)
5. `app/Services/SmsService.php` (MODIFY)
6. `tests/Feature/Api/Consultant/SmsCampaignTest.php` (MODIFY)

### Test Cases Bổ sung:
1. `testSmsCampaignResourceFormatsEmailSentAtWithoutTypeError`:
   Tạo campaign đã có `email_sent_at`, serialize qua `SmsCampaign` Resource và `GET /api/consultant/sms/candidate_campaigns`, xác nhận trả về HTTP 200, format giờ BST đúng chuẩn và không throw `TypeError`.
2. `testResumeSmsCampaignPreservesEmailSettingsWhenSendEmailOmitted`:
   Tạo campaign có `send_email = true` và subject/content email. Gọi `PUT /resume` chỉ cập nhật `subject` và `content` SMS (không truyền `send_email`), xác nhận các trường email cũ vẫn được giữ nguyên vẹn.
3. `testSendBulkCampaignEmailJobSkipsAlreadySentCandidatesOnRetry`:
   Mô phỏng candidate ID đã nằm trong cache `sent_emails`, verify job bỏ qua không gửi lại mail cho candidate đó.
4. `testSendBulkCampaignEmailJobExitsEarlyIfEmailSentAtIsAlreadySet`:
   Verify job exit sớm nếu `$campaign->email_sent_at` đã có giá trị.
