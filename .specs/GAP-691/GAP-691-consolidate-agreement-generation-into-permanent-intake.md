# SPEC: GAP-691 — Consolidate Work Finder Agreement into Permanent Candidate Intake Service

> **Trạng thái**: `DONE — BOTH PHASE GATES PASSED`
> **Ngày tạo**: 2026-10-05
> **Author**: Codex
> **Related follow-up**: [Agreement current date — plan riêng](001-work-finder-agreement-current-date.md); không nằm trong scope consolidation đã DONE.

## 1. Tổng quan và baseline

**Yêu cầu gốc**: Chuyển `WorkFinderAgreementService` vào `PermanentCandidateIntakeService`.

Gộp trực tiếp business workflow generation vào intake service, không inject hoặc delegate sang service cũ. Sau khi chuyển hết callers, xoá `WorkFinderAgreementService`, interface và binding riêng. Không thay đổi hành vi agreement/config/click/submit hoặc schema.

Baseline đã đọc từ ba living specs: `.business-spec/backend-business-flow-spec.md`, `.business-spec/backend-api-route-inventory.md`, `.business-spec/backend-database-relationship.md`; đã trace controller, hai service/contracts, provider, request/DTO/resource, CLI caller và tests.

### 1.1. Findings / deviations liên quan

- **CODE_FACT**: Controller hiện inject hai interfaces; chỉ agreement endpoint gọi `WorkFinderAgreementServiceInterface::generate()`. Intake service hiện chỉ có getConfig/recordAgreementClick/submit.
- **CODE deviation trong living CLI inventory**: `cmd:test` hiện gọi `agreementGenerate()` và tạo PDF/storage/File rồi `dd()`; inventory vẫn mô tả welfare check. Cập nhật caller và mô tả hiện hành, không sửa mail/welfare helpers hoặc chạy command này để thử.
- **CONFIG deviation trong working tree**: User đã thêm GPHL mappings cho branch IDs `57, 76, 77, 95, 99, 116, 117, 138, 139, 140, 141, 144, 150`. Config hiện giữ branch 14 → Hawk3 và entity IDs 1–7 → Tech. Living spec và production mapping test vẫn chỉ mô tả/assert branch 14. Giữ nguyên config; cập nhật assertion và living spec theo mapping đang có, không revert edit của user.
- **DATA/EXTERNAL/INFRASTRUCTURE**: Không query DB thật hoặc kiểm tra MM/storage deployment. User đã báo chạy migrate ở task trước, nhưng task này không thực hiện migrate hay rollback và không suy đoán trạng thái DB đang chạy.
- Dirty worktree có nhiều edits/staged files từ user/task trước; không stage, reset, format hoặc chỉnh unrelated code.

## 2. Database / data contracts

**N/A — không tạo/sửa migration, Model, Repository hoặc schema.**

- Reuse `candidate_jobs`, `jobs`, `branches`, `candidate_addresses`, `files` và repository contracts hiện có.
- Agreement vẫn tạo `files` record type `File::TYPE_WORK_FINDER_AGREEMENT`, scoped candidate/job, status/metadata qua `FileUtility::buildFileData()`.
- Giữ DTO `WorkFinderAgreementData` với đúng bảy keys: title, worker_name, worker_address, intermediary_name, signature, printed_name, date. Không thêm giả định về input/template fields.
- File persistence thất bại sau upload thì cleanup đúng object vừa upload; temp PDF luôn cleanup trong `finally`. Không mở rộng cleanup sang file/storage khác.

## 3. API và public service contract

### 3.1. HTTP contract giữ nguyên

`POST /api/candidate/me/permanent-intake/work-finder-agreement`

