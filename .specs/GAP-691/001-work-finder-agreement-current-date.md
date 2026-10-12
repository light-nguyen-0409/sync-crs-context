# SPEC: GAP-691 — Work Finder Agreement dùng ngày hiện tại

> **Trạng thái**: `IMPLEMENTED — REGRESSION GATE BLOCKED BY EXISTING EDITS`
> **Ngày tạo**: 2026-10-06
> **Author**: Codex

## 1. Tổng quan

**Yêu cầu gốc:** `PermanentCandidateIntakeService #buildAgreementData thay date là thời gian hiện tại`.

Plan riêng theo yêu cầu user; đây là source of truth cho thay đổi date. Đã kiểm tra directory GAP-691: chưa có numbered plan, bắt đầu tại `001`; không đổi tên các unnumbered plans cũ.

Related completed plans: [service consolidation](GAP-691-consolidate-agreement-generation-into-permanent-intake.md), [Tech visual fidelity](GAP-691-agreement-word-visual-fidelity.md), [GPHL/Hawk3 templates](GAP-691-gphl-hawk3-agreement-templates.md). Plan mới supersede riêng quyết định date rỗng cho DTO/PDF generate sau triển khai; không sửa evidence lịch sử hoặc các workflow khác.

Không chia implementation phases vì user không yêu cầu. Triển khai một lượt sau approval, không tạo skeleton hoặc layer rỗng.

## 2. Database Design / layer applicability

**N/A — không đổi schema, migration, model hoặc repository.**

Database/migrations/models/repositories: N/A. Controller/FormRequest/Resource/DTO/Service contract/config/Blade: không cần sửa. Thay đổi chỉ ở Service internal DTO builder/constants và affected Service/Feature tests; không Service→Service injection, query mới, loop query hoặc transaction mới.

## 3. API Contract

`POST /api/candidate/me/permanent-intake/work-finder-agreement` giữ nguyên route, auth:candidateApi, checkCandidateLockEdit và public Service signature.

**Request/validation không đổi:** job_id required integer min:1; candidate/address optional arrays; title/name/address/intermediary optional nullable strings max:255, postcode max:20. Không thêm input date từ FE.

**Response không đổi:** HTTP 200 cùng File resource tám field top-level id/type/url/converted_file_url/status/original_file_name/uploaded_at/toe_signed_ip; URL vẫn là temporary URL, không HTML/data wrapper. Custom Candidate APIErrorException/error keys/status hiện hành giữ nguyên.

Không đổi config/click/submit, files[] validation hoặc MM/event/job workflow. Chỉ nội dung Date trong PDF mới được cập nhật.

## 4. Business Logic (Service Layer)

1. `date` lấy từ clock hiện tại lúc backend build DTO khi generate agreement: `Carbon::now()->format(self::AGREEMENT_DATE_FORMAT)`; dùng existing Carbon import và timezone đang được app áp dụng.
2. **Format đã duyệt: `d/m/Y`** (ví dụ `06/10/2026`), theo Date label của agreement và date-only convention tại DocumentService/ApplicationPackService. Lấy thời gian hiện tại nhưng chỉ hiển thị ngày, không giờ/phút; user approve plan bằng `ok`.
3. Khai báo `public const AGREEMENT_DATE_FORMAT = 'd/m/Y'`; bỏ EMPTY_DATE không còn consumer. Giữ EMPTY_SIGNATURE và signature rỗng; generation không được coi là candidate đã ký hoặc accepted.
4. Không đổi public service signature, DTO shape, request validation, route/auth/lock, HTTP 200/File resource/temporary URL, mapping branch/entity, Blade/CSS/images hoặc MM/submit/event workflow.
5. Chỉ PDF được generate sau thay đổi nhận ngày mới; không regenerate hoặc overwrite các File/PDF đã lưu. Giữ upload/File error handling và temp cleanup.

## 5. Data Origin & Call Chain / baseline

