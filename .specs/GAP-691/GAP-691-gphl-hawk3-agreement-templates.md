# SPEC: GAP-691 — GPHL và HAWK 3 Agreement Blade templates

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-05
> **Author / implementation owner**: Codex

## 1. Tổng quan

Tạo hai Blade riêng tương ứng với hai DOCX nguồn tại repo root:

- `GPHL TERMS OF AGREEMENT WITH WORK-SEEKERS FOR PERMANENT OR CONTRACT STAFF.docx`.
- `HAWK 3 TERMS OF AGREEMENT WITH WORK-SEEKERS FOR PERMANENT OR CONTRACT STAFF.docx`.

Giữ nguyên wording pháp lý, numbering, Appendix, hyperlink và branding từng file; nội dung PDF vẫn là text selectable, không rasterize cả agreement. Đóng gói ảnh letterhead gốc trong repo để production không cần DOCX hoặc remote image.

**Scope**: hai views, hai static assets, integration tests và tài liệu. Không sửa Tech, Controller/Service/DTO, routes, validation hoặc storage/MM workflow. Không tự gán GPHL/HAWK 3 cho entity/branch: config production hiện giữ entity IDs 1–7 → Tech. Mapping mới cần danh sách IDs và approval riêng; tests được override config trong môi trường test để kiểm integration thật.

### Evidence từ nguồn

- Đã inspect document/styles/numbering/settings/header/footer/relationships và ảnh `word/media/image2.png` của cả hai DOCX.
- Cả hai có title hai dòng, introductory paragraph, **7 numbered clauses**, acknowledgement/thank-you và Appendix **4 cột, 5 data rows** (6 rows nếu tính header). Numbering là decimal `1.` → `7.`, không xuất hiện trực tiếp trong `w:t`, phải giữ khi chuyển HTML.
- Bốn cột: Industrial / Commercial / Driver / Management. Grid bằng nhau: `2125` twips mỗi cột; table width `8500`, indent `794` twips; header fill `#B4C6E7`, borders từ source. Không copy bảng Tech 5 cột/13 rows.
- Không có ô worker name/address/intermediary/signature/date trong hai mẫu này. Không thêm ô candidate hoặc auto-fill chữ ký/ngày chỉ vì DTO hiện có các biến đó. Candidate input vẫn được xử lý bởi pipeline hiện tại, nhưng hai documents này là static theo bản nguồn.
- GPHL body `#323E4F`, active body font Calibri 10pt; title cyan `#00B0F0` 14pt, Appendix cyan 11pt.
- HAWK 3 body `#292C63`, active body chủ yếu Calibri 11pt; title/Appendix teal `#62BEAF`. Size/bold/spacing của từng title run cần giữ theo source, không áp dụng palette/14pt của Tech toàn cục.
- A4 portrait, margins top/left/bottom `720`, right `726` twips. Không có explicit page break trước Appendix; không ép Appendix sang trang riêng như Tech. Metadata cả hai ghi 1 page, chỉ là reference, không phải xác nhận native Word render.
- Default header là `header2.xml`; settings không bật even/odd headers, section không bật title page. Dùng ảnh trong default header, không chọn `image1.png` chỉ vì có trong archive; không render trùng DrawingML/VML fallback hoặc `image3.png` bytes-identical của GPHL.
- GPHL default letterhead: `2472 × 3459`, gap personnel group logo và dải navy/purple/cyan; SHA-256 `1d47dc3a5d0b57a6e689f0f3e94a67df6970ac1668a13881fcf977805c460d5a`.
- HAWK 3 default letterhead: `4961 × 7016`, logo Hawk 3, website/social icons và teal footer; SHA-256 `a82263a3163d3139fee58660ecb9bad59b53a1efe69b4a2719258f00aaa475c1`.

### SOURCE inconsistencies / giới hạn

