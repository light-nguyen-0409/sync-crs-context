# SPEC: GAP-691 — Driving / Personnel Work Finder Agreement templates

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-07
> **Related**: [002-css-letterhead-rendering.md](002-css-letterhead-rendering.md)

## 1. Tổng quan

Theo yêu cầu mới, tạo `driving.blade.php` và `personnel.blade.php` dựa trên Tech hiện tại, dùng một logo tương ứng. Dùng Blade chung `legal_entity.blade.php` cho các legal entity để tránh copy toàn bộ CSS, wording, candidate fields và Appendix. Đây là scope thêm hai template độc lập với các thay đổi letterhead đã triển khai trong plan 002.

Yêu cầu trực tiếp clone Tech là baseline của task này; không tự áp dụng đề xuất wording GPHL/Umbrella của trao đổi trước, không tự đổi tên công ty, company number, privacy URL hoặc legal terms khi chưa có nội dung thay thế được yêu cầu.

## 2. Database Design

N/A: không migrations, schema hoặc data changes.

## 3. API Contract

Giữ endpoint generation, FormRequest, DTO, HTTP 200/File resource và error contract hiện tại. Theo bổ sung của user, cập nhật `config/work_finder_agreement.php`: entities `1, 2, 4, 5, 6, 8` → `pdf.work_finder_agreements.personnel`; entity `7` → `pdf.work_finder_agreements.driving`; entity `3` giữ `pdf.work_finder_agreements.tech`. Branch overrides hiện hữu vẫn ưu tiên hơn entity fallback.

## 4. Thiết kế template

- Extract Tech document vào `legal_entity.blade.php` cùng thư mục; đây là markup/CSS dùng chung cho các legal entity, không chứa quyết định chọn legal entity.
- `tech.blade.php` là entry wrapper include `pdf.work_finder_agreements.legal_entity` và truyền branding rõ ràng, giữ hai logo Tech/Construction hiện tại.
- `driving.blade.php` truyền đúng một logo `storage_path('logos/driving_force_thumbnail.png')`.
- `personnel.blade.php` truyền đúng một logo `storage_path('logos/gap_personnel_thumbnail.png')`.
- Logo được đọc local và nhúng data URI như pipeline hiện tại; giữ PNG validation/custom APIErrorException khi asset thiếu/hỏng.
- Blade `legal_entity` xử lý một/hai logo qua cấu hình wrapper; một logo nằm ở footer, giữ aspect ratio và nằm trong safe area, không để ô/logo thứ hai rỗng.
- Follow-up theo yêu cầu user: PNG Driving/Personnel phải giữ nền trong suốt; không đặt nền trắng bằng CSS cho ảnh logo đơn. Quyết định nền trắng khi preview ban đầu được thay thế bởi yêu cầu này; giữ màu header/footer và asset gốc.
- Giữ layout, màu, text, Via, date, signature và Appendix của Tech. Tên file Personnel không đồng nghĩa thay mẫu GPHL hiện hữu.
- Không thêm Controller/Service/Repository mới cho task Blade. Chủ sở hữu duy nhất Codex, thực hiện tuần tự.

## 5. Data Origin & Call Chain

`PermanentCandidateIntakeController::generateWorkFinderAgreement` → validated request → `PermanentCandidateIntakeService::generateWorkFinderAgreement` → owned candidate job/job/branch lookup → `resolveTemplate` → `buildAgreementData` → `WorkFinderAgreementData::toArray()` → Blade/Dompdf → storage/File resource.

DTO cung cấp `worker_name`, `worker_address`, `intermediary_name`, `signature`, `printed_name`, `date`, `title`; include `legal_entity.blade.php` kế thừa dữ liệu đó. Branding/logo descriptors chỉ do entry wrapper cung cấp, không nhận path từ request. Không giả định thêm runtime keys.

## 6. Constants & Enums

Tái sử dụng lỗi generation hiện hữu của PermanentCandidateIntakeService. Asset descriptors là cấu hình trình bày tĩnh trong wrapper Blade; test IDs/logo metadata khai báo constants theo convention hiện tại khi cần.

