# SPEC: GAP-691 — CSS-only letterhead cho Work Finder Agreement

> **Trạng thái**: `§15 IMPLEMENTED / REGRESSION GATE OPEN` — Via geometry/visual + Feature pass; full suite còn MM/Slack/date ngoài scope
> **Ngày tạo**: 2026-10-06
> **Author**: Codex
> **Related plan**: [GAP-691-gphl-hawk3-agreement-templates.md](GAP-691-gphl-hawk3-agreement-templates.md)

## 1. Tổng quan

Thay phần letterhead đang nhúng PNG trong ba Blade PDF bằng CSS/HTML thuần, tham khảo các file:

- `resources/views/pdf/work_finder_agreements/gphl.html`
- `resources/views/pdf/work_finder_agreements/tech.html`
- `resources/views/pdf/work_finder_agreements/hawk3.html`

Mục tiêu là loại bỏ việc Dompdf phải decode và render ảnh nền full-page, xóa các PNG letterhead không còn sử dụng, đồng thời giữ nguyên legal content, dynamic candidate fields, route, response, storage và template resolution hiện tại.

**Phương án hiện hành**: mục 13 thay thế các quyết định layout tại mục 12. Mục 14 đã được user duyệt và triển khai ngoại lệ PNG nhỏ cho footer branding Hawk3/GPHL/Tech; thay thế riêng yêu cầu CSS-only/no-image cho các logo này. Mục 11–13 giữ evidence lịch sử; trạng thái PNG/runtime/test hiện hành ở mục 14.7, không tạo plan mới cho cùng scope.

**Giả định cần approve**: các file `.html` là reference cho styling/branding; không copy mù toàn bộ document content vào Blade vì Blade hiện tại có contract dữ liệu và wording/pagination riêng đã được test. Các PNG letterhead sẽ bị xóa sau khi xác nhận không còn runtime/reference dependency; các file `.html` giữ lại làm reference.

## 2. Database Design

N/A. Không migration, model, repository, schema hoặc dữ liệu database.

## 3. API Contract

N/A về contract. Giữ nguyên endpoint:

`POST /api/candidate/me/permanent-intake/work-finder-agreement`

Giữ nguyên candidate authentication, request validation, ownership check, HTTP `200`, Candidate File resource, storage upload và không gọi MatchMaker trong bước generate.

## 4. Presentation / Business Logic

### 4.1. Call chain hiện tại

```text
POST route
  → PermanentCandidateIntakeController::generateWorkFinderAgreement
  → PermanentCandidateIntakeService::generateWorkFinderAgreement
  → resolveTemplate(branch-first/entity-fallback)
  → buildAgreementData(Candidate, address, validated draft)
  → Blade render
  → Dompdf render
  → FileUtility::uploadFile
  → FileRepository::create
  → Candidate File resource
```

### 4.2. Phạm vi thay đổi

- `gphl.blade.php`: thay ảnh bằng các lớp CSS header/footer và logo `gap personnel group` theo `gphl.html`.
- `tech.blade.php`: thay ảnh bằng các lớp CSS header/footer và hai logo `gap technical`/`gap construction` theo `tech.html`.
- `hawk3.blade.php`: thay ảnh bằng CSS header, social icons, Hawk 3 footer logo/banner và version text theo `hawk3.html`.
- Port các CSS rule cần thiết vào Blade; không load CSS/ảnh từ URL ngoài.
- Giữ escape mặc định cho các biến `WorkFinderAgreementData`: `title`, `worker_name`, `worker_address`, `intermediary_name`, `signature`, `printed_name`, `date`.
- Giữ legal wording, hyperlink, table contents, template resolver và các template-specific margins/typography hiện có trừ phần cần điều chỉnh để CSS letterhead không che nội dung.
- Không tạo thêm service/helper/controller chỉ cho presentation; CSS/markup nằm trong view theo pattern hiện tại.

### 4.3. Không thuộc phạm vi

- Không sửa API/request/DTO/resource/service/repository/database.
- Không chuyển CSS thành user-controlled input.
- Không xóa các file `.html` reference. Xóa ba PNG letterhead sau khi toàn bộ Blade/test đã bỏ dependency và `rg` xác nhận không còn reference runtime.
- Không thay đổi mapping branch/legal entity.

## 5. Data Origin & Runtime Verification

Các biến động vẫn đến từ production caller hiện tại:

| Biến | Nguồn | Xử lý |
|---|---|---|
| `$worker_name`, `$worker_address` | `PermanentCandidateIntakeService::buildAgreementData` từ candidate/address và draft validated | Giữ nguyên escape trong Blade |
| `$intermediary_name` | `WorkFinderAgreementRequest` validated data | Giữ nguyên |
| `$signature`, `$date` | `WorkFinderAgreementData` | Không tự suy diễn hoặc đổi contract |
| Template view | `branch.id` rồi `branch.legal_entity_id` qua config | Không nhận view path từ client |
| Letterhead/branding | CSS static trong từng Blade | Không đọc filesystem/network runtime |

## 6. Constants

N/A. Không thêm business constants. Các màu, kích thước và text branding là static presentation data của từng source template; giữ sát reference HTML, không đưa vào Model/Service.

## 7. Files cần sửa

| File | Thay đổi |
|---|---|
| `resources/views/pdf/work_finder_agreements/gphl.blade.php` | Loại `<img>`/Base64 letterhead; port CSS header/footer/logo từ `gphl.html`; giữ legal content hiện tại. |
| `resources/views/pdf/work_finder_agreements/tech.blade.php` | Loại `<img>`/Base64 letterhead; port CSS header/footer/logo từ `tech.html`; giữ candidate fields và 12-term content hiện tại. |
| `resources/views/pdf/work_finder_agreements/hawk3.blade.php` | Loại `<img>`/Base64 letterhead; port CSS header/social/footer/logo từ `hawk3.html`; giữ 7 clauses và Appendix hiện tại. |
| `resources/images/work_finder_agreements/gphl-letterhead.png` | Xóa vì không còn runtime usage sau khi chuyển sang CSS. |
| `resources/images/work_finder_agreements/tech-letterhead.png` | Xóa vì không còn runtime usage sau khi chuyển sang CSS. |
| `resources/images/work_finder_agreements/hawk3-letterhead.png` | Xóa vì không còn runtime usage sau khi chuyển sang CSS. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Cập nhật assertions từ image data URI/draw count sang CSS-only markers, PDF validity, branding text/geometry và dynamic data safety. Giữ các thay đổi đang có trong working tree. |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật runtime asset behavior: branding render bằng CSS, không cần đọc letterhead PNG khi generate. |

Các file `resources/views/pdf/work_finder_agreements/*.html` giữ lại làm reference; ba PNG letterhead là file bị xóa trong task này.

## 8. Test Cases & Acceptance Criteria