- **SOURCE inconsistency**: GPHL footer hiện ghi `HAWK 3 TERMS OF AGREEMENT WITH WORK-SEEKERS FOR PERMANENT OR CONTRACT STAFF  - VERSION 5 – 23/10/2019`; privacy hyperlink cũng là `https://www.hawk-3.com/privacy-policy/`. Giữ nguyên nguồn, không tự đổi thành GPHL hoặc đoán link. Footer XML có alternative textbox representations: chỉ in một bản, không nhân đôi.
- HAWK 3 wording có `gap personnel holdings limited t/a Hawk 3 Limited`; GPHL không có trading-name suffix này. Giữ riêng, không dùng tìm/thay toàn cục thay legal text giữa templates.
- Repo không có Calibri được cấp phép embed. Dùng font local sẵn có với Helvetica/DejaVu Sans fallback theo renderer hiện tại; không tải/copy font thương mại. Ghi rõ khác biệt font khi bàn giao, không cam kết pixel-perfect với Word.
- Native DOCX Quick Look đã không hoạt động trong sandbox ở task Tech. Đối chiếu nguồn bằng OOXML/ảnh và review PDF Dompdf; không tự cài LibreOffice/font hoặc thay PDF engine. Nếu cần pixel-level approval, cần Word-exported PDF từ user.
- Baseline living-spec và source call chain đã đối chiếu: template hiện chỉ Tech, đúng CONFIG đã ghi nhận. Hai views mới là capability chưa mapped, không phải thay đổi lựa chọn template hiện hành. DATA/EXTERNAL/INFRASTRUCTURE production không được kiểm chứng trong task này.

## 2. Database Design

N/A: không migration/model/repository/seed hoặc database contract mới. PDF tiếp tục lưu vào `files` qua workflow hiện tại khi template đã được chọn trong config.

## 3. API Contract / validation

Không thêm endpoint hoặc request field. Giữ `POST /api/candidate/me/permanent-intake/work-finder-agreement` qua `PermanentCandidateIntakeController`, HTTP **200**, Candidate File resource tám field top-level và temporary `url`; upload CV vẫn 201. Generate không gửi MM; chỉ submit gửi danh sách file đã chọn sang MM như hiện tại.

Validation không đổi: `job_id` required integer min 1; `candidate`/`candidate.address` sometimes array; tên/title và building/street/town_city/county sometimes nullable string max 255; postcode max 20; intermediary_name sometimes nullable string max 255. Không thêm template selector, entity ID hoặc brand input từ FE.

## 4. Layer applicability / presentation rules

- Áp dụng View + static assets + tests. Không tạo PHP Controller/Request/Resource/Exception/Service/Repository/DTO rỗng để đáp ứng phase rule.
- Hai view identifiers frozen: `work_finder_agreements.gphl`, `work_finder_agreements.hawk3`.
- Mỗi view dùng asset local cố định qua data URI, không user-provided path hoặc network. Extract nguyên bytes, verify hash; không sinh lại logo bằng imagegen.
- CSS dùng pt/mm, table layout hỗ trợ Dompdf; reserve header/footer safe areas theo từng letterhead. Background lặp đúng trên mọi trang nếu nội dung overflow; text và footer không che logo. HAWK footer chữ trắng đặt trên vùng teal, tránh vùng logo trắng bên trái.
- Giữ đủ 7 clauses, acknowledgement, thank-you, 4-column table/5 data rows và privacy hyperlink. Không thêm signature block hoặc Tech terms vào hai nguồn này.
- Không ép page count bằng thu nhỏ font quá mức hoặc clipping; target reference 1 trang khi thực tế vừa, ghi nhận chênh lệch do fallback font nếu cần. Không tự tạo Appendix page break.
- Không refactor Tech/shared Service chỉ để reuse code; không thêm business logic vào View. Chỉ chia sẻ test helper khi behavior thực sự giống và helper có visibility private.

## 5. Data Origin & Call Chain

Route → `PermanentCandidateIntakeController::generateWorkFinderAgreement` → validated `WorkFinderAgreementRequest` + authenticated Candidate → `WorkFinderAgreementService::generate` → ownership/job/branch/address repositories → branch-first/entity-fallback template resolution → `buildAgreementData` → `WorkFinderAgreementData::toArray()` → `view($view, $agreementData->toArray())` → Dompdf A4 → storage → File → File resource.

DTO keys đã verify: `title`, `worker_name`, `worker_address`, `intermediary_name`, `signature`, `printed_name`, `date`; signature/date service giữ rỗng. Không giả định email/phone/branch-name/template-title hoặc ngày hiện tại có trong payload. Hai nguồn không có candidate fields nên không cần sử dụng DTO keys hoặc đổi DTO. Tests kiểm pipeline thật bằng test-only mapping và View composer, không chỉ render isolated mock data.