## 7. Files

- Tạo `resources/views/pdf/work_finder_agreements/{legal_entity,driving,personnel}.blade.php`.
- Sửa đúng `tech.blade.php` để include `pdf.work_finder_agreements.legal_entity`; Driving và Personnel cũng include view này.
- Sửa `config/work_finder_agreement.php` theo mapping entity tại mục 3, giữ branch overrides.
- Audit/update `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` và Service tests bị ảnh hưởng bởi view extraction/mapping. Thay expectations "entity 3 only" và unmapped entities 1/2/4–7 từ task trước bằng mapping mới; giữ negative coverage bằng entity thực sự không mapped.
- Sau implementation cập nhật SPEC-039 trong `.business-spec/backend-business-flow-spec.md` với template/Blade chung legal_entity/logo/mapping facts đã xác minh. Không thay GPHL/Hawk3, DTO hay routes.

## 8. Verification / acceptance

- Tech regression: markup/legal content, hai logo, candidate escaping, blank/long Via, date, pagination và PDF/File generation giữ nguyên.
- Driving/Personnel: render qua actual service caller với config override; mỗi mẫu đúng một PNG tương ứng, không có Tech/Construction logo; PDF hợp lệ, ownership và response đúng contract.
- Production mapping assertion bao phủ đủ entity IDs 1–8; integration tests dùng config thật để verify Personnel cho 1/2/4/5/6/8, Driving cho 7 và Tech cho 3. Branch override vẫn thắng entity mapping; unmapped branch + unmapped entity vẫn lỗi template-not-found và không writes/MM.
- Missing/corrupt single-logo asset: lỗi generation, không tạo File/storage artifact; dùng fixture isolation để không sửa asset thật.
- Audit các view-location, logo-count/metadata và legal-content assertions trước khi cập nhật; không giảm coverage để che regression.
- Chạy tuần tự affected Feature và Service suites bằng `./vendor/bin/phpunit`, review PDF preview của hai mẫu mới; không formatter/linter.
- Self-check so với scope này; mọi lỗi ngoài scope báo riêng, không tự sửa unrelated methods/user changes.

## 9. Approval

User đã approve ngày 2026-10-07 sau khi bổ sung entity mapping và đổi tên Blade chung thành `legal_entity.blade.php`. PNG Driving 300×73 và Personnel 300×42; footer render width 240px, height auto để giữ aspect ratio.


## 10. Execution / self-check — 2026-10-07

- Implemented three entry wrappers + common `legal_entity.blade.php`, entity mappings 1–8 and single-logo PNG validation. Tech body/candidate fields/Appendix byte-identical to original HEAD body; two-logo geometry preserved. New single-logo white background was selected after visual review because supplied transparent PNGs have dark text.
- Test impact audit: existing default-mapping/negative entity expectations updated; view-location, real logo bytes/count, real PDF images, branch priority across Personnel/Driving entities, one-logo fixed-footer geometry/repetition and missing/corrupt storage PNG cleanup covered. Existing Service date/ownership/missing-view and Tech Via/Unicode/long-field tests remain passing. No Repository tests, extra runtime layers, migrations, formatter or unrelated changes.
- Final serial affected suites: Feature **82 tests / 7,952 assertions PASS**, Service **12 tests / 137 assertions PASS**; combined **94 tests / 8,089 assertions**. `git diff --check` pass. Full suite not run: task has no phases; scoped affected gates completed.
- Local sample PDFs generated via production `buildAgreementData` on unsaved sample Candidate and actual Blade/Dompdf: Tech, Driving, Personnel each 2 pages. PDFKit raster previews reviewed for Driving/Personnel first pages and Driving Appendix; text/logos visible, one logo, footer safe area, no stretching/overlap. Additional samples at `/private/tmp/gap-691-entity-agreements/`; no external MM/storage/network calls for previews. First Swift preview failed on sandbox cache path; retry with temporary module cache succeeded.
- Updated canonical SPEC-039 with current template/asset/mapping behavior; historical mappings below it marked superseded. No API/schema change; deployment/config cache/production behavior not verified.

