# SPEC: GAP-691 — Blade/PDF styling theo Work Finder Agreement Tech V6.docx

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-05
> **Author**: Codex

## 1. Tổng quan

**Yêu cầu gốc**: Blade Agreement chưa đầy đủ màu sắc/CSS như file Word; chỉnh để PDF bám sát mẫu `Work Finder Agreement Tech V6.docx`.

Chỉ cải thiện presentation của template Tech hiện có. Giữ nội dung điều khoản, candidate placeholders, mapping branch/entity, storage/File response HTTP 200 theo quyết định bổ sung của user và luồng submit/MM. Không thay bằng PDF ảnh toàn bộ: nội dung vẫn là text selectable, candidate vẫn được fill qua Blade.

### Baseline và evidence

- Blade `resources/views/work_finder_agreements/tech.blade.php` đang dùng text `#111`, table header xám, border `#555`, body 10px và không có letterhead.
- Đã đọc OOXML document/styles/theme/header/footer và đối chiếu với Blade. Body active runs dùng theme minor font **Calibri**, size **10pt**; title **14pt**, appendix heading **8pt**. Không dùng Lato chỉ vì tên này xuất hiện trong một style khác.
- Title `#00B0F0`, body `#323E4F`, appendix/footer accent `#1F3864`, table border `#242C52`.
- Table header nền trắng; tất cả 13 data rows nền `#A1D9F5`, không phải zebra stripe. Grid ratios lấy từ widths `1975 / 2126 / 2268 / 2126 / 2268` twips, scale vào vùng nội dung để không overflow.
- A4 portrait (`11906 × 16838` twips), section margins `720` twips = 12.7mm. Có một explicit page break giữa Date và Appendix. DOCX metadata ghi 2 pages; đây là metadata, chưa phải xác nhận qua Word render.
- Letterhead là ảnh gốc `word/media/image1.png`, `2480 × 3508`, gồm dải navy/purple/cyan ở đầu/cuối trang và logo gap technical/gap construction. Đã inspect ảnh trực tiếp; không cần vẽ lại hoặc sinh logo mới.
- Asset SHA-256: `ce1752cd399115f77d4ed31c4790bfb5d8f87b9e560b2dc38b01311f5e330f9f`.
- Đã đối chiếu living-spec flow/route/database với call chain thực tế: không phát hiện deviation nghiệp vụ trong scope. **CODE presentation gap** so với DOCX: màu, kích thước chữ, letterhead, footer và Appendix pagination đang thiếu/chưa đúng. Production DATA/CONFIG/EXTERNAL/INFRASTRUCTURE không nằm trong phạm vi xác minh này.

### Giới hạn fidelity

Mục tiêu là tái hiện màu/branding/bố cục trong Dompdf hiện cài, không cam kết pixel-perfect với Microsoft Word khi font/render engine khác nhau. Repo chưa thấy Calibri font asset. Không tải hoặc copy font thương mại thiếu quyền sử dụng; dùng font local đã có với fallback DejaVu Sans, chỉnh point sizes và spacing theo mẫu. Nếu yêu cầu đúng glyph/line metrics Calibri tuyệt đối, cần user cung cấp font có quyền embed và duyệt bổ sung file list.

## 2. Database Design

N/A: không migration, bảng, seed, model hoặc repository thay đổi.

## 3. API Contract

Giữ `POST /api/candidate/me/permanent-intake/work-finder-agreement`, auth/middleware và toàn bộ validation của `WorkFinderAgreementRequest`. **Amendment approved 2026-10-05**: user yêu cầu giữ HTTP 200; quyết định này thay thế riêng success status 201 trong plan response alignment trước đó. Không khôi phục `withStatus(HTTP_CREATED)` vào controller; cập nhật tests/OpenAPI/living-spec theo 200.

Success HTTP 200, Candidate File resource tám field top-level có temporary URL; cùng schema upload file nhưng upload CV vẫn HTTP 201. Không trả HTML/PDF bytes trong JSON. Error format, upload CV, submit exact two files và thời điểm gửi MM giữ nguyên. Không thêm input màu/font/template vào request.

## 4. Presentation rules và layer applicability

