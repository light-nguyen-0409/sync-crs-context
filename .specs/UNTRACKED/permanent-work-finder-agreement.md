# SPEC: Permanent Work Finder Agreement API và Blade Tech V6

> **Trạng thái**: `DRAFT`
> **Ngày tạo**: 2026-10-05
> **Author**: Codex
> **Task key**: UNTRACKED — chưa có task key xác nhận.

## Quyết định hiện hành — PDF lưu File, chỉ gửi MM khi submit

User đã chốt: API agreement tạo file từ Blade, upload storage, lưu bảng `files` và trả File resource để FE mở URL. Chỉ khi submit Permanent mới gửi agreement sang MatchMaker, thông qua `files[]` hiện hữu cùng CV. Timing/input decision đã xác nhận; toàn bộ plan vẫn DRAFT cho đến khi approve implementation. Các mục bên dưới cùng tuân theo contract này.

### Contract và output cập nhật

- Giữ endpoint POST và candidate draft input ở §3; output là existing `App\Http\Resources\Api\Candidate\File`, top-level có `id`, `type`, `url`, `converted_file_url`, `status`, `original_file_name`, `uploaded_at`, `toe_signed_ip` theo resource hiện hữu.
- Blade render HTML nội bộ → Dompdf A4 → PDF binary → storage theo existing default disk → FileRepository tạo record. Không trả HTML cho FE.
- `File::TYPE_WORK_FINDER_AGREEMENT = 'work_finder_agreement'` mới, job-scoped với `candidate_id` và owned `job_id`, `status=uploaded`. Không set SIGNED/APPROVED khi candidate chưa ký.
- File Resource hiện ký storage URL với TTL 10 phút; FE dùng `url` mở PDF. URL không phải public permanent URL. Xác minh route get-file hiện hữu để FE lấy URL mới khi hết hạn và document exact route sau implementation.
- File type thêm vào danh mục áp dụng thật sự (`getAllFileTypes`, job-associated retrieval), không thêm vào nhóm RTW/contract signature gây side effects không liên quan.
- Không inject FileService hoặc MatchMakerService vào AgreementService: giữ quy tắc Service không inject Service. Dùng FileUtility stateless + FileRepository cho persistence; inject MatchMakerApiInterface (EpsilonApi) cho external calls trong workflow owner tương ứng.
- PDF/logo dùng local assets, không cần remote HTML/logo fetch.
- Endpoint là data mutation; giữ checkCandidateLockEdit như route intake cho generate. Việc xem/lấy lại file dùng read GET ownership scope; không bypass edit lock cho endpoint generate.

### Call chain đã trace bổ sung

- `FileService::createFile` hiện dùng `FileUtility::uploadFile` rồi `FileUtility::buildFileData` + FileRepository::create. Có thể reuse các utilities này trực tiếp trong AgreementService để tránh service-to-service injection.
- `FileUtility::uploadFile` giữ job_id cho file job-scoped và upload default Storage disk. PDF đã là định dạng cuối; converted_file_url phải rỗng, không dùng giá trị `'nothing'` khiến File Resource ký một path không tồn tại.
- `Api/Candidate/File::toArray` sinh temporary URL 10 phút; không expose raw storage path.
- `WorkerWelfareCheckService::generateCertificatePdf` dùng view + Dompdf và storage/File workflow tương tự, là reference kỹ thuật.
- `MatchMakerService::syncPermanentCandidate` gọi RegisterCandidate, sau đó upload CV/contact log qua Epsilon, rồi mới lưu local peo_no. Trước Permanent submit, candidate mới thường chưa có peo_no để attach agreement.
- Upload MM đề xuất: `EpsilonApi::addContactLog` (`POST /api/Onboarding/AddToContactLog?peo_no=...`) → `uploadToContactLog` (`POST /api/Candidates/UploadAttachment`, AttachRef=log number, AttachType=3), document subject/action riêng Work Finder Agreement. Không gửi qua RTW UploadAnswer/UploadAttachment.
- DB source resolve từ owned job branch legal entity bằng MatchMakerUtility, nhất quán với Permanent registration.

