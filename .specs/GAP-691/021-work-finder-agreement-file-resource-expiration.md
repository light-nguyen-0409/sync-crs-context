# SPEC: GAP-691 Configurable File Resource Expiration & 30-Minute Work Finder Agreement URL

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-22
> **Author**: Antigravity
> **Task Key**: GAP-691

---

## 1. Tổng quan

- **Mục tiêu**: Cho phép thiết lập thời gian hết hạn (`expiration time` tính theo phút) của temporary URL trong `App\Http\Resources\Api\Candidate\File` từ bên ngoài, giữ giá trị mặc định là 10 phút như hiện tại; đồng thời trong API `POST /api/candidate/me/permanent-intake/work-finder-agreement` truyền vào thời gian hết hạn là 30 phút.
- **Yêu cầu gốc**: "check task 691 api /permanent-intake/work-finder-agreement ở resource File tôi muốn set được time expired link file ở ngoài (để default 10 như hiênj tại) ở api này truyênf vaof 30 min".

---

## 2. API Contract & API Docs Assessment (Pre-Deployment Gate)

- **Đánh giá ảnh hưởng API Docs / Contract**:
  - Endpoint: `POST /api/candidate/me/permanent-intake/work-finder-agreement`
  - Request schema: Không đổi (`job_id`, `candidate`, `intermediary_name`).
  - Response JSON structure & types: Không đổi (`id`, `type`, `url`, `converted_file_url`, `status`, `original_file_name`, `uploaded_at`, `toe_signed_ip`). Cả `url` và `converted_file_url` vẫn là URL tạm thời (string).
  - Không có field mới, không đổi kiểu dữ liệu, không đổi status code (200 OK), không đổi error contracts.
  - S3 / Storage signed URL expiration time là runtime behavior nội bộ của link truy cập file S3, không nằm trong OpenAPI / Docusaurus API documentation schema contracts.
- **Kết luận đồng bộ API Docs**:
  - `N/A — no API contract/API docs change`.

---

## 3. Database Design

- Không thay đổi database (bảng, cột, migration, quan hệ Eloquent giữ nguyên).

---

## 4. API Contract

### 4.1. Endpoint
```
POST /api/candidate/me/permanent-intake/work-finder-agreement
```
- **Auth**: `auth:candidateApi`, `checkCandidateLockEdit`
- **Controller**: `App\Http\Controllers\Api\Candidate\PermanentCandidateIntakeController@generateWorkFinderAgreement`

### 4.2. Request
- FormRequest: `App\Http\Requests\Api\Candidate\WorkFinderAgreementRequest` (giữ nguyên không đổi).

### 4.3. Response
- HTTP 200 OK
- Candidate `File` Resource:
```json
{
  "id": 123,
  "type": "work_finder_agreement",
  "url": "https://...",
  "converted_file_url": null,
  "status": "uploaded",
  "original_file_name": "work-finder-agreement.pdf",
  "uploaded_at": 1690000000,
  "toe_signed_ip": null
}
```
> URL trong response được ký với thời hạn 30 phút (thay vì 10 phút như trước).

---

## 5. Business Logic & Implementation Design

### 5.1. Resource: `App\Http\Resources\Api\Candidate\File`
- Khai báo hằng số mặc định:
  ```php
  public const DEFAULT_EXPIRATION_MINUTES = 10;
  ```
- Khai báo thuộc tính `$expirationMinutes` với giá trị mặc định (không can thiệp constructor, tuân thủ signature gốc của `JsonResource`):
  ```php
  protected int $expirationMinutes = self::DEFAULT_EXPIRATION_MINUTES;
  ```
- Cung cấp fluent setter `withExpirationMinutes`:
  ```php
  public function withExpirationMinutes(int $expirationMinutes): static
  {
      $this->expirationMinutes = $expirationMinutes;

      return $this;
  }
  ```
- Trong `toArray($request)`:
  Thay thế hardcoded `10` bằng `$this->expirationMinutes`:
  ```php
  $result['url'] = \Storage::temporaryUrl($this->resource->url, now()->addMinutes($this->expirationMinutes));
  if (!empty($this->resource->converted_file_url)) {
      $result['converted_file_url'] = \Storage::temporaryUrl($this->resource->converted_file_url, now()->addMinutes($this->expirationMinutes));
  }
  ```

### 5.2. Controller: `App\Http\Controllers\Api\Candidate\PermanentCandidateIntakeController`
- Khai báo hằng số thời gian hết hạn cho Work Finder Agreement:
  ```php
  public const WORK_FINDER_AGREEMENT_EXPIRATION_MINUTES = 30;
  ```