## 11. Follow-up — transparent single-logo background

**Status**: DONE — user approved follow-up, implemented 2026-10-07; mục 10 giữ evidence lịch sử.

- Root cause CODE: `.single-logo .brand-logo` trong `legal_entity.blade.php` có `background-color: #FFFFFF`, làm vùng ảnh có nền trắng dù PNG alpha trong suốt. Đây là CSS do Codex thêm khi review preview, không phải lỗi asset.
- Fix tối thiểu: bỏ đúng declaration `background-color: #FFFFFF`; giữ width, height auto, vị trí, ảnh gốc và mapping.
- Test impact: thêm assertion nền image trong suốt vào existing single-logo layout datasets Driving/Personnel, giữ asset-byte/aspect-ratio/repetition checks. Chạy affected Feature và Service suites tuần tự; review lại preview PDF.
- Sau fix cập nhật SPEC-039 bỏ mô tả nền trắng, ghi verification tại mục này. Không regenerate PDF/File đã lưu; PDF generation mới dùng CSS đã sửa.

- Follow-up verification: removed only the single-logo white-background declaration; added computed-image-background `transparent` assertions to existing Driving/Personnel layout datasets (source/forced extra page). Final serial Feature **82 tests / 7,962 assertions PASS**, Service **12 tests / 137 assertions PASS**, combined **94 / 8,099 PASS**. PDFKit previews of fresh Driving/Personnel PDFs confirm no white rectangle; aspect ratio/footer position unchanged. Canonical SPEC-039 updated; `git diff --check` passed. Existing stored PDFs unchanged; no original PNG edits.

## 12. Follow-up — white PNG logo assets only

**Status**: DONE — user approved asset-only scope và trực tiếp đồng ý xử lý ảnh/render font thay imagegen sau khi preview bị lỗi alpha.

### Scope hiện hành

Chỉ tạo thêm hai file PNG vào `resources/images/work_finder_agreements/`:

- `gap-personnel-logo.png`: biểu tượng người trắng bên trái + `gappersonnel` trắng; `gap` đậm, `personnel` mảnh; không có `group`.
- `driving-force-logo.png`: `driving force` trắng, `driving` đậm và `force` mảnh; `recruitment` nhỏ, đậm, canh phải bên dưới; không có biểu tượng người.

Cả hai có nền alpha trong suốt, không khung/nền trắng hoặc navy. Tỷ lệ ngang, nét chữ và spacing theo reference Construction/Personnel Group đã xem. Reference local: `gap-construction-logo.png`, `gap-personnel-group-logo.png` trong cùng thư mục. File reference Construction tồn tại trong workspace dù UI báo lỗi relative path.

### Phương án tạo và kiểm tra

- Dùng image generation/edit capability với reference local để tạo bitmap PNG đúng yêu cầu, output transparent_background=true; kiểm tra exact text, emblem chỉ ở Personnel, subline chỉ ở Driving, trắng trên nền navy.
- Chỉ đưa hai PNG final vào thư mục đã chỉ định; artifacts trung gian/preview đặt ngoài repo. Không ghi đè PNG hiện có. Nếu chưa đúng text/shape/transparency, iterate trước khi bàn giao.
- Verify PNG decode, kích thước, alpha trong suốt và preview trên nền navy; không thêm test code hay chạy PHPUnit vì không thay runtime/code/contracts hoặc asset đang được runtime tham chiếu.
- Không sửa Blade, config mapping, tests, Service, DTO hoặc living business spec: task này chỉ tạo assets chưa được tích hợp. Không tự chuyển các template sang đọc hai PNG mới.
- Thay thế toàn bộ phương án HTML/CSS/viewport emblem và test/runtime changes từng đề xuất ở mục 12 trước khi thu hẹp scope. Các mục 10/11 giữ lịch sử triển khai đã hoàn tất.


### Asset-only execution — 2026-10-07