### Quyết định MM timing và submit files[] đã chốt

Generate API luôn chỉ tạo PDF → upload storage → lưu File → trả File resource. Không gọi MM kể cả candidate đã có peo_no. Submit Permanent gọi RegisterCandidate theo flow hiện hữu rồi upload CV và đúng agreement FE chọn sang MM bằng Epsilon. Không tự lấy latest agreement, không gửi tất cả version và không register MM từ generate API.

FE truyền vào submit payload:

```json
{
  "files": [
    {"file_id": 101, "type": "cv"},
    {"file_id": 102, "type": "work_finder_agreement"},
    {"file_id": 103, "type": "other"}
  ]
}
```

Đúng một CV và đúng một Work Finder Agreement bắt buộc; tối đa một Other tùy chọn theo contract hiện hữu. `files` required array min:2 max:3; file_id integer/min:1/distinct; type allowlist CV, WORK_FINDER_AGREEMENT, OTHER và distinct. Không thêm field riêng `work_finder_agreement_file_id` ở API submit. Checkbox `work_finder_agreement_accepted` vẫn required|accepted, không đồng nghĩa PDF có chữ ký.

Service batch-load toàn bộ file IDs trước writes; verify candidate_id và DB type cho mọi file. Agreement còn phải có job_id đúng submitted owned job_id, PDF và storage object tồn tại. CV/Other giữ candidate-level scope hiện hữu. Thiếu/duplicate agreement, file của candidate/job khác, sai type hoặc missing binary trả custom validation error trước profile writes/MM calls. Event/listener chuyển agreement ID đã validate tới MM workflow cùng CV ID. Contract internal bổ sung agreementFileId; không mặc định bỏ qua agreement cho new submit. Job serialized cũ chỉ có CV ID cần backward compatibility riêng, không tự chọn một agreement không được user submit. Chốt cách giữ legacy payload ở Phase 1 và test riêng; không thêm queue dispatch/retry vào submit.

### State, failure và repeat behavior

- Không transaction bao render/storage/MM/read queries. Transaction chỉ bao DB writes yêu cầu atomicity.
- Generate lưu mỗi version vào path riêng; không overwrite/delete version FE đang xem. Repeated generate tạo File version mới; preview version không được hiểu là accepted/signed.
- Khi storage thành công nhưng DB create thất bại: cleanup đúng object vừa upload; không xóa file/version cũ. Cleanup temp PDF bằng finally theo utility hiện hữu.
- Khi MM thất bại ở submit sau local save: giữ File/PDF để recover; sử dụng Permanent sync failure 502 hiện hữu và không set is_permanent=true. Generate API không phụ thuộc MM availability. Không báo submit success khi agreement upload thất bại.
- Không thêm automatic retry/resync hay receipt schema trong task. Existing MM idempotency limitation vẫn còn; không claim exactly-once. Nếu retry manual sau failure, phải đối chiếu registration/contact log/attachment post-state trước lặp side effects; task không tự retry hoặc re-register sau lỗi. Legacy queued job behavior phải được trace/test để contract bổ sung không làm mất tương thích.

### Phạm vi triển khai

Reuse Candidate File resource, bỏ kế hoạch tạo WorkFinderAgreement Resource chỉ chứa HTML. Bổ sung ownership files: `app/Models/File.php`, FileRepositoryInterface/implementation chỉ khi cần named lookup, Permanent intake Request/Service, MatchMakerService/contract, PermanentCandidateSubmittedEvent/listener, legacy sync job nếu cần giữ payload compatibility, affected Service/Feature/Job tests và living specs. Data contracts gồm file type/job scope, File response, `files[]` submit bắt buộc agreement và internal event/service signature. Không migration/receipt table mới.

