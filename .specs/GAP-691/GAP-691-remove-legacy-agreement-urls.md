# SPEC: GAP-691 — Remove legacy Agreement URLs and group agreement views under pdf

> **Trạng thái**: `DONE — APPROVED / VERIFIED 2026-10-05`
> **Ngày tạo**: 2026-10-05
> **Author**: Codex

## 1. Tổng quan

**Yêu cầu gốc**: Xoá `agreement_url` khỏi bảng branches và entities, đồng thời bỏ các phần liên quan.

**Yêu cầu bổ sung**: Di chuyển folder agreement trong views vào `pdf`. Folder thực tế là `work_finder_agreements` (giữ spelling hiện hành, không tạo folder `work_fider_agreements`).

Tên thực tế đã xác minh trong source là `branches.work_finder_agreement_url` và `legal_entities.work_finder_agreement_url`. Không có bảng vật lý `entities` hoặc cột `agreement_url` cần đổi tên/xoá thêm trong phạm vi này.

Mục tiêu: bỏ hoàn toàn cấu hình URL agreement tĩnh cũ khỏi schema hiện hành, model, CRUD Branch, seeder và fixture tương ứng. Giữ nguyên luồng Blade → PDF → storage → `File` → File resource có `url`, HTTP 200 khi tạo agreement, và chỉ gửi MM khi submit cùng danh sách file.

Di chuyển cả ba Blade Tech/GPHL/Hawk3 sang `resources/views/pdf/work_finder_agreements/`; sửa các tham chiếu view tương ứng. Không đổi nội dung, màu sắc/CSS, placeholder hoặc layout PDF, không di chuyển `resources/images/work_finder_agreements/`.

Plan này thay thế các quyết định giữ URL tĩnh trong các plan GAP-691 cũ; không sửa/xoá lịch sử quyết định hoặc migration đã có.

### 1.1. Baseline và kiểm chứng

- Đã đọc ba living specs: `.business-spec/backend-business-flow-spec.md`, `.business-spec/backend-api-route-inventory.md`, `.business-spec/backend-database-relationship.md`, sau đó trace source.
- Source và baseline cùng mô tả hai cột legacy, Branch CRUD và URL seeder. Chưa thấy `CODE` deviation trong phạm vi này; đây là thay đổi được yêu cầu, không phải sửa một sai lệch đã xác nhận.
- `WorkFinderAgreementService::resolveTemplate()` dùng config theo branch ID rồi legal entity ID, không đọc URL legacy.
- **CONFIG deviation xác minh ở working tree khi bổ sung scope**: `config/work_finder_agreement.php` hiện có branch `14 → work_finder_agreements.hawk3`; living SPEC-039 và test production mapping vẫn ghi/assert branches rỗng. Giữ mapping user đang có, cập nhật view namespace/test/living spec tương ứng; không revert về branches rỗng. Deployment config vẫn chưa xác minh.
- Chưa kiểm tra DB đang chạy hoặc môi trường triển khai: trạng thái `DATA`, `CONFIG`, `EXTERNAL`, `INFRASTRUCTURE` chưa được xác minh. Không giả định migration cũ chưa chạy.

## 2. Database design và data contract

### 2.1. Forward migration mới

File dự kiến: `database/migrations/2026_10_05_110000_drop_work_finder_agreement_url_from_branches_and_legal_entities.php`.

| Bảng | `up()` | `down()` |
|---|---|---|
| `branches` | DROP `work_finder_agreement_url` | ADD nullable `text`, default NULL |
| `legal_entities` | DROP `work_finder_agreement_url` | ADD nullable `text`, default NULL |

- Giữ nguyên `2026_09_29_100000_add_permanent_intake_data_foundation.php`; migration mới chạy sau foundation và migration `2026_10_05_100000_add_journey_type_other_document_to_candidates_table.php` hiện có.
- Dùng schema contract đã có: cả hai cột phải tồn tại trước `up()` và không tồn tại trước `down()`. Không silently skip schema drift bằng conditional guards; nếu schema khác lịch sử migration thì dừng và xác minh trước triển khai.
- Không thay đổi bảng/quan hệ, index, foreign key, ID hoặc dữ liệu của các cột khác.
- Không copy URL cũ vào `files`, không tạo file mới và không truy cập/xoá storage hoặc tài liệu ngoài hệ thống.
- Không thêm transaction nghiệp vụ, truy vấn dữ liệu trong loop hoặc seed dữ liệu thay thế.

### 2.2. Cảnh báo mất dữ liệu và rollback

