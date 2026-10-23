# SPEC: 019 - Add Required Health & Safety, Shift Preference, Criminal, and Agreement Fields to Permanent Candidate MatchMaker Payload

> **Task**: GAP-691
> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-22
> **Author**: Antigravity

---

## 1. Tổng quan

### 1.1. Bối cảnh & Yêu cầu
Khi thực hiện nộp hồ sơ Permanent Candidate Intake và đồng bộ ứng viên sang MatchMaker qua job nền `SyncPermanentCandidateToMatchMakerJob`, tiến trình đồng bộ thất bại với lỗi HTTP 400 Bad Request từ MatchMaker API:
```text
[2026-10-22 03:08:17] staging.CRITICAL: Permanent candidate MatchMaker sync failed after all retries.
{"candidate_id":5351,"job_id":8634,"file_id":1608,"agreement_file_id":1607,"permanent_form_file_id":null,
"error":"{\"Message\":\"The request is invalid.\",\"ModelState\":{
  \"model.health_and_safety\":[\"The health_and_safety field is required.\"],
  \"model.shift_preference\":[\"The shift_preference field is required.\"],
  \"model.health_and_criminal\":[\"The health_and_criminal field is required.\"],
  \"model.agreements\":[\"The agreements field is required.\"]}}",
"exception":"[object] (App\\Exceptions\\Services\\ExternalAPIException(code: 0)... at /var/www/html/app/Services/MatchMakerService.php:935)"}
```

### 1.2. Phân tích nguyên nhân gốc (Root Cause)
1. Endpoint `POST /api/Candidates/RegisterCandidate` của MatchMaker dùng chung cho cả Candidate thông thường (Temporary) lẫn Permanent Candidate.
2. Model C# của MatchMaker phía backend đặt ràng buộc `[Required]` đối với 4 đối tượng:
   - `model.health_and_safety`
   - `model.shift_preference`
   - `model.health_and_criminal`
   - `model.agreements`