Ba phase và gate triển khai được định nghĩa tại §8; public contracts đã chốt trong Phase 1 chỉ thay đổi sau khi cập nhật plan và được approve.

Không code edits/migrations trong turn cập nhật plan này.

## 1. Tổng quan

Tách Work Finder Agreement khỏi `/api/candidate/me/permanent-intake/config`, chuyển nội dung `Work Finder Agreement Tech V6.docx` sang Blade và expose API tạo PDF theo candidate input, upload storage, lưu File và trả File resource có URL. Resolve template ưu tiên branch mapping, fallback legal entity mapping; entity IDs 1–7 tạm dùng chung template Tech V6. Chỉ submit mới gửi file đã chọn sang MM.

Plan này chỉ đề xuất contract; chưa thay đổi production code. Chờ user approve theo AGENTS.md và backend-workflow.

### Baseline đã trace

- `routes/candidate.php`: config, submit và agreement click nằm trong candidate auth/checkCandidateLockEdit group.
- `PermanentCandidateIntakeController::config` gọi `PermanentCandidateIntakeService::getConfig`; kiểm tra candidate sở hữu job, resolve job → branch → legal entity; URL ưu tiên branch rồi entity.
- Working tree hiện có `approved_documents` trong service/resource config và test liên quan. Phải bảo toàn các thay đổi này.
- `recordAgreementClick` là write riêng vào candidate timings; render không tự ghi click hoặc acceptance.
- DOCX có heading, 12 điều khoản đánh số, hyperlink privacy notice, logo header, footer Version 6 / 07.08.2023, ô candidate name/address, intermediary, signature, printed name/date và appendix 5 cột/14 hàng kể cả header.
- Canonical references: `.business-spec/backend-business-flow-spec.md` SPEC-039; `.business-spec/backend-api-route-inventory.md`; `.business-spec/backend-database-relationship.md`.
- **CODE deviation so với living spec**: config hiện có thêm `approved_documents`, trong khi SPEC-039 mô tả chỉ URL. Sau implementation cần cập nhật living spec theo source thực tế.
- DATA/CONFIG/EXTERNAL/INFRASTRUCTURE deployment chưa kiểm tra; turn cập nhật plan này không gọi MM hoặc thay đổi dữ liệu production. Implementation bao gồm MM integration khi submit, được kiểm thử bằng mock.

## 2. Database Design

Không migration, không bảng mới. Generate tạo record trong bảng `files` hiện hữu với type `work_finder_agreement`, candidate_id và job_id. Giữ các cột URL cũ và seeders hiện hữu để tránh mở rộng phạm vi; API generate mới không resolve template từ URL cũ.

Mapping lưu trong config, chưa tạo màn hình quản trị hay DB mapping. Existing repositories cung cấp ownership/job/branch/address; không tạo repository mới chỉ để bọc lại query sẵn có.

## 3. API Contract đề xuất

### 3.1. Endpoint

`POST /api/candidate/me/permanent-intake/work-finder-agreement`

Auth: candidate bearer token. Route mới giữ `checkCandidateLockEdit` vì tạo storage object và File record; ownership bắt buộc. Không yêu cầu candidate đã có `is_permanent=true` vì tài liệu được tạo trước submit. Xem/lấy lại file dùng read GET có ownership scope; xác minh và document exact route lấy URL mới trước khi hoàn tất Phase 2.

### 3.2. Request và validation

```json
{
  "job_id": 123,
  "candidate": {
    "title": "Mr",
    "first_name": "John",
    "middle_name": "",
    "last_name": "Smith",
    "address": {
      "building": "10",
      "street": "Example Street",
      "town_city": "Chester",
      "county": "Cheshire",
      "postcode": "CH1 1AA"
    }
  },
  "intermediary_name": ""
}
```