`up()` xoá vĩnh viễn các giá trị URL legacy trong hai cột. `down()` chỉ phục hồi schema nullable text, không phục hồi URL. Cần backup hai cặp `id`/URL trước triển khai nếu muốn có khả năng phục hồi dữ liệu. Rollback application cũ chỉ thực hiện sau khi phục hồi schema; dữ liệu muốn khôi phục phải lấy từ backup riêng.

Không chạy migration trên DB local/STG/production trong task này. Chỉ kiểm tra migrations trong SQLite `:memory:` của PHPUnit; triển khai DB thực cần xác nhận môi trường/target riêng.

## 3. API contract

### 3.1. Endpoints hiện có

- `GET /api/admin/branches`, `GET /api/admin/branches/{id}`.
- `POST /api/admin/branches`, `PUT /api/admin/branches/{id}`.
- Các endpoints tương ứng dưới `/api/compliance/branches`.
- Không thêm route/controller mới; giữ nguyên auth, validation các trường khác và status hiện có (Branch create 201, read/update 200).

### 3.2. Request

- Bỏ `work_finder_agreement_url` khỏi `$fields` và `fakeArray()` của `BranchAdd`/`BranchUpdate`.
- Request cũ vẫn có thể gửi key này: bỏ qua, không lưu và không phản hồi lại. Không thêm rule `prohibited` hoặc thay đổi cách xử lý unknown fields toàn cục.
- **Call-chain quan trọng**: Controller dùng `$request->toArray()` kế thừa Laravel Request, trả toàn bộ input; không dùng `JsonRequest::array()` có allowlist. Vì vậy phải bỏ key khỏi allowlist trong cả `BranchService::addBranch()` và `updateBranch()`, không chỉ sửa FormRequest/model.

### 3.3. Response

- Bỏ `work_finder_agreement_url` khỏi `$columns` của shared Compliance Branch resource; list/detail/create/update Admin và Compliance không còn key này, kể cả null.
- Shared Branches collection tạo từng Branch resource nên dùng cùng contract.
- LegalEntity resource hiện không expose key này; không cần sửa Controller/Resource LegalEntity.
- Giữ `File.url`, `converted_file_url`, `key_information_document_url`, registration/map/privacy URLs và các response fields khác.
- `/permanent-intake/config` tiếp tục chỉ trả approved documents như hiện tại; agreement API tiếp tục trả File resource, không HTML và không URL legacy.

## 4. Kiến trúc và layer applicability

- Sửa đúng các lớp hiện có: Model, FormRequest, Resource, Service, DatabaseSeeder, migration; thêm việc relocate Blade và cập nhật view config/tests.
- Không tạo Controller, Service contract, Repository, DTO, Exception, binding hoặc route rỗng: các public signatures và dependency boundaries hiện có vẫn hợp lệ.
- Repository và Service contracts không thay đổi; Service chỉ bỏ legacy input khỏi danh sách trường được ghi.
- Không refactor method khác, không chạy formatter/linter, không đụng các thay đổi ngoài task trong dirty worktree.

## 5. Data origin và call chain

1. Admin/Compliance BranchController nhận BranchAdd/BranchUpdate → `toArray()` → BranchService field filtering → BranchRepository create/save → DB. Gỡ field ở Service bảo đảm legacy input không tạo SQL nhắm cột đã drop.
2. BranchController read/list → BranchService/repository → Branch/Branches resource. Gỡ resource column bảo đảm schema response không phụ thuộc legacy model attribute.
3. DatabaseSeeder hiện gọi URL seeder ở testing/local/development/production. Bỏ đăng ký trước khi drop schema; sau đó xoá seeder chỉ dùng cho URL, CSV hai cột và test dành riêng cho seeder đó.
4. PermanentCandidateIntakeController → WorkFinderAgreementService → CandidateJob/job/branch lookup → config mapping (`branches` ưu tiên, fallback `legal_entities`) → DTO/view → PDF → FileUtility storage → FileRepository → File resource. Không có thao tác đọc hai URL legacy trong luồng này.
5. Permanent submit và MM sync đọc danh sách `File` hiện có; giữ nguyên file type và payload/MM integration.
6. `resolveTemplate()` trả nguyên view name từ config, sau đó `generate()` gọi `view()->exists($view)` và `view($view, $agreementData->toArray())`. Không có path hardcode cần sửa trong Service/Controller/DTO. Config và tests (view composers, render calls, providers và mapping assertions) phải dùng tên mới; image paths trong Blade vẫn lấy từ `resource_path('images/work_finder_agreements/...')` và giữ nguyên.

## 6. Constants / contracts không đổi

