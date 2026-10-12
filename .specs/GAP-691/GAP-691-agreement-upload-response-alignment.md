# SPEC: GAP-691 — Agreement response giống API upload file

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-05
> **Author**: Codex

## 1. Tổng quan

**Yêu cầu gốc**: API lấy/tạo agreement trả response tương tự API upload file.

Phạm vi là endpoint hiện có `POST /api/candidate/me/permanent-intake/work-finder-agreement`, không đổi thành GET vì endpoint tạo PDF và lưu File. Plan này thay thế riêng quyết định success status `200` trong các plan Agreement trước; các quyết định template, mapping, storage và submit/MM giữ nguyên.

### Baseline đã đối chiếu với source

- `PermanentCandidateIntakeController::generateWorkFinderAgreement` đã trả `App\Http\Resources\Api\Candidate\File`, HTTP mặc định `200`.
- `MeFileController::upload` trả cùng resource, refresh File và đặt HTTP `201`.
- Resource hiện trả tám field top-level, không có `data` wrapper; `url` là temporary storage URL.
- Đã đối chiếu ba living-spec canonical với route/controller/service/resource. Không thấy deviation CODE so với mô tả hiện tại; khác biệt HTTP status giữa hai endpoint là contract cần chỉnh theo yêu cầu mới. DATA/CONFIG/EXTERNAL/INFRASTRUCTURE production chưa xác minh và không cần thay đổi cho task này.

## 2. Database Design

N/A: không migration, bảng, field, repository contract hoặc seed mới.

## 3. API Contract

### Endpoint và request

- Giữ `POST /api/candidate/me/permanent-intake/work-finder-agreement` và middleware hiện tại `api, auth:candidateApi, checkCandidateLockEdit`.
- Giữ nguyên `WorkFinderAgreementRequest`: `job_id` required/integer/min:1; `candidate` sometimes/array; title/first_name/middle_name/last_name sometimes/nullable/string/max:255; address sometimes/array; building/street/town_city/county sometimes/nullable/string/max:255; postcode sometimes/nullable/string/max:20; intermediary_name sometimes/nullable/string/max:255.
- Không đổi error response, authorization hay ownership validation hiện tại.

### Success response

HTTP **201 Created**, dùng chính Candidate `File` resource đang dùng ở API upload, không tạo resource riêng.

Các field giữ nguyên: `id`, `type`, `url`, `converted_file_url`, `status`, `original_file_name`, `uploaded_at`, `toe_signed_ip`.

- Response là một File object top-level, không HTML, không wrapper `data`, `success` hay `message`.
- `type` = `File::TYPE_WORK_FINDER_AGREEMENT`; `status` = trạng thái uploaded hiện có; tên file PDF giữ nguyên.
- `url` dùng temporary URL hiện có để FE mở PDF. Không expose storage key thô hoặc đưa nội dung PDF vào JSON.
- Không đổi `converted_file_url` hoặc giá trị/default field chỉ để giống một loại file khác; cùng schema không có nghĩa cùng giá trị.
- FE dùng `id` của File này trong `files[]` khi submit cùng CV. Không đổi submit hoặc thời điểm gửi MM.

## 4. Business Logic và layer applicability

Giữ workflow hiện tại: validate → resolve template → Blade/PDF → upload storage → FileRepository create → Candidate File resource.

Chỉ chỉnh presentation status trong controller. Không tạo Controller/Service/Repository/Exception/DTO mới; không sửa global File resource hay upload API.

Upload có refresh nhưng đó không phải một field của response. Không thêm query Model/refresh vào controller Agreement để sao chép implementation. Kiểm thử xác nhận response khớp File đã lưu và cùng resource; nếu phát hiện field thiếu do DB default, phải cập nhật plan với lookup qua Repository trong Service trước khi triển khai mở rộng đó.

## 5. Data Origin & Call Chain

`routes/candidate.php` → `PermanentCandidateIntakeController::generateWorkFinderAgreement(WorkFinderAgreementRequest)` → `WorkFinderAgreementServiceInterface::generate(auth()->user(), $request->validated())` → `WorkFinderAgreementService` → `FileUtility::buildFileData` → `FileRepositoryInterface::create` → File model → Candidate File resource → JSON.

`id` lấy từ File đã tạo; metadata lấy từ FileUtility/model và default hiện có của resource. URL signed lấy từ storage path trên File qua resource. Không thêm hoặc giả định candidate field mới. Test dùng route production thật, không chỉ instantiate resource với dữ liệu giả.

## 6. Constants

Dùng `Symfony\Component\HttpFoundation\Response::HTTP_CREATED`, không hardcode `201` trong production code. File type/status/name dùng constants đang có; không tạo magic value mới.

## 7. Files cần sửa và implementation phases

### 7.1. Danh sách file thay đổi

| File | Thay đổi dự kiến | Phase |
|------|-----------------|-------|
| `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php` | Chuẩn bị status constant, sau đó trả FileResource với HTTP 201 trong `generateWorkFinderAgreement`; không đổi method khác. | 1 → 2 |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Kiểm tra tám field top-level và metadata File đã lưu; cập nhật assertion HTTP 201 và regression response Agreement. | 1 → 2 |
| `documents/Gap-API-Candidate.yaml` | Đổi success response Agreement từ 200 sang 201; bảo đảm mô tả/schema endpoint dùng File resource, không HTML hoặc wrapper. | 2 |
| `.business-spec/backend-business-flow-spec.md` | Ghi nhận Agreement generation trả File resource với HTTP 201 trong SPEC-039. | 2 |
| `.specs/GAP-691/GAP-691-agreement-upload-response-alignment.md` | Ghi kết quả từng phase, test gates và trạng thái thực hiện. | 1 → 2 |

