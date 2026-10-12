# SPEC: GAP-691 — Dùng chung Permanent intake controller và bỏ Other

> **Trạng thái**: `DONE` — user đã approve; hai phase và test gates đã pass.
> **Ngày tạo**: 2026-10-05
> **Task**: GAP-691
> **Author**: Codex

## 1. Mục tiêu và phạm vi

Đưa API generate Work Finder Agreement vào `PermanentCandidateIntakeController` hiện hữu và xóa `WorkFinderAgreementController`. Permanent submit chỉ nhận đúng hai file: CV và Work Finder Agreement.

Đây là plan độc lập cho hai thay đổi trên, đủ để review và triển khai mà không cần đọc plan feature trước.

`File::TYPE_OTHER` chỉ bị loại khỏi Permanent intake. Constant, stored files và các workflow upload Other ngoài Permanent tiếp tục hoạt động. Revision không sửa Blade, mapping, PDF generation, storage, resource hoặc MM registration/upload.

## 2. Baseline và database

Source hiện tại:

- `routes/candidate.php` trỏ endpoint generate tới `WorkFinderAgreementController::generate`.
- Controller này inject `WorkFinderAgreementServiceInterface`, gọi `generate(auth()->user(), $request->validated())`, trả Candidate File resource.
- `PermanentCandidateIntakeRequest` cho phép `files` min:2/max:3 với CV, Work Finder Agreement và Other; IDs và types distinct.
- Intake service batch-load files, xác minh ownership/type, lấy CV và agreement để dispatch event/MM. Other không gửi MM.
- Feature/Service tests hiện có fixture Other trong submit thành công.

Không cần migration, thêm bảng/cột hoặc xóa dữ liệu.

Living-spec baseline nằm trong `.business-spec/backend-business-flow-spec.md` (SPEC-039), `backend-api-route-inventory.md`, `backend-database-relationship.md`. Hai hành vi controller/Other hiện khớp source; thay đổi mới sẽ được ghi vào living specs sau implementation. DATA/CONFIG/EXTERNAL/INFRASTRUCTURE deployment chưa xác minh trong revision.

## 3. API contract

### 3.1. Generate agreement

`POST /api/candidate/me/permanent-intake/work-finder-agreement`

Middleware: `auth:candidateApi`, `checkCandidateLockEdit` trong API group hiện hữu.

Handler mới: `PermanentCandidateIntakeController::generateWorkFinderAgreement(WorkFinderAgreementRequest $request): FileResource`.

Controller inject trực tiếp `WorkFinderAgreementServiceInterface` bên cạnh `PermanentCandidateIntakeServiceInterface`. Các service không inject nhau. Reuse request và generate service hiện hữu.

Request: required integer `job_id` min:1; optional `candidate` gồm title/name/address draft và `intermediary_name` theo `WorkFinderAgreementRequest`. Profile/address không gửi trong draft được resolve từ candidate đã đăng nhập. Branch/entity mapping do service chọn từ owned job.

Response HTTP 200: existing `App\Http\Resources\Api\Candidate\File`, top-level `id`, `type`, `url`, `converted_file_url`, `status`, `original_file_name`, `uploaded_at`, `toe_signed_ip`. FE mở PDF qua signed `url`. Generate vẫn thực hiện Blade → PDF → storage → File record; MM chỉ được gọi khi submit.

### 3.2. Submit Permanent

`POST /api/candidate/me/permanent-intake`

Phần `files[]` của payload:

```json
{
  "files": [
    {"file_id": 101, "type": "cv"},
    {"file_id": 102, "type": "work_finder_agreement"}
  ]
}
```

FormRequest validation:

```php
'files' => 'required|array|size:'.self::REQUIRED_FILE_COUNT,
'files.*.file_id' => 'required|integer|min:1|distinct',
'files.*.type' => 'required|string|in:'.implode(',', [File::TYPE_CV, File::TYPE_WORK_FINDER_AGREEMENT]).'|distinct',
```

Khai báo `public const REQUIRED_FILE_COUNT = 2` trong `PermanentCandidateIntakeRequest`. Với đúng hai phần tử, allowlist hai types và type distinct, request buộc có một CV và một agreement.

Other thay thế một file hoặc được thêm thành file thứ ba trả validation HTTP 400 theo JsonRequest (`status`, `errors`) trước writes/MM. Các field profile/journey/checkbox, service ownership guards, success response và sync failure behavior giữ contract hiện hữu.

## 4. Business logic và data origin

Generate call chain:

`route → PermanentCandidateIntakeController::generateWorkFinderAgreement → WorkFinderAgreementRequest → WorkFinderAgreementServiceInterface::generate → repositories/DTO/Blade/PDF/storage → File → Candidate File resource`.

Submit call chain:

`PermanentCandidateIntakeRequest → PermanentCandidateIntakeController::submit → PermanentCandidateIntakeService::submit → batch file lookup/validation → profile writes → event/listener → MatchMakerService`.

Candidate lấy từ auth; draft và submitted file IDs/types lấy từ validated request; File model lấy từ service/repository. Không thêm biến Blade/DTO mới. Service submit hiện đã xử lý CV và agreement riêng, nên không cần sửa workflow production để loại Other.

## 5. Files và ownership

Owner duy nhất: coordinating agent, chỉnh sequential để tránh đè shared files và user edits.