- Blade compile được cho cả ba view.
- HTML render của cả ba view không còn `<img>` letterhead, `data:image`, `base64_encode` hoặc `file_get_contents` đến thư mục images.
- `rg` toàn repo không còn production/runtime reference tới ba PNG; ba file PNG không còn tồn tại sau implementation.
- PDF generate qua đúng HTTP production pipeline và trả `200`/File resource như hiện tại.
- PDF bắt đầu bằng `%PDF-`, có ít nhất một page, không phụ thuộc network/remote image và không tạo lỗi khi asset PNG không được đọc.
- Kiểm tra branding CSS tương ứng:
  - GPHL: layered navy/purple/cyan header/footer và `gap personnel group`.
  - Tech: layered header/footer và `gap technical`/`gap construction`.
  - HAWK 3: website/social icons, Hawk 3 logo/banner và version/footer text.
- Candidate draft có Unicode/HTML-like text vẫn được escape; static legal text không bị thay đổi ngoài phần branding/layout được yêu cầu.
- Candidate fields, signature/date, table rows, privacy link và response keys hiện tại vẫn giữ nguyên.
- Chạy affected `PermanentCandidateIntakeTest` và toàn bộ `./vendor/bin/phpunit` sau implementation; không chạy formatter/linter.
- So sánh thời gian render trước/sau trên server hoặc môi trường tương đương để xác nhận không còn phụ thuộc decode full-page PNG. Không thêm timing assertion cứng vào PHPUnit.

## 9. Rủi ro / quyết định cần review

- Dompdf hỗ trợ CSS hạn chế hơn browser; `flex`, `border-radius`, pseudo-elements và nested layout từ reference HTML có thể render khác browser. Cần kiểm tra PDF thực tế, không chỉ HTML snapshot.
- Logo CSS là approximation của logo trong PNG; cần review visual trước khi xóa assets. Sau khi approve output, xóa PNG và cập nhật mọi test/hash assertion liên quan.
- HAWK 3 hiện có PNG metadata 600 DPI nhưng kế hoạch này loại bỏ runtime image dependency nên không cần xử lý DPI trong Blade.
- Working tree đang có thay đổi chưa thuộc task này, gồm template/test/asset edits; implementation phải giữ nguyên thay đổi đó và chỉ sửa phần CSS-only scope.

## 10. Approval

- [x] User review CSS-only approach và phạm vi giữ nguyên content/API.
- [x] User approve plan trước khi sửa Blade, tests hoặc living spec (2026-10-06).

## 11. Execution & Verification

- Đã chuyển `gphl.blade.php`, `tech.blade.php` và `hawk3.blade.php` sang branding bằng CSS/HTML, không còn runtime image dependency.
- Đã xóa ba PNG letterhead; các file `.html` reference vẫn được giữ lại.
- Đã cập nhật `PermanentCandidateIntakeTest` để kiểm tra CSS-only markers, PDF validity và dynamic data safety.
- Affected suite đã chạy: các case render GPHL/HAWK3 đều PASS; suite còn 2 failure do mapping branch `1`/`14` trong config hiện tại, không thuộc scope CSS.
- Full suite đã chạy: `555 tests, 3241 assertions`; còn 7 lỗi không thuộc scope CSS này: 1 Mockery expectation trong MatchMaker sync và 6 lỗi DNS tới `hooks.slack.com`, cùng 2 failure mapping branch nói trên.
- `git diff --check` và scan toàn repo không phát hiện whitespace error hoặc runtime reference tới ba PNG đã xóa.
- Không chạy formatter/linter theo workspace rule.

## 12. Follow-up: Match header/footer exactly to HTML references

### 12.1. Findings

Bản hiện tại đã bỏ PNG và render được PDF, nhưng chưa giữ đầy đủ hình học của các file HTML reference:

- GPHL/Tech: header/footer đang dùng vị trí và kích thước riêng cho Dompdf; một số lớp lồng đang dùng `99%`/`99.5%` thay cho `calc(100% - 7px)`/`calc(100% - 3px)` trong HTML.
- GPHL/Tech: footer content đang được định vị absolute khác với flex layout, nên khoảng cách metadata/logo chưa khớp reference.
- HAWK 3: header đang neo theo vùng fixed PDF khác vị trí `top: 10mm; right: 13mm` của HTML; footer đang dùng màu phẳng thay vì gradient; layout logo/banner và version box chưa khớp hoàn toàn.

### 12.2. Planned changes after approval

- Port lại các giá trị header/footer, màu, radius, kích thước, khoảng cách và vị trí từ từng HTML reference vào Blade tương ứng.
- Giữ `position: fixed` ở Blade khi cần để header/footer lặp đúng trên các trang PDF; chỉ chuyển đổi cơ chế layout tối thiểu khi Dompdf không hỗ trợ trực tiếp `flex`, `gap` hoặc gradient.
- Khôi phục gradient Hawk3 bằng CSS tương đương được Dompdf hỗ trợ; không đưa ảnh quay lại.
- Không thay đổi legal content, dynamic fields, API contract, template resolver hoặc test data.
- Render lại cả ba template qua `PermanentCandidateIntakeTest`, kiểm tra PDF và visual geometry của header/footer sau thay đổi.

### 12.3. Acceptance criteria

- Header/footer của từng Blade khớp HTML reference về màu, lớp viền, radius, vị trí, kích thước, logo và text.
- HAWK 3 giữ được social header, logo và dải gradient footer theo reference.
- Không có `<img>`, `data:image` hoặc reference tới ba PNG đã xóa.
- Affected suite pass; full-suite issues hiện có được phân biệt rõ với thay đổi CSS.

### 12.4. Execution result

- Đã cập nhật cả ba Blade theo header/footer geometry của HTML reference; giữ `position: fixed` và offset PDF cần thiết để Dompdf lặp header/footer trên nhiều trang.
- Đã kiểm tra `git diff --check` và scan asset/reference.
- Đã chạy affected test và full PHPUnit; không chạy formatter/linter.

## 13. Dompdf-compatible header/footer — Proposed remediation

### 13.1. Mục tiêu và bằng chứng

PDF của GPHL, Tech và HAWK3 phải giữ format header/footer của HTML reference về hình học, màu, typography và cách căn các thành phần, dùng DOM/CSS được phiên bản Dompdf cài trong repo hỗ trợ. Không đánh đồng copy CSS với render đúng.

Audit đã xác nhận:

| Vấn đề | Bằng chứng | Hệ quả |
|---|---|---|
| Flex không được hỗ trợ | `vendor/dompdf/dompdf/src/Css/Style.php::_compute_display` chuyển `flex` thành `block` | Metadata/logo xuống dòng; social icons Hawk3 xếp dọc. |
| CSS gradient không được hỗ trợ | Callback render của banner/emblem Hawk3 trả `background_image: none`, `background_color: transparent` | Mất nền gradient; version text trắng không có nền tương phản. |
| Kích thước lớp footer cộng padding | Border box footer-inner vượt mép phải A4 595.28pt trong callback render | Lớp màu, logo có thể tràn hoặc bị cắt. |
| Thiếu thông số từ reference | GPHL font logo 24px thay vì 26px; Tech 20px thay vì 24px; GPHL dot và pseudo-element khác kích thước | Branding không khớp reference. |
| Tọa độ bị tính theo vùng nội dung | Fixed wrappers dùng lề nội dung; Hawk3 `right: 13mm` cộng thêm lề phải `@page` | Header/footer bị dịch vào trong trang. |
| Logo Hawk3 không cùng hình | HTML dùng SVG path chim ưng; Blade dùng vòng tròn và pseudo-element | CSS hiện tại không tái tạo đúng logo SVG. |
| Test chưa kiểm tra layout | Helper hiện tại chỉ kiểm tra số trang; HTTP 200 và PDF magic bytes đều có thể pass khi layout sai | Không thể dùng kết quả test cũ làm bằng chứng visual. |