- Giữ controller action `generateWorkFinderAgreement(WorkFinderAgreementRequest $request): FileResource`, route, auth:candidateApi và lock middleware hiện có.
- FormRequest không đổi: job_id required integer min:1; candidate/address optional arrays; title/name/address/intermediary fields optional nullable strings theo max lengths hiện hành (255, postcode 20).
- Controller lấy authenticated Candidate và `$request->validated()` rồi gọi intake service method mới.
- HTTP 200 và File resource top-level giữ đúng tám fields: id, type, url, converted_file_url, status, original_file_name, uploaded_at, toe_signed_ip. Temporary URL vẫn do File resource tạo, không HTML/data wrapper.
- Error keys/messages, auth/validation và error response format giữ nguyên. Không thêm exception class/status mới.
- Không đổi getConfig, agreementClick, submit response, validation files[], MM payload, event/job/retry behavior.

### 3.2. Method mới trên existing interface / implementation

```php
public function generateWorkFinderAgreement(Candidate $candidate, array $data): File;
```

- Thêm File import vào `PermanentCandidateIntakeServiceInterface`; không sửa signatures ba methods hiện có.
- Service constructor giữ tám dependencies hiện hành, append `JobRepositoryInterface` và `BranchRepositoryInterface`; không thêm Service/ServiceInterface dependency.
- Reuse CandidateJob/Address/File repository injections đã có; không inject lại cùng repository dưới tên khác.
- Phase 2 Controller constructor chỉ còn `PermanentCandidateIntakeServiceInterface $intakeService`; đây là DI change nội bộ đã được chốt trong plan, không đổi HTTP action signature/request/resource.
- CLI `agreementGenerate()` đổi resolve/import/type annotation/call sang intake interface và method mới, không đổi payload hoặc chạy command.

## 4. Business logic (move, không đổi behavior)

1. Lấy job_id từ validated input; reuse private `getOwnedCandidateJob()` của intake service để xác minh ownership một lần, dùng error constants hiện có thay vì copy guard.
2. JobRepository → job.branch_id → BranchRepository → branch/legal entity config selectors.
3. Private `resolveTemplate(?Model $branch): string`: branch-first, entity fallback như cũ; không tự thêm default template hoặc remap branches.
4. Address repository lookup và private `buildAgreementData(Candidate $candidate, ?Model $address, array $data): WorkFinderAgreementData`: draft overrides, fallback Candidate/Address, signature/date rỗng, giữ escaping ở Blade.
5. View exists → render `view($view, $dto->toArray())` → Dompdf A4 → temp PDF → FileUtility upload → FileRepository create → return File.
6. Giữ custom APIErrorException handling, cleanup upload nếu persistence/generation lỗi, finally cleanup temp file; không đổi error classification.

**Invariants**:

- Generate không dispatch submit event, không gọi MM, không set is_permanent, không mutate profile/address/answers, không tự submit/sign agreement.
- Submit không tự gọi generate; FE tiếp tục gửi selected agreement File ID cùng CV như hiện tại.
- Không bọc PDF/storage hoặc reads vào submit transaction; không query trong loop.
- Không copy business logic vào Controller/Repository/Utility. Chỉ dùng FileUtility cho existing technical operations; DTO/Blade không query DB.
- Internal helpers mới/chuyển vào service phải `private`; không refactor private submit helpers hoặc unrelated methods.

## 5. Data origin và actual callers

| Dữ liệu / consumer | Nguồn đã xác minh | Contract sau chuyển |
|---|---|---|
| Candidate + job_id + optional draft | Controller auth + WorkFinderAgreementRequest validated | Truyền vào intake generate method |
| Candidate ownership | CandidateJobRepository::findByCandidateIdAndJobId qua getOwnedCandidateJob | Không duplicate query/guard |
| branch_id / legal_entity_id | JobRepository + BranchRepository records | Config branch-first/entity-fallback |
| worker/address fields | Candidate, Address lookup và explicit draft-key overrides | DTO bảy keys truyền qua caller production như trước |
| template/image paths | config/work_finder_agreement.php, views/pdf/work_finder_agreements, resource_path images | Không đổi paths/content/config selection |
| storage URL + File metadata | FileUtility upload/buildFileData → FileRepository | Candidate File resource tạo temporary URL |
| cmd:test | TestCommand::agreementGenerate resolve service, Candidate::find(4248), literal job_id=1 | Chỉ thay service/method; Candidate/ownership runtime có thể thiếu, chưa xác minh và không chạy command |
| existing unit constructors | Một `new PermanentCandidateIntakeService(...)` trong ServiceTest | Append hai repository mocks; submit không gọi chúng |