- Built-in imagegen tried Personnel edit + clean retry and Driving generation; rejected all three outputs for alpha/outline artifacts. User explicitly approved direct image processing/rendering through async question before switching approach.
- Personnel: PHP GD crops rows 0–123 from existing Personnel Group logo. Final `gap-personnel-logo.png` **788×124**, **14,808 bytes**; all pixels byte-value-equivalent to source crop, retaining exact human emblem and bold/light main wordmark. Only group subline excluded.
- Driving: AppKit/HelveticaNeue-Bold + HelveticaNeue-Light main line, HelveticaNeue-Bold smaller recruitment subline, pure white text on alpha canvas, 2× raster render. Trimmed with GD to **1293×317**, **26,025 bytes**, 6px alpha padding. No emblem, subline aligned right. Final `driving-force-logo.png`.
- PNG decode/alpha/antialias checks pass; Personnel has 71,881 fully transparent pixels, Driving 314,876; previews on #2A2B4F navy reviewed, no opaque background, no clipping/noise, exact text and readable contrast. Temporary generators/previews live at `/private/tmp/gap-691-logo-assets/`; failed imagegen outputs remain outside repo.
- Only two new PNG assets added in requested directory. No Blade/config/tests/runtime/living-spec edits for this asset-only scope. PHPUnit not run because no code or runtime dependency changed; original assets unchanged. New PNGs are not yet referenced by runtime templates.

## 13. Follow-up — tests for resource PNG integration

**Status**: DONE — user approved ngày 2026-10-07, implementation và affected test gates hoàn tất.

User đã đổi Personnel/Driving wrappers sang `resource_path('images/work_finder_agreements/gap-personnel-logo.png')` và `resource_path('images/work_finder_agreements/driving-force-logo.png')`, yêu cầu cập nhật tests. Scope này là test alignment cho runtime edits của user, không đổi lại Blade/config hoặc PNG.

### Root cause / baseline

Existing `SINGLE_AGREEMENT_LOGOS`, byte-comparison helper và missing/corrupt fixtures còn dùng storage thumbnail cũ. Focused gate vừa chạy: **44 tests / 5,615 assertions / 11 failures**, chủ yếu byte mismatch. Missing/corrupt single-logo cases có thể pass nhầm vì fixture thiếu asset mới thay vì cố ý corrupt đúng asset.

### Changes

- Chỉ sửa `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`.
- Metadata: Driving `driving-force-logo.png`, native 1293×317, rendered 240×(240×317/1293) ≈ 58.84px; Personnel `gap-personnel-logo.png`, native 788×124, rendered 240×(240×124/788) ≈ 37.77px. Giữ alt text, width, transparent background assertions.
- `assertAgreementLogoImages` đọc tất cả agreement PNG từ resources, so byte actual image với đúng file mới. Dùng digest comparison nếu cần để thất bại không dump binary PNG ra log, vẫn bảo đảm exact bytes qua SHA-256.
- Fixture missing/corrupt: copy cả existing branding assets và hai PNG mới vào temporary resources directory; sửa đúng target file ở đó. Loại bỏ fixture storage path/mutation chỉ phục vụ thumbnail cũ; giữ isolation, restore basePath và cleanup.
- Audit affected default mapping, single-logo repeated-footer geometry, logo-byte/count và invalid asset tests; giữ Tech/GPHL/Hawk3 coverage, entity mapping expectations và Service contract.

### Verification / documentation

- Chạy tuần tự toàn bộ `PermanentCandidateIntakeTest` và `PermanentCandidateIntakeServiceTest`; yêu cầu pass cả hai, `git diff --check`, không formatter/linter.
- Sau verification cập nhật SPEC-039 resource asset references của user để living spec không còn mô tả storage thumbnails; không thay API/route/schema.
- Record final evidence/self-check tại mục này. Không sửa unrelated runtime/user changes hoặc chạy migrations.


### Resource logo test alignment — execution / self-check