- Không thêm type/status/cache key/fixed business identifier mới.
- Giữ các constants hiện hành, gồm work finder agreement file type.
- Mapping selection không đổi: giữ branch 14 → Hawk3 và entity IDs 1–7 → Tech; không thêm/xoá branch/entity mapping khác. Chỉ đổi view values sang `pdf.work_finder_agreements.hawk3` / `pdf.work_finder_agreements.tech`; GPHL available nhưng không tự thêm mapping.
- Schema identifiers trong migration là tên cột/bảng, không phải business magic values cần thêm constants vào runtime đã bỏ field.

### 6.1. View relocation contract

| Template | Đường dẫn mới | View name mới |
|---|---|---|
| Tech | `resources/views/pdf/work_finder_agreements/tech.blade.php` | `pdf.work_finder_agreements.tech` |
| GPHL | `resources/views/pdf/work_finder_agreements/gphl.blade.php` | `pdf.work_finder_agreements.gphl` |
| Hawk3 | `resources/views/pdf/work_finder_agreements/hawk3.blade.php` | `pdf.work_finder_agreements.hawk3` |

- Move nguyên nội dung, không copy giữ alias/template trùng ở folder cũ; các PDF templates/layout khác trong `views/pdf` không đổi.
- Chốt namespace trong Phase 1 dưới dạng contract plan này; actual moves/config/test replacements là một integration change đồng bộ ở Phase 2, không expose skeleton view/PDF rỗng.

## 7. Danh sách file change và ownership

Owner duy nhất: Codex; triển khai tuần tự, không chỉnh shared files song song.

### Phase 1 — Integration boundary / retirement contract

**Modify:**

- `app/Models/Branch.php`: bỏ docblock property và fillable legacy.
- `app/Models/LegalEntity.php`: bỏ docblock property và fillable legacy.
- `app/Http/Requests/Api/Compliance/BranchAdd.php`: bỏ field/fake field.
- `app/Http/Requests/Api/Compliance/BranchUpdate.php`: bỏ field/fake field.
- `app/Http/Resources/Api/Compliance/Branch.php`: bỏ response column.
- `app/Services/BranchService.php`: bỏ legacy field khỏi add/update allowlists, không sửa business behavior khác.
- `database/seeders/DatabaseSeeder.php`: bỏ đăng ký URL seeder khỏi cả bốn environment lists, giữ thứ tự các seeders khác.
- `tests/Feature/Api/Admin/BranchesTest.php`: cập nhật fixture/assertions và thêm negative-contract coverage.
- `tests/Feature/Api/Compliance/BranchesTest.php`: tương tự Admin.

### Phase 2 — Schema removal / cleanup / verification

**Move (nội dung không đổi):**

- `resources/views/work_finder_agreements/tech.blade.php` → `resources/views/pdf/work_finder_agreements/tech.blade.php`.
- `resources/views/work_finder_agreements/gphl.blade.php` → `resources/views/pdf/work_finder_agreements/gphl.blade.php`.
- `resources/views/work_finder_agreements/hawk3.blade.php` → `resources/views/pdf/work_finder_agreements/hawk3.blade.php`.

**Modify:**

- `config/work_finder_agreement.php`: chỉ thêm `pdf.` vào view values, giữ branch 14 và entity IDs 1–7.
- `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`: đổi view names trong config overrides/composers/render/providers; cập nhật production mapping assertion giữ branch 14 → Hawk3; thêm kiểm tra view paths mới tồn tại, đường dẫn cũ không còn và HTTP generation dùng mapping thực tế vẫn render được.

**Create:**

- `database/migrations/2026_10_05_110000_drop_work_finder_agreement_url_from_branches_and_legal_entities.php`.
- `tests/Feature/Database/RemoveLegacyWorkFinderAgreementUrlsTest.php`: schema migration/seed/data preservation coverage; không phải Repository unit test.

**Delete:**

- `database/seeders/UpdateLegalEntityWorkFinderAgreementUrlsSeeder.php`.
- `database/seeders/data/legal_entity_work_finder_agreement_urls.csv`.
- `tests/Feature/Database/UpdateLegalEntityWorkFinderAgreementUrlsSeederTest.php`.

**Update living docs:**

- `.business-spec/backend-business-flow-spec.md`: Branch CRUD/seed/deployment và data register liên quan; ghi schema mới, cập nhật đường dẫn ba Blade/namespace cùng branch 14 mapping theo source; không đổi PDF/MM workflow.
- `.business-spec/backend-database-relationship.md`: bỏ legacy columns khỏi ERD/current dictionary, bổ sung forward migration và rollback/data-loss contract.
- `.business-spec/crs-matchmaker-crm-current-state.md`: bỏ hai legacy columns khỏi ERD hiện hành.