## 6. Constants và frozen contracts

- Move các public constants ERROR_TEMPLATE_NOT_FOUND, ERROR_GENERATION_FAILED, MESSAGE_TEMPLATE_NOT_FOUND, MESSAGE_GENERATION_FAILED, TEMPLATE_CONFIG_KEY, AGREEMENT_FILE_NAME, EMPTY_SIGNATURE, EMPTY_DATE sang intake service, giữ values.
- Reuse ERROR_CANDIDATE_JOB_NOT_FOUND / MESSAGE_CANDIDATE_JOB_NOT_FOUND hiện có; không tạo tên lỗi mới hoặc magic status/type.
- Fixed technical options trong generation (A4, temp prefix, selector fallback 0, empty converted-file URL) dùng named public constants trong intake service nếu cần khi di chuyển; values/behavior không đổi. Trace `FileUtility::buildFileData()` xác nhận argument rỗng cuối là converted-file URL, không phải signature IP; toe_signed_ip vẫn do File resource default, không thay đổi contract.
- Signature method mới, constructor service dependencies và error/resource/DTO contracts chốt ở Phase 1, không đổi ở Phase 2 nếu chưa cập nhật plan/approval.
- HTTP Controller action signatures giữ nguyên xuyên hai phases. Phase 1 không tạo/đổi Controller constructor contract; việc bỏ agreement dependency ở Phase 2 đã khai báo trước trong mục 3.2.

## 7. File changes / ownership

Owner duy nhất Codex; triển khai tuần tự, không sửa shared files song song.

| File | Phase | Thay đổi |
|---|---|---|
| app/Contracts/Services/PermanentCandidateIntakeServiceInterface.php | 1 | File import + generateWorkFinderAgreement signature |
| app/Services/PermanentCandidateIntakeService.php | 1 → 2 | Imports/constants/dependencies/safe skeleton, rồi move implementation + private helpers, reuse ownership guard |
| tests/Unit/Services/PermanentCandidateIntakeServiceTest.php | 1 → 2 | Append constructor mocks, skeleton fail-closed test, rồi thay bằng final generation ownership/template/error cleanup coverage |
| app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php | 2 | Bỏ old interface/dependency; gọi intake method; methods khác không đổi |
| app/Console/Commands/TestCommand.php | 2 | Cập nhật agreement caller; không đổi các mail/welfare methods, fixture inputs hoặc dd behavior |
| app/Providers/ServiceServiceProvider.php | 2 | Bỏ riêng singleton binding old agreement interface; giữ intake binding và bindings khác |
| app/Services/WorkFinderAgreementService.php | 2 | Delete sau khi đã chuyển toàn bộ callers/implementation |
| app/Contracts/Services/WorkFinderAgreementServiceInterface.php | 2 | Delete sau khi callers và binding không còn dùng |
| tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php | 2 | Verify Controller gọi intake contract, real pipeline/error cleanup, mapping assertion phù hợp current GPHL edits |
| .business-spec/backend-business-flow-spec.md | 2 | SPEC-039 service owner/source/call chain, cmd:test inventory, current GPHL mappings và regression evidence |

**Không đổi:** routes, request/resource/DTO, FileUtility, Repository/contracts/bindings, models/migrations/seeders, template config, Blade/CSS/images, OpenAPI HTTP contract, MM/event/job workflow, .business-spec route inventory/database relationship (không đổi routes/schema), các historical task plans và unrelated staged edits.

Không tạo standalone Agreement Service unit test hoặc Repository unit tests. Các hai file service cũ hiện untracked; xoá sau khi logic/callers đã chuyển và verified, không coi chúng chắc chắn phục hồi được bằng Git nếu chưa commit.