- `job_id`: required|integer|min:1, internal jobs.id; service kiểm tra candidate_job ownership.
- `candidate`: sometimes|array:title,first_name,middle_name,last_name,address.
- Các trường tên: sometimes|nullable|string|max:255.
- `candidate.address`: sometimes|array:building,street,town_city,county,postcode.
- Address fields: sometimes|nullable|string|max:255; postcode max:20.
- `intermediary_name`: sometimes|nullable|string|max:255; không suy ra từ bank/agency nếu không có dữ liệu xác minh.
- Candidate ID lấy từ auth, branch_id/entity_id lấy từ job/branch trên server. Client không được chọn arbitrary candidate ID, view path hoặc mapping IDs.
- Draft input được fill vào PDF, không cập nhật candidate profile/address; API có ghi File record. Field không gửi dùng profile/address đã lưu; field gửi null/empty thể hiện để trống, không bị ghi đè bằng dữ liệu cũ.
- Signature và signed date để trống; endpoint preview không chứng minh ký/acceptance. Printed name dùng tên render.

### 3.3. Response

HTTP 200 JSON top-level dùng existing `App\Http\Resources\Api\Candidate\File`. Ví dụ minh họa (URL được ký thực tế lúc trả response):

```json
{
  "id": 102,
  "type": "work_finder_agreement",
  "url": "https://storage.example.com/agreements/102.pdf?signature=example",
  "converted_file_url": "",
  "status": "uploaded",
  "original_file_name": "work-finder-agreement.pdf",
  "uploaded_at": 1791158400,
  "toe_signed_ip": null
}
```

FE dùng `url` để mở PDF, giữ `id` và `type` để truyền cùng CV trong `files[]` khi submit. URL temporary có TTL 10 phút theo File resource hiện hữu, không phải URL public vĩnh viễn. Không trả field `html`; HTML chỉ là trung gian nội bộ giữa Blade và Dompdf. Generate không gọi MM và không capture chữ ký.

Errors dùng `App\Exceptions\Api\Candidate\APIErrorException` và Candidate Status/config lỗi hiện hữu: auth 401, validation theo JsonRequest convention, ownership dùng candidateJobNotFound hiện hữu, thiếu job/branch/entity/template mapping hoặc template file dùng custom agreement error 404 cấu hình rõ trong `config/api.php`. Không fallback sang template bất kỳ khi entity không được map.

### 3.4. Config endpoint sau thay đổi

`GET /api/candidate/me/permanent-intake/config?job_id=...` giữ validation/ownership hiện tại và `approved_documents`; bỏ `work_finder_agreement_url` trong service result và resource ở Phase 3. Frontend chuyển sang gọi endpoint generate riêng. Đây là thay đổi response contract cần FE cập nhật cùng rollout với submit bắt buộc agreement trong `files[]`.

## 4. Business Logic

1. Controller nhận validated input và authenticated candidate, gọi WorkFinderAgreementService.
2. Service xác minh candidate sở hữu job bằng repository lookup có tên ổn định `findByCandidateIdAndJobId` hiện hữu; load job/branch và candidate address trước rendering.
3. Resolve `branches[branch.id]` trước; chỉ khi không có branch mapping mới resolve `legal_entities[branch.legal_entity_id]`.
4. Branch mapping tồn tại nhưng template không hợp lệ/thiếu file phải báo lỗi cấu hình; không im lặng fallback entity.
5. `branches` tạm là empty mapping vì chưa có branch IDs riêng. Entity IDs 1,2,3,4,5,6,7 cùng dùng view `work_finder_agreements.tech_v6`.
6. Build DTO từ auth profile, saved address và whitelist draft overrides. Render Blade với đúng DTO; escape mọi dynamic text bằng `{{ }}`.
7. Render Blade nội bộ → Dompdf A4 → PDF; upload storage bằng FileUtility và tạo File record bằng FileRepository. Trả existing Candidate File resource có signed URL. Không cập nhật profile, click, acceptance hoặc gọi MM trong generate.
8. Khi submit: batch-load và validate `files[]` trước writes/MM; bắt buộc CV và agreement đúng candidate/job/type. Chuyển đúng agreement ID FE gửi qua event/listener vào MM workflow; sau RegisterCandidate, upload CV và agreement qua Epsilon contact log/attachment. Không tự chọn latest agreement.

