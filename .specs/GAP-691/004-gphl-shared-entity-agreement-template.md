# SPEC: GAP-691 — Shared GPHL renderer for entity Work Finder Agreements

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-07
> **Author**: Codex
> **Related**: [003-driving-personnel-agreement-templates.md](003-driving-personnel-agreement-templates.md)

---

## 1. Tổng quan

Thay đổi riêng cách dùng Blade chung cho nhóm Work Finder Agreement: bỏ `legal_entity.blade.php`, dùng `gphl.blade.php` làm renderer chung và để `tech.blade.php`, `personnel.blade.php`, `driving.blade.php` truyền logo footer vào view này. Giữ nguyên toàn bộ pipeline và contract hiện tại ngoài phạm vi Blade.

**Yêu cầu gốc**: User muốn cập nhật GAP-691 để các Blade Tech/Personnel/Driving truyền logo vào footer của `gphl.blade.php` và bỏ `legal_entity.blade.php`.

**Giới hạn scope**: Plan này không port baseline, không bổ sung entity mapping, không thêm/chỉnh asset PNG và không thay đổi config/service/API/DB. Nếu một Blade mục tiêu không tồn tại ở thời điểm implementation, phải báo lại thay vì mở rộng scope sang các commit khác.

**Quyết định cần user xác nhận khi approve**: Cụm “dùng `gphl` thay cho `legal_entity`” được hiểu là ba wrapper sẽ kế thừa toàn bộ body/layout wording hiện tại của `gphl.blade.php`; wrapper chỉ cung cấp logo footer. Nếu cần giữ wording Tech cũ trong một renderer khác, phải sửa plan trước khi implementation.

## 2. Database Design

N/A: không tạo/sửa migration, bảng, cột, index, foreign key hoặc quan hệ Eloquent.

## 3. API Contract

N/A về public contract: không thêm/sửa route, HTTP method, middleware, FormRequest validation, DTO, Resource, response status hoặc error payload.

Endpoint hiện hữu giữ nguyên:

```http
POST /api/candidate/me/permanent-intake/work-finder-agreement
```

Service vẫn nhận payload đã validate và trả `File`; thay đổi chỉ nằm ở template resolution output/presentation footer.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

```text
Candidate request
  → PermanentCandidateIntakeController::generateWorkFinderAgreement
  → WorkFinderAgreementRequest::validated()
  → PermanentCandidateIntakeService::generateWorkFinderAgreement
  → verify owned candidate/job and resolve Job → Branch → legal_entity
  → resolveTemplate(): branch mapping wins over legal_entity mapping
  → buildAgreementData() → WorkFinderAgreementData::toArray()
  → render selected entry Blade
  → entry Blade includes gphl.blade.php and supplies static logo descriptors
  → Dompdf → storage → File repository/resource
```

### 4.2. Business Rules

- `gphl.blade.php` là renderer dùng chung cho entry views `tech`, `personnel` và `driving`; không copy lại legal markup/CSS vào từng wrapper.
- `gphl.blade.php` phải giữ fallback logo GPHL hiện tại khi service render trực tiếp view `pdf.work_finder_agreements.gphl` từ branch mapping và không truyền `$logos`.
- `tech.blade.php` truyền hai logo `gap-technical-logo.png` và `gap-construction-logo.png`; `personnel.blade.php` truyền một `gap-personnel-logo.png`; `driving.blade.php` truyền một `driving-force-logo.png`.
- Logo chỉ được lấy từ resource path tĩnh trong code. Không nhận file path, URL, alt text hoặc brand selector từ HTTP payload, DTO, database hay user input.
- Không thay đổi config mapping entity/branch hoặc quy tắc resolve template; các view entry hiện hữu tiếp tục được service chọn như hiện tại.
- Không tạo hoặc giữ runtime reference tới `pdf.work_finder_agreements.legal_entity`; view cũ không được resolve nhầm.
- Thiếu/hỏng PNG phải dùng `APIErrorException` và error constants hiện hữu của `PermanentCandidateIntakeService`; không tạo file/storage artifact không hoàn chỉnh.
- Giữ nguyên candidate fields, date/signature behavior, legal content của renderer được chọn, PDF pagination, response/File contract và không gọi MatchMaker trong bước generate agreement.

### 4.3. Side Effects

Không có side effect mới. Side effect hiện hữu vẫn là tạo PDF tạm, upload storage và tạo metadata `files` type `work_finder_agreement`; cleanup khi generation/persistence lỗi phải giữ nguyên.