- Updated only Feature test code: two resource PNG names/rendered aspect-ratio expectations; resource-based byte digest checks with strict base64 decode; unified missing/corrupt fixtures copy all seven logo assets into temporary resources directory, mutate correct new PNGs, restore only basePath, clean up.
- Preserved exact alt/count/transparent background/footer geometry/branch priority/mapping expectations; no runtime Blade/config/PNG edits. Existing failure datasets now operate on correct assets rather than missing unrelated resource references.
- Full affected Feature **82 tests / 8,011 assertions PASS**, Service **12 tests / 137 assertions PASS**, run sequentially; total **94 tests / 8,148 assertions PASS**. `git diff --check` pass. No formatter/linter or migrations; full project suite not run for scoped test alignment.
- Canonical SPEC-039 corrected from storage thumbnails to white resource PNGs, actual rendered heights, emblem/subline facts. API/schema contracts unchanged; deployment not verified.

## 14. Follow-up — dùng `gphl.blade.php` thay cho `legal_entity.blade.php`

**Trạng thái**: `DRAFT` — chờ user review/approve trước khi sửa code.

### 14.1. Baseline và phạm vi

Yêu cầu mới là cập nhật tiếp GAP-691: không dùng Blade chung `legal_entity.blade.php`; `tech.blade.php`, `personnel.blade.php` và `driving.blade.php` sẽ truyền danh sách logo tĩnh vào `gphl.blade.php` để render footer chung.