1. Tái sử dụng nguyên ảnh letterhead trích từ DOCX, local deterministic asset. Không phụ thuộc remote URL/CDN hoặc DOCX tồn tại ở runtime production.
2. Blade embed ảnh local bằng data URI từ asset cố định trong repo; asset là trusted static content, không dùng user-provided path. Tránh phụ thuộc network hoặc chroot của Dompdf cho file URL bên ngoài root mặc định.
3. Đặt letterhead ở background full A4, lặp theo trang, bên dưới text. Chừa vùng header/footer để nội dung không che logo/dải màu; lấy geometry từ OOXML/ảnh rồi kiểm chứng trên PDF.
4. Chỉnh CSS point/mm units, màu, bold/underline, paragraph spacing và numbered-clause indentation theo source. Không dùng flex/grid hoặc kỹ thuật chưa chứng minh hoạt động trong renderer hiện cài.
5. Footer version/date/company text đặt đúng vùng theo source footer, không in trùng các alternative VML/DrawingML representations của cùng textbox.
6. Appendix bắt đầu trang riêng bằng explicit page break. Table năm cột, widths theo ratios, nền body xanh nhạt, header trắng, border navy; không clip chữ hoặc tách table row giữa trang.
7. Candidate tên/địa chỉ dài được wrap, không fixed height cắt text. Không ép mọi dữ liệu vào đúng 2 trang bằng cách làm chữ quá nhỏ; mẫu thông thường target 2 trang, input dài có thể thêm trang với letterhead/footer vẫn đúng.
8. Giữ escaped `{{ ... }}` placeholders, signature/date trống như hiện tại; không tự lấy ngày hiện tại hoặc thêm chữ ký.
9. Không sửa hoặc viết lại nội dung pháp lý/link. Nếu phát hiện khác biệt wording giữa DOCX và Blade, ghi riêng để user quyết định, không tự đổi trong task styling.

Áp dụng layer: View + static asset + tests. Không tạo Controller/FormRequest/Resource/Exception/Service/Repository/DTO mới và không sửa các layer này chỉ để đáp ứng skeleton phase.

## 5. Data Origin & Call Chain

Route → `PermanentCandidateIntakeController::generateWorkFinderAgreement` → `WorkFinderAgreementRequest::validated()` + authenticated Candidate → `WorkFinderAgreementService::generate` → `buildAgreementData` → `WorkFinderAgreementData::toArray()` → `view($view, $agreementData->toArray())` → Dompdf A4 → storage → File.

Các biến đã verify từ DTO: `title`, `worker_name`, `worker_address`, `intermediary_name`, `signature`, `printed_name`, `date`. Worker/address/intermediary lấy từ draft validated với fallback profile/address hiện có; signature/date từ service constants rỗng. Không giả định logo URL, branch name, footer variables hoặc font data có trong DTO.

Letterhead đọc từ static `resource_path('images/work_finder_agreements/tech-letterhead.png')` trong template, không lấy từ Candidate hoặc DB. Chỉ đọc asset tin cậy, không thêm business workflow/DB query vào View.

## 6. Constants / styling values

Không thêm business magic values. File type/status/template-name constants giữ nguyên. CSS literal colors, dimensions, sizes và grid ratios là presentation data lấy từ DOCX, không tạo Model/Service constants cho từng CSS property.

## 7. Files cần tạo/sửa

### Files mới

| File | Vai trò | Phase |
|------|---------|-------|
| `resources/images/work_finder_agreements/tech-letterhead.png` | Extract nguyên `word/media/image1.png` từ DOCX, giữ bytes/hash gốc. | 1 |

### Files sửa

| File | Thay đổi | Phase |
|------|----------|-------|
| `resources/views/work_finder_agreements/tech.blade.php` | Chuẩn bị style hooks/asset boundary, sau đó hoàn thiện màu/typography/letterhead/footer/Appendix table và pagination. Không đổi legal wording hoặc data placeholders. | 1 → 2 |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Regression render qua caller production; kiểm tra asset/style hooks, candidate escaping, PDF thật, HTTP/File schema, long-field rendering và generate không MM. | 1 → 2 |
| `documents/Gap-API-Candidate.yaml` | Amendment: success response Agreement từ 201 thành 200, giữ schema/example File. | 1 |
| `.business-spec/backend-business-flow-spec.md` | Ghi nhận Tech template dùng local letterhead/presentation theo source sau khi implement, không ghi desired behavior như hiện trạng trước khi code hoàn tất. | 2 |
| `.specs/GAP-691/GAP-691-agreement-word-visual-fidelity.md` | Record từng phase, visual review evidence, deviations/font fallback, test results và status. | 1 → 2 |

**Không đổi/xóa**: DOCX nguồn, Service/DTO/Controller/Request/Resource/Repository, routes, template mapping config, storage/MM workflow; không thêm font binary khi chưa có quyền sử dụng/approval bổ sung.