**Keep unchanged:** foundation migration, route inventory (không thay đổi routes/auth), Controller/Repository/contracts, agreement Service/DTO, nội dung ba Blade và image assets, các PDF templates khác, `documents/Gap-API-Candidate.yaml`, File resource/model và unrelated existing edits. Các assertions kiểm tra không có legacy key được phép giữ tên key; không xoá negative regression chỉ để search bằng không. Historical task plans giữ path cũ như decision history, không replace hàng loạt.

## 8. Implementation phases và gates

### Phase 1 — Skeleton / Integration Boundary

**Input/dependencies:** Plan đã approve; schema cũ còn hai cột; call chain/contracts trên đã xác minh.

**Output:** Compile-valid existing layers có retirement contract cuối cùng: không nhận/lưu/expose URL legacy trong Branch API; models không fillable; automatic seeding không gọi URL seeder. Schema, old seeder file và test cũ chưa xoá. View namespace/path contracts mục 6.1 được chốt, chưa di chuyển templates hoặc sửa config trước Phase 2.

**Scope:** Không có lớp mới để tạo skeleton rỗng. Không tạo migration `up()` no-op vì migration đó có thể bị đánh dấu applied sai. Những thay đổi đơn giản ở boundary hoàn thành thật, không fake success.

**Deferred owner marker:** `// TODO[GAP-691-P2]: Drop both legacy columns, remove URL seeder/CSV/test, relocate all three agreement views under pdf with config/test references, add schema/render regression coverage, and update living specs.` Marker này ghi trong plan; không thêm comment không cần thiết vào production method.

**Acceptance:** Legacy key không xuất hiện ở Branch list/detail/create/update; POST/PUT mang key cũ vẫn thành công theo status hiện hành nhưng không ghi giá trị mới; trường khác và auth không đổi; DatabaseSeeder không đăng ký URL seeder.

**Test gate:** PHP syntax checks các file sửa; Admin/Compliance Branches tests và existing URL seeder test đều pass trên schema cũ. Negative API tests xác minh input cũ bị bỏ qua; có thể assert giá trị DB legacy vẫn null trong Phase 1, sau Phase 2 đổi phần schema-specific assertion thành column/attribute absence. Không thay contract public sau gate.

### Phase 2 — Schema Removal / Full Regression

**Input/dependencies:** Phase 1 gate pass; runtime không còn phụ thuộc schema URL; schema/data contract mục 2 đã chốt.

**Output:** Migration thật drop columns; không còn URL seeder/CSV/registration/test; ba agreement Blade chỉ còn dưới `views/pdf/work_finder_agreements`, config/tests dùng namespace mới; schema/render coverage và living specs cập nhật.

**Acceptance:** Fresh migrate + testing seed thành công; cả hai cột absent; unrelated data/foreign keys giữ nguyên; down restores nullable text không restore values; up sau down thành công; agreement generation/upload/submit vẫn chạy sau drop schema và view relocation, HTTP 200/File URL giữ nguyên. Ba Blade giữ nội dung byte-for-byte so với trước move, image paths không đổi; view exists/render/PDF checks pass qua namespace mới, branch-first/entity-fallback giữ nguyên và không còn runtime/test tham chiếu view namespace cũ.

**Test gate:** Schema feature tests + toàn bộ affected suites pass; sau đó `LOG_CHANNEL=single ./vendor/bin/phpunit` pass 100%. Gate không được xem là đạt nếu test chưa chạy hoặc còn fail.

## 9. Mandatory test impact review

- Audit/update Branch Admin và Compliance tests: bỏ fixture ghi legacy column; thay positive URL assertions bằng key absence; kiểm tra list/detail/create/update; add/update gửi legacy input vẫn được bỏ qua và trường nghiệp vụ khác lưu đúng.
- Thêm schema feature tests dùng SQLite in-memory: fresh migration/seed không cần URL column; restore/drop round-trip đúng; dữ liệu name/KID/branch relation không bị mất và giá trị URL trước drop không trở lại sau down.
- Audit chạy existing LegalEntities Admin/Compliance, Consultant Branches, User MeBranch vì model/seed là shared dependencies. Không sửa nếu không có assertion bị ảnh hưởng.
- Chạy PermanentCandidateIntake feature, PermanentCandidateIntakeService unit, SyncPermanentCandidateToMatchMakerJob unit để chứng minh agreement/File/submit không phụ thuộc legacy schema; giữ config no-URL regression.
- Audit toàn bộ `work_finder_agreements.*` view refs: cập nhật composers/config/render/providers sang `pdf.work_finder_agreements.*`, không replace image paths hoặc MM payload key `work_finder_agreements` không liên quan. Kiểm tra cả ba view tồn tại ở đường dẫn mới và không còn ở đường dẫn cũ; dùng existing source-text/image hashes, CSS/escaping/PII assertions và PDF/File integration tests để bảo đảm chỉ di chuyển, không sửa mẫu. Production mapping test phải phản ánh branch 14 hiện có; thêm HTTP test dùng default mapping branch này và entity fallback.
- Existing Repository tests được chạy trong full suite nhưng không thêm Repository unit tests.
- Không gọi MM/storage thật; integrations giữ mock/test disk theo test setup hiện có.
- Syntax checks và targeted diff check không phải formatter/linter.

