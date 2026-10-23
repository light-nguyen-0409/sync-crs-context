# SPEC: 020 - Dedicated Permanent Candidate MatchMaker Payload Helpers with Safe Fallback

> **Task**: `GAP-691`
> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-22
> **Author**: Antigravity Pair Programmer
> **Liên kết liên quan**: [019-permanent-candidate-matchmaker-payload-required-fields.md](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-691/019-permanent-candidate-matchmaker-payload-required-fields.md)

---

## 1. Tổng quan

### 1.1. Bối cảnh & Mục tiêu
Khi đồng bộ ứng viên Permanent sang MatchMaker (`POST /api/Candidates/RegisterCandidate`), backend C# của MatchMaker bắt buộc phải có 5 sections: `health_and_safety`, `shift_preference`, `health_and_criminal`, `agreements`, và `references`. 

Form nộp hồ sơ Permanent Candidate Intake (`PermanentCandidateIntakeService`) chỉ thu thập thông tin cá nhân, địa chỉ, CV, Work Finder Agreement và 3 câu hỏi cơ bản (`transportation_method`, `transportation_distance`, `recruitment_source`), không thu thập các câu hỏi kho vận/ca kíp/DBS của ứng viên Temporary.

### 1.2. Phân tích kiến trúc: Tách riêng (Dedicated) vs Dùng chung (Shared Flag)
1. **Tại sao KHÔNG dùng chung hàm cũ của Temporary (`getHealthAndSafetyParams`, `getHealthAndCriminalParams`, `getAgreementsParams`)**:
   - Các hàm cũ gọi `getAnswerByCategory($answers, $category, true)` (mặc định ném `ServerSideException` khi thiếu câu trả lời). Vì Permanent candidate không có các câu hỏi này, nếu tái sử dụng trực tiếp sẽ gây **CRASH 100% luồng đồng bộ Permanent**.
   - Nếu sửa hàm cũ thêm cờ `$isPermanent = false`: Vi phạm nguyên lý Clean Code (Flag Argument Anti-pattern), vi phạm quy tắc dự án (*"Do not modify an existing method unless its behavior is directly required..."*) và có nguy cơ gây lỗi hồi quy (regression) cho luồng Temporary Candidate đang chạy ổn định trên production.
   - Trong `getHealthAndCriminalParams` cũ có `'agree_to_check' => true` và `getAgreementsParams` cũ có `'opt_out' => true`. Nếu dùng chung sẽ tiếp tục vi phạm quy định Compliance/DBS của Anh.
2. **Quyết định thiết kế**:
   - **Tách riêng 4 helper methods `private` cho Permanent Candidate**: Nhận `$answers` và sử dụng `getAnswerByCategory($answers, $category, false)` (cờ `false` để không ném ngoại lệ).
   - **Tôn trọng dữ liệu thực tế nếu có**: Nếu `$answers` chứa câu trả lời (ví dụ ứng viên từng điền bảng hỏi), hệ thống sẽ đọc giá trị thực tế.
   - **Safe Compliance Fallback nếu không có câu trả lời**: Tự động fallback về các giá trị bảo vệ pháp lý (`'No answer'`, `false`), tuyệt đối không tự ý giả mạo đồng thuận DBS hay khai man tiền án tiền sự.

---

## 2. Database Design

`N/A — Không thay đổi Database schema hay dữ liệu.`

---

## 3. API Contract & API Docs Pre-Deployment Gate

`N/A — Không có API contract / API docs change.`
Thay đổi chỉ nằm ở tầng nội bộ `MatchMakerService` khi build payload gửi sang internal MatchMaker API, không ảnh hưởng đến bất kỳ public endpoint, request parameters, response schema hay tài liệu nào trong `~/projects/crs-api-docs`.

---

## 4. Thiết kế chi tiết mã nguồn