### 13.2. Giới hạn scope và contract

- Chỉ chỉnh presentation của ba Blade, tests liên quan và documentation sau implementation.
- Header/footer là nội dung static từ reference; không thêm biến runtime hoặc dữ liệu client-controlled. Các candidate fields hiện tại vẫn đến từ `PermanentCandidateIntakeService::buildAgreementData`.
- Giữ endpoint, API response, legal wording, appendix data và việc escape dữ liệu; không migration hoặc thay đổi layers Controller/Request/Service/Repository.
- Giữ các HTML reference và trạng thái xóa PNG; không tạo `<img>`, data URI ảnh hoặc remote asset.
- Không sửa mapping HAWK3 branch `1`/`14`, Slack logging hoặc MatchMaker mock trong scope này. Các lỗi baseline sẽ được ghi riêng khi chạy test.
- Không chia thành nhiều phase; đây là một scope implementation sau khi plan được duyệt.

### 13.3. Thiết kế layout

**Tọa độ A4 và fixed wrappers**

- Dùng một hệ tọa độ toàn trang 210mm × 297mm cho header/footer. Body tiếp tục dùng lề và pagination hiện có.
- Với lề `@page` là T/R/B/L: wrapper full-width dùng `left: -L`, `width: 210mm`; header ở mép trên dùng `top: -T`; footer ở mép dưới dùng `bottom: -B`.
- Hawk3 website/social đặt tại x = chiều rộng trang − 13mm − chiều rộng cụm, y = 10mm; chuyển offset theo lề PDF đúng một lần.
- Cả ba fixed header/footer phải lặp trên mọi trang, gồm trang appendix Tech. Khoảng dành cho body phải đủ tránh overlap; chỉ điều chỉnh lề khi render chứng minh cần thiết.

**GPHL và Tech**

- Giữ các màu `#6EC2E5`, `#592568`, `#2A2B4F`, tỷ lệ và radius từ reference. Header cao 46px; các lớp cao 45/39/36px và lớp trong giảm rộng 7px/3px.
- Footer cao tổng cộng 90px, outer rộng 94.6% toàn trang, căn phải. Dựng từng lớp bằng absolute offsets và kích thước content box đã trừ padding để border box không vượt tổng chiều rộng/cao.
- Thay flex/align/gap bằng các vị trí absolute hoặc inline-block có width/height và khoảng cách xác định; không đưa CSS flex không hoạt động vào đường render PDF.
- Metadata và logos nằm đúng vùng trái/phải theo reference; giới hạn vùng text để không đè logo. GPHL giữ xuống dòng footer như `<br>` trong HTML, bảo toàn nội dung version text.
- GPHL: chữ logo 26px, dot 4.8px tại 8.5px/14.5px, pseudo-element 19px × 23px với border 3.6px; khoảng chữ/subtext lấy đúng reference.
- Tech: chữ logo 24px, margin chữ 3px, khoảng hai logo 18px; giữ emblem 26px và các kích thước riêng của Tech.
- Kiểm tra các span dùng `inline-block` khi cần dimensions; pseudo-elements được định vị rõ. Không dựa vào `box-sizing: border-box` nếu renderer bỏ qua rule này.

**Hawk3**

- Social icons nằm cùng hàng, cao/rộng 22px và khoảng cách 8px. Canh chữ/camera bằng line-height hoặc absolute offsets thay flex; các nét camera giữ thông số reference.
- Footer wrapper cao 22mm, logo cách mép trái 8mm. Banner bám mép phải/dưới toàn trang, rộng 72%, cao 19.5mm; version box rộng 264.45pt và cách phải 12mm.
- Dựng banner gradient bằng khoảng 100 dải CSS absolute liên tiếp, mỗi dải 1% chiều rộng. Màu nội suy theo các stops reference 0%/28%/65%/100%; composite màu `#61BEB0` với nền trắng theo alpha 0/0.35/0.85/1. Không dùng `linear-gradient()` trong PDF. Render kiểm tra đường nối, banding và text đặt phía trên dải màu.
- Chọn font từ các font local renderer thực sự có. Giữ kích thước/letter-spacing reference; nếu Century Gothic/Calibri không có thì ghi nhận fallback Helvetica cùng khác biệt hình thức, không hứa typography giống tuyệt đối.
- Logo Hawk3 là quyết định visual cần duyệt: phương án mặc định giữ yêu cầu CSS thuần, dựng hình gần reference bằng các shape/border/radius/transform được Dompdf hỗ trợ và review trên PDF; không gọi bản CSS là logo SVG chính xác. Nếu yêu cầu bắt buộc đúng SVG path, cần quyết định bổ sung về vector rendering trước khi mở rộng scope. Không âm thầm dùng `<img>` hoặc renderer mới.

### 13.4. Files và ownership

| File | Thay đổi dự kiến |
|---|---|
| `resources/views/pdf/work_finder_agreements/gphl.blade.php` | Chuyển header/footer sang layout tương thích Dompdf, sửa kích thước logo và vùng metadata. |
| `resources/views/pdf/work_finder_agreements/tech.blade.php` | Sửa fixed footer toàn trang, căn hai logo cùng hàng và typography theo reference. |
| `resources/views/pdf/work_finder_agreements/hawk3.blade.php` | Căn social icons, footer/banner/version, gradient strips và CSS emblem được review. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Bổ sung kiểm tra kết quả render/layout thật; giữ test legal content, data escaping và response. |
| `.business-spec/backend-business-flow-spec.md` | Cập nhật cách render header/footer và giới hạn CSS/vector sau khi implementation được kiểm chứng; đọc lại ba canonical living specs trước khi cập nhật. |
| `.specs/GAP-691/002-css-letterhead-rendering.md` | Ghi execution, render artifacts, test results và mọi sai khác còn lại. |

Một owner thực hiện tuần tự các file; không tạo file implementation hoặc abstraction ngoài scope chỉ để gom CSS.

### 13.5. Verification và acceptance gate