Template bảo toàn toàn bộ điều khoản, thứ tự numbering, appendix grid, privacy hyperlink `https://www.gap-technical.com/documents`, logo và version footer từ DOCX. Dùng typography/page-break phù hợp PDF A4. Extract logo gốc từ DOCX trong implementation, không generate logo khác.

**Nội dung công ty**: mẫu ghi `gap Technical Limited`, company no. 05646432, địa chỉ Pulford House… và umbrella/intermediary wording. Theo yêu cầu dùng chung file cho entity 1–7, giữ nguyên wording mẫu; không tự thay bằng entity.name vì chưa có company registration/address contract. User cần review việc dùng nguyên văn Tech V6 cho cả 7 entity trước approval. Đây là quyết định nội dung cần ghi nhận, không suy ra pháp nhân từ tên branch.

## 5. Data Origin & Call Chain

Generate: `route → WorkFinderAgreementController → WorkFinderAgreementRequest → WorkFinderAgreementServiceInterface/Service → ownership/profile repositories → WorkFinderAgreementData DTO → Blade → Dompdf → FileUtility/storage → FileRepository → Candidate File resource`.

Submit: `PermanentCandidateIntakeRequest (files[]) → PermanentCandidateIntakeService (batch validation) → PermanentCandidateSubmittedEvent → SyncPermanentCandidateToMatchMakerListener → MatchMakerService (RegisterCandidate → CV + selected agreement attachment via Epsilon)`.

| Biến | Nguồn xác minh | Hành vi |
|---|---|---|
| candidate identity | auth:candidateApi | Không nhận candidate ID từ client |
| branch/entity IDs | owned job → jobs.branch_id → branches.legal_entity_id | Mapping do server chọn |
| name/title | Candidate properties + validated draft override | DTO cung cấp đầy đủ keys |
| address | CandidateAddressRepository + validated draft override | Không có address thì blank fields |
| intermediary | validated intermediary_name | Không gửi thì blank |
| print name | kết hợp name fields đã resolve | Cùng nguồn worker name |
| signature/date | blank strings do service cung cấp | Không fake signing |
| company/legal text | DOCX Tech V6 static content | Giữ nguyên theo shared mapping |
| logo/footer/table/link | DOCX XML/media | So sánh source/template khi verify |

DTO phải khai báo đầy đủ tất cả biến Blade dùng, không truyền raw model hoặc request array để template tự đoán keys.

## 6. Constants & Mapping

WorkFinderAgreementService public constants: template ID/view, supported entity IDs, configuration key, error keys/messages, empty signature/date policy nếu dùng fixed identifiers. Config mapping tham chiếu service constants phù hợp convention hiện hữu; không nhét config/business branching vào repository. Request giới hạn độ dài có public const thay magic number.

Config mới `config/work_finder_agreement.php`: `branches` và `legal_entities`; values là allowlisted template identifier. Service map identifier sang view đã biết, không render arbitrary input path.

## 7. Files và ownership

Owner duy nhất: coordinating agent; thực thi sequential vì files/contract phụ thuộc nhau.

Files mới:

- `app/Http/Controllers/Api/Candidate/WorkFinderAgreementController.php`
- `app/Http/Requests/Api/Candidate/WorkFinderAgreementRequest.php`
- `app/Contracts/Services/WorkFinderAgreementServiceInterface.php`
- `app/Services/WorkFinderAgreementService.php`
- `app/Dto/WorkFinderAgreementData.php`
- `config/work_finder_agreement.php`
- `../../resources/views/work_finder_agreements/tech.blade.php`
- Logo asset theo convention local static assets hiện hữu, path chốt sau khi scan; phải nằm trong repo và embed được trong PDF mà không fetch remote.
- `tests/Feature/Api/Candidate/WorkFinderAgreementTest.php`
- `tests/Unit/Services/WorkFinderAgreementServiceTest.php`