File: [`app/Services/MatchMakerService.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/MatchMakerService.php)

### 4.1. Cập nhật `getPermanentCandidateRegistrationPayload`
Truyền `$answers` vào 4 helper methods chuyên biệt:
```php
private function getPermanentCandidateRegistrationPayload(Candidate $candidate, CandidateAddress $candidateAddress, Collection $answers): array
{
    // ... [giữ nguyên phần candidate và overview]
        'health_and_safety' => $this->getPermanentHealthAndSafetyParams($answers),
        'shift_preference' => $this->getPermanentShiftPreferenceParams($answers),
        'health_and_criminal' => $this->getPermanentHealthAndCriminalParams($answers),
        'agreements' => $this->getPermanentAgreementsParams($answers),
        'references' => [],
    ];
}
```

### 4.2. Triển khai 4 Helper Methods riêng biệt

#### A. `getPermanentHealthAndSafetyParams(Collection $answers): array`
- Tra cứu an toàn với cờ `false` (không ném ngoại lệ).
- Khi không có câu trả lời: `own` = `false`, `size` = `'No answer'`.
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

#### B. `getPermanentShiftPreferenceParams(Collection $answers): array`
- Dùng lại `getShiftPreferenceParams($values)` thuần túy (không query DB thêm nếu không cần thiết).
```php
private function getPermanentShiftPreferenceParams(Collection $answers): array
{
    $shiftPreferenceParamValues = $this->getShiftPreferenceParamValues($answers);

    return $this->getShiftPreferenceParams($shiftPreferenceParamValues);
}
```
*(Nếu `$answers` không có ca làm việc, `$shiftPreferenceParamValues` trả về `[]`, tất cả các ca `days`, `nights`... đều tự động là `false`).*

#### C. `getPermanentHealthAndCriminalParams(Collection $answers): array`
- Lấy chi tiết sức khỏe/tiền án nếu ứng viên có khai `yes`.
- Nếu không có câu trả lời: trả về `'No answer'`.
- `agree_to_check`: luôn là `false` (vì Permanent candidate chưa từng được hỏi / ký đồng ý kiểm tra lý lịch tư pháp).
```php
private function getPermanentHealthAndCriminalParams(Collection $answers): array
{
    $anyHealthIssues = $this->getAnswerByCategory($answers, Question::YOUR_HEALTH, false);
    if ($anyHealthIssues === Answer::ANSWER_YES) {
        $anyHealthIssues = $this->getAnswerByCategory($answers, Question::YOUR_HEALTH_DETAIL, false);
    }

    $anyConvictions = $this->getAnswerByCategory($answers, Question::CONVICTIONS_WARNINGS, false);
    if ($anyConvictions === Answer::ANSWER_YES) {
        $anyConvictions = $this->getAnswerByCategory($answers, Question::CONVICTIONS_WARNINGS_DETAIL, false);
    }

    return [
        'any_health_issues' => $anyHealthIssues,
        'any_convictions' => $anyConvictions,
        'agree_to_check' => false,
    ];
}
```

#### D. `getPermanentAgreementsParams(Collection $answers): array`
- `data_protection`: Luôn là `true` vì ứng viên Permanent bắt buộc phải tích đồng ý Work Finder Agreement & Privacy Policy khi submit form.
- `opt_out`, `health_disability`, `dbs`: Đọc từ `$answers` với cờ `false`. Nếu không có câu trả lời, tự động nhận `false` (bảo vệ quyền lợi ứng viên, tuân thủ UK Working Time Regulations & DBS Code of Practice).
```php
private function getPermanentAgreementsParams(Collection $answers): array
{
    return [
        'data_protection' => true,
        'opt_out' => Answer::ANSWER_AGREE === $this->getAnswerByCategory($answers, Question::TIME_REGULATIONS_48_HOUR_OPT_OUT, false),
        'health_disability' => Answer::ANSWER_AGREE === $this->getAnswerByCategory($answers, Question::HEALTH_DISABILITY, false),
        'dbs' => Answer::ANSWER_AGREE === $this->getAnswerByCategory($answers, Question::DBS, false),
    ];
}
```

---

## 5. Data Origin & Call Chain Verification

| Tham số / Biến | Nguồn gốc dữ liệu | Đảm bảo an toàn |
|---|---|---|
| `$answers` | [`MatchMakerService:466`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Services/MatchMakerService.php#L466) gọi `$this->getAnswersByCandidateId($candidateId)` | Đã có sẵn trong scope của `syncPermanentCandidateToMatchMaker()`, kiểu `Collection<Answer>`. |
| `Question::*` constants | [`App\Models\Question`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Models/Question.php) | Các hằng số loại câu hỏi đã được định nghĩa chuẩn trong Model. |
| `Answer::*` constants | [`App\Models\Answer`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Models/Answer.php) | Hằng số `ANSWER_YES` ('yes'), `ANSWER_AGREE` ('agree'). |

---

## 6. Test Impact Review & Verification Plan

### 6.1. File test cần cập nhật
File: [`tests/Unit/Services/MatchMakerPermanentSyncTest.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/tests/Unit/Services/MatchMakerPermanentSyncTest.php)
- Cập nhật method `expectPermanentRegistrationPayload()` để khớp với payload an toàn:
  - `health_and_safety`: `own => false`, `size => 'No answer'`
  - `shift_preference`: toàn bộ `false`
  - `health_and_criminal`: `any_health_issues => 'No answer'`, `any_convictions => 'No answer'`, `agree_to_check => false`
  - `agreements`: `data_protection => true`, `opt_out => false`, `health_disability => false`, `dbs => false`
  - `references`: `[]`