1. Audit existing assertions của cả ba template. Bổ sung test bằng Dompdf render callbacks để đo vị trí/border boxes thực, thay vì chỉ assert stylesheet chứa chuỗi CSS.
2. Kiểm tra mọi header/footer nằm trong A4 với sai số tối đa 1pt; các lớp màu có tổng kích thước đúng reference và không overlap body. Đo sibling social icons cùng hàng và metadata/logo không chồng nhau.
3. Kiểm tra các dải gradient có màu và nằm liên tiếp; version text đọc được trên nền màu. Giữ tests candidate empty, Unicode/HTML-like text và long/unbroken text qua production caller.
4. Kiểm tra fixed header/footer xuất hiện và giữ tọa độ trên mọi trang; tạo thêm trường hợp multipage cần thiết để bắt lỗi footer chỉ có ở trang cuối.
5. Tạo PDF samples của cả ba template tại thư mục tạm, render thành preview bằng công cụ local sẵn có và đối chiếu header/footer với HTML reference. Nếu chưa có rasterizer/browser suitable, ghi rõ thiếu visual verification, không coi HTTP 200 là thay thế.
6. Chạy affected suite và full `./vendor/bin/phpunit` theo workspace rule; ghi riêng baseline failures, không thay config chỉ để làm test xanh. Không chạy formatter/linter.
7. Scan không có PNG/`<img>`/remote image dependency, review minimal diff và kiểm tra legal content/dynamic contract không đổi.

**Completion**: chỉ chuyển plan sang DONE khi render geometry đã kiểm chứng và preview review hoàn tất, hoặc đã có quyết định rõ về sai khác visual được chấp nhận. Bất kỳ logo/font khác reference phải ghi lại và nêu rõ khi handoff.

### 13.6. Approval cho phương án remediation

- [x] Duyệt chuyển layout sang CSS Dompdf hỗ trợ và gradient bằng dải màu.
- [x] Duyệt giới hạn logo Hawk3 CSS thuần và font fallback nếu font reference không có trong môi trường.
- [x] User duyệt triển khai mục 13 bằng `ok` sau khi nhận plan.

### 13.7. Execution & self-check (2026-10-06)

- Đã triển khai đúng các files ownership của mục 13; không đổi Service/API/DTO/schema/config mapping hoặc các HTML reference, không thêm implementation phases/layers.
- GPHL/Tech footer dùng các lớp cao 90/84/81px với offsets 6/3px, loại overflow 4.5pt được geometry test phát hiện khi dùng auto-height. Fixed footer đặt trước body để lặp trên mọi trang. Metadata/logo và Tech hai logos được căn absolute, không dùng flex.
- Hawk3 website/social đúng offsets 10mm/13mm toàn trang; icons 22px, gap 8px; banner rộng 72%, cao 19.5mm. Gradient gồm 100 dải CSS theo alpha-composited reference stops; overlap 1px tránh đường trắng khi rasterize, dải cuối giữ width 1%.
- Font weight 300/500 của reference resolve nhầm Times-Bold trong Dompdf local; thay bằng Helvetica 400/700 và thêm assertion font thực tế. Logo chim Hawk3 CSS là approximation đã được approve, khác SVG path reference. Không cam kết pixel-perfect hoặc server hết timeout.
- Đã trace production caller `generateWorkFinderAgreement` → `buildAgreementData` → DTO `toArray` → Blade. Test layout dùng view data thu từ production HTTP caller, không tự giả định biến. Body/legal wording/hash, escaping và public contract giữ nguyên so với đầu lượt remediation.
- Test impact review: giữ toàn bộ existing response/default mapping/legal hash/Unicode/long fields/cleanup/submit tests; thêm 6 dataset geometry/multipage tests và helper Dompdf callbacks đo boxes/màu/font. Không thêm repository unit tests.
- Affected gate đầu lượt: Feature **47 tests / 5,871 assertions PASS** (16.297s); Service **12 tests / 137 assertions PASS** (0.857s).
- Full `./vendor/bin/phpunit --log-junit ...`: **561 tests / 8,142 assertions**, 7 errors + 1 failure (174.980s), không phải full pass. 1 error là MM `addContactLog` mock do debug guard bị comment ở user code; 6 errors DNS `hooks.slack.com`; 1 failure default mapping sau config đổi Hawk3 branch 14 → 1 trong lúc chạy. Không gọi MM/Slack thật để vượt qua test, không sửa config hoặc mock ngoài scope.
- Sau lượt full regression, Service constant cũng đã đổi `AGREEMENT_DATE_FORMAT` từ `d/m/Y` → `ymd`. Chạy lại Feature suite trên trạng thái mới: **47 tests / 5,497 assertions**, 18 failures (16 date assertions + 2 mapping assertions), 0 errors. Chạy riêng 6 geometry/multipage datasets trên cùng trạng thái mới: **6 tests / 4,897 assertions PASS** (4.559s). Đây là các snapshots khác nhau của worktree đang thay đổi; không diễn giải affected pass ban đầu thành trạng thái full-green hiện tại.
- Visual artifacts nằm tại `/private/tmp/gap-691-css-remediation.B4vTpk`: `gphl.pdf` (1 trang), `tech.pdf` (2 trang), `hawk3.pdf` (1 trang), các `*-final-page-*.png`, DOM frame JSON và browser reference screenshots. Dùng PDFKit local rasterize, review đầy đủ PDF pages; đối chiếu HTML/CSS và Chrome previews. Tech browser screenshot đầu viewport chỉ chứa body/header, nên footer được đối chiếu với CSS reference và PDF preview, không tuyên bố screenshot ấy chứng minh Tech footer. Samples dùng dữ liệu giả lập, không phải PDF production.
- Preview review: footer không tràn/cắt, Tech logos cùng hàng cả trang appendix; Hawk3 version trắng trên gradient nhìn rõ, social icons cùng hàng. Khác biệt còn lại: CSS emblem Hawk3 và Helvetica fallback; body/pagination giữ thiết kế Blade, không copy layout body HTML vào PDF.
- `git diff --check` pass; scan cả ba runtime Blade không có `flex`, `gap:`, `linear-gradient`, `<img>`, `data:image`, PNG reference. Giữ các PNG deletions đã tồn tại; lượt remediation không xóa thêm file. Không formatter/linter, migrations hoặc deployment.
- Living spec đã cập nhật runtime rendering và các CODE/CONFIG/EXTERNAL deviations. CSS implementation/geometry/visual gates đã đạt; **chưa đóng regression gate** cho tới khi quyết định riêng về branch/date contracts và xử lý MM/Slack baseline.

## 14. PNG exemption — Footer logos Hawk3 / GPHL / Tech (APPROVED)

### 14.1. Yêu cầu, nguyên nhân và scope