## 8. Hai implementation phases và test gates

### Phase 1 — Skeleton / Service Integration Boundary

- **Input/dependencies:** plan approve, source/contracts đã trace, existing route còn hoạt động qua service cũ.
- **Output:** compile-valid intake interface/method/imports/constants; constructor đủ mười repositories; updated existing unit constructor mocks. Chưa switch Controller/CLI/binding hoặc xoá old service.
- **Safe skeleton:** method mới có `// TODO[GAP-691-P2]: Move agreement generation and private template/data helpers here; reuse getOwnedCandidateJob and preserve upload/temp cleanup.` và throw existing custom Candidate APIErrorException generation-failed. Không delegate sang old service, không tạo PDF/File hoặc fake success.
- **Applicability:** task service refactor, không tạo Controller/Request/Response/Exception rỗng, không route mới. HTTP vẫn dùng old service trong Phase 1; safe skeleton chưa wired vào route. Không tạo hai bản workflow đầy đủ song song.
- **Acceptance:** existing submit/config/click signatures/behavior giữ nguyên; container resolve intake với các repositories hiện có; new skeleton failure có zero persistence/storage/MM side effects. Service public contract frozen sau gate.
- **Test gate:** syntax checks changed PHP files, existing PermanentCandidateIntakeService unit suite với hai mocks mới và skeleton fail-closed coverage pass. Không dùng old full-suite evidence của task trước thay gate hiện tại. Later phase chỉ bắt đầu khi gate pass.

### Phase 2 — Implementation Move / Caller Cutover / Cleanup

- **Input/dependencies:** Phase 1 gate pass và signature/error/data contracts đã frozen.
- **Output:** intake sở hữu generation/helper logic; Controller và CLI dùng new method; old agreement class/interface/binding bị xoá; unit/feature tests và living spec cập nhật.
- **Acceptance:** HTTP generation giữ 200/File resource/ownership/template/default-mapping/escaping/PDF layout/cleanup; generate không MM hoặc mutate submit state; old interface/class không còn runtime references. Current branch mappings/config/three Blade contents không bị đổi. Config/click/submit và MM-failure flows pass như trước.
- **Test gate:** all affected suites pass, sau đó full `LOG_CHANNEL=single DB_CONNECTION=sqlite DB_DATABASE=:memory: ./vendor/bin/phpunit` pass 100%, syntax + scoped diff check pass. Không formatter/linter tự động.
- **Merge/review:** Phase 1 là boundary-only, reviewable với dependencies trên; Phase 2 là atomic caller cutover. Chỉ deploy bản final Phase 2 nếu muốn loại old service khỏi runtime; không deploy file deletions trước caller update.

## 9. Mandatory test impact review

- Audit existing intake ServiceTest constructor/mock expectations và getConfig/click/submit tests; không cho mocks generation repositories vô tình tham gia submit flow.
- Update Feature tests để assert agreement Controller gọi đúng intake generate method với authenticated Candidate + validated data; verify binding tới class thật và endpoint signature/status/resource unchanged.
- Keep production-caller DTO assertions, Tech/GPHL/Hawk3 source/PDF/image/layout checks, unicode/escaping, default mapping branch-first/entity-fallback, storage/File owner/job scope và no-MM generation coverage.
- Update production mapping assertion đang lỗi so với user config: expected complete branch mapping gồm 14 → Hawk3 và 13 GPHL branch IDs mục 1.1; entity IDs 1–7 → Tech. Không chỉ đọc cùng config làm expected để tạo assertion tautological; không sửa config để test pass.
- Add final negative coverage: missing candidate-job ownership (no downstream reads/writes), mapping missing, mapped view absent, error after upload/File create failure cleanup, profile/is_permanent unchanged và no submit Event/MM calls. Reuse existing custom exception types/test disk; không lỗi generic được throw từ production code mới.
- Run affected `PermanentCandidateIntakeServiceTest`, `PermanentCandidateIntakeTest`, `MatchMakerPermanentSyncTest`, `SyncPermanentCandidateToMatchMakerJobTest`, `FileUtilityTest` và `MeFileTest`; full suite bao phủ consumers/Repository tests hiện có nhưng không thêm Repository unit tests.
- CLI caller chỉ syntax/static reference check và container/new method coverage từ Service/Feature; không execute cmd:test vì upload/persist/dd và hardcoded candidate context chưa xác minh. Nếu cần test CLI runtime thực tế, đó là validation scope riêng cần dữ liệu/target rõ.
- SQLite in-memory + test disk/mocked integrations; không migrate/rollback DB thực, không gọi MM/storage/email thực.