- Sửa `app/Http/Controllers/Api/Candidate/PermanentCandidateIntakeController.php`: imports, DI và method generate.
- Sửa `routes/candidate.php`: đổi controller handler và bỏ import controller cũ.
- Xóa `app/Http/Controllers/Api/Candidate/WorkFinderAgreementController.php` sau khi route đã chuyển.
- Sửa `app/Http/Requests/Api/Candidate/PermanentCandidateIntakeRequest.php`: constant, exact size và allowlist.
- Sửa `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php`: success fixtures, negative validation và route/controller coverage.
- Sửa `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php`: bỏ Other fixture/ID khỏi expectation batch query và payload, giữ agreement ID event assertion.
- Test impact review: sửa `tests/Unit/Jobs/SyncPermanentCandidateToMatchMakerJobTest.php` để kỳ vọng argument thứ tư `null` theo source hiện tại; không đổi production Job.
- Sửa `documents/Gap-API-Candidate.yaml`: `files` minItems/maxItems = 2, enum CV/Agreement, description tương ứng.
- Sửa `.business-spec/backend-business-flow-spec.md`: Permanent intake nhận hai file.
- Sửa `.business-spec/backend-api-route-inventory.md`: generate handler mới.

Không cần thêm Model, Repository, Service, DTO, Resource hoặc migration.

## 6. Phases và test gates

### Phase 1 — Skeleton / Integration Boundary

- Input/dependency: plan này được approve; Agreement Request/Service Interface và File resource hiện hữu đã có.
- File ownership: coordinating agent sửa `PermanentCandidateIntakeController.php`.
- Output: compile-valid imports/constructor injection/method signature và delegate generate tới service hiện hữu. Route hiện tại tiếp tục hoạt động cho đến Phase 2.
- Acceptance: method mới chỉ nhận validated input, gọi service và trả File resource; config/submit/click không đổi behavior. Không có fake success hoặc business TODO vì implementation được reuse đầy đủ.
- Test gate: PHP syntax, DI resolution và generate Feature test pass. Gate pass trước Phase 2. Public generate signature và File response được freeze.

### Phase 2 — Route / validation / cleanup / documentation

- Input/dependency: Phase 1 gate pass.
- File ownership: coordinating agent sửa các route/request/test/docs ở §5; xóa controller cũ sau khi route chuyển. Không thay MM/service workflow.
- Output: endpoint hoạt động qua Permanent intake controller; submit chỉ nhận CV + agreement; API/living docs khớp contract.
- Acceptance: không còn source reference controller cũ; response generate vẫn File có URL/PDF; request Other bị chặn trước persistence/MM; valid submit truyền đúng selected agreement ID; workflow Other ngoài Permanent không đổi.
- Test gate: affected Feature/Service tests và legacy Job/MM tests pass, rồi full `./vendor/bin/phpunit`. Chạy riêng từng suite hoặc dùng filter để tránh PHPUnit chỉ nhận file đầu khi truyền nhiều đường dẫn. Nếu logging gửi Slack trong test, dùng `LOG_CHANNEL=single` theo môi trường hiện hữu, không sửa production logging. Self-check diff và plan trước handoff; không formatter tự động.

## 7. Test impact và acceptance checklist

- Generate endpoint resolves handler mới và tạo stored PDF/File resource.
- Submit CV + agreement thành công, dispatch đúng hai IDs.
- Chỉ CV, chỉ agreement, ba files, Other thay CV/Agreement hoặc thêm Other đều bị từ chối.
- Duplicate IDs/types, foreign candidate/job/file và sync failure giữ coverage phù hợp contract hiện tại.
- Negative Other requests không cập nhật profile hoặc dispatch MM event.
- Service test batch query chỉ gồm CV/Agreement; không có repository unit tests mới.
- Config approved_documents, click, legacy sync job và MM upload regressions pass.
- User edits được bảo toàn; file count/type docs và route inventory khớp code.

## 8. Implementation và verification

- Phase 1: controller DI/method đã triển khai; PHP syntax và hai config/generate Feature tests pass.
- Phase 2: route đã chuyển sang `PermanentCandidateIntakeController::generateWorkFinderAgreement`; controller riêng đã xóa; validation nhận đúng CV/Agreement, docs và living specs đã cập nhật.
- Test impact review giữ các thay đổi source hiện hữu: Service test bỏ ba repository mocks vì constructor hiện tại đã loại các dependency đó; Job test kỳ vọng agreement ID nullable theo signature đang chạy. Revision không sửa production Service/Job.
- Affected suites: `LOG_CHANNEL=single ./vendor/bin/phpunit --filter 'PermanentCandidateIntakeTest|PermanentCandidateIntakeServiceTest|MatchMakerPermanentSyncTest|SyncPermanentCandidateToMatchMakerJobTest'` — 27 tests, 285 assertions, pass.
- Full suite: `LOG_CHANNEL=single ./vendor/bin/phpunit` — 523 tests, 2419 assertions, pass.
- YAML parse/file-count/type assertions pass; PHP syntax và scoped diff whitespace checks pass; không còn reference controller riêng trong app/routes/tests/living specs.
- Không migrations, production external calls hoặc stored file deletion. File controller đã xóa chỉ là delegate; implementation tương đương nằm trong controller Permanent intake.