- User cho phép `dùng png` để logo chim cạnh chữ Hawk3 giống HTML reference, sau đó yêu cầu GPHL/Tech cũng có thể chuyển thành img để sát nhất. Gộp amendment trong cùng scope/footer plan, không tạo plan riêng.
- Hawk3: thay riêng emblem chim bằng PNG nhỏ; chữ `hawk3`/`talent solutions` giữ CSS theo phương án trước. GPHL/Tech: đề xuất export cả cụm emblem + wordmark/subtext thành PNG để giữ hình dáng và typography của browser reference, không chỉ thay biểu tượng tròn rồi để Dompdf render font khác.
- Header/footer layered backgrounds, gradient banner, version text, social icons và legal body tiếp tục CSS/text. Chỉ bố trí lại vùng logo/metadata nếu geometry chứng minh cần tránh overlap; không đổi wording hoặc legal content.
- **SOURCE/BRAND DECISION CORRECTED**: User xác nhận quyết định hai logo GPHL trước đó là nhầm và đã sửa `gphl.html`. Source mới đã kiểm tra: GPHL chỉ có **một `gap personnel group`** trong `.brand-logo-single`, emblem 30px, wordmark 26px và subtext `group` 13.5px. Tech tiếp tục hai logo `gap technical` / `gap construction`, emblem 29px, wordmark 25px, gap 22px. Quyết định này thay thế lựa chọn hai logo GPHL trước đó; không đổi legal wording, tên công ty trong body hoặc template mapping.
- Không phục hồi ba letterhead PNG full-page đã xóa. Không thay renderer, API, request validation, DTO, Service, mapping branch/date, MM/logging, DB/migrations hoặc dữ liệu production. Không chia phases.
- Quyền dùng PNG và thiết kế đã được duyệt cho cả ba mẫu bằng `ok` trước implementation. Các yêu cầu no-image cũ được miễn trừ chỉ cho footer logo assets, không cho ảnh nền toàn trang.

### 14.2. Asset contract và nguồn dữ liệu

- Nguồn Hawk3: SVG `viewBox="0 0 100 100"`, exact path và gradient stops trong `hawk3.html`. Nguồn GPHL: toàn bộ `.brand-logo-single` personnel/group trong `gphl.html` đã sửa, gồm emblem + wordmark + subtext. Nguồn Tech: hai `.brand-logo` technical/construction trong `tech.html`. Snapshot CSS, font thực tế và source hash lúc export; nếu source thay đổi sau approval thì báo sai khác trước export, không tự thiết kế lại logo.
- Rasterize xác định bằng browser/tool local, không vẽ lại logo/AI generation, không crop từ ảnh cả trang hoặc tải asset bên ngoài. Export element riêng trên canvas transparent bằng native element capture hoặc viewport riêng; giữ mask/negative-space/white wordmarks. Nếu browser thiếu font reference, báo font resolved và review preview trước chốt, không tuyên bố giống font thương hiệu tuyệt đối.
- Hawk3 asset: `resources/images/work_finder_agreements/hawk3-emblem.png`, **176 × 176px**, hiển thị **44 × 44 CSS px** (4× sampling), giữ padding/viewBox. GPHL asset: `gap-personnel-group-logo.png`, gồm emblem + chữ personnel + subtext group. Tech assets: `gap-technical-logo.png`, `gap-construction-logo.png`, gồm emblem + chữ. Tổng cộng bốn PNG khác nội dung; không dùng hai logo Tech cho GPHL và không tạo assets trùng lặp.
- PNG wordmark canvases bằng 4× border/content bounds của logo element được đo sau fonts ready; giữ aspect ratio, không ép mỗi logo vào width cố định khác tỷ lệ. Ghi source CSS dimensions, measured display size và decoded PNG dimensions vào execution record trước khi thay Blade; nội dung chỉ là logo, không kèm footer background/metadata.
- RGBA được phép để giữ alpha ở viền/vùng rỗng, không convert RGB tạo nền trắng. Mục tiêu **≤50 KiB/asset, ≤200 KiB tổng**, mỗi canvas **≤1024×256px**, tổng decoded canvases **≤500,000 pixels**. Kiểm tra cả dung lượng nén và decoded dimensions; nếu không đạt budget/quality, điều chỉnh lossless/export và ghi rõ, không hạ chất lượng âm thầm.
- Xuất PNG một lần lúc triển khai, commit assets; runtime không chạy browser/rasterizer. Blade đọc paths local cố định qua `resource_path`, nhúng PNG data URI vào imgs có class cụ thể để không phụ thuộc URL/network/chroot hoặc caller cung cấp biến mới. Base64 chỉ áp dụng logo nhỏ; không đặt file reads trong Blade loop.
- Production chain đã trace: `PermanentCandidateIntakeService::generateWorkFinderAgreement` → `view($view, $agreementData->toArray())->render()` → Dompdf A4 → storage/File. Không thêm DTO key. File read nằm trong existing generation try/catch; lỗi thiếu/hỏng asset phải thất bại theo API error hiện hữu, không giả thành công với logo rỗng.
- Cập nhật `.hawk-emblem` với absolute coordinates/width/height hiện hữu; bỏ pseudo-elements/`.hawk-beak` cũ. GPHL/Tech giữ wrappers/footer positions, thay nội dung logo bằng một img personnel/group ở GPHL và hai imgs ở Tech, loại CSS logo shapes/wordmarks không còn runtime use. Tech gap 22px, cùng baseline và display sizes đo từ browser; GPHL giữ bố cục một logo với group ở dưới như source đã sửa. Điều chỉnh vùng logo/metadata wrap chỉ khi geometry chứng minh cần, không đổi text.
- Wordmark GPHL/Tech sẽ không còn selectable text trong PDF, chỉ nội dung pháp lý/metadata giữ selectable; imgs cần alt đúng brand. Hawk3 font fallback vẫn khác reference. PNG nhỏ giảm rủi ro so với full-page PNG, **không cam kết server hết timeout** nếu chưa benchmark cùng deployment.

### 14.3. Layer applicability, constants và files

Database/types/repositories/services/controllers/requests/routes: **N/A**. Không public contract, business constant hoặc abstraction mới; asset path/dimensions là static presentation contract. Một owner thực hiện tuần tự, bảo toàn user edits.

| File | Thay đổi sau approval |
|---|---|
| `resources/images/work_finder_agreements/hawk3-emblem.png` | Thêm PNG nhỏ export từ đúng SVG source. |
| `resources/images/work_finder_agreements/gap-personnel-group-logo.png` | Thêm một logo đầy đủ từ `.brand-logo-single` trong GPHL HTML đã sửa. |
| `resources/images/work_finder_agreements/gap-technical-logo.png`, `gap-construction-logo.png` | Thêm hai logo đầy đủ riêng cho Tech reference. |
| `resources/views/pdf/work_finder_agreements/hawk3.blade.php` | Thay shape CSS chim bằng một img local embedded, loại rules/markup mô phỏng cũ. |
| `resources/views/pdf/work_finder_agreements/gphl.blade.php`, `tech.blade.php` | Thay các logo thành imgs theo nguồn/brand được duyệt, giữ header/footer/body CSS. |
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Kiểm tra số imgs/branding/asset/geometry/PDF theo mỗi mẫu; không giữ no-img gate mâu thuẫn với contract mới. |
| `.business-spec/backend-business-flow-spec.md` | Sau triển khai, đọc lại ba canonical specs và ghi ngoại lệ PNG/footer logos cùng asset behavior đã verify. |
| `.specs/GAP-691/002-css-letterhead-rendering.md` | Ghi source/export tool, asset metadata, preview, test results và self-check. |

### 14.4. Test impact, verification và acceptance