## 10. Rollout và self-check

1. Chờ approve; chưa sửa code hay chạy migration ngoài PHPUnit trong lượt lập plan.
2. Triển khai application đã loại dependency trước; publish ba view mới cùng config namespace mới trong một release, xử lý config/view cache bằng quy trình deploy hiện hành để không giữ old namespace. Không tự chạy cache/deploy commands trên môi trường ngoài tests. Bảo đảm không còn worker/release cũ hoặc quy trình deploy gọi seeder URL trực tiếp.
3. Backup legacy values nếu cần; xác minh DB đúng target, migration history và tồn tại hai cột trước schema deployment.
4. Chạy forward migration trong quy trình deploy được xác nhận riêng. Không chạy bản app cũ trên schema đã drop.
5. Không xóa File rows, PDFs, storage objects hoặc tài liệu nguồn. Ba file obsolete bị xoá khỏi repo có thể phục hồi qua Git; giá trị DB mất chỉ phục hồi được từ backup.
6. Self-check toàn bộ file list, source search (chỉ còn historical migration/new rollback/negative tests/decision history), contracts, affected/full test results và living docs. Không đánh dấu DONE khi verification chưa pass.

## 11. Approval

- [x] User approve plan mở rộng, gồm drop hai legacy columns (không restore URL bằng `down()`) và di chuyển ba Blade vào `views/pdf` cùng config/test references, giữ mappings đang có.
- [x] Phase 1 gate pass — syntax checks + 37 tests / 253 assertions, SQLite `:memory:`, 2026-10-05.
- [x] Phase 2 affected/full test gate pass — affected 101 tests / 1,335 assertions; full 547 tests / 3,248 assertions.
- [x] Self-check và documentation complete — minimal runtime diff, đúng file ownership, source references/three Blade hashes đã kiểm tra, living specs cập nhật.

## 12. Verification / handoff

- Phase 1: 37 tests / 253 assertions, 00:07.763; old schema còn cột, URL seeder test chạy trực tiếp vẫn pass trước khi bị xoá ở Phase 2.
- Phase 2 schema/view smoke gate: 9 tests / 81 assertions, 00:21.291.
- Affected suites: 101 tests / 1,335 assertions, 02:53.972; Branch Admin/Compliance/Consultant/User, LegalEntities, Permanent intake feature/service/job và schema coverage.
- Full `LOG_CHANNEL=single DB_CONNECTION=sqlite DB_DATABASE=:memory: ./vendor/bin/phpunit`: 547 tests / 3,248 assertions, 04:47.073, peak memory 356.89 MB, exit 0. Includes existing MatchMakerPermanentSync, File and Repository suites; không thêm Repository unit tests.
- PHP syntax checks và targeted `git diff --check` pass. Source search không còn runtime/seeder URL field hoặc obsolete seeder/CSV references, không còn concrete view namespace cũ ở config/callers/living docs; negative tests và migration history/rollback giữ tên legacy có chủ đích.
- SHA-256 trước/sau move không đổi: Tech `4eb6963a202d414359f1ff43fcc35ecf9eeb7f5b54a8c9da1a3bdfd3300cce20`; GPHL `989c0a1d7ccb7b0c57bae57f701dec8d87890150b66f4c76f290f4d834f6cc1f`; Hawk3 `5e0fcbe4e69a23fa1cbba6c77d6388a07ba28efde746f2b2724f14c65bdb85cb`.
- Folder view cũ rỗng đã được bỏ sau khi move; image assets và các PDFs/File records thực tế không bị xoá. Seeder/CSV/test obsolete là tracked files và phục hồi được từ Git.
- Không chạy migrate/cache/deploy trên DB local/STG/production; schema/data/deployment production vẫn UNVERIFIED. Cần backup URL values và triển khai theo mục 10 để áp dụng drop columns vào DB thật.

**Hoàn tất implementation và test verification; chưa áp dụng migration vào DB thực.**
