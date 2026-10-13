# SPEC: GAP-723 — Require referee token for employment reference updates

> **Trạng thái**: `IMPLEMENTED — TEST VERIFICATION BLOCKED BY ENVIRONMENT`
> **Ngày tạo**: 2026-10-12
> **Ngày cập nhật**: 2026-10-12
> **Author**: Codex
> **Jira**: [GAP-723](https://gappersonnel.atlassian.net/browse/GAP-723)

---

## 1. Tổng quan

GAP-723 sửa lỗi IDOR ở public referee workflow. Hiện tại GET dùng referee token để mở form, nhưng PUT chỉ nhận numeric `employment_history_references.id`; một người không xác thực có thể đoán ID và sửa đánh giá employment reference của reference khác.

Client hiện lấy record bằng token, sau đó gửi PUT bằng `id` nhưng bỏ token khỏi payload. Backend cần bind update vào cả `id` và token, giữ route public cho referee nhưng không cho phép ID-only update. Việc cập nhật client nằm ngoài phạm vi plan này.

**Yêu cầu gốc**: Jira `GAP-723` — `[Security] Require referee token for employment reference updates`.

### 1.1. Baseline và deviation đã trace

- `CODE`: `routes/candidate.php` expose GET `.../{token}` và PUT `.../{id}` trong group chỉ có middleware `api`; không có candidate/user authentication.
- `CODE`: `RefereeEmploymentHistoryReferenceController::getByToken()` resolve theo token; `update()` resolve và update theo ID.
- `CODE`: `CandidateService::updateEmploymentHistoryReference()` cập nhật các field referee, sau đó gửi email notification cho branch.
- `CODE`: `EmploymentHistoryReferenceUpdate` whitelist các field update bằng `array()`, nhưng chưa có `token` trong payload.
- `CODE`: Client route `/employment-references/:token` dùng token cho GET, nhưng submit chỉ gửi `id` và form fields; client update nằm ngoài phạm vi GAP-723 backend.
- `DATA`: Không thay đổi database trong GAP-723. Bảng `employment_history_references` đã có `token` và index token; không bổ sung expiry/revocation/used/replay state. Business relationship spec có mô tả `status`, nhưng migration/model hiện tại không có cột status tương ứng; không tự dùng `status` làm token lifecycle.
- `CONFIG`: API middleware đã có rate-limit mặc định `120/min` theo IP cho public routes; GAP-723 sẽ dùng nguyên limiter này, không thêm limiter riêng.
- `EXTERNAL`: update hợp lệ gửi email `TYPE_TO_CONSULTANT_REFERENT_FEEDBACK`; không có external API bắt buộc trong update.

### 1.2. Mục tiêu và ngoài phạm vi

**Trong phạm vi**:

- Bắt buộc token cho PUT và resolve exact `reference id + token`.
- Reject token missing, malformed hoặc mismatched; không tiết lộ trạng thái/reference existence qua error khác nhau.
- Giảm IDOR bằng exact `reference id + token`; không claim one-time/replay protection khi không có persistent state.
- Giữ public access vì referee không đăng nhập candidate account.
- Dùng rate limiting mặc định và audit log cho thành công/từ chối quan trọng.
- Cập nhật API contract để client có thể gửi token trong PUT; không implement client trong plan này.

**Ngoài phạm vi**:

- Không thêm login/authentication cho referee.
- Không thay đổi field nghiệp vụ hoặc scoring form.
- Không thay đổi candidate/consultant employment-history CRUD.
- Không expose token trong response resource.

### 1.3. Quyết định cần user/BA duyệt trước Phase 2

Plan đề xuất các quyết định sau trong phạm vi không sửa DB:

1. Token được gửi trong JSON body với key `token`; URL vẫn dùng numeric `{id}` để giữ tương thích route.
2. Không thêm expiry, revocation hoặc used/replay state vì task không được sửa DB. Token hợp lệ khi exact match với `id` và token hiện lưu trong DB; token có thể được dùng lại theo behavior hiện tại.

Do không có persistent lifecycle state, acceptance criteria Jira về expired/revoked/replayed token được ghi nhận là **deferred/out of scope**, không được báo cáo là đã đạt trong GAP-723.

---

## 2. Database Design

**N/A — không tạo hoặc sửa migration, schema, column, index, foreign key hay relationship.** Query chỉ dùng các cột/index hiện có: `employment_history_references.id` và `employment_history_references.token`.

### 2.1. Relationships

Giữ nguyên:

```
Candidate hasMany EmploymentHistoryReference
EmploymentHistory hasMany EmploymentHistoryReference
EmploymentHistoryReference belongsTo Candidate và EmploymentHistory
```

---

## 3. API Contract

### 3.1. Endpoint

```text
GET /api/candidate/referee/employment_history_references/{token}
PUT /api/candidate/referee/employment_history_references/{id}
```

**Auth**: Public referee bearer-by-link; không dùng `auth:candidateApi` hoặc `auth:userApi`.

**Middleware**: `api` với throttle mặc định `120/min` theo IP cho GET/PUT; không dựa vào candidate auth.

**Route params**:

| Param | Type | Required | Mô tả |
|---|---|---:|---|
| `token` | string | YES | Secret token trong public GET link |
| `id` | integer | YES | Reference ID; chỉ là một phần của scope, không đủ để authorize update |

### 3.2. PUT request

**Headers**:

```text
Content-Type: application/json
```

**Body**: giữ các field hiện tại và thêm `token` bắt buộc.

```json
{
    "token": "<referee-token>",
    "start_date": "2025-01-01",
    "end_date": "2025-12-31",
    "job_title": "Warehouse Operative",
    "candidate_comment": "Reliable and punctual",
    "is_detail_reference_allowed": true,
    "reason_for_leaving": "Career change",
    "can_reemploy": true,
    "rate_punctuality": 8,
    "rate_reliability": 8,
    "rate_honesty": 9,
    "rate_flexibility": 8,
    "rate_teamwork": 9
}
```

**FormRequest rules**:

- `token`: `required|string|max:255`; malformed/blank token không đi tới write.
- Existing date, string, boolean và rating validation phải được xác định từ runtime behavior/OpenAPI trước khi siết thêm constraints không thuộc task.
- `array()` whitelist phải truyền token xuống Service; không cho phép mass-assignment các field khác.

### 3.3. Authorization/business scope

Service chỉ cho update nếu:

1. `id` tồn tại.
2. `token` khớp exact với token của cùng reference, với safe comparison (`hash_equals` ở application boundary nếu record đã được resolve).
3. Tất cả checks xảy ra trước notification và write.
4. Không có persistent token lifecycle trong phạm vi task; repeated use của token exact-match vẫn được phép.

GET by token tiếp tục resolve theo token hiện có; không thêm expiry/revocation/used checks.

### 3.4. Response và errors

**Success (200)**: giữ `EmploymentHistoryReference` response hiện tại; không trả token hoặc lifecycle internals.

**Error policy**:

| HTTP | Khi nào | Contract |
|---:|---|---|
| 400 | Missing/malformed token hoặc invalid form | Existing validation/API error contract |
| 400 | ID-token mismatch hoặc reference không tồn tại | Cùng generic not-found/invalid-token response, không tiết lộ record/token state |
| 429 | Rate limit vượt ngưỡng | Existing throttle response |

Notification không được gửi khi request bị reject.

### 3.5. API docs impact — mandatory docs-first

Đây là API contract/security change: PUT thêm required body token, exact scope/error behavior và examples. Rate limit dùng middleware `api` mặc định hiện có.

Phase 1 phải cập nhật trước backend code:

- `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/candidate/put-referee-employment-history-references-id.md`
- `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/candidate/get-referee-employment-history-references-token.md`
- `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/candidate/index.md` nếu contract status/summary cần đồng bộ.
- `documents/Gap-API-Candidate.yaml` chỉ sửa nếu source-of-truth OpenAPI được task owner yêu cầu đồng bộ; otherwise ghi rõ docs page/runtime contract deviation.

Docs phải ghi `NOT YET DEPLOYED` cho contract mới, token location/body schema, exact `id + token` binding, no-expiry/revocation/replay limitation, default API throttle/429 behavior, success response không có token và examples.

Docs gate: `git diff --check`, validation/build của `crs-api-docs`, stage chỉ file GAP-723, commit và push remote `main`. Plan phải ghi actual files/diff, validation result, commit SHA và push result trước Phase 2.

**Phase 1 result (2026-10-12): PASS.** Updated files: `crs-api-docs/docs/api/candidate/put-referee-employment-history-references-id.md` and `crs-api-docs/docs/api/candidate/get-referee-employment-history-references-token.md`. The candidate index required no change; `documents/Gap-API-Candidate.yaml` is not present in the docs repository, so no OpenAPI file was changed. `git diff --check` passed and `npm run build` passed. Commit `3dc252e` (`docs: document GAP-723 referee token contract`) was pushed successfully to `origin/main`.

---

## 4. Business Logic (Service Layer)

### 4.1. Call chain

```text
API client /employment-references/{token}
  → GET /api/candidate/referee/employment_history_references/{token}
  → api + default throttle
  → RefereeEmploymentHistoryReferenceController@getByToken
  → CandidateService token lookup
  → Repository token query
  → EmploymentHistoryReference Resource (không expose token)

API client submit form
  → PUT /api/candidate/referee/employment_history_references/{id}
  → api + default throttle + EmploymentHistoryReferenceUpdate
  → Controller lấy id + validated token + form data
  → CandidateService loads by id and validates token
  → Repository existing id lookup
  → save successful reference
  → audit log + notify branch
  → EmploymentHistoryReference Resource
```

### 4.2. Repository design

- Giữ repository lookup hiện có theo `id`; không tạo thêm `findByIdAndToken()`.
- Repository chỉ đọc record theo ID. So sánh token là security/business check nên thực hiện trong Service sau khi record được load.
- Không thêm atomic consume/lifecycle write vì không thay đổi DB.
- Không để Controller gọi Model/repository trực tiếp.

### 4.3. Service design

- Service update flow được scope bởi cả `id` và token; được phép load bằng `getEmploymentHistoryReferenceById()` nhưng không được update nếu token không khớp.
- Service load reference theo `id`, sau đó kiểm tra token exact match bằng safe comparison (`hash_equals`); ID-only request không được đi tới update.
- Service kiểm tra token trước notification/write, rồi update field allowlist và orchestration side effects.
- Token không bị consume/revoke/expire trong task; invalid request không update và không gửi email.
- Sau write thành công hoặc reject security-scope, ghi application audit log gồm reference ID/candidate ID/action outcome/timestamp và request metadata phù hợp; không log raw token. Không ghi audit vào DB.
- Giữ notification email cho branch sau successful update; không thay đổi template/recipient ngoài yêu cầu security.
- Không dùng transaction cho update đơn lẻ; không có lifecycle consume write trong scope.

### 4.4. Rate limiting

- Dùng nguyên middleware `api` mặc định hiện tại: `throttle:120,1`, key theo IP đối với public referee requests.
- Không thêm named limiter, config mới hoặc route-specific throttle trong GAP-723.
- Đây là mitigation chung, không phải replay protection; token vẫn được bảo vệ chính bằng việc kiểm tra cặp `id + token` trước mutation.

---

## 5. Data Origin & Call Chain Verification

| Giá trị | Nơi dùng | Nguồn cung cấp | Trạng thái |
|---|---|---|---|
| `token` GET | Controller → Service | Client route `/employment-references/:token`, email link từ `config('app.candidate_employment_reference_link')` | ✅ Đã trace |
| `id` PUT | Controller → Service | GET response `employmentHistoryReference.id`, client URL path | ✅ Đã trace |
| `token` PUT | FormRequest → Controller → Service | API client gửi token trong request body; client implementation nằm ngoài scope | ⚠️ Contract cần implement |
| Form fields | FormRequest → Service | API client submit; backend `EmploymentHistoryReferenceUpdate::array()` whitelist | ✅ Đã trace |
| Candidate/branch for notification | Service | Reference → `employmentHistory.candidate_id` → `getMostProgressedBranchForCandidate()` | ✅ Đã trace |
| Token | FormRequest → Service | Request body token được gửi vào Service để so sánh với token của record đã load | ⚠️ Phải implement |

Không giả định referee login, candidate auth hoặc token tồn tại trong PUT body trước implementation phase.

---

## 6. Constants & Enums

- Dùng structured application log/audit event phù hợp; không thêm database audit table/column.
- Dùng middleware `api` rate limit mặc định; không thêm named limiter hoặc config mới.
- Không đưa raw token vào log, response, exception message hoặc audit content.
- Không thêm status transition matrix cho employment reference fields; task chỉ thêm token binding.

---

## 7. Files cần tạo/sửa

### 7.1. Docs-first Phase 1 — `/Users/nexusfrontiertech/projects/crs-api-docs`

| File | Thay đổi |
|---|---|
| `docs/api/candidate/put-referee-employment-history-references-id.md` | Required token body, exact scope, token mismatch errors, rate limit, examples, NOT YET DEPLOYED |
| `docs/api/candidate/get-referee-employment-history-references-token.md` | Existing token lookup behavior, response/token handling and no lifecycle state |
| `docs/api/candidate/index.md` | Chỉ sửa nếu endpoint status/summary cần đồng bộ |
| `documents/Gap-API-Candidate.yaml` | Chỉ sửa nếu API docs owner xác nhận OpenAPI source phải đổi cùng contract |

### 7.2. Backend Phase 2 — `/Users/nexusfrontiertech/projects/gap-web-backend`

| File | Thay đổi |
|---|---|
| `app/Contracts/Services/CandidateServiceInterface.php` | Scoped token-bound update contract nếu cần public service API |
| `app/Services/CandidateService.php` | Load by ID, token validation/update, application audit và notification orchestration |
| `app/Http/Requests/Api/Candidate/EmploymentHistoryReferenceUpdate.php` | Add token to whitelist and validation rules |
| `app/Http/Controllers/Api/Candidate/RefereeEmploymentHistoryReferenceController.php` | Pass validated token; remove ID-only authorization path; preserve response contract |
| `routes/candidate.php` | Giữ public routes và middleware `api` mặc định; không thêm authentication hoặc route-specific throttle |
| `tests/Feature/Api/Candidate/RefereeEmploymentHistoryReferenceTest.php` | Token binding, rate-limit and notification side-effect tests |
| `tests/Unit/Services/CandidateServiceTest.php` or existing Service test location | Service token-scope/business-rule tests; no Repository-only unit test |
| `.business-spec/backend-business-flow-spec.md` | Update SPEC-006 after verified implementation |
| `.business-spec/backend-api-route-inventory.md` | Record token-required PUT behavior/rate limit if route inventory contract changes |
| `.business-spec/backend-database-relationship.md` | Record no-schema-change token relationship only if living spec needs clarification |

**Phase 2 implementation result (2026-10-12):** Updated `CandidateServiceInterface`, `EmploymentHistoryReferenceUpdate`, `RefereeEmploymentHistoryReferenceController`, `CandidateService`, and `RefereeEmploymentHistoryReferenceTest`. No migration, model, repository, route, or database-schema file was changed. Security audit uses application `Log` with reference/candidate IDs and outcome only; raw token is never logged and no audit row is written to the database. Living specs were updated in `backend-business-flow-spec.md` and `backend-api-route-inventory.md`; database relationship spec required no change.

---

## 8. Test Cases & Verification Gates

### 8.1. Backend Feature tests

| Case | Kỳ vọng |
|---|---|
| GET valid token | HTTP 200, expected reference data, no token in response |
| PUT without token | Reject, no DB write, no branch notification |
| PUT with malformed/blank token | Reject, no DB write |
| Token A + reference ID B | Reject with generic error, B unchanged, no notification |
| Valid token + wrong ID | Reject with generic error, no write |
| Valid token + valid ID | HTTP 200, fields updated, notification/application audit recorded |
| Repeated valid token + same ID | Existing behavior remains allowed; no one-time state is added in this task |
| Default API rate limit exceeded | HTTP 429; no write/notification |
| Existing invalid ID | Preserve not-found behavior and no side effects |

### 8.2. Backend Service tests

- ID-only request is rejected before notification or write because token validation is mandatory.
- Repository loads by ID, then Service validates the supplied token before any write or notification.
- No expiry/revocation/replay business rule is claimed without persisted DB state.
- Invalid token never calls notification or audit-success path.
- Valid update preserves existing field allowlist and branch notification contract.
- Raw token is absent from logs/audit payloads.

### 8.3. Verification gates

**Phase 1 — Docs gate**:

- Docs contract reviewed and marked `NOT YET DEPLOYED`.
- `git diff --check` and docs build/validation pass.
- Docs commit contains only GAP-723 files and is pushed to `origin/main`.
- Plan records changed paths, result, SHA and push result.

**Phase 2 — Implementation gate**:

- No migration/schema checks are required; verify `git diff` contains no DB files.
- Affected backend Feature/Service tests pass.
- Backend `./vendor/bin/phpunit` is run; any unrelated environment failures are recorded, not hidden.
- Living business specs are updated with actual verified behavior.
- Self-check confirms no public ID-only update path remains.

**Phase 2 verification result (2026-10-12):** PHP syntax checks, `git diff --check`, and the existing `CandidateServiceTest` smoke test (`1 test, 1 assertion`) passed. The targeted Feature suite and full PHPUnit run could not complete successfully because the project test bootstrap seeds CSV rows with fixed IDs without resetting PostgreSQL sequences; factory setup then fails at `legal_entities.id=1` before GAP-723 assertions run. The host run additionally cannot resolve Docker-only `pgsql`. No GAP-723 assertion failure was reached.

**Deployment gate**:

- Backend API contract is deployed after the docs phase and is ready for API consumers to send the required token.
- Existing emailed links retain current token behavior; token remains valid while the stored token matches.
- Smoke test uses a real non-production referee token: GET → PUT valid → repeated PUT remains consistent with the approved no-DB-lifecycle policy → notification/audit verified.

---

## 9. Acceptance Criteria

- [x] PUT requests without token are rejected by FormRequest validation.
- [x] Token for Reference A cannot update Reference B.
- [x] Missing, malformed and mismatched tokens are rejected.
- [x] Valid referee update continues to work for API consumers sending the token contract (implementation verified by call-chain/static review; runtime test blocked).
- [x] Backend never updates by numeric ID alone.
- [x] Invalid requests do not trigger branch notification or success audit.
- [x] Valid update triggers the expected branch notification and application audit log without raw token.
- [x] Public referee GET/PUT dùng middleware API throttle mặc định `120/min` theo IP; không thêm limiter riêng.
- [x] API docs are synchronized and pushed before implementation code.
- [x] Không thay đổi DB; token lifecycle/expiry/replay được ghi nhận là out of scope.
- [ ] Affected backend tests pass; full backend suite results are recorded. **Blocked by test environment sequence/seed issue; see Phase 2 verification result.**
- [x] Living business specs reflect the implemented token-bound workflow.

---

## 10. Checklist trước khi Approve

- [ ] Duyệt token transport là JSON body key `token`.
- [x] Xác nhận không thêm expiry/revocation/single-use state hoặc migration.
- [x] Duyệt dùng rate limit mặc định `api` (`120/min` theo IP), không thêm limiter riêng.
- [ ] Duyệt audit log location/type và không log raw token.
- [x] Duyệt docs-first Phase 1, commit/push trước backend code.
- [ ] Xác nhận API consumers phải gửi token trong PUT body trước khi rollout backend.