1. Audit tất cả no-img/font/branding assertions cho cả ba mẫu: Hawk3 đúng một emblem img; GPHL đúng một personnel/group img; Tech đúng hai technical/construction imgs. Assert class/alt/source/PNG bytes, không cho thêm full-page img hoặc hai logo Tech trong footer GPHL. Không sửa date/mapping assertions ngoài scope.
2. Asset gate: PNG signature, decoded dimensions/sampling ratio, transparency và per-asset/aggregate budgets; nhúng trùng bytes asset. Test missing/corrupt assets qua production generation với mock read phù hợp không mutate asset repo, trả lỗi hiện hữu thay vì logo rỗng; không thêm runtime Service chỉ để mock.
3. Theo dõi img boxes qua Dompdf callbacks: Hawk3 44×44 CSS px, cách text 8px; wordmark imgs giữ measured aspect ratios, đúng gap/baseline theo reference. Tất cả nằm trong A4/footer, không đè metadata/banner/body. Giữ font assertions cho text còn runtime render; thay assertions font chữ GPHL/Tech đã rasterize bằng asset/PDF image checks.
4. Giữ 6 layout/multipage datasets, legal wording/hash, empty/Unicode/long-input, API/File/storage tests. Imgs/footer lặp trên trang bổ sung; không sửa legal content của GPHL/Tech. Kiểm chứng image thực sự render trong PDF, không chỉ có img tag.
5. Export PDF rồi rasterize preview local; đối chiếu logo shapes/gradient/wordmark/padding/kích thước và vị trí với HTML references đã chốt. Kiểm tra mask không có nền trắng, chữ trắng trên footer navy rõ nét. Không coi HTTP 200 hoặc asset hash là bằng chứng giống hình.
6. Chạy affected Feature/Service suites và full `./vendor/bin/phpunit`. Ghi riêng baseline date/mapping/MM/Slack failures; không sửa unrelated code để làm gate xanh. Không formatter/linter.
7. Scan chỉ có footer-logo PNG dependencies đã duyệt; không có references tới ba letterhead PNG đã xóa hoặc remote image. Review minimal diff, self-check đối chiếu scope/asset contract; ghi local render time, server performance vẫn UNVERIFIED nếu chưa có phép đo.

### 14.5. Approval

- [x] User cho phép dùng PNG cho vấn đề logo Hawk3.
- [x] User mở rộng quyền dùng img cho GPHL/Tech để sát HTML reference.
- [x] User sửa lại quyết định GPHL: một logo personnel/group theo `gphl.html` đã sửa; source đã kiểm tra, lựa chọn hai logo trước đó không còn hiệu lực.
- [x] User duyệt thiết kế PNG footer logos theo mục 14 bằng `ok` trước khi sửa Blade/tạo assets.
- [x] Implement, kiểm chứng PNG/visual/layout gates và cập nhật living spec sau approval.
- [ ] Đóng affected/full regression gate sau quyết định riêng cho các failures date/mapping/MM/Slack ngoài scope.

### 14.6. Export evidence (2026-10-06)

Export riêng source DOM/SVG bằng Chrome headless local + DevTools capture, device scale 4×; viewport bounds làm tròn lên CSS pixel để không cắt subpixel glyphs. Không chỉnh các HTML reference. Script/metadata tạm: `/private/tmp/gap-691-png-logos.7Ky2W9/`.

| Asset | Display canvas (CSS px) | PNG pixels | Bytes |
|---|---|---|---|
| `gap-personnel-group-logo.png` | 197×45 | 788×180 | 18,887 |
| `gap-technical-logo.png` | 179×29 | 716×116 | 13,678 |
| `gap-construction-logo.png` | 214×29 | 856×116 | 16,202 |
| `hawk3-emblem.png` | 44×44 | 176×176 | 10,228 |

Tổng 58,995 bytes / 355,168 decoded pixels, dưới budgets. Browser resolve wordmarks đúng Helvetica-Bold / Helvetica-Light, GPHL subtext Helvetica-Bold. Source hashes và CSS hashes nằm trong `export-metadata.json`; fonts không do Dompdf render cho các wordmarks PNG. PNG asset/PDF/visual verification đã ghi ở mục 14.7.

### 14.7. Execution & self-check (2026-10-06)