Workspace hiện đang ở `develop` tại parent của commit `0c895eaf` (commit #691 bổ sung mapping entity/personnel/driving). Vì vậy source hiện tại chưa có các wrapper `personnel`/`driving`, chưa có mapping entity 1–8 và chưa có hai PNG logo single-brand dù các quyết định/asset này đã được ghi trong các mục trước. Khi thực thi, sẽ port đúng phần baseline còn thiếu của GAP-691 và áp dụng refactor mới trong cùng scope; không checkout/reset hoặc ghi đè các thay đổi không liên quan của working tree.

Theo cách hiểu hiện tại của câu “dùng `gphl` thay cho `legal_entity`”, toàn bộ renderer dùng chung (bao gồm wording/layout GPHL hiện có) sẽ nằm ở `gphl.blade.php`; ba wrapper chỉ chọn logo footer. Như vậy Tech/Personnel/Driving sẽ kế thừa nội dung GPHL. Nếu chỉ muốn đổi tên include nhưng vẫn giữ nguyên wording Tech trong `legal_entity`, cần điều chỉnh plan này trước khi approve.

### 14.2. Thiết kế và data origin

- Mở rộng `gphl.blade.php` nhận `$logos` và cờ layout single/multi từ các wrapper. Khi service render trực tiếp view GPHL theo branch mapping, Blade dùng fallback logo GPHL tĩnh hiện tại; không giả định service truyền thêm key mới.
- Giữ validation PNG hiện hữu: đọc file local từ `resource_path`, kiểm tra decode/type và ném `APIErrorException` generation hiện tại nếu asset thiếu/hỏng. Không nhận path/logo từ HTTP payload, DTO hoặc database.
- `tech.blade.php` include `pdf.work_finder_agreements.gphl` với hai resource logo Tech/Construction; `personnel.blade.php` và `driving.blade.php` include cùng view với một resource logo tương ứng. Không tạo lại hoặc copy toàn bộ legal markup giữa các wrapper.
- Không tạo hoặc giữ runtime reference tới `pdf.work_finder_agreements.legal_entity`; nếu file này xuất hiện khi port baseline thì xóa file và cập nhật test assert view cũ không tồn tại.
- Giữ thứ tự resolve branch override → legal entity fallback trong `PermanentCandidateIntakeService`; giữ HTTP/File/DTO/route, DB schema, storage workflow và MatchMaker workflow nguyên trạng.

Call chain đã xác minh:

```text
routes/candidate.php
  → PermanentCandidateIntakeController::generateWorkFinderAgreement
    → WorkFinderAgreementRequest::validated()
    → PermanentCandidateIntakeService::generateWorkFinderAgreement
      → resolveTemplate(branch)
      → WorkFinderAgreementData::toArray()
      → view($view, $agreementData)
      → gphl.blade.php (logo descriptors do wrapper/fallback cung cấp)
      → Dompdf → storage → File resource
```

Các key candidate hiện hữu (`worker_name`, `worker_address`, `intermediary_name`, `signature`, `printed_name`, `date`) vẫn do DTO cung cấp. `$logos`/single-logo flag là presentation data tĩnh của wrapper hoặc fallback trong Blade; không thêm FormRequest rule, DTO field hay service parameter.

### 14.3. Mapping và constants

- Giữ branch mappings Hawk3/GPHL hiện có.
- Bổ sung/giữ entity mapping: `1, 2, 4, 5, 6, 8` → `personnel`, `7` → `driving`, `3` → `tech`; entity không map vẫn trả lỗi template-not-found trước khi tạo file.
- Không thêm magic business value mới. View names, asset paths, alt text và CSS dimensions là presentation literals đã nằm trong config/Blade; dùng exception constants hiện hữu của `PermanentCandidateIntakeService`.

### 14.4. Files dự kiến sửa/tạo

| File | Thay đổi dự kiến |
|------|------------------|
| `config/work_finder_agreement.php` | Bổ sung entity mapping 1–8 theo mục 14.3, không đổi branch priority. |
| `resources/views/pdf/work_finder_agreements/gphl.blade.php` | Trở thành renderer chung: nhận logo descriptors, fallback logo GPHL, render một/nhiều logo đúng aspect ratio và giữ GPHL body/layout. |
| `resources/views/pdf/work_finder_agreements/tech.blade.php` | Đổi thành wrapper truyền hai logo Tech/Construction vào GPHL. |
| `resources/views/pdf/work_finder_agreements/personnel.blade.php` | Tạo wrapper truyền `gap-personnel-logo.png`. |
| `resources/views/pdf/work_finder_agreements/driving.blade.php` | Tạo wrapper truyền `driving-force-logo.png`. |
| `resources/views/pdf/work_finder_agreements/legal_entity.blade.php` | Không tồn tại trong baseline hiện tại; nếu được port từ commit cũ thì không giữ lại. |
| `resources/images/work_finder_agreements/gap-personnel-logo.png` | Reuse exact GAP-691 asset nếu chưa có trong current baseline; không regenerate/chỉnh sửa bytes. |
| `resources/images/work_finder_agreements/driving-force-logo.png` | Reuse exact GAP-691 asset nếu chưa có trong current baseline; không regenerate/chỉnh sửa bytes. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Audit/update mapping, wrapper view location, GPHL shared renderer, logo bytes/count/aspect ratio, branch-over-entity priority, missing/corrupt asset và không còn legal_entity reference. |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Cập nhật caller capture/expectation nếu wrapper/GPHL render ảnh hưởng test date/template; không thêm Repository tests. |
| `.business-spec/backend-business-flow-spec.md` | Sau khi code/test xác minh, cập nhật SPEC-039 từ shared `legal_entity`/Tech wording sang shared GPHL renderer và mapping thực tế; không sửa API inventory/database spec vì không đổi route/schema. |

### 14.5. Acceptance và test gate

- GPHL direct mapping vẫn render đúng một logo GPHL khi không có wrapper-provided `$logos`.
- Tech, Personnel và Driving đều render qua `gphl.blade.php`, đúng logo footer, không có logo thừa, không stretch/sai aspect ratio; mọi trang PDF lặp header/footer đúng safe area.
- Không còn file/reference/view `legal_entity`; các template cũ không bị resolve nhầm.
- Entity mapping 1–8 và branch override được kiểm tra qua production HTTP caller; entity không map không tạo storage/File record.
- Missing/corrupt logo trả generation error và cleanup temp/storage như contract hiện tại.
- Chạy tuần tự `PermanentCandidateIntakeTest` và `PermanentCandidateIntakeServiceTest`, sau đó chạy full `./vendor/bin/phpunit`; yêu cầu 100% pass. Chỉ chạy `git diff --check`, không formatter/linter/migration.
- Self-check đối chiếu mục 14, các mục trước trong plan 003 và dirty worktree; không sửa Controller/Service/DTO/Repository ngoài khi test chứng minh contract bị ảnh hưởng.
