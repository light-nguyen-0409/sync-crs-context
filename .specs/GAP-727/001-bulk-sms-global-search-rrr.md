# SPEC: GAP-727 — Bulk SMS với Global Search và MM RRR

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-13
> **Author**: Codex

## 1. Tổng quan

Điều chỉnh Bulk SMS để consultant có thể gửi tới candidate ngoài branch/legal entity hiện tại khi bật Global Search, nhưng chỉ trong trường hợp danh sách được lọc đúng theo MM + MM status RRR và có ít nhất một skill.

**Yêu cầu gốc**: [GAP-727 — Consultant - Bulk SMS - RRR Status](https://gappersonnel.atlassian.net/browse/GAP-727).

### Nội dung đã được confirm trong comment Jira

- Bulk SMS tiếp tục yêu cầu có ít nhất một skill filter.
- Chỉ mở rộng phạm vi qua tất cả branch/legal entity khi Global Search bật.
- Case mở rộng phải là job status `MM` và MM status chính xác `RRR`.
- Các filter khác như postcode/client radius vẫn tiếp tục được áp dụng.
- Logic lọc recipient hiện tại vẫn giữ nguyên: permanent, đã nhận SMS trong 24 giờ, on-plan, DNU và marketing consent.

### Quyết định bổ sung đã confirm

- Nếu user chọn nhiều job status, trong đó có `MM` và status khác, không kích hoạt cross-branch; Bulk SMS giữ branch scope và logic cũ.
- Chỉ khi `job_status` chỉ có duy nhất `MM` mới xét điều kiện Global Search + MM status `RRR` + có skill để mở rộng cross-branch.

### Security review amendment

- Global Search trong Bulk SMS là flow có side effect: estimate tạo `sms_pre_campaign` chứa receiver IDs và bước tiếp theo có thể tạo campaign gửi SMS.
- `DetectBranchForConsultant` chỉ xác thực branch header qua `allowToAccessTheBranch`; method hiện tại không chứng minh quyền cross-branch bằng `User::can_access_all_branches`.
- Không được coi việc user có role consultant hoặc truy cập được branch trong header là đủ quyền mở rộng sang tất cả branch/legal entity.
- Chỉ cho phép effective cross-branch khi authenticated user có `can_access_all_branches=true`. Nếu user gửi `all_branches=true` nhưng không có quyền này, giữ nguyên branch scope hiện tại để tránh mở rộng recipient; không thay đổi success response shape.

## 2. Database Design

N/A — không thay đổi schema, migration, model relationship hoặc dữ liệu lưu trữ.

Campaign vẫn lưu `branch_id` của user tạo campaign và danh sách candidate qua quan hệ SMS hiện tại; thay đổi chỉ nằm ở scope candidate được chọn trước khi tạo pre-campaign.

## 3. API Contract

### 3.1. Endpoint hiện hữu

```text
GET /api/consultant/sms/estimate
```

**Auth**: Required — `auth:userApi`
**Middleware**: `detectBranchForConsultant`, `autoLogout`
**Headers**: `Authorization`, `Gap-Branch-ID`

### 3.2. Query parameters liên quan

| Param | Type | Required | Mô tả |
|---|---|---:|---|
| `all_branches` | boolean | No | Global Search; chỉ được dùng để mở rộng scope khi toàn bộ điều kiện GAP-727 đạt |
| `can_access_all_branches` | boolean từ authenticated user | — | Quyền bắt buộc để `all_branches=true` có hiệu lực trong Bulk SMS; không lấy từ query client |
| `job_status[]` | array | No | Phải chỉ có duy nhất `matchmaker` để kích hoạt cross-branch; nếu có thêm status khác thì giữ branch scope cũ |
| `mm_status[]` | array | No | Phải chỉ gồm `rrr` để kích hoạt cross-branch |
| `skill_ids[]` | array | No | Phải có ít nhất một skill để kích hoạt cross-branch |
| Các filter hiện hữu | tùy loại | No | Filter text, location, client location/radius và các filter khác không bị bỏ qua |

Không đổi route, request field mới, success response schema hoặc error envelope. Thay đổi là business semantics của scope candidate khi estimate.

### 3.3. Response và giới hạn recipient

- Thành công giữ nguyên `pre_campaign_id`, `numb_of_receivers`, `estimated_cost`.
- API tiếp tục giới hạn recipient bằng `min(config('sms.max_sms_per_bulk'), provider max)`; mặc định `MAX_SMS_PER_BULK=500` nếu environment không override.
- Vượt giới hạn trả `operationNotAllowed` và không tạo pre-campaign.

### 3.4. API documentation gate

Phải kiểm tra `~/projects/crs-api-docs` trước implementation để xác định endpoint estimate và semantics Global Search có được document hay không.

- Nếu docs có mô tả behavior bị ảnh hưởng: Phase 1 phải cập nhật docs trước, đánh dấu contract chưa deploy theo convention, chạy docs validation, commit chỉ các file GAP-727 và push remote `main`; ghi file diff, validation result, commit SHA và push result vào plan.
- Nếu không có API contract/docs cần sửa: ghi rõ `N/A — no API contract/API docs change` vào plan sau khi kiểm tra.

## 4. Business Logic (Service Layer)

### 4.1. Call chain hiện tại

```text
GET /api/consultant/sms/estimate
  → SmsController::estimateCandidateCampaign
    → CandidateRequestFilter::filterCandidateRequest
    → CandidateService::getCandidatesByBranch
    → CandidateRepository::searchCandidateWithDetailAndJob
    → SmsService::filterPotentialReceiversFromCandidateCollection
    → SmsService::createSmsPreCampaign
```

### 4.2. Rules

1. Global Search tắt: giữ branch scope hiện tại.
2. Nếu `job_status` có nhiều status hoặc có status khác ngoài `MM`: giữ branch scope và logic Bulk SMS hiện tại, không xét cross-branch.
3. Chỉ khi `job_status` chỉ có duy nhất `MM`, Global Search bật, authenticated user có `can_access_all_branches=true`, `mm_status` là `RRR` và `skill_ids` không rỗng mới truyền empty branch scope tương đương Candidate search Global Search.
4. `job_status=MM` là candidate job status `CandidateJob::STATUS_MATCHMAKER`; `mm_status=RRR` là candidate MM status `Candidate::MM_STATUS_RRR`.
5. Không bỏ qua các filter đã chọn, gồm skill, postcode/client radius, text search và các filter hiện hữu khác.
6. Không thay đổi các recipient exclusions và provider/max-recipient validation đang có.
7. Khi tạo pre-campaign, giữ branch của consultant làm campaign ownership/audit scope; chỉ candidate receiver scope được mở rộng.
8. `all_branches=true` từ user không có `can_access_all_branches` phải giữ branch scope hiện tại; không được tin một permission flag do client gửi lên.

### 4.3. Side Effects

Không có side effect mới. Vẫn tạo `sms_pre_campaign` sau khi candidate collection đã qua filter và giới hạn recipient.

## 5. Data Origin & Call Chain

| Biến / key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|---|---|---|---|
| `branch_id` | Candidate search và pre-campaign | `Gap-Branch-ID` header qua `JsonRequest`/`CandidateRequestFilter` | ✅ |
| `all_branches` | Quyết định Global Search | Query parameter từ `Request::boolean('all_branches')` | ✅ ở Candidate search; cần nối vào SMS estimate |
| `can_access_all_branches` | Authorization cho SMS cross-branch | Authenticated `User` từ `auth()->user()`; field persisted trên `users` | ✅ field được dùng bởi `UserService`/`BranchController`; chưa được dùng trong SMS estimate |
| `job_status` | Candidate job filter | Query parameter `job_status[]`, validate trong `CandidateRequestFilter` | ✅ |
| `mm_status` | Candidate MM status filter | Query parameter `mm_status[]`, repository filter trên `candidates.match_maker_status` | ✅ |
| `skill_ids` | Candidate skill filter | Query parameter `skill_ids[]`, repository filter trên `candidateSkills` | ✅ |
| Candidate collection | SMS eligibility | `CandidateService::getCandidatesByBranch` → repository query | ✅ |
| Recipient count | Max-recipient gate | Collection sau `SmsService::filterPotentialReceiversFromCandidateCollection` | ✅ |

Current source evidence:

- SMS estimate hiện gọi `getCandidatesByBranch` với `branchId` nguyên trạng tại `app/Http/Controllers/Api/Consultant/SmsController.php:45-68`.
- Candidate list đã đổi branch scope khi `all_branches=true` tại `app/Http/Controllers/Api/Consultant/CandidateController.php:137-149`.
- Candidate repository đã có filter `skill_ids`, `mm_status` và job status tại `app/Repositories/CandidateRepository.php:89-100,295-325`.

## 6. Constants & Enums

Tái sử dụng constants hiện hữu, không hardcode giá trị mới:

- `CandidateJob::STATUS_MATCHMAKER`
- `Candidate::MM_STATUS_RRR`
- Existing SMS config `sms.max_sms_per_bulk`
- Existing provider max receiver contract

Nếu implementation cần truyền trạng thái cross-branch qua Service/DTO, phải đặt tên rõ ràng và dùng boolean/constant phù hợp, không dùng magic string.

## 7. Files cần tạo/sửa

### 7.1. Files mới

N/A.

### 7.2. Files dự kiến sửa

| File | Thay đổi |
|---|---|
| `app/Contracts/Services/SmsServiceInterface.php` | Khai báo method Service xác định branch scope cho Bulk SMS theo Global Search, quyền cross-branch, job status, MM status và skill filters |
| `app/Services/SmsService.php` | Implement business rule xác định cross-branch eligibility, bao gồm `can_access_all_branches`; không thay đổi recipient exclusions ngoài scope |
| `app/Http/Controllers/Api/Consultant/SmsController.php` | Truyền quyền từ authenticated user vào Service trước `getCandidatesByBranch`; giữ max-recipient gate và campaign branch ownership |
| `tests/Feature/Api/Consultant/SmsCampaignTest.php` | Thêm/update feature tests cho branch scope, cross-branch authorization, mixed status, skill prerequisite và max recipients |
| `.business-spec/backend-business-flow-spec.md` | Ghi nhận behavior GAP-727 đã triển khai và call chain thực tế |

Không sửa `CandidateRequestFilter` hoặc Repository: filter hiện hữu đã cung cấp và xử lý job status/MM status/skill; `all_branches` được đọc tại SMS controller rồi truyền vào Service.

## 8. Test Cases

| Test File | Test Method | Mô tả |
|---|---|---|
| `tests/Feature/Api/Consultant/SmsCampaignTest.php` | new | Global Search + chỉ MM + RRR + skill: candidate branch khác được đưa vào estimate |
| same | new | Global Search tắt: candidate branch khác không được đưa vào estimate |
| same | new | Global Search + MM nhưng không có skill: không kích hoạt cross-branch |
| same | new | Global Search + skill + MM status khác RRR: không kích hoạt cross-branch |
| same | new | Global Search + `job_status` gồm MM và status khác: không cross-branch, giữ branch-scoped behavior |
| same | new | User không có `can_access_all_branches` dù gửi Global Search + MM + RRR + skill: không được cross-branch |
| same | existing/new | Location/client-radius filter vẫn giới hạn candidate sau khi cross-branch được bật |
| same | existing/new | Max receiver gate vẫn trả `operationNotAllowed` khi vượt giới hạn |
| same | existing | Existing exclusion rules: permanent, recent SMS, on-plan, DNU, marketing disagree |

Sau code change phải audit toàn bộ test hiện hữu liên quan SMS/candidate search, chạy affected suites và full `./vendor/bin/phpunit` theo workspace rule.

## 9. Execution Phases & Gates

### Phase 1 — API docs/contract synchronization gate

**Input**: Plan này và behavior đã confirm từ GAP-727.

**Work**: Inspect/update `~/projects/crs-api-docs` as required, validate, commit task docs, push remote `main` nếu docs bị ảnh hưởng.

**Output**: Updated `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/consultant/get-sms-estimate.md` with GAP-727 local/not-deployed query behavior and mixed-status rule. `npm run build` PASS; `git diff --cached --check` PASS; commit `72842ed` pushed successfully to remote `main`.

**Amendment output**: Đã cập nhật `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/consultant/get-sms-estimate.md` để ghi rõ `can_access_all_branches=true` là điều kiện authorization; user không có quyền sẽ giữ branch scope. `npm run build` PASS; `git diff --cached --check` PASS; commit `57d8718` đã push thành công lên remote `main` trước backend code.

**Gate**: PASS — docs commit/push completed before backend code.

### Phase 2 — Backend implementation and verification

**Input**: Phase 1 PASS và quyết định mixed-status đã được confirm: nhiều status không cross-branch; chỉ duy nhất MM mới xét Global Search flow.

**Work**: Implement minimal change, update feature tests, audit call chain and self-check against this plan.

**Output**:

- `SmsServiceInterface`, `SmsService` và `SmsController` đã được cập nhật để chỉ mở rộng candidate scope khi Global Search bật, chỉ có status MM, MM status RRR và có skill; pre-campaign vẫn giữ branch ownership của consultant.
- Thêm 3 Feature tests cho cross-branch hợp lệ, mixed job status và thiếu skill.
- Cập nhật `.business-spec/backend-business-flow-spec.md` với behavior và source evidence của GAP-727.
- Syntax checks (`php -l`) cho các file thay đổi: PASS.
- Affected suite `./vendor/bin/phpunit tests/Feature/Api/Consultant/SmsCampaignTest.php`: PASS — 13 tests, 27 assertions.
- Full suite với `LOG_CHANNEL=single ./vendor/bin/phpunit`: PASS — 616 tests, 9,292 assertions.
- Full suite mặc định hoàn tất 616 tests, 9,279 assertions nhưng có 6 lỗi DNS không liên quan khi gửi Slack tới `hooks.slack.com`; rerun với channel local đã PASS.

**Gate**: PASS — implementation, affected tests và full PHPUnit verification hoàn tất; không chạy formatter/linter tự động.

### Amendment Phase 2 — Authorization gate implementation and verification

**Input**: Security review đã xác nhận thiếu kiểm tra `can_access_all_branches` trong Bulk SMS Global Search.

**Work**:

- Truyền explicit permission từ authenticated user tại `SmsController` vào `SmsService`; không đọc permission từ query string và không inject thêm Service vào Service.
- Chỉ trả empty branch scope khi đồng thời đạt Global Search, quyền cross-branch, chỉ MM, RRR và có skill.
- Khi không có quyền, giữ branch ID từ `Gap-Branch-ID`; không thay đổi flow read-only của `CandidateController` và không sửa authorization ngoài phạm vi GAP-727.
- Bổ sung Feature test chứng minh user không có quyền không thể đưa candidate branch khác vào pre-campaign; giữ các test hợp lệ/mixed-status hiện tại.
- Audit `CandidateCampaign` flow để bảo đảm test chứng minh receiver IDs ngoài branch không đi qua khi permission không đạt.

**Gate**: Docs amendment Phase 1 PASS trước code; syntax checks, affected SMS feature suite và full `LOG_CHANNEL=single ./vendor/bin/phpunit` PASS. Không chạy formatter/linter tự động.

**Amendment output**:

- `SmsServiceInterface`, `SmsService` và `SmsController` đã nhận/truyền permission `can_access_all_branches` từ authenticated user; chỉ user có quyền mới được mở rộng empty branch scope.
- User không có quyền dù gửi `all_branches=true` vẫn bị giới hạn bởi branch header.
- Thêm Feature test unauthorized Global Search; affected suite PASS — 14 tests, 29 assertions.
- Syntax checks (`php -l`) và `git diff --check`: PASS.
- Full suite `LOG_CHANNEL=single ./vendor/bin/phpunit`: PASS — 617 tests, 9,294 assertions.

**Gate**: PASS — docs amendment commit/push hoàn tất trước backend code; authorization fix và verification hoàn tất; không chạy formatter/linter tự động.

## 10. Checklist trước khi Approve

- [x] Mixed job status `MM + status khác` không kích hoạt cross-branch; giữ logic branch hiện tại.
- [x] API docs impact đã được đánh giá; docs Phase 1 PASS hoặc ghi N/A.
- [x] Không đổi DB schema/API response shape.
- [x] Global Search chỉ mở rộng scope khi đủ MM + RRR + skill.
- [x] Branch hiện tại vẫn giữ logic Bulk SMS cũ.
- [x] Max recipient/provider limit vẫn được enforce.
- [x] Test cases và full PHPUnit gate đã được chấp thuận.

## 11. Security amendment checklist

- [x] Đã xác định thiếu authorization check cho cross-branch Bulk SMS.
- [x] API docs amendment mô tả `can_access_all_branches` và đã commit/push trước code.
- [x] Service chỉ mở rộng scope khi authenticated user có quyền cross-branch.
- [x] User không có quyền vẫn bị giới hạn bởi branch header.
- [x] Có Feature test cho unauthorized Global Search và full PHPUnit sau amendment.