**File mới/xóa**: không tạo hoặc xóa file implementation. Không sửa `MeFileController`, global Candidate `File` resource, Request, Service, Repository, routes, template, config hay migration trong scope này.

### 7.2. Implementation phases và ownership

Chỉ một owner Codex, thực hiện tuần tự; giữ nguyên các dirty changes khác trong workspace.

#### Phase 1 — Skeleton / response integration boundary

- **Input**: plan được approve, controller/request/service/resource hiện có.
- **Files owned**: `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php`; `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`.
- **Implementation**: chuẩn bị import HTTP status constant; ghi `// TODO[GAP-691-P2]: Align agreement success status with file upload (HTTP_CREATED).` tại boundary hiện có. Bổ sung assertion tám field top-level/no HTML/no wrapper trên feature test generate hiện có, kiểm tra metadata từ File thực sự lưu. Chưa đổi status ở phase này.
- **Output**: boundary compile-valid, schema regression test xanh; giữ response thực tế hiện có, không fake success hoặc tạo endpoint chưa implement.
- **Contracts frozen**: route, request validation, handler signature/return FileResource, service contract, tám field/schema và target HTTP 201 đã chốt trong plan.
- **Dependencies**: không migration/binding mới; dùng các layer hiện có.
- **Acceptance/test gate**: PHP syntax check cho hai file; feature test generate/config pass bằng `LOG_CHANNEL=single ./vendor/bin/phpunit` với filter phù hợp. Chỉ bắt đầu Phase 2 khi gate pass.

#### Phase 2 — Activate aligned response, docs và regression

- **Input**: Phase 1 pass và contracts đã freeze.
- **Files owned**: controller và feature test trên; `documents/Gap-API-Candidate.yaml`; `.business-spec/backend-business-flow-spec.md`; plan này.
- **Implementation**: trả FileResource với `withStatus(Response::HTTP_CREATED)`; xóa TODO P2; đổi assertion generate thành 201, kiểm tra cùng schema resource upload và URL dùng được theo storage test fixture. Cập nhật success response của endpoint từ 200 sang 201 trong OpenAPI; nếu ví dụ/schema riêng endpoint còn HTML hoặc wrapper thì sửa đúng contract File. Ghi HTTP 201 trong living flow.
- **Output**: response Agreement cùng File resource và success HTTP status với upload; docs/tests phản ánh contract thực tế.
- **Dependencies**: Phase 1; không thay đổi generate storage/MM hoặc submit validation.
- **Acceptance/test gate**: audit existing generate/config/submit, File upload/resource và WorkFinderAgreementService tests; bổ sung/cập nhật tests bị ảnh hưởng, chạy affected suites và full `LOG_CHANNEL=single ./vendor/bin/phpunit`. Kiểm tra YAML và scoped diff. Không chạy formatter/linter tự động. Không sửa test hoặc code ngoài scope nếu suite có lỗi không liên quan; báo rõ blocker.

## 8. Test Cases và self-check

- Generate thành công: HTTP 201; đủ tám field cùng File resource; không HTML/data wrapper.
- `id`, `type`, `status`, filename và uploaded metadata tương ứng File được lưu; PDF tồn tại trên storage; signed URL không phải storage key thô.
- Request validation/ownership/error responses giữ nguyên; config không quay lại trả agreement_url/HTML.
- Generate không gọi MM; submit vẫn chọn agreement File ID và CV như contract hiện có.
- Không thêm repository unit tests. Không đổi upload/global resource để đạt test.
- Sau hai phase, đối chiếu diff với plan, syntax, affected tests, full suite và docs trước khi đánh dấu DONE.

## 9. Approval

- [x] Baseline/call chain đã đối chiếu.
- [x] Scope, contract, constants, hai phase và gates đã xác định.
- [x] User approve trước khi sửa production code hoặc tests (2026-10-05).

## 10. Execution record

- Phase 1 PASS: controller/test PHP syntax checks; generate/config feature gate `2 tests, 23 assertions`. Đã xác nhận metadata response từ File lưu thực tế; không cần thêm refresh/query vào controller hoặc Service.
- Phase 2 PASS: activate HTTP_CREATED, thêm response comparison test với CV upload, cập nhật OpenAPI và living-spec. Đã audit `PermanentCandidateIntakeTest`, `MeFileTest`, `PermanentCandidateIntakeServiceTest`, `MatchMakerPermanentSyncTest`, `SyncPermanentCandidateToMatchMakerJobTest`, `FileServiceTest`, `FileUtilityTest`; chưa có standalone WorkFinderAgreementService test, generation được bao phủ qua feature route/service thật. Không sửa repository unit tests.
- Affected test suites PASS: `42 tests, 349 assertions` qua regex filter các class đã audit.
- Full `LOG_CHANNEL=single ./vendor/bin/phpunit` PASS: `524 tests, 2433 assertions` (01:44.694). Thông báo unknown legal_entity_id `999999` là output của existing negative seeder test, không phải failure.
- PHP syntax checks, Ruby YAML parse/status/schema/example checks và scoped `git diff --check` PASS. Không chạy formatter/linter.
- Self-check PASS: chỉ method generate đổi production behavior; cùng File resource tám field, URL/storage PDF và persisted metadata được xác nhận qua route thật; không thêm query, refresh, migration, public contract hay MM side effect. Giữ nguyên dirty changes khác của user và route/request/service/template/submit.
