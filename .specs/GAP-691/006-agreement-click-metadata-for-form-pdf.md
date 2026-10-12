# SPEC: GAP-691 — Agreement click metadata cho FE export Permanent form PDF

> **Trạng thái**: `DONE` baseline và amendment §11 (backend/docs/tests; FE handoff separate)
> **Ngày tạo**: 2026-10-08
> **Author**: Codex
> **Related**: [Permanent form PDF/MM upload](005-permanent-intake-form-pdf-mm-upload.md), [GAP-691 implementation plan](GAP-691-implementation-plan.md), [Living flow SPEC-039](../../.business-spec/backend-business-flow-spec.md#spec-039--permanent-candidate-intake-gap-691)

## 1. Tổng quan

**Yêu cầu gốc**: User yêu cầu plan mới cho phương án 1: API `POST /api/candidate/me/jobs/{jobId}/work_finder_agreement/click` trả IP và thời gian đã lưu; FE đưa hai giá trị này vào PDF `permanent_candidate_form` lúc export rồi upload qua API hiện hữu.

Đây là task plan riêng theo yêu cầu user, không mở rộng retrospective approval của các plan liên quan. Phạm vi implementation trong repo này là backend API, docs và tests; phần FE được mô tả thành integration contract/handoff vì chưa có frontend repository được chỉ định.

### 1.1. Baseline đã trace

- Đã đọc ba canonical living specs: business-flow, API-route-inventory, database-relationship.
- Controller `PermanentCandidateIntakeController::agreementClick` lấy `auth()->user()`, route job ID, `Carbon::now()` và `$request->ip()` rồi gọi Service; hiện trả `Status::ok('Agreement click recorded')`.
- `PermanentCandidateIntakeService::recordAgreementClick` xác minh Candidate sở hữu job, gọi timing repository và có return type `void`.
- `CandidateTimingRepository::recordWorkFinderAgreementClick` firstOrCreate row theo candidate/job, chỉ update khi timestamp đang null, rồi `refresh()` và trả Model. Service hiện bỏ kết quả này.
- `CandidateTiming` hiện chưa khai báo cast cho click timestamp; runtime value từ database có thể là string dù PHPDoc ghi Carbon. Implementation phải parse timestamp từ persisted value, không assume Carbon instance.
- `Status::ok()` không sử dụng `$extraData`; shared Resource chỉ serialize `$columns`. Truyền thêm metadata vào `Status::ok()` hiện tại sẽ không đưa metadata ra response.
- FE-exported form upload hiện yêu cầu PDF và `Gap-Job-ID`, lưu job-scoped file rồi được submit/MM dùng lại. Backend không sửa nội dung PDF.
- **CODE deviation**: chưa thấy khác baseline click behavior của living spec. **DATA/CONFIG/EXTERNAL/INFRASTRUCTURE**: production records, timezone/proxy settings và deployed clients chưa xác minh. Source app timezone hiện UTC; `TrustProxies` hiện trust `*`. IP được resolve theo middleware hiện hữu; không thay proxy configuration trong task.

## 2. Database Design

N/A — dùng cột hiện hữu trên `candidate_timings`:

| Field | Semantics |
|---|---|
| candidate_id + job_id | Timing thuộc Candidate/job đã xác minh ownership |
| work_finder_agreement_link_clicked_at | Thời điểm click Agreement đầu tiên; không ghi đè khi gọi lại |
| work_finder_agreement_link_clicked_ip | IP của click đầu tiên; hỗ trợ IPv4/IPv6, cột length 45 |

Không thêm migration, file metadata column, consent timestamp hay quan hệ mới. Không đổi casts của Model để tránh ảnh hưởng các caller/test ngoài scope.

## 3. API Contract

### 3.1. Endpoint và request

```http
POST /api/candidate/me/jobs/{jobId}/work_finder_agreement/click
Authorization: Bearer <candidate-token>
```

- Route/middleware giữ `api`, `auth:candidateApi`, `checkCandidateLockEdit`.
- `jobId`: route parameter integer theo Controller hiện hữu; phải có CandidateJob thuộc Candidate đang đăng nhập. Không thêm rule hoặc thay status route-binding hiện hữu.
- Không có required request body/query fields, không yêu cầu `Gap-Job-ID` cho click route.
- FormRequest **N/A**: không bổ sung client input; IP/time lấy server-side. Client truyền `ip`, `clicked_at` hoặc candidate/job identity trong body không điều khiển persisted metadata/response.

### 3.2. Success — HTTP 200

Giữ success/message/detail hiện hữu, thêm **hai top-level fields**, không có `data` wrapper:

```json
{
  "success": true,
  "message": "Agreement click recorded",
  "detail": "",
  "clicked_at": "2026-10-08T09:15:30+00:00",
  "ip": "192.0.2.10"
}
```

| Field | Type | Rule |
|---|---|---|
| success | boolean | true |
| message | string | Giữ existing message |
| detail | string | Empty string như hiện tại |
| clicked_at | string, date-time | Giá trị DB sau persistence; ISO 8601, UTC `+00:00`, second precision |
| ip | string hoặc null | IP đã persist; nullable chỉ cho legacy timing thiếu IP |

Gọi lại ở thời gian/IP khác vẫn trả nguyên `clicked_at`/`ip` của click đầu tiên. Response không lấy trực tiếp current request IP/time sau khi repository trả kết quả. First-click semantics giữ nguyên cả khi record đã tồn tại từ trước deploy.

Legacy row có timestamp nhưng thiếu IP trả `ip: null`, không lấy IP hiện tại để giả làm IP lần đầu. Không backfill legacy records trong task. Timestamp phải có sau successful click; nếu persisted timestamp vẫn thiếu, trả custom Candidate API error HTTP 500 thay vì fake success/timestamp hiện tại.

### 3.3. Errors

| HTTP | Contract / condition |
|---|---|
| 401 | Candidate auth thiếu/invalid; existing error handling |
| 400 | Profile locked hoặc job state bị existing lock middleware chặn; envelope hiện hữu |
| 404 | `candidateJobNotFound`, code 1015; job không tồn tại/không thuộc Candidate; không expose timing của Candidate khác |
| 500 | Không lấy được persisted timestamp sau write; reuse existing `severError`, code 1005, qua `App\Exceptions\Api\Candidate\APIErrorException` |

Error responses giữ Candidate Status envelope, không thêm click metadata và không đổi shared Status/error catalog. Thông điệp cho missing metadata: `Agreement click metadata is unavailable.`; khai báo const trong Service. Không throw generic PHP exceptions.

## 4. Business Logic và FE integration

### 4.1. Backend

1. Controller lấy server request context và gọi existing Service method.
2. Service giữ ownership validation trước timing writes.
3. Repository giữ first-click-only write và refresh existing row; không thêm query method/logic/transaction nếu không cần.
4. Service dùng Model returned từ repository: đọc hai persisted fields, kiểm tra timestamp, parse timestamp với app timezone cho raw DB value rồi convert UTC và format bằng constant. Không dùng current request timestamp/IP làm response fallback.
5. Service trả array `{clicked_at, ip}`; contract method đổi `void` → `array` (docblock định nghĩa shape). Controller chuyển kết quả vào dedicated Resource và giữ success message.
6. Resource mới serialize success/message/detail/metadata theo `$columns`, HTTP 200. Không sửa `Status::ok`, shared Resource hoặc other endpoint responses.

Không query trong loop; không thêm transaction quanh read/refresh. Không inject Service vào Service. Internal helpers nếu cần phải private. Existing repository mutation return `Model` không phải nullable lookup mới; giữ contract hiện hữu.

### 4.2. FE handoff / acceptance

1. User mở Agreement → FE gọi click endpoint cho đúng job và chờ response thành công.
2. FE giữ metadata theo Candidate session/job; dùng response `clicked_at` và `ip` khi export form. Không dùng browser clock hoặc dịch vụ client-IP khác làm nguồn dữ liệu.
3. Form PDF render label **Agreement first clicked at** và **Agreement first click IP**. Đây là metadata mở Agreement, không phải consent/signature/submit time.
4. FE hiển thị thời gian theo một timezone thống nhất và ghi timezone/UTC offset trên PDF; đề xuất render UTC từ response để QA đối chiếu trực tiếp. Không loại timezone khỏi timestamp khi truyền dữ liệu.
5. Nếu `ip=null`, render `Not recorded`; không ghi IP giả. Nếu request lỗi/timeout hoặc metadata chưa có, dừng export/upload, hiển thị retry; retry vẫn lấy metadata lần đầu. Không xóa dữ liệu form khi retry.
6. FE đưa metadata vào PDF rồi upload `permanent_candidate_form` với valid Candidate token và `Gap-Job-ID`; submit tiếp tục dùng returned file ID như hiện tại.
7. Export nhiều lần dùng metadata lần đầu từ API. Session/job thay đổi phải lấy metadata đúng context, không reuse metadata của Candidate/job khác.

Frontend code và PDF layout implementation **chưa nằm trong backend execution ownership**. Docs cung cấp contract để FE thực hiện; backend task không được báo FE integration đã hoàn tất nếu chưa có evidence từ frontend. Backend không kiểm tra/chứng thực metadata FE thực sự render trong uploaded PDF; DB vẫn là nguồn đối chiếu.

## 5. Data Origin & Call Chain

```text
Candidate token + route jobId + server request IP/current clock
  → PermanentCandidateIntakeController::agreementClick
  → PermanentCandidateIntakeService::recordAgreementClick
  → CandidateJobRepository::findByCandidateIdAndJobId (ownership)
  → CandidateTimingRepository::recordWorkFinderAgreementClick
      firstOrCreate → conditional write → refresh Model
  → Service formats persisted fields
  → WorkFinderAgreementClick Resource → HTTP 200
  → FE renders returned metadata into PDF → existing upload/submit/MM flow
```

| Value | Verified origin |
|---|---|
| Candidate identity | auth candidate guard; never body |
| jobId | existing route parameter + ownership check |
| incoming click IP/time | request->ip(), Carbon::now(), existing trusted-proxy behavior |
| response clicked_at/ip | refreshed DB timing row returned by repository; never body/current-request fallback |
| uploaded PDF/file ID | FE-exported PDF → existing upload endpoint → File resource ID |

## 6. Constants

- Service `public const AGREEMENT_CLICK_TIMESTAMP_FORMAT = 'Y-m-d\\TH:i:sP'` (PHP single-quoted format literal phải truyền một literal backslash cho `T`).
- Service `public const AGREEMENT_CLICK_RESPONSE_TIMEZONE = 'UTC'`.
- Service `public const ERROR_AGREEMENT_CLICK_METADATA_UNAVAILABLE = 'severError'` (existing config spelling), `public const MESSAGE_AGREEMENT_CLICK_METADATA_UNAVAILABLE = 'Agreement click metadata is unavailable.'`.
- Giữ existing Controller message constant và CandidateJob error constants. Không thêm statuses/cache keys/types.

## 7. Files cần tạo/sửa

| Owner | File | Change |
|---|---|---|
| Backend | `app/Http/Resources/Api/Candidate/WorkFinderAgreementClick.php` (new) | Dedicated success Resource extends project Resource, `$columns`: success/message/detail/clicked_at/ip; không sửa shared Status |
| Backend | `app/Contracts/Services/PermanentCandidateIntakeServiceInterface.php` | recordAgreementClick return array + shape docblock |
| Backend | `app/Services/PermanentCandidateIntakeService.php` | Use returned persisted timing, normalize timestamp, constants/custom error, metadata array |
| Backend | `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php` | Consume Service result and return dedicated Resource response; preserve JsonResponse public signature |
| Tests | `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Update first-click response checks, add scenarios below |
| Tests | `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Service result comes from repository Model, parse/timezone/custom failure coverage |
| Docs | `documents/Gap-API-Candidate.yaml` | Endpoint-specific success schema/example, nullable IP, errors and first-click semantics; keep shared Status schema unchanged |
| Living specs | `.business-spec/backend-business-flow-spec.md` | Update SPEC-039 and metadata FE handoff after implementation; actual results/deviations |
| Plan | This file | Approval, docs SHA/push, actual paths/diffs and validation/test/self-check evidence |

Repository, Model, route inventory và database relationships assessment: **N/A — no change**. Existing storage/FileService/MM/submit behavior không cần edit. Một agent thực hiện tuần tự; không yêu cầu delegation.

## 8. Test Impact Review & Cases

Audit existing callers/mocks/response assertions cho recordAgreementClick trước edits; đã tìm production caller duy nhất là Controller. Review full intake Feature/Service suites, shared Status coverage và upload/MM suites liên quan; update chỉ khi affected contract yêu cầu. Không viết Repository unit tests.

| Test scope | Acceptance |
|---|---|
| Feature first click | Freeze clock/IP, HTTP 200 có đủ năm top-level fields, no data/errors wrapper; timestamp/IP khớp actual persisted row |
| Feature repeated click | Đổi clock/IP, response và DB vẫn giữ pair đầu tiên; timing row không duplicate |
| Feature pre-existing timing | Existing timestamp/IP được trả lại, không overwrite |
| Feature body spoofing | Body ip/clicked_at/identity không đổi source of truth |
| Feature auth/ownership/lock | Missing auth 401, foreign/missing job 404, locked profile 400; không trả metadata hoặc ghi timing trái phép |
| Feature IPv6 | IPv6 lưu/trả nguyên value; không truncate IPv4/IPv6 |
| Feature legacy IP | Pre-existing timestamp + null IP → response null, timestamp unchanged, no silent backfill |
| Service serialization | Returned repository metadata khác incoming params; response lấy persisted pair; raw datetime string được parse đúng, timezone converted to UTC, second precision |
| Service invalid state | Missing persisted timestamp → custom Candidate APIErrorException / existing 500 error; không synthesize success |
| Regression | Config/agreement/submit/file upload/MM contracts và error envelopes giữ behavior ngoài scope |
| FE QA handoff | PDF hiển thị metadata đúng response và timezone; failed click không export/upload, retry/context switching dùng đúng pair; chưa claim executed nếu FE repo chưa được thực hiện |

Unit mocks dùng actual persisted field names/type đã trace; Feature tests chứng minh production caller cung cấp data, không chỉ test DTO với fabricated payload. Restore frozen clocks/config sau tests.

## 9. Execution phases và gates

Hai phases bắt buộc do API contract/docs thay đổi; không thêm skeleton phase.

### Phase 1 — Docs-first synchronization

**Input**: user approve plan này; read docs repo instructions/git state và confirm owned files. Phase này phải hoàn tất trước implementation PHP.

**Owned outputs**:

- `~/projects/crs-api-docs/docs/api/candidate/post-me-jobs-jobid-work-finder-agreement-click.md`: request/auth/ownership, five-field success schema, UTC/nullability, first/repeated-click examples, 400/401/404/500 contracts, planned/not-yet-deployed status.
- `~/projects/crs-api-docs/docs/flows/permanent-intake.md`: FE metadata/export/upload sequence, event semantics và trust boundary; không sửa unrelated stale workflow sections.
- `~/projects/crs-api-docs/docs/api/candidate/post-me-files-type.md`: targeted cross-link cho `permanent_candidate_form` PDF FE embedding; upload request/response rules unchanged.
- Backend `documents/Gap-API-Candidate.yaml`: same endpoint-specific contract, without modifying generic Status schema. Docs repo hiện Markdown-first, historical YAML source reference; không copy toàn bộ OpenAPI sang docs repo.

**Acceptance/gate**: docs/OpenAPI schema/examples agree with §3; docs mark planned backend contract not yet deployed; parse/schema check affected YAML bằng existing available tool, validate examples against schema, `npm run build` trong docs repo và `git diff --check`. Không tự chạy formatter/linter. Stage task-owned docs files only, commit docs repo và normal push remote main; safely integrate remote updates và rerun checks nếu integration ảnh hưởng docs. Ghi actual files/diff/checks/docs SHA/successful push vào §10. Không stage/commit/push backend.

Nếu docs repo unavailable/unwritable hoặc validation/commit/push chưa PASS, report blocker và không bắt đầu Phase 2. Approval workspace rules đã authorize docs commit/push; không xin separate permission trừ actual sandbox approval block.

### Phase 2 — Backend implementation, regression, living spec

**Input/dependency**: Phase 1 PASS; approved five-field contract frozen. Read relevant backend/architecture skills và current workspace trước edits; preserve unrelated user changes.

**Execution order**: scan approved contracts → schema/types N/A → reuse repository contract/return → Service return/format logic → dedicated Resource/Controller → test impact review/tests → living spec/plan evidence.

**Output/acceptance**: API trả persisted first-click metadata, errors/auth unchanged, docs/backend response agree; minimal diff đúng §7. FE handoff documented, frontend execution tracked separately. Không PDF mutation, deployment, migration hoặc MM calls thực tế.

**Test gate**: affected `PermanentCandidateIntakeTest`, `PermanentCandidateIntakeServiceTest`, MeFile và relevant MM/upload/shared-Status suites phát hiện qua test audit; full `./vendor/bin/phpunit` phải PASS trước backend completion. Report unrelated environment failures riêng, không sửa production/shared config để xanh. Self-check original plan, architecture, constants, return types, private helpers, no N+1/read transactions, data provenance và preserved workspace diff.

## 10. Approval & execution evidence

- [x] User approve plan mới / additive click response contract (2026-10-08, “ok”).
- [x] Phase 1 docs/OpenAPI validation, docs commit + push main PASS; SHA: `4e66afc444c89416e60696267593859482fa39d2`.
- [x] Phase 2 affected/full PHPUnit + self-check PASS.
- [x] Living spec cập nhật current implemented behavior; actual changed paths/test evidence recorded.
- [ ] FE integration/QA evidence: separate handoff, pending frontend ownership.

Phase 1 PASS: ba owned Markdown pages trong crs-api-docs (+74 lines), backend `documents/Gap-API-Candidate.yaml` (+43 lines). Parsed YAML bằng available js-yaml và compile endpoint response schema bằng Ajv/ajv-formats; success/legacy-null-IP/IPv6 examples PASS, invalid datetime rejected. `npm run build` PASS (log `/private/tmp/gap-691-click-docs-build.log`), git diff --check PASS. Docs commit/push `origin main` thành công (`4324ec3..4e66afc`); không commit/push backend. Docs đánh dấu planned/not yet deployed. Không có docs repo AGENTS bổ sung từ lượt kiểm tra trước; preserve unrelated changes.

### Phase 2 implementation / test audit

- Implemented contract/Service/Controller và new `WorkFinderAgreementClick` Resource đúng owned paths. Repository first-click conditional write/refresh được reuse không edit; không thay Model casts, shared Resource/Status, routes, FileService/upload/submit/MM hoặc proxy config.
- Test audit tìm production caller duy nhất Controller; existing Feature first-click case được nâng lên exact five-field response + frozen clock/repeated-call checks. Added six Feature cases/datasets (pre-existing IPv4/IPv6/null IP; spoofed body with real IPv6; unauthenticated/no-write; missing persisted timestamp HTTP 500), foreign/missing-job/locked response assertions strengthened. Added six Service cases/datasets (raw DB/legacy IP/non-UTC/offset+precision; ownership before timing write; missing timestamp custom 500). Existing test helper chỉ thêm optional timing dependency để reuse setup, không tạo Repository unit tests.
- Initial focused unit fixtures failed because Candidate primary key `id` không fillable qua constructor; sửa new fixtures bằng explicit id assignment theo existing model behavior, không sửa production Model/Service cho fixture. Focused gate PASS **13 tests / 67 assertions**, 2.768s; reports `/private/tmp/gap-691-click-focused.{log,xml}`.
- Affected gate PASS **142 tests / 7,100 assertions**, 34.442s: Intake Feature 74, Intake Service 18, MeFile 17, Compliance Files 4, Consultant Files 11, MM Unit 5, MM Job 8, FileUtility 5. Reports `/private/tmp/gap-691-click-affected.{log,xml}`. Feature tests đi qua actual auth/Controller/Service/Repository/SQLite persistence; external file/MM boundaries giữ fake/mock conventions. Date/time test clocks reset in finally; config restored by per-test Laravel app lifecycle.
- Living spec SPEC-039 updated metadata response/FE handoff; no schema/routes/relationship change. Full default `./vendor/bin/phpunit` PASS **612 tests / 9,114 assertions**, 02:26.037, zero failures/errors, no LOG_CHANNEL override; `/private/tmp/gap-691-click-full.{log,xml}`. No manual migrations, formatter/linter, backend stage/commit/push hoặc production DB/ClamAV/MM calls; existing test harness migrations/seeding chạy SQLite in-memory.
- Backend completion không đồng nghĩa FE PDF/deployment đã được verify; FE handoff remains outside this repository ownership.

### Final docs synchronization / self-check

- Docs follow-up chuyển task annotation từ pending backend verification sang implemented/verified locally, vẫn giữ deployment/FE unverified. Rebuilt docs PASS và git diff --check PASS; log `/private/tmp/gap-691-click-docs-final-build.log`. Final docs commit `82378561aba371eba34caae2ed04ec7d9875f2a9` normal push `origin main` thành công (`4e66afc..8237856`), repo clean. Backend YAML description đồng bộ local verification; endpoint schema không đổi từ Phase 1.
- Self-check **PASS**: five-field HTTP response đúng contract, persisted first-click data provenance verified qua real production HTTP chain trong Feature tests; UTC/raw datetime/null-IP/IPv6/spoofing/error/no-write coverage passes. No extra queries/transactions/loops/Service injection; constants/custom exception đúng convention. Controller only delegates/serializes, dedicated Resource không thay shared success/error contracts. Single-record Repository contracts/implementation không edit. New helper public exposure không phát sinh; private test helper optional dependency chỉ phục vụ affected Service tests.
- Final owned implementation paths: Service contract, intake Service, intake Controller, new WorkFinderAgreementClick Resource, two intake test files; documentation paths: backend Candidate YAML, three owned crs-api-docs Markdown pages, living business flow và this plan. Route inventory/database spec N/A; untouched unrelated user workspace changes preserved. Backend chưa stage/commit/push/deploy.
- FE acceptance checklist chưa executed vì không có frontend ownership/repo: await click, render server pair with UTC offset/null-IP fallback, scoped session/job data, stop export on errors, existing PDF upload/submit. Backend deliverable complete; FE implementation/QA tracked separately.

## 11. Amendment — Trả clicked_at trực tiếp từ timing (2026-10-08, DONE)

### 11.1. Yêu cầu / diagnosis

User đã sửa Service thành `'clicked_at' => $timing->work_finder_agreement_link_clicked_at` và yêu cầu rà soát/update test cùng các phần liên quan. Mở rộng plan 006 cùng scope, không tạo plan mới. Baseline §1–10 và test counts phía trên là historical evidence cho ISO contract cũ; user approve amendment bằng “ok” ngày 2026-10-08.

- Trace verified: Repository vẫn write-first-only + refresh, CandidateTiming không cast timestamp, Service trả field raw, Controller chuyển array qua dedicated Resource không format. Với DB timestamp hiện hữu response là string như `2026-10-08 09:15:30`, không thêm `T`, offset hoặc normalize timezone/precision.
- **CODE deviation** so với current living spec và approved baseline: không còn ISO 8601 UTC conversion. DB/auth/IP/first-click/error handling vẫn giữ behavior; không có evidence DATA/EXTERNAL/INFRASTRUCTURE deviation mới. App timezone source hiện UTC nhưng response không encode timezone và task không xác minh deployment timezone.
- Unit-only baseline (không chạy DB/migrations): `./vendor/bin/phpunit tests/Unit/Services/PermanentCandidateIntakeServiceTest.php --filter AgreementClick` → **6 tests, 4 failures, 0 errors**. Bốn serialization datasets còn expected ISO/UTC format; ownership và missing-timestamp cases pass. Reports `/private/tmp/gap-691-click-raw-baseline.{log,xml}`.
- Feature expectations bị ảnh hưởng: first/repeated click, pre-existing IPv4/IPv6/null-IP metadata và IPv6/body-spoofing case đang assert ISO; DB assertions đã dùng raw timestamp nên giữ. Auth/ownership/lock/500/resource five-field semantics không cần đổi.
- Hai constants `AGREEMENT_CLICK_TIMESTAMP_FORMAT` và `AGREEMENT_CLICK_RESPONSE_TIMEZONE` hiện không còn caller (rg trong app/tests). CandidateTiming PHPDoc vẫn khai báo Carbon cho field không có cast; cần chỉnh annotation theo actual raw string/null, không thêm cast.

### 11.2. Contract thay thế (supersedes ISO/timezone parts of §3–6)

```json
{
  "success": true,
  "message": "Agreement click recorded",
  "detail": "",
  "clicked_at": "2026-10-08 09:15:30",
  "ip": "192.0.2.10"
}
```

- `clicked_at`: required string, nguyên giá trị persisted timestamp do Model trả sau refresh; không server-side format, parse, đổi timezone hoặc truncate precision. Ví dụ trên là actual normal DB representation, không cam kết ISO `date-time` hoặc timezone suffix. Không biến raw timestamp thành epoch/Carbon/date object.
- OpenAPI bỏ `format: date-time`, sửa description/examples thành raw stored timestamp string. Không dùng regex để giả định mọi database timestamp representation giống nhau.
- `ip`, first-click repeat behavior, null-IP legacy, error guard/500, ownership/auth/lock và five-field/no-wrapper response giữ nguyên. Metadata vẫn lấy persisted row, không current request/body fallback.
- FE render timestamp nguyên giá trị để đưa vào PDF; không append `UTC`/offset hoặc gọi browser Date parsing dựa trên assumed timezone. Nếu FE muốn đổi timezone/format, phải biết storage/write timezone qua deployment configuration được xác nhận riêng; task không thêm timezone field. Labels first click, session/job scoping, null-IP fallback và failure/retry handoff giữ nguyên.
- Preserve user raw-return edit; không restore ISO logic hoặc sửa unrelated runtime behavior.

### 11.3. Phase 1 — Docs-first synchronization

**Input**: user approve amendment. API contract/docs assessment **affected**, do response datetime representation thay đổi. Phải PASS trước test/annotation/constants edits.

**Owned files**:

- `~/projects/crs-api-docs/docs/api/candidate/post-me-jobs-jobid-work-finder-agreement-click.md`: success examples, clicked_at type/description, timezone/FE rendering guidance; phân biệt old ISO verification với pending raw-contract verification và deployment unverified.
- `~/projects/crs-api-docs/docs/flows/permanent-intake.md`: raw timestamp và FE handling, không ISO/UTC-offset promise.
- `~/projects/crs-api-docs/docs/api/candidate/post-me-files-type.md`: review existing metadata cross-link; chỉ sửa nếu còn timezone/schema wording thực sự cần đổi.
- `documents/Gap-API-Candidate.yaml`: targeted clicked_at schema/examples/description update, không đổi shared Status hoặc unrelated endpoints.

**Acceptance/gate**: schema/examples phản ánh passthrough raw string; docs mark planned/raw amendment not yet deployed, không reuse historical green counts như evidence cho source mới. YAML parse + affected schema/example validation bằng available js-yaml/Ajv; `npm run build` và git diff --check. Commit task-owned docs repo changes và normal push remote main theo authorization existing workspace rules, preserve unrelated changes/integrate remote safely. Record actual paths/diffs/validation/docs SHA/push ở §11.5. Không commit/push backend. Nếu gate blocked thì report blocker, không start Phase 2.

### 11.4. Phase 2 — Test alignment / related annotation cleanup

**Input/dependency**: Phase 1 PASS; read relevant skills/current source trước edits, preserve user runtime change.

| File | Minimal change |
|---|---|
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Update only affected response timestamp literals to actual raw DB strings; preserve exact response/DB/first-click/IPv6/null-IP/spoofing assertions |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Existing four datasets expect returned storedTimestamp unchanged; giữ non-UTC/offset+precision datasets để chứng minh không convert/truncate, giữ ownership và missing-timestamp coverage |
| `app/Services/PermanentCandidateIntakeService.php` | Remove only two unused ISO/timezone constants after rechecking references; raw-return method và custom guard giữ nguyên |
| `app/Models/CandidateTiming.php` | Correct only click timestamp PHPDoc to string/null according to traced production value; không thêm cast hoặc đổi persistence |
| `.business-spec/backend-business-flow-spec.md` | Current response raw timestamp, FE timezone guidance và actual verification evidence; historical baseline counts marked/superseded |
| This plan | Approved amendment, actual files/tests/docs sync/self-check evidence |

Controller, Resource, Service Interface shape, Repository, migrations, routes, upload/submit/MM assessment **N/A — behavior unchanged**. Không refactor helper/test structures hoặc sửa unrelated date/Agreement rendering tests. Không thêm Repository unit tests.

**Test audit/gate**: rerun focused AgreementClick unit/Feature cases; existing datasets được update thay vì thêm duplicate tests. Raw identity/nonconversion/precision coverage là changed-contract coverage; production Feature assertions phải match actual persisted values. Chạy affected intake Feature/Service và file/MM/job regression suites, sau đó full `./vendor/bin/phpunit`. Không formatter/linter; report unrelated failures riêng và không sửa shared runtime config để xanh. Self-check rằng user raw return giữ nguyên, docs/tests/runtime agree và không đổi first-click/IP/errors. Không manual migrations/deploy/backend stage/commit/push.

### 11.5. Approval / execution evidence

- [x] User approve raw clicked_at contract + docs-first amendment.
- [x] Phase 1 docs/schema validation + docs commit/push main PASS (`35f60e4730c4c8e242ec107837605af39d3e7986`).
- [x] Phase 2 focused/affected/full tests + self-check PASS.
- [x] Living spec current contract và FE handoff được synchronized.

Phase 1 PASS: updated click endpoint Markdown và permanent-intake flow (8 additions / 6 deletions), backend Candidate YAML clicked_at schema/examples (removed date-time format; raw timestamp). File-upload docs metadata cross-link reviewed, no format/timezone wording requiring edit. js-yaml parse/Ajv affected schema compilation + raw/null-IP/explicit-offset precision examples PASS, numeric timestamp rejected. npm run build + git diff --check PASS; log `/private/tmp/gap-691-click-raw-docs-build.log`. Docs commit/push origin main successful (`8237856..35f60e4`); preserve unrelated files, no backend commit/push. Docs raw amendment planned/pending backend verification, deployment unverified.

Phase 2: changed only three Feature response assertions và four Service dataset expected strings; giữ actual DB assertions, first/repeated-click/IP/null/IPv6/body spoof/error/ownership coverage. Non-UTC dataset vẫn kỳ vọng raw value unchanged; explicit-offset/microseconds dataset không convert/truncate. Existing tests là coverage cho changed contract, không thêm duplicate tests hoặc Repository unit tests. Removed only two unused ISO/timezone constants sau reference audit; CandidateTiming PHPDoc changed Carbon|null → string|null, không thêm cast. User raw-return line unchanged.

- Focused PASS **13 tests / 67 assertions**, 1.792s; `/private/tmp/gap-691-click-raw-focused.{log,xml}`.
- Affected PASS **142 tests / 7,100 assertions**, 29.981s; `/private/tmp/gap-691-click-raw-affected.{log,xml}`. Suites giữ Intake Feature/Service, MeFile, Compliance/Consultant Files, MM Unit/Job và FileUtility như prior gate.
- Living spec SPEC-039 current response/FE guidance đã chuyển raw timestamp; historical ISO full-green evidence được đánh dấu old snapshot, không dùng cho current state. Route inventory/database relationships N/A. Full default `./vendor/bin/phpunit` PASS **612 tests / 9,114 assertions**, 02:01.330, zero failures/errors, no LOG_CHANNEL override, `/private/tmp/gap-691-click-raw-full.{log,xml}`.
- No formatter/linter, backend stage/commit/push/deploy hoặc manual migrations/production DB/MM calls. PHPUnit uses existing SQLite in-memory setup. FE implementation/production timezone/PDF rendering remains unverified.

Final docs sync: two owned pages record raw-contract focused/affected/full PASS; docs rebuild + git diff --check PASS, log `/private/tmp/gap-691-click-raw-docs-final-build.log`. Commit `b53010aa8f355ba549464e8bcb71ed33d2a84ebe`, normal push origin main successful (`35f60e4..b53010a`); docs repo clean. Source/API docs/OpenAPI/living spec agree that raw string has no ISO/timezone guarantee.

Self-check PASS: raw-return line preserved; only affected timestamp expectations/unused constants/Model annotation updated, no casts/runtime format change or unrelated test refactor. Full production HTTP chain Feature tests verify persisted first-click/raw data, while Service datasets prove nonconversion/no precision truncation. First-click/IP/errors/security coverage remains passing; no duplicate/Repository tests. Unrelated user working-tree edits preserved. Backend changes remain uncommitted by agent.
