# SPEC: Sanitize Candidate Names Before MatchMaker Synchronization

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-07
> **Author**: Codex

## 1. Tổng quan

Khi CRS gửi candidate sang MatchMaker, các trường `first_name`, `middle_name`
và `last_name` hiện được map trực tiếp vào các field `peo_forename`,
`peo_middlename` và `peo_surname`. MatchMaker production không chấp nhận ký tự
nháy đơn trong các field tên, làm registration/update thất bại.

Thay đổi này sẽ loại bỏ ký tự nháy đơn ASCII (`'`) và nháy đơn typography
(`’`) ở boundary payload gửi sang MatchMaker, đồng thời viết hoa ký tự ngay
sau dấu nháy trước khi ghép tên lại. Ví dụ: `O'nel` → `ONel`. Tên gốc trong
bảng `candidates` không bị thay đổi.

**Yêu cầu gốc**: Fix production bug: candidate name containing apostrophe must
be synchronized to MatchMaker successfully.

### 1.1. Root cause đã xác minh

- Standard candidate payload lấy raw `first_name`, `middle_name`, `last_name`
  trong `MatchMakerService::getCandidateParams()`.
- Permanent candidate payload cũng lấy raw name trong
  `MatchMakerService::getPermanentCandidateRegistrationPayload()`.
- Standard duplicate flow dùng lại standard payload để gọi
  `UpdateCandidateMain` và `CheckForDuplicate`, nên sẽ được xử lý gián tiếp
  nếu normalization được đặt tại bước tạo payload.
- Không cần sửa Controller, FormRequest, Repository, migration hoặc database
  data.

## 2. Database Design

N/A — không thay đổi schema, migration, model persistence hoặc dữ liệu tên gốc.

## 3. API Contract

N/A — không thay đổi public route, request schema, response schema, HTTP status,
error key hoặc authentication. Chỉ thay đổi giá trị trong outbound payload từ
CRS tới MatchMaker.

### 3.1. API contract/API docs pre-deployment gate

- `~/projects/crs-api-docs`: **N/A — no API contract/API docs change**.
- Không cập nhật route inventory vì route và public API contract không đổi.
- Cần ghi nhận outbound payload behavior trong living business spec theo mục 9.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. Candidate được đọc từ CRS qua flow hiện tại.
2. `MatchMakerService` chuẩn bị payload registration/update.
3. Trước khi áp dụng giới hạn độ dài MatchMaker, service sanitize từng trường
   tên bằng cách viết hoa ký tự ngay sau mỗi dấu nháy rồi loại bỏ `'` và `’`.
4. Payload đã sanitize được dùng cho:
   - Standard `Candidates/RegisterCandidate`.
   - Permanent `Candidates/RegisterCandidate` với `peo_status = PERM`.
   - Standard duplicate `UpdateCandidateMain` thông qua `candidateDto`.
   - Standard duplicate pre-check `Candidates/CheckForDuplicate`.
5. CRS tiếp tục lưu tên gốc và các flow local khác tiếp tục sử dụng tên gốc.

### 4.2. Business rules

- Chỉ sanitize ở boundary gửi dữ liệu sang MatchMaker; không mutate `$candidate`
  và không ghi đè `candidates.first_name`, `middle_name`, `last_name`.
- Với mỗi ASCII apostrophe (`'`) hoặc right single quotation mark (`’`), viết
  hoa ký tự ngay sau nó rồi loại bỏ dấu nháy. Ví dụ `O'nel` → `ONel` và
  `d’arcy` → `dArcy`.
- Sanitize trước khi truncate theo giới hạn của MatchMaker, để dữ liệu sau cùng
  vừa không chứa ký tự bị cấm vừa không vượt giới hạn field.
- Giữ nguyên các ký tự khác, bao gồm khoảng trắng, dấu gạch nối và Unicode
  không thuộc nhóm apostrophe.
- Không sanitize emergency-contact name, email template, contact-log text,
  file name hoặc dữ liệu inbound từ MatchMaker trong scope này.
- Dùng một private helper và constant dùng chung trong `MatchMakerService`,
  không copy-paste logic giữa standard và Permanent payload builders.

### 4.3. Side Effects

| Loại | Trigger | Mô tả |
|------|---------|-------|
| External API | Standard candidate transfer | MM nhận tên đã loại apostrophe trong registration/update/check duplicate payload |
| External API | Permanent candidate submit | MM nhận tên đã loại apostrophe trong Permanent registration payload |
| Database | Không có | Tên gốc trong CRS không bị thay đổi |

## 5. Data Origin & Call Chain

### 5.1. Standard candidate