- Cập nhật method `generateWorkFinderAgreement` sử dụng fluent method `withExpirationMinutes`:
  ```php
  public function generateWorkFinderAgreement(WorkFinderAgreementRequest $request): FileResource
  {
      return (new FileResource(
          $this->intakeService->generateWorkFinderAgreement(auth()->user(), $request->validated())
      ))->withExpirationMinutes(self::WORK_FINDER_AGREEMENT_EXPIRATION_MINUTES);
  }
  ```

---

## 6. Data Origin & Call Chain

```
POST /api/candidate/me/permanent-intake/work-finder-agreement
  → PermanentCandidateIntakeController@generateWorkFinderAgreement
    → WorkFinderAgreementRequest validated input
    → PermanentCandidateIntakeServiceInterface@generateWorkFinderAgreement
      → File Model instance returned
    → FileResource instantiated & ->withExpirationMinutes(30)
      → Storage::temporaryUrl($path, now()->addMinutes(30))
  → JSON Response (tám field của Candidate File Resource với link 30 phút)
```

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|-----------------|------------|
| `$this->expirationMinutes` | `FileResource::toArray()` | Default `10` hoặc qua `withExpirationMinutes()` | ✅ |
| `WORK_FINDER_AGREEMENT_EXPIRATION_MINUTES` | `PermanentCandidateIntakeController` | Constant `30` | ✅ |
| `DEFAULT_EXPIRATION_MINUTES` | `FileResource` | Constant `10` | ✅ |

---

## 7. Constants & Enums

- `App\Http\Resources\Api\Candidate\File`:
  ```php
  public const DEFAULT_EXPIRATION_MINUTES = 10;
  ```
- `App\Http\Controllers\Api\Candidate\PermanentCandidateIntakeController`:
  ```php
  public const WORK_FINDER_AGREEMENT_EXPIRATION_MINUTES = 30;
  ```

---

## 8. Files cần sửa đổi

| File | Thay đổi |
|------|----------|
| `app/Http/Resources/Api/Candidate/File.php` | Thêm `DEFAULT_EXPIRATION_MINUTES`, thuộc tính `protected int $expirationMinutes = self::DEFAULT_EXPIRATION_MINUTES;`, method `withExpirationMinutes()`, và dùng biến trong `toArray()` |
| `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php` | Thêm hằng số `WORK_FINDER_AGREEMENT_EXPIRATION_MINUTES = 30`, gọi `->withExpirationMinutes(self::WORK_FINDER_AGREEMENT_EXPIRATION_MINUTES)` trong `generateWorkFinderAgreement` |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Thêm test case xác thực temporary URL của Work Finder Agreement có expiration đúng bằng `now() + 30 minutes`, và test case xác thực `FileResource` mặc định vẫn có expiration là `10 minutes` |

---

## 9. Test Cases & Verification Plan

1. **Feature Test trong `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`**:
   - `testGenerateWorkFinderAgreementReturnsTemporaryUrlWithThirtyMinutesExpiration`:
     - Freeze time bằng `Carbon::setTestNow('2026-10-22 12:00:00')`.
     - Gọi API `POST /api/candidate/me/permanent-intake/work-finder-agreement`.
     - Lấy URL từ response, parse query parameter `expiration`.
     - Assert timestamp của `expiration` khớp chính xác với `Carbon::now()->addMinutes(30)->getTimestamp()`.
   - `testCandidateFileResourceDefaultsToTenMinutesExpiration`:
     - Freeze time bằng `Carbon::setTestNow('2026-10-22 12:00:00')`.
     - Tạo `FileResource` với constructor mặc định.
     - Assert temporary URL có query param `expiration` khớp chính xác với `Carbon::now()->addMinutes(10)->getTimestamp()`.
2. **Regression Test Suite**:
   - Chạy toàn bộ suite `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` (69 tests).
   - Chạy `tests/Feature/Api/Candidate/MeFileTest.php` để đảm bảo các endpoint upload/get file khác không bị ảnh hưởng.
   - Chạy `./vendor/bin/phpunit` toàn bộ hệ thống.

---

## 10. Checklist trước khi Approve

- [x] Database design: N/A (không thay đổi)
- [x] API Contract / API docs assessment: Đã đánh giá (`N/A — no API contract/API docs change`)
- [x] Business rules: Hết hạn link file set từ ngoài, mặc định 10 phút, API work-finder-agreement truyền 30 phút
- [x] Call chain: Đã trace và verify
- [x] Constants: Đầy đủ constant, không có magic number
- [x] Test placement policy: Tuân thủ quy định (Feature Test cho API và Resource, không tạo non-service unit test)
- [x] Đã được User Approve và hoàn thành triển khai, test verify 100% pass