Files sửa có scope:

- `routes/candidate.php`: import + generate route, giữ edit-lock middleware.
- `app/Models/File.php`: type constant và applicable job-scoped type lists. Reuse Candidate File resource, không tạo resource chỉ chứa HTML.
- FileRepository contract/implementation chỉ bổ sung nếu thiếu named lookup cần thiết; không thêm business logic vào repository.
- `app/Providers/ServiceServiceProvider.php`: binding theo cơ chế hiện hữu nếu cần explicit registration.
- `config/api.php`: custom agreement error nếu error registry dùng file này; xác nhận exact error config trước Phase 1.
- `PermanentCandidateIntakeService.php`/`PermanentCandidateIntakeConfig.php`: bỏ URL response, giữ approved_documents/user edits.
- `PermanentCandidateIntakeRequest.php`/Service: `files[]` bắt buộc CV + agreement, optional Other; batch ownership/type/job validation và chuyển exact selected ID.
- MatchMakerService/contract, PermanentCandidateSubmittedEvent/listener và legacy sync job: internal agreement ID contract, upload agreement sau registration; giữ tương thích legacy serialized payload, không thêm retry/queue dispatch.
- `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` và các unit tests assert getConfig: cập nhật response contract.
- Affected Service/Feature/Job tests: generate persistence/cleanup/no-MM, submit selected-file/MM failure và legacy job compatibility.
- `documents/Gap-API-Candidate.yaml`: endpoint/request/response mới và config change; bảo toàn user edits.
- `.business-spec/backend-business-flow-spec.md`, `backend-api-route-inventory.md`: cập nhật current flow/route sau implementation; database relationship chỉ cập nhật nếu có mô tả flow bị stale, không claim schema change.

## 8. Implementation phases và test gates

### Phase 1 — Skeleton / Integration Boundary

Input: approved plan/API/data contracts và working tree đã trace. Output: compile-valid Controller/Request/Service contract/DTO/config mapping, File type constant, reused File response, service binding và custom error path; public contracts frozen.

Applicable layers là Controller/Request/DTO/Service, existing File model/resource và repositories. Không tạo Model/Migration/Repository rỗng. Freeze internal submit→event→listener→MM agreement ID contract; chọn backward-compatible optional internal argument cho legacy callers/serialized job, nhưng không cho new submit bỏ agreement. Trace và test legacy property initialization trước khi chốt signature.

Route chưa expose cho đến Phase 2. Service skeleton dùng custom not-implemented exception/error theo existing API convention nếu gọi trực tiếp; không return fake success. Frozen method `generate(Candidate $candidate, array $data): File` (App\Models\File). Đánh dấu `// TODO[UNTRACKED-WFA-P2]: ...` cho PDF/local save, owner AgreementService; `// TODO[UNTRACKED-WFA-P3]: ...` cho submit/MM, owner intake/MM workflow. Chưa activate required agreement validation hoặc mới phát sinh MM side effect trong phase skeleton.

Ownership: coordinating agent, các files mới/binding/error registry/File constant và internal contract files ở §7, chỉnh shared files sequential; không đổi config response cũ trong phase này.

Acceptance/gate: PHP syntax/load/DI và contract tests pass; legacy callers còn tương thích; không đăng ký route incomplete, fake success hoặc external calls/state mutation. Chỉ chuyển Phase 2 khi gate pass.

### Phase 2 — Blade → PDF → Storage → File

Input/dependency: Phase 1 contracts đã pass. Output: DOCX chuyển đầy đủ sang Blade/logo, ownership/mapping/draft merge, PDF/storage/File persistence và complete generate route trả File resource. Không gọi MM. Chưa bỏ config URL, chưa activate submit bắt buộc agreement cho đến Phase 3.