- Ownership: chỉ sửa ba Blade, affected Feature test, thêm bốn logo PNG và cập nhật plan/living business spec. Không sửa HTML references, Service/Controller/DTO/request/response/config/mapping/date/MM/logging/schema; giữ unrelated user edits và staged full-page PNG deletions hiện hữu. Không formatter/linter, migration hoặc deployment.
- Source snapshot: `gphl.html` SHA256 `5863b9747047b19412f9967a41cedb16f9f09ee0660ddde62f7ae077cb5bde83`; `tech.html` `61bed9bb72e567548e244dd0596e730dd91b4432a0b553a9f1436c2c5df24506`; `hawk3.html` `c2156b929dcab7436d3d4da7bbbcb8f92dcc61e9b9680234e5d80ac7f8918a59`. Recheck xác nhận cả ba nguồn không đổi trong implementation, installed PNG bytes trùng export outputs.
- GPHL đúng một personnel/group img; Tech đúng hai technical/construction imgs, gap 22px. Bỏ CSS logo shapes/wordmarks không còn dùng. Hawk3 thay riêng CSS bird approximation bằng exact SVG-source PNG; text `hawk3` / `talent solutions`, social icons, CSS gradient/banner giữ nguyên. Header/footer layered backgrounds vẫn CSS; không khôi phục full-page PNG.
- PNG transparent 4× canvases đáp ứng mọi byte/pixel budget ở mục 14.6. Runtime paths static/local, chỉ base64 bốn logo; không caller key mới hoặc network/browser runtime. PNG type và GD decode được kiểm tra trước render, decode resource được giải phóng. Kiểm tra chỉ header/dimensions không đủ: PNG bị truncate sau 33-byte header vẫn được getimagesize nhận ra; guard decode thật từ chối trường hợp này.
- Đã retrace production Controller → intake ownership/template resolver → DTO → Blade → Dompdf → storage/File. Test layout dùng data thu từ production HTTP caller; thêm shared private legal-body hash assertion vào layout gate để GPHL/Hawk3 legal wording/PII/privacy checks vẫn chạy độc lập với date assertion đang fail ngoài scope. Giữ toàn bộ existing date/mapping expectations, empty/Unicode/long-input/API/storage/cleanup/submit tests; không thêm Repository unit tests.
- Test impact: thay no-img gates bằng img count/class/alt/embedded bytes/PDF image-object checks; Dompdf callbacks xác nhận real image resolution, không broken placeholders. Sáu layout/multipage datasets kiểm tra canvas containment, logo size/gap, metadata/body separation và branding ổn định mọi trang. Thêm một asset-budget/transparency test và tám missing/truncated-PNG datasets. Invalid fixtures dùng resources tree tạm riêng, restore app base path và cleanup fixtures; không sửa/xóa asset repo để test.
- PNG/layout/legal/integrity gate: **15 tests / 5,059 assertions PASS**, 0 errors/failures (6.621s). Reports tại `/private/tmp/gap-691-png-logos.7Ky2W9/logo-tests-final.{xml,log}`.
- Full regression bản cuối: **570 tests / 7,907 assertions**, **7 errors + 21 failures**, 170.322s. Errors: một MM debug `addContactLog` mock + sáu Slack DNS; failures: 19 date assertions (`d/m/Y` vs working-tree `ymd`) + hai branch mapping assertions (baseline 14 vs working-tree 1). Không chỉnh các contracts/config/mocks này để làm gate xanh. Full report `full-suite-final.{xml,log}` trong thư mục artifact trên; không coi task là full-green.
- Một affected run song song full suite gặp thêm null stored PDF do `Storage::fake('test')` dùng chung disk và reset thư mục. Đây là nhiễu do cách chạy verification, không phải missing-logo regression; affected suites được chạy lại tuần tự sau full run, kết quả final ghi bên dưới. Không dựa vào concurrent affected report để kết luận pass/fail production.
- Final serial verification: Feature **56 tests / 5,663 assertions**, 0 errors + 17 failures (27.050s; 16 date + một mapping assertion); Service **12 tests / 113 assertions**, 0 errors + ba date failures (1.161s); focused PNG/layout/legal gate **15 tests / 5,059 assertions PASS**, 0 errors/failures (10.817s). Reports `feature-suite-serial`, `service-suite-serial`, `logo-tests-serial` là lượt tuần tự sau full run, không có null storage PDF error.
- Outside-scope source tiếp tục đổi trong serial verification: read-only check cuối lúc 13:51 +0700 xác nhận Hawk3 mapping đã trở lại branch 14 (source mtime 13:50:17), Service date constant đổi tiếp thành `Y/m/d` (mtime 13:51:20), khác snapshot `ymd` lúc full run. Không chỉnh/revert hai files này. Default mapping generation test đã pass ở serial snapshot; production mapping assertion còn fail vì source được load trước restoration. Không gộp các snapshot thành full-green cho worktree mới nhất, không chạy vòng lặp tests đuổi theo user edits ngoài scope; required PNG changes đã được gate độc lập/full-suite kiểm tra.
- PDF samples mới tại `/private/tmp/gap-691-css-remediation.B4vTpk/{gphl,tech,hawk3}.pdf`: GPHL/Hawk3 một trang, Tech hai trang. Đã review cả bốn `*-final-page-*.png` bằng PDFKit; logo/emblem/white wordmarks rõ trên nền, không nền trắng hoặc footer clipping, Tech logos lặp trên appendix. Source logos được capture riêng từ DOM/SVG và kiểm tra PNG preview, không AI generation. Samples dùng synthetic DTO date `06/10/2026`, không đại diện cho Service date formatter đang thay đổi ngoài scope.
- Local render probe bản cuối: process bootstrap + render cả ba PDF mất **1.71s wall / 0.72s user / 0.21s system** (`/usr/bin/time -p`), không gồm upload/API/MM và không phải server benchmark; timeout 60s deployment vẫn **UNVERIFIED**. Chrome headless tạm riêng port 9227 đã đóng, không tác động browser của user.
- Self-check: đúng source/brand counts/alpha/budgets, legal wording/hash và public contract giữ nguyên trong scope này; scan không có letterhead PNG/remote image/flex/linear-gradient dependencies trong ba runtime Blade, chỉ bốn local footer-logo PNG đã duyệt. `git diff --check` pass. Đã đọc lại đầy đủ ba canonical business specs và cập nhật SPEC-039; route inventory/DB relationships không cần sửa vì contract/schema không đổi. PNG implementation/visual gate đạt; regression gate còn mở cho deviations ngoài scope, không đánh dấu DONE.

## 15. Tech Via underline — Empty inline-block height (IMPLEMENTED / REGRESSION GATE OPEN)

### 15.1. Report, trace và root cause

- User báo underline của `Via:` nằm cao hơn text, khác Worker name/address, trong mẫu worker `mr Alex Taylor`, address `10 High Street, London, Greater London, SW1A 1AA`, intermediary trống. Đây là remediation cùng context Tech PDF presentation, mở rộng plan hiện hữu thay vì tạo file/phase mới.
- Đã đọc đầy đủ ba canonical living specs trước trace. Runtime chain: `PermanentCandidateIntakeController::generateWorkFinderAgreement` (line 46) → validated `WorkFinderAgreementRequest` → intake service `generateWorkFinderAgreement` (line 126) → `buildAgreementData` (line 380) → `WorkFinderAgreementData::toArray` → Tech Blade → Dompdf A4. Request cho `intermediary_name` missing/null/string; service `(string) ($data['intermediary_name'] ?? '')` cung cấp key rỗng hợp lệ, không phải thiếu DTO variable hoặc data lỗi.
- **CODE deviation / presentation**: `tech.blade.php:18` dùng `.field` inline-block, border-bottom 0.5pt, vertical-align top, không min-height; `tech.blade.php:62` render span rỗng khi intermediary trống. Border-bottom không bị đổi thành border-top: content height bằng 0 khiến border nằm ở đỉnh ô so với baseline text bên cạnh. Worker name/address có nội dung nên có chiều cao font; signature đã có height 12pt riêng.
- Read-only local reproduction dùng production `buildAgreementData` qua reflection, synthetic Candidate/draft address và Dompdf end_frame callback; không query/save DB, upload storage, gọi MM hoặc sửa source. Missing intermediary: Via border box `[56.01,154.3516,175.7480,0.5]` pt; populated intermediary: cùng x/y/width, height `14.3283` pt. Worker name/address ở cả hai cases height `14.3283` pt. Source `tech.html:354` dùng underscore text; Blade chủ động dùng border để bảo toàn dynamic data và wrapping.
- **DATA / CONFIG / EXTERNAL / INFRASTRUCTURE**: Không có bằng chứng input/config/PNG/network gây lỗi underline này. Current date format `Y/m/d` và các regression snapshots mục 14 giữ riêng, không thay đổi để sửa underline. HTML reference không thay đổi trong scope này.

### 15.2. Design và phạm vi nhỏ nhất

- Thêm class riêng cho span intermediary của dòng Via và CSS min-height tương đương một dòng text hiện tại (khoảng 13.83pt content height theo DejaVu Sans render). Chốt giá trị presentation bằng đo Dompdf sau approval; underline rỗng phải ở dưới glyphs/label, gần vị trí underline của ô có nội dung.
- Dùng `min-height`, không fixed height, để intermediary Unicode/dài vẫn wrap và tăng chiều cao tự nhiên; giữ font, line-height, border-bottom 0.5pt, width/min-width/max-width, vertical-align và escaping hiện tại. Không thêm underscore/NBSP hay tên giả vào dữ liệu/PDF chỉ để dựng chiều cao.
- Chỉ target ô Via; không sửa Worker name/address, signature/printed-name/date fields, legal body, Appendix, header/footer/logos, renderer hoặc dữ liệu service/API. Không migration, public contract, layer/utility mới hoặc implementation phases.