## 8. Implementation phases

Owner Codex, tuần tự, giữ các dirty changes hiện có. Public contracts/data keys frozen theo sections 3/5; chỉ presentation hooks nội bộ View được bổ sung.

### Phase 1 — Skeleton / render integration boundary

- **Input**: plan approve; DOCX source, Blade hiện có và production data chain đã verify.
- **Ownership**: local letterhead asset, Blade, feature test, plan; OpenAPI/living flow cho amendment HTTP 200.
- **Implementation**: extract và verify asset bytes/hash; thêm CSS class hooks cho document header/body/footer/Appendix nhưng giữ active layout trước khi Phase 2 hoàn thiện. Ghi `{{-- TODO[GAP-691-P2]: Apply DOCX letterhead, typography, palette and pagination. --}}`. Chuẩn bị test observers/assertions tại production Blade render để xác nhận data/escaped fields không bị thay đổi.
- **Output**: View compile-valid, asset đóng gói local, production route vẫn render PDF thực tế; không fake success, không endpoint/service mới hoặc state mutation ngoài workflow hiện có.
- **Dependencies**: không DB/bindings mới; không network hoặc DOCX runtime.
- **Acceptance/test gate**: asset hash matches source; Blade compile/render qua existing API tests; generate/config/upload response tests PASS với `LOG_CHANNEL=single ./vendor/bin/phpunit`. Chỉ tiếp tục Phase 2 khi gate pass.

### Phase 2 — DOCX styling / PDF visual verification

- **Input**: Phase 1 PASS, existing API/DTO contracts frozen.
- **Ownership**: Blade, feature test, living flow, plan.
- **Implementation**: activate local letterhead; apply source palette/font sizes/spacing/table borders/fills/column ratios; explicit Appendix page break; footer/logo safe areas; remove TODO P2. Chỉ đổi markup khi cần styling, giữ nguyên text và escaped data. Thêm tests candidate dài/ký tự đặc biệt và escaped HTML, giữ signature/date blank.
- **Output**: PDF có branding/màu và bố cục theo source, vẫn text selectable và fill candidate được; tạo PDF preview bằng pipeline Blade/Dompdf thật với fixture ngắn/trống/dài, không upload/gọi MM ngoài test fake storage.
- **Dependencies**: Phase 1, installed Dompdf và công cụ preview local. Máy hiện có Quick Look/Swift, không thấy LibreOffice/pdftoppm; không tự cài dependency hệ thống hoặc đổi PDF engine. Dùng công cụ preview sẵn có; nếu native DOCX preview không hoạt động thì báo giới hạn đối chiếu và có thể cần PDF export Word để duyệt pixel-level, không khẳng định đã visually match chỉ từ XML.
- **Acceptance/test gate**: HTML render/style assertions từ production data chain; PDF mở được; review mọi trang để kiểm tra màu/background/footer không che nội dung, cột/border/wrapping, Appendix trang riêng và không mất clauses/rows. Audit affected tests trong intake/upload/File resource; chạy affected suites và full `LOG_CHANNEL=single ./vendor/bin/phpunit`. Kiểm tra scoped diff; không chạy formatter/linter.

## 9. Test Cases / self-check

- Asset gốc đúng hash, không remote references; background xuất hiện trên mọi trang.
- Header/title/body/Appendix/table palette khớp DOCX; body 10pt, title 14pt, source table column ratios và nền trắng/xanh đúng.
- PDF fixture thông thường có Terms/signature rồi Appendix trang riêng; không ép page count cho candidate dài.
- Candidate field trống/ngắn/dài, Unicode và HTML-like input: escape đúng, không clip/đè text/footer.
- Giữ nguyên đủ 12 clauses, 5 table columns và 13 data rows, hyperlinks và legal wording hiện có.
- Signature/date không bị auto-fill; API HTTP 200 theo amendment, tám File fields không đổi; storage PDF hợp lệ; generate không MM.
- Không repository unit tests. Review và cập nhật existing tests theo changed markup/style, không chỉ dùng isolated fake DTO mà không kiểm caller.
- Self-check sau hai phase: diff đúng file ownership, không business/API change, visual evidence và font fallback được ghi rõ, affected/full tests PASS trước DONE.

## 10. Approval

- [x] DOCX styling/asset và data source đã inspect.
- [x] Files, hai implementation phases, dependencies và gates xác định.
- [x] User approve trước khi sửa template/assets/tests (2026-10-05).