Assets đọc từ trusted `resource_path('images/work_finder_agreements/gphl-letterhead.png')` / `hawk3-letterhead.png`. Legal wording, footer, colors và table contents là static source content, không lấy từ DB.

## 6. Constants

Giữ nguyên business constants/error codes/file type/status của `WorkFinderAgreementService` và `File`. CSS literals/source legal text là presentation data, không tạo Model constants cho CSS. Test fixtures/template selectors đặt trong named test data provider; không hardcode production entity/branch IDs mới.

## 7. Danh sách file change / ownership

Owner duy nhất Codex, thực thi tuần tự; giữ nguyên unrelated dirty worktree.

| File | Change | Phase |
|------|--------|-------|
| `resources/views/work_finder_agreements/gphl.blade.php` | NEW — GPHL skeleton rồi legal content/CSS/letterhead/footer/table. | 1 → 2 |
| `resources/views/work_finder_agreements/hawk3.blade.php` | NEW — HAWK 3 skeleton rồi legal content/CSS/letterhead/footer/table. | 1 → 2 |
| `resources/images/work_finder_agreements/gphl-letterhead.png` | NEW — nguyên `word/media/image2.png` của GPHL, hash verified. | 1 |
| `resources/images/work_finder_agreements/hawk3-letterhead.png` | NEW — nguyên `word/media/image2.png` của HAWK 3, hash verified. | 1 |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | MODIFY — skeleton safe-failure/asset tests rồi test cả hai templates qua production API; không đổi Tech expectations. | 1 → 2 |
| `.business-spec/backend-business-flow-spec.md` | MODIFY — sau implement ghi nhận hai templates available nhưng chưa mapped; giữ HTTP 200 và entity 1–7 → Tech. | 2 |
| `.specs/GAP-691/GAP-691-gphl-hawk3-agreement-templates.md` | MODIFY — phase gates, deviations, preview/test evidence, execution status. | 1 → 2 |

Không sửa/xóa DOCX nguồn, Tech Blade/assets, config mapping, Controller/Service/DTO/Request/Resource/routes, OpenAPI hoặc living route/database docs vì contract và relationships không đổi. Temporary PDF previews không phải production files.

## 8. Implementation phases

### Phase 1 — Skeleton / integration boundary

- **Input**: user approve plan; DOCX và production call chain đã verify.
- **Ownership**: hai views, hai assets, existing feature test và plan, theo section 7.
- **Implementation**: extract assets/verify hashes; tạo compile-valid Blade document/style hooks với `{{-- TODO[GAP-691-P2]: Render source terms, appendix, branding and footer. --}}`. Chưa mapped vào production config. Skeleton render phải fail closed bằng custom `App\Exceptions\Api\Candidate\APIErrorException` và existing generation-failed constants của `WorkFinderAgreementService`, không xuất PDF trống/fake success nếu ai override mapping trước Phase 2.
- **Output**: views tồn tại/compile được, local assets đóng gói, integration boundary và safe failure được chứng minh; Tech endpoint hiện hành không đổi.
- **Dependencies**: existing Blade compiler/custom exception/constants, không DB schema/bindings mới, không network.
- **Acceptance / test gate**: kiểm hash và Blade compile; test-only mapping mỗi skeleton phải trả custom error, không tạo File/upload/MM; Tech generation/config/response tests PASS. Dùng `LOG_CHANNEL=single ./vendor/bin/phpunit` với affected feature filters; không tiếp tục Phase 2 nếu gate chưa PASS.
- **Frozen contracts**: view names/asset paths, API/schema/validation, existing DTO keys, mapping policy và nguyên tắc không thêm candidate fields.

### Phase 2 — Source content / styling / PDF verification