3. Trong [`MatchMakerService::getPermanentCandidateRegistrationPayload`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/MatchMakerService.php#L505-L533), hàm chỉ dựng và gửi 2 section: `'candidate'` và `'overview'`. Vì thiếu hoàn toàn 4 section bắt buộc trên, MatchMaker từ chối đăng ký với mã lỗi 400.
4. Đối với candidate thông thường, 4 section này được dựng từ các câu hỏi phỏng vấn/khai báo mà Permanent candidate không thực hiện. Do đó, cần xây dựng các helper an toàn (safe fallbacks) cho Permanent candidate để không văng ngoại lệ `ServerSideException` khi thiếu câu trả lời và cung cấp các giá trị mặc định hợp lệ cho MatchMaker.

### 1.3. API Contract Pre-Deployment Gate
- **Đánh giá ảnh hưởng API Docs**: `N/A — no API contract/API docs change`.
- **Lý do**: Thay đổi chỉ thuộc phạm vi payload gửi outbound từ CRS sang MatchMaker API (`MatchMakerService`), không làm thay đổi public endpoints, FormRequest, response resources hay tài liệu API cho frontend / client (`~/projects/crs-api-docs`).

---

## 2. Thiết kế chi tiết

### 2.1. Cấu trúc Payload bổ sung vào `getPermanentCandidateRegistrationPayload`

File: [`app/Services/MatchMakerService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/MatchMakerService.php)

Cập nhật `getPermanentCandidateRegistrationPayload` gửi thêm 4 keys:
```php
return [
    'candidate' => [ ... ],
    'overview' => [ ... ],
    'health_and_safety' => $this->getPermanentHealthAndSafetyParams($answers),
    'shift_preference' => $this->getPermanentShiftPreferenceParams($answers),
    'health_and_criminal' => $this->getPermanentHealthAndCriminalParams($answers),
    'agreements' => $this->getPermanentAgreementsParams($answers),
];
```

### 2.2. Chi tiết các hàm helper riêng cho Permanent Candidate

Tất cả các helper phải là `private` và không throw `ServerSideException` khi candidate chưa có câu trả lời:

#### A. `getPermanentHealthAndSafetyParams(Collection $answers): array`
* **Mục đích**: Cung cấp cấu trúc giày bảo hộ và áo phản quang.
* **Logic**:
  ```php
  private function getPermanentHealthAndSafetyParams(Collection $answers): array
  {
      return [
          'owns_safety_boots' => [
              'own' => Answer::ANSWER_YES === $this->getAnswerByCategory($answers, Question::SAFETY_BOOTS, false),
              'size' => $this->getAnswerByCategory($answers, Question::BOOT_SIZE, false),
          ],
          'owns_hi_viz_vest' => [
              'own' => Answer::ANSWER_YES === $this->getAnswerByCategory($answers, Question::HI_VIS_VEST_OR_JACKET, false),
              'size' => $this->getAnswerByCategory($answers, Question::VEST_OR_JACKET_SIZE, false),
          ],
      ];
  }
  ```
  *(Khi không có câu trả lời, `own` = `false`, `size` = `'No answer'`, phù hợp với schema MatchMaker chấp nhận).*

#### B. `getPermanentShiftPreferenceParams(Collection $answers): array`
* **Mục đích**: Cung cấp cấu trúc ca làm việc.
* **Logic**:
  ```php
  private function getPermanentShiftPreferenceParams(Collection $answers): array
  {
      $question = $this->questionRepository->firstByFilter([
          'category' => Question::SHIFT_PREFERENCES,
      ]);
      $values = [];
      if ($question) {
          foreach ($answers as $answer) {
              if ($answer->question_id === $question->id && !empty($answer->answer[0])) {
                  $values = $this->getValues($answer->answer[0]);
              }
          }
      }

      return $this->getShiftPreferenceParams($values);
  }
  ```
  *(Khi không có câu trả lời, tất cả các ca `days`, `nights`, `weekends`... đều là `false`).*

#### C. `getPermanentHealthAndCriminalParams(Collection $answers): array`
* **Mục đích**: Cung cấp thông tin sức khỏe và tiền án tiền sự.
* **Logic**:
  ```php
  private function getPermanentHealthAndCriminalParams(Collection $answers): array
  {
      $healthAnswer = $this->getAnswerByCategory($answers, Question::YOUR_HEALTH, false);
      $anyHealthIssues = Answer::ANSWER_YES === $healthAnswer
          ? $this->getAnswerByCategory($answers, Question::YOUR_HEALTH_DETAIL, false)
          : ($healthAnswer === 'No answer' ? 'No' : $healthAnswer);

      $convictionsAnswer = $this->getAnswerByCategory($answers, Question::CONVICTIONS_WARNINGS, false);
      $anyConvictions = Answer::ANSWER_YES === $convictionsAnswer
          ? $this->getAnswerByCategory($answers, Question::CONVICTIONS_WARNINGS_DETAIL, false)
          : ($convictionsAnswer === 'No answer' ? 'No' : $convictionsAnswer);

      return [
          'any_health_issues' => $anyHealthIssues,
          'any_convictions' => $anyConvictions,
          'agree_to_check' => true,
      ];
  }
  ```
  *(Khi không có câu trả lời, mặc định sức khỏe và tiền án là `'No'`, `agree_to_check` là `true`).*

#### D. `getPermanentAgreementsParams(Collection $answers): array`
* **Mục đích**: Cung cấp thông tin đồng thuận điều khoản.
* **Logic**:
  ```php
  private function getPermanentAgreementsParams(Collection $answers): array
  {
      return [
          'data_protection' => true,
          'opt_out' => true,
          'health_disability' => true,
          'dbs' => true,
      ];
  }
  ```
  *(Permanent candidate đã đồng thuận các điều khoản và Work Finder Agreement lúc submit, nên các cờ đều là `true`).*

---

## 3. Cập nhật Living Business Specifications

* Cập nhật file `.business-spec/backend-matchmaker-api-call-inventory.md`:
  - Tại mục `MM-W01 — POST /api/Candidates/RegisterCandidate` -> `Permanent registration body`: Bổ sung 4 đối tượng `health_and_safety`, `shift_preference`, `health_and_criminal`, `agreements` vào mô tả cấu trúc payload.
  - Ghi chú rõ rằng MatchMaker API model enforce 4 đối tượng này là bắt buộc (`[Required]`).

---

## 4. Kiểm thử & Đánh giá tác động (Test Impact Review)

### 4.1. Tests bị ảnh hưởng
* **`tests/Unit/Services/MatchMakerPermanentSyncTest.php`**:
  - Method `expectPermanentRegistrationPayload()` đang mock và assert payload JSON chỉ gồm `'candidate'` và `'overview'`.
  - Cần cập nhật fixture kỳ vọng (expectation) của test case này để bổ sung 4 keys mới (`health_and_safety`, `shift_preference`, `health_and_criminal`, `agreements`) tương ứng.

### 4.2. Kế hoạch chạy test verification
1. Chạy unit test trực tiếp:
   ```bash
   ./vendor/bin/phpunit tests/Unit/Services/MatchMakerPermanentSyncTest.php
   ```
   * **Kết quả**: `PASS (5 tests, 155 assertions)`.
2. Chạy feature tests liên quan đến Permanent Candidate Intake:
   ```bash
   ./vendor/bin/phpunit tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php tests/Feature/Api/Candidate/PermanentCandidateFormTest.php
   ```
   * **Kết quả**: `PASS (69 tests, 6599 assertions)`.

---

## 5. File Checklist

| STT | File | Hành động | Mục đích |
| :--- | :--- | :--- | :--- |
| 1 | [`app/Services/MatchMakerService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/MatchMakerService.php) | MODIFY | Bổ sung 4 helper methods và 4 keys vào payload trong `getPermanentCandidateRegistrationPayload`. |
| 2 | [`tests/Unit/Services/MatchMakerPermanentSyncTest.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/tests/Unit/Services/MatchMakerPermanentSyncTest.php) | MODIFY | Cập nhật expectation của payload trong test mock `expectPermanentRegistrationPayload()`. |
| 3 | [`.business-spec/backend-matchmaker-api-call-inventory.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.business-spec/backend-matchmaker-api-call-inventory.md) | MODIFY | Cập nhật tài liệu living spec phản ánh đúng schema thực tế của MatchMaker. |
| 4 | [`.specs/GAP-691/019-permanent-candidate-matchmaker-payload-required-fields.md`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-691/019-permanent-candidate-matchmaker-payload-required-fields.md) | CREATE | Plan chi tiết cho việc xử lý lỗi (file này). |