## 11. Execution record

- Phase 1: extracted local letterhead; SHA-256 matches DOCX source. Added View class hooks/TODO and production View composer assertions for actual candidate/address/intermediary/signature/date data. Test file PHP syntax PASS.
- Phase 1 test gate **NOT PASS**: generate/config/upload comparison filter ran 3 tests, 20 assertions; 1 pass, 2 failures. Both failures expect Agreement HTTP 201 but runtime returns 200.
- **CODE deviation found after approval**: `PermanentCandidateIntakeController::generateWorkFinderAgreement` now returns `(new FileResource(...))` without the previously implemented `withStatus(Response::HTTP_CREATED)`. This controller edit predates this styling implementation and is outside this plan's file ownership; preserved without overwriting it.
- User decision received 2026-10-05: **giữ 200**. Amend plan contracts/file ownership, update tests/OpenAPI/living flow, rerun Phase 1 gate before Phase 2. Controller preserved.
- Original clauses snapshot: 12 clauses, SHA-256 `f350842fe5ebd1afde22670ea4033c87f76cb8e70a078d4c162ac96175e11b94`; original tbody snapshot SHA-256 `c0cfeb51a30f9144727e06f80f429bed993faa36fa9ccf836281f4b77c2fbee0`. Use to verify no legal/table-content changes during Phase 2.
- Phase 1 gate rerun PASS after HTTP 200 amendment: `3 tests, 44 assertions`. Phase 2 started with frozen API/data contracts; no controller edits.
- Phase 2 implementation: original local letterhead embedded as data URI, fixed full A4; page margins reserve header/footer; source palette, point sizes and table column ratios applied; explicit Appendix page break. Helvetica chosen for static text to keep source-like metrics at 10pt; candidate fields retain embedded DejaVu Sans for Unicode. This is the approved local-font fallback, not Calibri fidelity.
- Dompdf integration finding: whitespace as an HTML-root child prevented fixed elements from being collected/repeated. Joining root/head/body boundaries ensures the first flow child is body; repeated image draw counts are asserted for every PDF page. No renderer/library/Service changes.
- Actual request-chain finding: `TrimStrings` and API `XssProtection` strip tags before validated data reaches Service/DTO. Rendering tests compare production View data, not unsanitized raw request strings; encoded HTML-like text and ampersands remain escaped by Blade.
- Clause and tbody SHA-256 snapshots unchanged from Phase 1. API/File schema and MM workflow untouched; only docs/tests reconcile the separately approved HTTP 200 decision.
- Agreement render tests PASS: `5 tests, 128 assertions`. Affected suites PASS: `45 tests, 453 assertions` (intake, upload, permanent sync/job, File service/utility). PHP syntax, YAML HTTP 200 check and scoped diff checks PASS.
- Preview PDFs: `/private/tmp/gap-691-styled-agreement.ACMScD/{normal,empty,long,unbroken}.pdf`, generated using the actual Blade/DTO/Dompdf pipeline without DB/storage/MM writes. Normal/empty = 2 pages; long/unbroken = 3 pages, Appendix on last separate page. Local PDFKit verifies readable text/A4, CoreGraphics renders page PNGs for visual inspection. Image/footer draw counts equal page counts for all four PDFs.
- Native DOCX Quick Look preview unavailable in sandbox (initialization failed). Reference colors/typography/pagination/asset grounded in OOXML and inspected original letterhead; cannot claim pixel-level visual equivalence to Microsoft Word. No system dependencies/fonts installed.
- Final visual review PASS: A4 text/fields/table wrap within content area, signature/date blank, Appendix separate, no clipping/overlap in normal/empty/long/unbroken fixtures. Pixel sampling verifies navy letterhead at top/bottom of every generated page PNG (10 pages total), in addition to PDF image/footer draw counts. Candidate Unicode remains legible; fixed legal text remains selectable. This is local PDF presentation verification, not a native Microsoft Word pixel comparison.
- Full `LOG_CHANNEL=single ./vendor/bin/phpunit` PASS: `527 tests, 2537 assertions` (02:08.774). Existing unknown legal_entity_id `999999` negative-seeder output is not a failure.
- Self-check PASS: source asset exact hash, 12 clauses and tbody hashes unchanged, no new DTO/view inputs assumed, no queries/transactions/integrations added, no route/controller/service/global resource changes. New helper is test-only/private. HTTP 200 docs/tests consistent; upload CV still 201; no formatter/linter run. All required phase/test gates passed.