```text
POST /api/consultant/candidates/{id}/match_maker
  → CandidateController::sendCandidateToMatchMaker()
    → MatchMakerService::sendCandidateToMatchMaker()
      → getCandidateParams($candidate, ...)
        → candidate.first_name / middle_name / last_name
        → sanitized candidate payload
      → RegisterCandidate
      hoặc duplicate → updateExistingCandidate()
        → MatchMakerApiInterface::updateCandidate()
        → EpsilonApi::updateCandidateBasicInfo()
        → UpdateCandidateMain
      hoặc new candidate → checkDuplication()
        → CheckForDuplicate
```

Source:

- `routes/consultant.php:153`
- `app/Http/Controllers/Api/Consultant/CandidateController.php:402`
- `app/Services/MatchMakerService.php:338`
- `app/Services/MatchMakerService.php:960`
- `app/Services/MatchMakerService.php:721`
- `app/Services/MatchMakerService.php:1481`
- `app/Externals/EpsilonApi.php:499`

### 5.2. Permanent candidate

```text
POST /api/candidate/me/permanent-intake
  → PermanentCandidateIntakeController::submit()
    → PermanentCandidateIntakeService::submit()
      → PermanentCandidateSubmittedEvent / listener
        → MatchMakerService::syncPermanentCandidate()
          → getPermanentCandidateRegistrationPayload()
            → candidate.first_name / middle_name / last_name
            → sanitized candidate payload
          → RegisterCandidate
```

Source:

- `routes/candidate.php:105`
- `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php:60`
- `app/Services/PermanentCandidateIntakeService.php`
- `app/Events/Listeners/SyncPermanentCandidateToMatchMakerListener.php`
- `app/Services/MatchMakerService.php:418`
- `app/Services/MatchMakerService.php:480`

### 5.3. Variable verification

| Biến / key | Nguồn cung cấp | Nơi sử dụng | Confirmed? |
|------------|----------------|-------------|------------|
| `$candidate->first_name` | Candidate model loaded by current caller/service | Standard/Permanent outbound payload builders | ✅ |
| `$candidate->middle_name` | Candidate model loaded by current caller/service | Standard/Permanent outbound payload builders | ✅ |
| `$candidate->last_name` | Candidate model loaded by current caller/service | Standard/Permanent outbound payload builders | ✅ |
| `$candidateParams['peo_forename']` | Standard payload builder | Duplicate update/check-duplicate flow | ✅ |
| `$candidateParams['peo_surname']` | Standard payload builder | Duplicate update/check-duplicate flow | ✅ |

## 6. Constants & Enums

Thêm constant tại `MatchMakerService` cho tập ký tự MatchMaker không chấp nhận,
ví dụ `MATCHMAKER_NAME_APOSTROPHE_CHARACTERS = ["'", "’"]`. Không hardcode
tập ký tự trong nhiều payload builder.

Private helper dự kiến:

```php
private function sanitizeCandidateNameForMatchMaker(?string $name): string
```

Helper phải xử lý theo thứ tự: tìm từng dấu nháy, uppercase ký tự Unicode ngay
sau dấu nháy nếu có, loại bỏ dấu nháy, rồi trả về chuỗi đã ghép. Helper chỉ
chịu trách nhiệm transformation string, không query DB và không thực hiện
workflow khác.

## 7. Files cần tạo/sửa

### 7.1. Files mới

Không tạo production source file mới.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `app/Services/MatchMakerService.php` | Thêm constant/helper private; áp dụng normalization trước truncation trong standard và Permanent name payload builders. |
| `tests/Unit/Services/MatchMakerPermanentSyncTest.php` | Bổ sung candidate names có ASCII/typographic apostrophe và assert registration payload đã uppercase ký tự sau dấu nháy rồi loại dấu nháy; giữ assert candidate local không bị mutate. |
| `tests/Unit/Services/MatchMakerServiceTest.php` | Tạo test coverage cho standard registration payload và xác nhận duplicate update/check-duplicate dùng giá trị đã sanitize, nếu chưa có test harness phù hợp trong file hiện hữu. |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật CODE_FACT của standard/Permanent outbound MM flow: name fields được sanitize tại payload boundary. |
| `.business-spec/crs-matchmaker-crm-current-state.md` | Cập nhật bảng mapping name và ghi rõ tên local giữ nguyên, outbound MM bỏ apostrophe. |
| `.business-spec/backend-matchmaker-api-call-inventory.md` | Cập nhật contract notes của `RegisterCandidate`, `UpdateCandidateMain` và `CheckForDuplicate` nếu inventory hiện tại cần phản ánh transformation trước outbound call. |