## 5. Data Origin & Call Chain

```text
routes/candidate.php: POST /permanent-intake/work-finder-agreement
  → App\Http\Controllers\Api\Candidate\PermanentCandidateIntakeController::generateWorkFinderAgreement
    → WorkFinderAgreementRequest::validated()
    → App\Services\PermanentCandidateIntakeService::generateWorkFinderAgreement($candidate, $data)
      → getOwnedCandidateJob($candidate->id, $data['job_id'])
      → JobRepository::find(job_id)
      → BranchRepository::find(job.branch_id)
      → resolveTemplate($branch)
      → buildAgreementData($candidate, address, $data)
      → WorkFinderAgreementData::toArray()
      → view($view, $agreementData)
      → Blade/Dompdf/storage/File resource
```

| Biến / key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$data['job_id']` | Service ownership/template resolution | `WorkFinderAgreementRequest::validated()` | ✅ |
| `$data['candidate']` | `buildAgreementData()` draft fields | FormRequest validated nested input, nullable/missing keys handled by service | ✅ |
| `$data['intermediary_name']` | `WorkFinderAgreementData` | FormRequest validated input, default empty string in service | ✅ |
| `$worker_name`, `$worker_address`, `$signature`, `$printed_name`, `$date` | GPHL/entry Blade body | `WorkFinderAgreementData::toArray()` | ✅ |
| `$logos` | GPHL footer | Static descriptors passed by Tech/Personnel/Driving wrapper; static GPHL fallback when direct view has no key | ✅ |
| `$singleLogo` / layout mode | GPHL footer CSS/markup | Static wrapper presentation value with safe fallback | ✅ |

Logo descriptors are not part of the request or DTO contract. The view must use an explicit fallback for direct GPHL rendering rather than assuming the service supplies new keys.

## 6. Constants & Enums

Không thêm business constants hoặc enum. Tái sử dụng:

- `PermanentCandidateIntakeService::ERROR_GENERATION_FAILED`.
- `PermanentCandidateIntakeService::MESSAGE_GENERATION_FAILED`.
- `PermanentCandidateIntakeService::ERROR_TEMPLATE_NOT_FOUND` và message hiện hữu.
- Existing `File::TYPE_WORK_FINDER_AGREEMENT`.

View names, resource asset paths, alt text và CSS dimensions là presentation literals của config/Blade; không đưa vào Model/Service constants nếu không được dùng ngoài renderer.

## 7. Files cần tạo/sửa

### 7.1. Files thuộc scope Blade

| File | Namespace | Mô tả |
|------|-----------|-------|
| `resources/views/pdf/work_finder_agreements/personnel.blade.php` | — | Cập nhật wrapper hiện hữu để truyền một logo Personnel vào GPHL renderer. |
| `resources/views/pdf/work_finder_agreements/driving.blade.php` | — | Cập nhật wrapper hiện hữu để truyền một logo Driving vào GPHL renderer. |

### 7.2. Files sửa/xóa

| File | Thay đổi |
|------|----------|
| `resources/views/pdf/work_finder_agreements/gphl.blade.php` | Nhận logo descriptors từ wrapper, fallback logo GPHL khi render trực tiếp, validate/decode PNG và render single/multi footer đúng aspect ratio; giữ GPHL body/layout. |
| `resources/views/pdf/work_finder_agreements/tech.blade.php` | Chuyển từ full document sang entry wrapper include GPHL với hai logo Tech/Construction. |
| `resources/views/pdf/work_finder_agreements/legal_entity.blade.php` | Không tạo file này; nếu baseline port tạo ra file thì xóa và bỏ mọi include/reference. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Chỉ audit/update assertion liên quan đến Blade include, logo footer, view legacy và PDF render nếu bị ảnh hưởng trực tiếp. |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Chỉ cập nhật assertion render nếu output Blade dùng trong test bị ảnh hưởng trực tiếp; giữ nguyên test service contract. |

Không sửa config mapping, Controller, FormRequest, DTO, Resource, Repository, Service implementation, route, migration, business-spec hoặc image assets.

## 8. Test Cases

| Test File | Test Method/Scope | Mô tả |
|-----------|-------------------|-------|
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Entry template rendering datasets | Render các entry Blade liên quan qua caller hiện tại; xác nhận wrapper include GPHL, đúng logo footer, footer repeated và PDF hợp lệ. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Legacy view location/reference assertion | Xác nhận `legal_entity.blade.php` và view namespace cũ không tồn tại/không được gọi. |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Existing agreement generation/date/ownership tests | Đảm bảo Blade refactor không làm lệch DTO data origin, current date, ownership guard hoặc service contract. |
| `./vendor/bin/phpunit` | Full suite | Chạy sau các affected suites; yêu cầu 100% passing trước khi hoàn tất. |

## 9. Checklist trước khi Approve

- [x] Đã xác nhận `gphl.blade.php` là renderer chung và Tech/Personnel/Driving kế thừa body/layout GPHL.
- [x] Không có database/schema/API contract change.
- [x] Call chain và nguồn của mọi Blade variable đã được trace.
- [x] Config mapping, branch priority và business logic ngoài Blade không bị thay đổi.
- [x] `legal_entity.blade.php` không còn trong runtime scope.
- [x] Logo path/validation và fallback direct-GPHL đã được định nghĩa trên view hiện hữu, không thêm asset mới.
- [x] Test impact và test cases chỉ bao phủ wrapper, PDF, logo và legacy reference removal.
- [x] Đã thống nhất chỉ implementation sau khi user approve plan này.

## 10. Approval

User đã approve plan ngày 2026-10-07 trước khi implementation.

## 11. Execution / self-check — 2026-10-07

- `gphl.blade.php` hiện nhận logo descriptors từ wrapper, fallback về logo GPHL khi render trực tiếp, validate/decode PNG và hỗ trợ single/multi-logo footer.
- `tech.blade.php`, `personnel.blade.php` và `driving.blade.php` đều include `gphl.blade.php` và truyền logo tĩnh tương ứng; `legal_entity.blade.php` đã được xóa.
- Chỉ cập nhật các assertion test bị ảnh hưởng trực tiếp bởi renderer GPHL dùng chung và việc loại bỏ view legacy. Không sửa config mapping, Service, Controller, DTO, API, DB hoặc image assets.
- Feature suite: **82 tests / 6,921 assertions PASS**.
- Service suite: **12 tests / 140 assertions PASS**.
- Full suite: **602 tests / 9,295 assertions PASS**.
- `git diff --check` PASS; không chạy formatter/linter/migration.

## 12. Follow-up — align tests with current user-edited mapping and Tech logo

**Trạng thái**: `DONE` — user đã approve và test alignment đã được triển khai, kiểm chứng.

### 12.1. Context

Sau implementation, user đã chỉnh runtime ngoài scope test hiện tại:

- `config/work_finder_agreement.php` chỉ còn branch mapping Hawk3 và legal entity mapping Personnel cho `1, 2, 4, 5, 6, 8`; các mapping GPHL branch, Tech entity `3` và Driving entity `7` đã bị bỏ.
- `tech.blade.php` hiện truyền một logo `gap-technical-logo.png` với `singleLogo => true`; không còn logo Construction.

Full PHPUnit trước follow-up: **602 tests / 8,645 assertions / 18 failures**. Các failure tập trung ở expectation mapping cũ và expectation Tech có hai logo.

### 12.2. Scope

Chỉ cập nhật test để phản ánh đúng runtime đang có. Không sửa lại config, Blade, Service, Controller, DTO, API, DB, assets hoặc các thay đổi unrelated của working tree.

### 12.3. Test changes

- Cập nhật production mapping assertions theo config hiện tại.
- Cập nhật default-mapping/negative-mapping datasets để cover entity/branch còn được map và lỗi template-not-found cho mapping đã bị bỏ.
- Cập nhật logo metadata, layout assertions và missing/corrupt asset cases của Tech theo single-logo `gap-technical-logo.png`.
- Giữ coverage cho Personnel, Driving, GPHL direct fallback, PDF generation, response contract và service date/ownership behavior.

### 12.4. Verification gate

- Chạy `PermanentCandidateIntakeTest`.
- Chạy `PermanentCandidateIntakeServiceTest`.
- Chạy full `./vendor/bin/phpunit` và yêu cầu 100% pass.
- Chạy `git diff --check`; không formatter/linter/migration.

### 12.5. Kết quả

- Đã cập nhật `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` theo mapping hiện tại và Tech single-logo.
- Feature suite: **75 tests / 6,682 assertions PASS**.
- Service suite: **12 tests / 140 assertions PASS**.
- Full suite: **595 tests / 9,056 assertions PASS**.
- `git diff --check` PASS; không chạy formatter/linter/migration.