- Living baseline: SPEC-039 trong `.business-spec/backend-business-flow-spec.md`, agreement route trong `backend-api-route-inventory.md`, files/candidate-job relationships trong `backend-database-relationship.md`.
- **CODE:** `buildAgreementData()` truyền `self::EMPTY_DATE` vào constructor DTO; constant hiện chỉ có declaration và một consumer trong Service. Rule hiện hành vẫn là blank date, chưa có deviation so với living spec ở field này. Đổi sang current date là requested behavior change.
- Route → PermanentCandidateIntakeController::generateWorkFinderAgreement → authenticated Candidate + WorkFinderAgreementRequest::validated → intake generate → buildAgreementData → WorkFinderAgreementData::toArray → view($view, $dtoData) → Dompdf → storage/File → File resource.
- DTO `date` là readonly string; `toArray()` cung cấp key `date` thật cho production view caller. Tech Blade đã render escaped `{{ $date }}` ở dòng Date, không cần sửa Blade/DTO để hiển thị.
- GPHL/Hawk3 không có candidate/date placeholders; DTO date sẽ có giá trị nhưng hai documents vẫn static theo nguồn, không thêm date block hoặc sửa footer version dates.
- WorkFinderAgreementRequest không nhận date; thời gian phải do backend tạo, không lấy từ draft candidate, frontend hoặc thời điểm submit/sign.
- **CONFIG:** `config/app.php` hiện timezone UTC. Không tự đổi sang Europe/London hoặc Asia/Ho_Chi_Minh.
- **DATA/EXTERNAL/INFRASTRUCTURE:** không query DB thật, gọi MM/storage deployment hoặc suy đoán deployment timezone. Giữ mọi unrelated user edits trong method/service/tests.

## 6. Constants & Enums

- Thêm `public const AGREEMENT_DATE_FORMAT = 'd/m/Y'` trong PermanentCandidateIntakeService; format đã duyệt.
- Bỏ `EMPTY_DATE` sau khi đổi consumer duy nhất trong buildAgreementData; giữ EMPTY_SIGNATURE và các constants khác.
- Dùng Carbon import đã có; không hardcode timezone mới hoặc đổi config/app.php.

## 7. Files cần tạo/sửa / ownership

Owner duy nhất Codex; implementation tuần tự sau approval, minimal diff, không formatter.

| File | Thay đổi cho plan |
|---|---|
| app/Services/PermanentCandidateIntakeService.php | Đổi EMPTY_DATE thành AGREEMENT_DATE_FORMAT và truyền formatted current date trong buildAgreementData; không sửa các profile/address fallback khác |
| tests/Unit/Services/PermanentCandidateIntakeServiceTest.php | Thêm generation coverage qua public method/real DTO + view, repository mocks và test storage; frozen clock kiểm format/current date, signature vẫn rỗng |
| tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php | Cập nhật cả ba nhóm assertions date rỗng; freeze clock, verify date đi qua production caller/Tech rendered HTML; GPHL/Hawk3 vẫn không hiển thị date |
| .business-spec/backend-business-flow-spec.md | Sau implementation cập nhật SPEC-039: signature trống, date là ngày generate theo app timezone/format; ghi fresh regression evidence |
| .specs/GAP-691/001-work-finder-agreement-current-date.md | Approval/execution evidence cho plan; không sửa evidence lịch sử |

Không tạo file production mới, không đổi living route/schema docs vì route/schema không đổi. Không thêm Repository unit tests.

## 8. Test Cases / acceptance / gates

- Existing Feature assertions tại stored-PDF resource test, additionalAgreementRenderingProvider cases và safe candidate-field rendering đều đang expect `date === ''`; cập nhật tất cả, không chỉ một test.
- Freeze clock với expected string độc lập, ví dụ `2026-10-06 13:14:15 UTC` → `06/10/2026`; thêm midnight rollover case cho ngày tiếp theo. Reset test clock sau mỗi test, không để ảnh hưởng uploaded_at/auth hoặc các suites khác.
- Verify bằng public generate caller và View composer rằng real DTO date được cung cấp; Tech HTML chứa ngày đúng tại Date field. Không chỉ render Blade với mock date hoặc gọi private helper bằng reflection.
- GPHL/Hawk3 nhận DTO date mới nhưng HTML vẫn bằng static source view, không thêm candidate/date/signature nội dung. Signature trống; no MM/no submit event/profile mutation và File HTTP 200 contract giữ nguyên.
- Review/rerun Service và Feature intake suites, MeFile/FileUtility và permanent MM sync/job affected consumers; sau đó full `LOG_CHANNEL=single DB_CONNECTION=sqlite DB_DATABASE=:memory: ./vendor/bin/phpunit`.
- Syntax checks changed PHP files, scoped git diff check và self-check theo plan. Không formatter/linter, migrations/rollback DB thật, MM/storage thật hoặc execute cmd:test.
- Chỉ đánh dấu plan DONE sau fresh affected/full tests pass; unit result 100 tests / 370 assertions ở lượt trước là baseline, không dùng thay gate của plan.