Không sửa `routes`, FormRequest, Repository, migration, database seed hoặc
`~/projects/crs-api-docs`.

## 8. Test Cases

| Test File | Test Method / Scope | Mô tả |
|-----------|---------------------|-------|
| `tests/Unit/Services/MatchMakerPermanentSyncTest.php` | Existing permanent registration test hoặc provider mới | `O'nel`, `d’arcy`, `O'neil` được gửi thành `ONel`, `dArcy`, `ONeil`; registration vẫn thành công và candidate local giữ nguyên tên gốc. |
| `tests/Unit/Services/MatchMakerServiceTest.php` | Standard `RegisterCandidate` payload | Assert `peo_forename`, `peo_middlename`, `peo_surname` không chứa hai dạng apostrophe và việc truncate xảy ra sau sanitize. |
| `tests/Unit/Services/MatchMakerServiceTest.php` | Standard duplicate update path | Assert DTO truyền vào `UpdateCandidateMain` dùng tên đã sanitize. |
| `tests/Unit/Services/MatchMakerServiceTest.php` | Standard duplicate pre-check | Assert query `CheckForDuplicate` dùng `peo_forename`/`peo_surname` đã sanitize. |
| Affected existing suites | Regression | Chạy các test suite Candidate/Consultant/Permanent intake liên quan để đảm bảo không đổi local candidate data, route, status và error behavior. |
| Repository-wide | `./vendor/bin/phpunit` | Full PHPUnit suite phải pass 100% trước khi hoàn tất task. |

Không thêm unit test cho Repository implementation/contract.

## 9. Acceptance Criteria

- [x] Standard registration không gửi `'` hoặc `’` trong ba field name tới MM và
      ký tự ngay sau dấu nháy được uppercase trước khi dấu nháy bị loại bỏ.
- [x] Permanent registration không gửi `'` hoặc `’` trong ba field name tới MM
      và ký tự ngay sau dấu nháy được uppercase trước khi dấu nháy bị loại bỏ.
- [x] Duplicate update và duplicate pre-check dùng cùng giá trị đã sanitize.
- [x] Sanitize xảy ra trước giới hạn độ dài MM.
- [x] Tên gốc trong CRS không bị thay đổi hoặc persist lại dưới dạng đã sanitize.
- [x] Các ký tự không phải apostrophe được giữ nguyên.
- [x] Input `O'nel` được gửi sang MM thành `ONel`.
- [x] Không thay đổi route, public request/response contract, status, exception
      mapping hoặc DB schema.
- [x] Living business specs được cập nhật và cross-check với source sau code.
- [x] `~/projects/crs-api-docs` được ghi nhận là `N/A — no API contract/API docs change`.
- [x] Affected tests và full `./vendor/bin/phpunit` pass.

## 10. Implementation & verification sequence

1. Đã đọc lại plan, giữ nguyên các thay đổi unrelated trong working tree.
2. Đã thêm constant/helper private trong `MatchMakerService` và áp dụng đúng
   cho standard/Permanent name payload builders.
3. Đã cập nhật test coverage; không chạy formatter/linter tự động.
4. Affected suites pass: `3 tests / 80 assertions` cho Permanent sync và
   `67 tests / 6,136 assertions` cho Candidate/Consultant/Permanent feature
   suites.
5. Đã cập nhật và cross-check living business specs.
6. Full `./vendor/bin/phpunit` pass: `588 tests / 8,518 assertions`.
7. Self-check pass; API docs gate là N/A; `git diff --check` pass.
8. Deployment vẫn là bước vận hành tiếp theo; thay đổi không có migration và
   có thể rollback bằng cách revert code-only commit.

## 11. Risk & rollback

- **Risk**: Hai candidate có thể trở thành cùng một tên sau khi bỏ apostrophe;
  đây là giới hạn bắt buộc theo MM contract và không thay đổi email/phone/DOB
  duplicate signals hiện có.
- **Risk**: Removing characters before truncation có thể làm phần cuối tên được
  giữ lại khác với trước đây; đây là chủ đích để đảm bảo payload hợp lệ sau cùng.
- **Rollback**: Revert code-only change trong `MatchMakerService` và test/docs
  commit tương ứng; không cần rollback database hoặc migration.

## 12. Checklist trước khi Approve

- [x] Root cause và call chain standard/Permanent đã trace.
- [x] Phạm vi update duplicate/check-duplicate đã xác định.
- [x] Không có DB/API public contract change.
- [x] Không mutate tên gốc trong CRS.
- [x] Test impact và full-suite gate đã liệt kê.
- [x] User review và approve plan.
- [x] Implementation và verification hoàn tất.