## 10. Self-check / handoff

1. Đối chiếu file ownership, constants, constructor/contract signatures, helper visibility và no Service→Service injection.
2. Search runtime/test/provider/CLI references old class/interface; chỉ historical plans hoặc explicit negative assertions được phép giữ tên cũ.
3. Verify source chain DTO/Blade/File vẫn như mục 5, không query trong loops/reads trong new transactions; generate không đi qua submit workflow.
4. Review minimal diff, giữ staged user config/assets/Blade và unrelated edits; không tự stage/commit.
5. Sau cả hai phase gates và full tests mới cập nhật trạng thái DONE/evidence, living spec ownership và CLI/config deviations đã trace.

## 11. Approval

- [x] User approve plan gộp service, gồm CLI caller update và current mapping test/spec alignment (user: `ok`).
- [x] Phase 1 gate pass: syntax checks; intake unit suite **5 tests / 66 assertions**, SQLite in-memory.
- [x] Phase 2 affected/full test gate pass.
- [x] Self-check và living documentation complete.

**Kết quả:** Phase 2 implementation/caller cutover/test impact review đã hoàn tất; scoped syntax/diff checks và affected suites pass **70 tests / 1,154 assertions** (03:23.247). Smoke gate pass **14 tests / 171 assertions**. Full `LOG_CHANNEL=single DB_CONNECTION=sqlite DB_DATABASE=:memory: ./vendor/bin/phpunit` pass **555 tests / 3,270 assertions** (05:54.590, 352.89 MB). Không thao tác DB thật hoặc chạy `cmd:test`.

### Final self-check evidence

- Intake contract có `generateWorkFinderAgreement(Candidate, array): File`, constructor mười Repository interfaces, không Service→Service injection. Existing getConfig/click/submit implementations không bị sửa trong task này.
- Controller và CLI agreement caller dùng intake contract; standalone service/interface và singleton binding đã xoá. Không còn old class/interface runtime references trong app/tests/routes/config/bootstrap; phase TODO đã được thay bằng implementation thật.
- Generation body được đối chiếu trực tiếp với source cũ: chỉ thay duplicate ownership guard bằng getOwnedCandidateJob và technical literals bằng constants; DTO build helper giữ byte-for-byte. Upload/temp cleanup, File metadata, custom exceptions và no-MM generation behavior giữ nguyên.
- Tech/GPHL/Hawk3 Blade hashes giữ nguyên; config và image assets không thay đổi. Current production mapping assertion bao phủ branch 14 → Hawk3, 13 GPHL branch IDs và entity 1–7 → Tech.
- Service/Feature regression cases mới bao phủ container binding, validated Controller delegation, ownership/missing job/unmapped template/missing view, custom/other throwable cleanup sau upload, persisted profile unchanged và no PermanentSubmittedEvent/MM.
- Living `.business-spec/backend-business-flow-spec.md` đã cập nhật service owner/call chain, CLI inventory, current GPHL config và fresh regression evidence. Route inventory/schema docs không đổi vì routes/schema không đổi.
- Existing unrelated/staged edits giữ nguyên; không formatter, stage/commit, migrate/rollback DB thật, external MM hoặc execute cmd:test.