### 15.3. Files ownership và test impact

- `resources/views/pdf/work_finder_agreements/tech.blade.php`: CSS min-height cho Via và class hook trên existing intermediary span; minimal diff.
- `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`: thêm regression qua HTTP production generation, capture actual view data và đo field/text boxes bằng Dompdf callbacks; không giả định DTO input. Audit existing empty/Unicode/long fields, Tech layout/multipage và stored-PDF tests.
- Cần sửa đúng test `testWorkFinderAgreementRendersCandidateFieldsSafely`: existing `assertAgreementLogoImages($html, Storage::get($file->url), 'tech')` đang dùng `$file` trước `File::findOrFail`. Đưa lookup lên trước assertion để affected test chạy được; không thay date/mapping expectations hoặc business behavior nhằm làm suite xanh.
- `.business-spec/backend-business-flow-spec.md`: sau implementation/verification, ghi behavior Via blank-line layout trong SPEC-039; API inventory/DB relationship không đổi.
- Plan này: ghi approval, đo geometry trước/sau, PDF preview, self-check và test reports. Các user edits ngoài scope được bảo toàn; không format/lint.

### 15.4. Verification / acceptance

1. Cases missing key, null, empty string, whitespace-only, short/non-empty, Unicode/HTML-like và long intermediary theo request contract; worker name/address populated để tái hiện mixed-state bug. Giữ empty candidate-field suite hiện có.
2. HTTP 200/File resource/PDF/storage không đổi; rendered intermediary text vẫn bằng data từ production caller, escape đúng và không chứa filler character do fix thêm vào.
3. Đo border dưới ô Via nằm thấp hơn bottom của text label, chiều cao ô blank tương đương một dòng; trường hợp populated giữ vị trí/border/typography trong sai số nhỏ. Long input không bị fixed-height clip, không overlap đoạn tiếp theo/footer và không phá pagination.
4. Generate local PDFs với Via empty/populated/long rồi rasterize review; so sánh underline với Worker name/address. Giữ PNG/header/footer/Tech Appendix multipage regression gates.
5. Chạy affected Feature/Service và full `./vendor/bin/phpunit` tuần tự, không chạy song song vì fake storage dùng chung. Report riêng existing date/MM/Slack failures và mọi source drift, không claim full-green khi còn fail. Self-check against scope và minimal diff.

### 15.5. Approval

- [x] User duyệt thiết kế mục 15 bằng `ok` trước mọi code/template/test edits.
- [x] Implement, visual/geometry verification, chạy affected/full tests và cập nhật living spec; full-green gate vẫn mở vì failures ngoài scope.

### 15.6. Execution & self-check (2026-10-06)

- Đã dùng `debug-workflow` để trace/reproduce trước sửa và `backend-workflow` để thực hiện đúng approved scope. Database/types/Repository/Service/API layers không cần thay đổi; không tạo layer/file implementation/phase mới. Runtime diff chỉ thêm `.via-field { min-height: 13.83pt; }` và class vào existing span Via. Không đổi HTML reference, fonts, escaping, width, các field khác, legal wording, Appendix, assets, header/footer, date/mapping/MM/logging hoặc schema. Giữ unrelated user edits, bao gồm Feature date expectations đã đổi sang `Y/m/d` trước lúc patch.
- Thêm tám HTTP regression datasets: missing/null/empty/whitespace/populated/Unicode + HTML-like/long/unbroken intermediary, với Worker name/address có nội dung đúng report. Capture DTO từ production view composer; assert HTTP 200/File/storage/PDF, text không filler, HTML tags không trở thành markup, label/underline geometry, không overlap introduction, wrapping và baseline comparison. Request đi qua API `XssProtection::stripTags` nên HTML-like input trở thành `Nguyễn  & Sons` trước DTO; không đổi middleware hoặc dựa vào giả định raw request luôn tới Blade nguyên trạng. Width conversion assertions dùng tolerance 0.01pt để không fail vì floating-point chênh 1e-14pt.
- Đã audit stored-PDF, empty/Unicode/long candidate fields, six letterhead/multipage datasets, PNG budgets/integrity, legal hashes, request/controller/storage/cleanup/submit và Service generation/current-date tests. Sửa đúng existing `$file` lookup trước `assertAgreementLogoImages` trong candidate-rendering test. Không sửa date/mock/logging expectations để che failures, không thêm Repository unit tests hoặc formatter/linter.
- Production `buildAgreementData` reflection probe (synthetic unsaved Candidate, không DB/MM/storage API) tạo local before/after PDFs. Blank Via border-box height **0.5 → 14.33pt**, underline Y **154.3516 → 168.1816pt**, sau sửa thấp hơn label bottom **166.7406pt**. Populated height **14.32832 → 14.33pt**, delta **0.00168pt**, trong tolerance 0.01pt; Worker name/address boxes không đổi. Long 252-character input height **41.98496pt** trước/sau, 2 pages; unbroken 255-character input height **55.81328pt** trước/sau, 3 pages; không ép chiều cao hoặc thay pagination của populated cases. Sample render riêng khoảng **0.16–0.19s/PDF**, không phải benchmark API/server.
- PDFKit white-background previews đã review: blank before/after, populated, long, unbroken page 1/2 và Tech Appendix. Blank underline nay nằm dưới text; populated geometry/typography giữ nguyên, chuỗi dài wrap và đoạn tiếp theo không bị overlap. Long/unbroken pagination vốn có được giữ nguyên; header/footer/Appendix/PNG regression gates pass. Samples/report/script tại `/private/tmp/gap-691-via-underline.3zaVdG/`: `{empty,populated,long,unbroken}-{before,after}.pdf`, `*-final-page-*.png`, `geometry.json`, `render.php`.
- Verification chạy **tuần tự** để không reset chung fake storage: focused **26 tests / 5,795 assertions PASS** (15.993s); affected Feature **64 tests / 6,789 assertions PASS** (23.783s); affected Service **12 tests / 113 assertions**, còn **3 date failures** (4.091s; expected d/m/Y vs code Y/m/d). Full `./vendor/bin/phpunit`: **578 tests / 9,037 assertions**, **7 errors + 3 failures** (02:11.593). Errors: một MM `addContactLog` mock do debug upload baseline, sáu Slack DNS; failures: ba Service current-day/midnight date datasets. Không có Via/layout/PNG/mapping failures ở fresh full snapshot. JUnit/log reports `focused-tests`, `feature-tests`, `service-tests`, `full-suite` trong artifact directory trên.
- Self-check: implementation đúng mục 15, không filler/public contract/schema/migration/deployment changes; minimal runtime diff 2 added/1 removed lines; existing unrelated user changes không sửa/revert. `git diff --check` pass trên affected files. SPEC-039 living business spec ghi blank Via behavior, middleware/caller facts và fresh regression evidence; route inventory/DB relationships không cần đổi vì API/schema không đổi. Scoped fix + visual/Feature gates đạt, **không đánh dấu full task DONE/full-green** khi required Service/full suite còn outside-scope regressions; server timeout/deployment vẫn chưa xác minh.