## 9. Checklist trước khi approve / execution

- [x] User duyệt plan, gồm date-only format `d/m/Y` và app timezone hiện hành (UTC): `ok`.
- [x] Implement minimal Service/test changes, cập nhật living spec.
- [ ] Affected/full PHPUnit gates pass và self-check hoàn tất.

**Code date đã triển khai; chưa đánh dấu DONE vì affected/full gates bị các unrelated user edits làm fail. Chờ user quyết định scope xử lý baseline.**

### Execution / test impact review (2026-10-06)

- Production diff đúng hai dòng: EMPTY_DATE → AGREEMENT_DATE_FORMAT và DTO date → Carbon::now()->format(...). Giữ signature rỗng, DTO/API/template/assets/config và các user edits khác.
- Thêm ba Service test cases (current day, trước/sau midnight UTC) qua public generate/real DTO/view; cập nhật cả DTO và DOM Date assertions trong các Feature consumers. Laravel test teardown reset Carbon test clock.
- Syntax checks ba PHP files và scoped diff check pass. Smoke 18 tests / 269 assertions có 16 cases pass, hai failures ở baseline không liên quan date: production mapping expect GPHL branch 57 nhưng user config đã đổi thành 1; Hawk3 asset fixture expect hash a82263a3163d3139fee58660ecb9bad59b53a1efe69b4a2719258f00aaa475c1 nhưng user image hiện da14772b397a3ee547ce6a28f5e63de398b12f9bda733e2a5688f329c6950189.
- Không sửa config/image hoặc thay các source-hash/mapping expectations ngoài yêu cầu date để làm tests xanh. Tiếp tục affected/full gates; nếu cùng baseline failures còn tồn tại, cần user cho phép cập nhật expectations theo config/asset hiện tại hoặc user sửa lại những thay đổi đó. Chưa đánh dấu task DONE.
- Affected suites chạy đủ: **73 tests / 938 assertions, 1 error / 7 failures** (00:55.478). Bảy failures gồm sáu Hawk3 source-hash cases và một production-mapping case. Error tại MatchMakerPermanentSyncTest: user edit trong MatchMakerService đã comment guard `if (!$this->debugMode)`, làm debug flow gọi addContactLog ngoài mock expectations. Code/fixture MM này ngoài file ownership của date plan, không bị sửa; full suite đang chạy để xác minh phạm vi.
- Full `LOG_CHANNEL=single DB_CONNECTION=sqlite DB_DATABASE=:memory: ./vendor/bin/phpunit` đã chạy đủ: **555 tests / 3,015 assertions, 1 error / 7 failures** (03:23.904, 179.61 MB), đúng ba nhóm baseline issues trên, không có lỗi khác của date change. Không tuyên bố full suite pass.
- Final self-check: so source snapshot trước task, production Service diff chỉ hai dòng đã approve; all Blade/config/image hashes so đầu turn giữ nguyên, không Service/API/DTO/repository/schema hoặc MM behavior change. Signature rỗng, date được tạo tại generate, không ký/submit hoặc overwrite File cũ. Scoped syntax/diff checks pass; Carbon test clock được framework teardown reset.
- Re-run targeted date/intake suites không gồm unrelated baseline cases: **16 tests / 261 assertions PASS** (00:10.093), gồm Service/current-day/midnight và Tech HTTP/PDF/escaping/DOM Date field. Full regression gate vẫn chưa pass; cần user direction để xử lý ba nhóm baseline issues ngoài scope.