- **Input**: Phase 1 PASS và frozen contracts.
- **Ownership**: hai views, feature tests, living flow và plan; assets chỉ verify, không transform bytes.
- **Implementation**: remove skeleton guard/TODO, render đầy đủ từng nguồn; preserve numbering, source title/body styles, table contents/geometry, hyperlink và footer một lần. Apply source letterhead và safe margins; không forced Appendix page break. Tests dùng test-only config, production View data và real Dompdf generation để verify cả branch override và entity fallback lựa chọn đúng view mà không đổi config repo.
- **Output**: hai templates complete, chọn được bởi resolver hiện tại khi có mapping; PDF previews mỗi brand tạo bằng Blade/Dompdf thật, không DB/storage/MM external writes ngoài test fake storage. Living docs chỉ ghi capability đã triển khai, không mô tả mapping chưa có như hiện trạng.
- **Dependencies**: Phase 1, installed Dompdf và local preview tools; không font/system dependency mới.
- **Acceptance / test gate**: đủ 7 numbered clauses, 4 columns/5 data rows, đúng legal entity wording/link/footer/asset; PDF hợp lệ, text selectable, logo/colors readable, mọi trang không clip/overlap và background đúng. API HTTP 200/File shape/signed URL unchanged, generate không MM; entity 1–7 mặc định vẫn Tech. Audit tests impact, chạy affected suites rồi full `LOG_CHANNEL=single ./vendor/bin/phpunit`; scoped diff check, không formatter/linter. Ghi preview evidence/font fallback và self-check trước DONE.

## 9. Test impact review / self-check

- Review `PermanentCandidateIntakeTest`, `MeFileTest`, `PermanentCandidateIntakeServiceTest`, `MatchMakerPermanentSyncTest`, `SyncPermanentCandidateToMatchMakerJobTest`, `FileServiceTest`, `FileUtilityTest`; chỉ sửa tests trực tiếp liên quan.
- Add parameterized feature coverage cho GPHL/HAWK 3: test-only mapping → actual production caller → PDF/storage/File response; View data observed từ caller, không assumed keys.
- Assert clauses/body text và table cell contents theo source, numbering 1–7, privacy URL, static footer không duplicated, đúng image hash/data URI và draw count theo số trang thực tế. Không dùng Tech 12-clause/13-row/2-page expectations cho templates mới.
- Candidate draft trống/Unicode/dài đi qua request vẫn generate đúng static source documents, không tự chèn PII hoặc signature/date vào agreement này.
- Tests branch mapping ưu tiên entity và entity fallback bằng config override riêng; repository config production không đổi.
- No repository unit tests; no DB queries trong loops, no service injection/transaction/integration changes. Preserve unrelated edits, minimal diff, no formatters.
- Self-check sau cả hai phase: đối chiếu source/plan/file ownership/data origin, remove phase TODO/guard, tests affected/full PASS; ghi rõ source inconsistencies và chưa có production mapping.

## 10. Approval

- [x] DOCX content/numbering/style/header/footer/images đã inspect.
- [x] Existing resolver/API/DTO/data source đã trace.
- [x] File list, minimum two phases, contracts và test gates được xác định.
- [x] User approve trước khi tạo/sửa implementation views/assets/tests (2026-10-05).

## 11. Execution record