### 6.2. Test cases cần bổ sung
Thêm test case kiểm tra:
1. **Trường hợp mặc định (Default Permanent Flow)**: Candidate không có câu trả lời cho các câu hỏi kho vận $\rightarrow$ Verify payload nhận đúng các giá trị safe defaults.
2. **Trường hợp có câu trả lời trong `$answers`**: Tạo candidate có câu trả lời `SAFETY_BOOTS`, `DBS` $\rightarrow$ Verify helper đọc đúng câu trả lời thực tế.

### 6.3. Kế hoạch chạy kiểm thử & Kết quả thực tế
1. **Unit Test Service**:
   ```bash
   ./vendor/bin/phpunit tests/Unit/Services/MatchMakerPermanentSyncTest.php
   ```
   * **Kết quả**: `PASS (6 tests, 171 assertions)` (Bao gồm 5 test cases default safe fallback và 1 test case mapped actual answers).
2. **Feature Test Permanent Candidate Form**:
   ```bash
   ./vendor/bin/phpunit tests/Feature/Api/Candidate/PermanentCandidateFormTest.php
   ```
   * **Kết quả**: `PASS (23 tests, 222 assertions)`.
3. **Feature Test Permanent Candidate Intake**:
   ```bash
   ./vendor/bin/phpunit tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php
   ```
   * **Kết quả**: `PASS (69 tests, 6599 assertions)`.
   * **Tổng cộng**: **98 tests, 6.992 assertions, 100% PASS**.

---

## 7. Checklist Tuân thủ (Self-Check Gate)

- [x] Đã đánh giá tính tương thích của API docs (`N/A — no API contract/API docs change`)
- [x] Không làm thay đổi hay gây rủi ro hồi quy (zero regression) cho luồng Temporary Candidate hiện có
- [x] Không dùng flag argument lồng ghép `if ($isPermanent)` gây code smell
- [x] Tuân thủ quy tắc **Minimal Git Diff** & **No Unsolicited Formatting**
- [x] Tránh được nguy cơ crash với `ServerSideException` bằng cách truyền cờ `false` cho `getAnswerByCategory`
- [x] Đảm bảo tuân thủ 100% quy định pháp lý lao động & kiểm tra tư pháp (UK DBS / Working Time Regulations)