Ownership: coordinating agent sửa sequential Agreement controller/request/service/DTO, Blade/logo/mapping, File retrieval nếu cần, route và generate tests/docs ở §7. Không thay public contract trừ khi update plan và user approve.

Acceptance: entity 1–7 dùng Tech V6, branch mapping priority/fallback đúng, missing mapping rõ ràng; PDF fill/escape đúng, đủ 12 clauses/appendix/logo/footer/hyperlink; signature/date blank. Lưu File job-scoped với URL mở PDF được; converted_file_url rỗng; không profile/click/acceptance mutation hoặc MM calls. Repeated generate tạo version riêng; DB failure cleanup đúng object mới; temp file được cleanup.

Gate: affected Service/Feature suites pass; verify PDF text/layout với đầy đủ/blank/Unicode data và DOCX paragraph/table comparison; storage/DB failure tests pass; URL expiry/retrieval route verified và documented. Chỉ chuyển Phase 3 sau gate pass.

### Phase 3 — Submit files[] / MM integration / rollout

Input/dependency: Phase 2 pass và FE phối hợp chuyển contract. Output: submit yêu cầu CV + agreement, optional Other; exact selected agreement được gửi MM sau RegisterCandidate; config bỏ URL nhưng giữ approved_documents.

Ownership: coordinating agent sửa sequential intake Request/Service/config resource, event/listener/legacy job, MM service/contract, affected tests và API/living docs ở §7. Các public contract Phase 1 giữ nguyên.

Acceptance: batch validation trước writes/MM; reject thiếu/duplicate/sai candidate/job/type hoặc missing PDF; không chọn latest file. MM dùng đúng candidate/db source/contact attachment; Other vẫn chỉ lưu GAP theo flow hiện hữu. MM failure trả failure 502, giữ PDF/File, không báo success hoặc set is_permanent=true. Không thêm retry/resync; legacy job payload còn tương thích; generate luôn không gọi MM.

Gate: mocked MM requests assert exact selected file; failure/contact log/upload và selected-version tests; legacy queued payload compatibility; config/approved_documents/click regressions. Review toàn bộ affected tests, chạy affected suites rồi full `./vendor/bin/phpunit`, self-check với plan. Không chạy formatter/linter tự động. Nếu môi trường test bị block, report rõ và chưa đánh dấu task done. Cập nhật docs/living specs theo code thực tế trước handoff.

## 9. Test cases / approval decisions

Coverage cần thiết: unauthenticated/edit-lock, invalid job ID/nested keys, foreign job, missing branch, entity mapping 1–7, branch override/fallback, invalid mapped view/missing mapping, saved profile fallback, explicit blank override, missing address, escaping và full PDF clauses/table/link/footer. File response/persistence/job scope, signed URL, repeat versions/cleanup, no profile write/no fake signature/no MM during generate. Submit CV + selected agreement validation/MM success/failure/legacy payload; config URL removal + approved_documents preservation, click first-write regression.

Không repository unit tests; repository behavior được cover qua Service/Feature. Không tests chỉ mirror constants.

Các điểm user review trước implementation:

- API POST tạo PDF, upload storage, lưu File, trả existing File resource có `url`; FE mở PDF và giữ File ID/type.
- Submit gửi agreement cùng CV trong `files[]`, chỉ lúc này mới gửi MM; Other vẫn optional.
- Branch/entity resolve từ owned job trên server; draft candidate input không ghi profile.
- Giữ nguyên Tech V6 company/legal wording cho entity 1–7 theo yêu cầu dùng chung mẫu.
- Config endpoint bỏ URL, giữ approved_documents; FE migration cần phối hợp.
- Generate dùng candidate auth + edit-lock middleware; xem/lấy lại file dùng read GET có ownership scope.

Chưa có implementation changes hoặc migrations được thực hiện trong turn lập plan này.