- User approved 2026-10-05. Phase 1 started; applicable layers only View/assets/tests. Database/types/repository/service/API layers không cần thay đổi, giữ existing contracts.
- Đã extract hai ảnh vào temporary directory để inspect, không thêm production assets trước approval.
- Phase 1 PASS: original source assets extracted vào approved paths; hashes verified. Hai Blade compile-valid, fail closed với existing custom generation-error nếu test-only config chọn skeleton; không upload/create File/MM. Tech config/generation/upload-response regression PASS: `5 tests, 75 assertions` (`LOG_CHANNEL=single ./vendor/bin/phpunit`). Phase 2 bắt đầu sau gate này; contracts/mapping frozen.
- Phase 2 source implementation complete: hai independent Blade documents với 7 numbered clauses, source-specific legal text/colors/title sizes (GPHL 14pt, HAWK 3 16pt), 4-column/5-data-row Appendix, original local letterheads và single source footer. No candidate fields added; phase guard/TODO removed. Mapping/API/service/DTO/Tech untouched.
- Body normalized text snapshots lấy trực tiếp từ source OOXML (intro + 7 clauses + acknowledgement + thank-you, 10 paragraphs): GPHL SHA-256 `6710534b88b1e2cb1547ed590d647e6a8a096095d6af5fa503a21047a70b1213`; HAWK 3 `b791b9d35dd01c167e41038846c18644dce79d39715aa3ca23e2d23181bf6d58`. Feature tests verify rendered body against these independent source hashes; source DOCX not required at test/production runtime.
- New integration coverage PASS: `13 tests, 568 assertions` (02:12.813). Twelve cases cover both templates × empty/Unicode-HTML-like/long-unbroken candidate draft × branch override/entity fallback; extra test checks repo config stays Tech for IDs 1–7. HTTP 200/File metadata/signed URL/storage PDF, unchanged static content with no injected PII, source text/table/footer/link and asset/image draw assertions all pass.
- Preview initial review found footer placement too close to GPHL curved corner and HAWK 3 transparent gradient start. Adjusted only footer safe-area CSS: GPHL left 10mm; HAWK 3 left 105mm within content area. Original asset bytes, white footer/source wording unchanged. HAWK 3 footer background includes source alpha gradient; retained rather than replacing source asset.
- Final previews: `/private/tmp/gap-691-gphl-hawk3-preview.W3LhAa/{gphl,hawk3}-final.pdf`. Both 1 page A4; PDFKit extracts legal text/Appendix/footer (2512 / 2664 characters), CoreGraphics PNG visual review confirms body/table within margins, header/footer not overlapping logo/content, complete footer readable after repositioning. Helvetica fallback and no native Word pixel comparison remain documented limitations.
- Test impact audit reviewed intake/upload/File service/utility/permanent sync/job tests. Only affected template/intake test coverage changed; other tests retain existing contracts. PHP syntax and scoped whitespace checks PASS; no formatter/linter. Affected/full suites and final self-check pending.
- Affected suites PASS: `58 tests, 1021 assertions` (02:15.451), after final footer CSS adjustments. Both compiled Blade PHP syntax checks PASS; asset hashes still match source (including unchanged Tech asset). Final PDFs: GPHL 81,662 bytes / HAWK 3 229,223 bytes, one A4 page each. Full PHPUnit started; final gate pending.
- Final review scoped the template catalogue helper as private (only actual PHPUnit data provider remains public). Interrupted the in-progress pre-review full run; rerun affected and full suites on final code before completion. No production behavior/template change in this review adjustment.
- Extra source spacing review verified blank OOXML paragraphs P18/P20 between clauses 5–7 use 10pt GPHL / 11pt HAWK 3, just like the earlier clause gaps. Removed the initial nth-child spacing compression: only last list item suppresses duplicate trailing gap. Added CSS regression assertions; refreshing preview and rerunning final affected/full gates after this presentation correction. Wording/assets/contracts unchanged.
- Latest source-spacing-corrected previews supersede earlier `*-final.pdf`: `/private/tmp/gap-691-gphl-hawk3-preview.W3LhAa/gphl-reviewed.pdf` and `hawk3-reviewed.pdf`. Both remain 1 page A4 with identical extracted legal text character counts; reviewed new PNGs confirm all seven clauses separated as source, full Appendix fits and header/footer safe areas remain clear.
- Final affected suite gate PASS after all code changes: `58 tests, 1045 assertions` (02:15.676). Syntax/scoped diff checks pass; production views/tests frozen, running full PHPUnit on this final code. No additional implementation edits planned.
- Final full `LOG_CHANNEL=single ./vendor/bin/phpunit` PASS: `540 tests, 3129 assertions` (03:53.574, peak 354.89 MB). Existing negative-seeder warning about unknown legal_entity_id `999999` is expected and not a test failure.
- Self-check PASS: approved phase gates executed sequentially; new files match ownership; source legal-text snapshots and both original asset hashes match; 7 numbered clauses/4 columns/5 data rows preserved; source paragraph spacing and footer safe areas reviewed on latest PDF; no assumed candidate data or added PII/signature/date fields. Internal catalogue helper private; no repository tests/queries in loops/transaction/service/API integration changes. Tech/config/entity IDs 1–7 preserved, response HTTP 200 unchanged, generate does not MM. Living docs updated for implemented but unmapped templates. No formatter/linter, font downloads, new external dependencies, migration or real MM/storage side effects. Both implementation phases and final affected/full gates completed.
