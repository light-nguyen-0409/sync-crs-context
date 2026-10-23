# SPEC: GAP-743 — Shorten Links in Email Bodies

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-16
> **Author**: Codex
> **Nguồn yêu cầu**: [GAP-743](https://gappersonnel.atlassian.net/browse/GAP-743)
> **Approval**: User approved on 2026-10-16; scope limited to rich-text email bodies.
> **Template**: [SPEC_TEMPLATE.md](../SPEC_TEMPLATE.md)

---

## 1. Tổng quan

GAP-743 yêu cầu rút ngắn các HTTP(S) link nằm trong rich-text email body để giảm khả năng URL bị xuống dòng/hỏng khi ứng viên mở email trên mobile. Thiết kế này dùng short-link first-party do backend tạo và một public redirect endpoint; không dùng third-party URL-shortener.

Short link được tạo tại central mail-rendering boundary chỉ khi email đang dùng rich-text template. URL gốc vẫn được giữ nguyên về mặt nghiệp vụ; người nhận chỉ đi qua một bước HTTP redirect.

### Phạm vi

- Bao phủ các link `http://` và `https://` trong rich-text email body sau khi HTML template và placeholder đã được render.
- Chỉ áp dụng cho email có `EmailTemplate::isRichText = true` và nội dung được xử lý qua `RichTextMailProcessor`.
- Legacy/plain-text template giữ nguyên behavior hiện tại, bao gồm regex auto-link URL và URL hiển thị đầy đủ.
- Giữ nguyên visible label nếu anchor đã có label như `Click here`; nếu label chính là URL gốc thì thay bằng short URL để tránh hiển thị URL dài.
- Không shorten `img src`, `mailto:`, `tel:`, fragment-only link hoặc URL trong email subject.
- Không thay đổi public contract của `POST /api/consultant/candidates/invite`, legacy email hoặc các email producer hiện có.

### Giả định cần review

- Short link endpoint được public qua HTTPS trên backend domain hoặc một short-link domain trỏ về backend.
- Redirect dùng HTTP `302 Found` để tránh cache vĩnh viễn và giữ khả năng thay đổi policy sau này.
- Short-link layer không tự đặt expiry; các destination token hiện hữu (password reset, profile deletion, referee, v.v.) vẫn tự quyết định thời hạn của chúng.
- Khi tạo short link thất bại, email vẫn được gửi với URL gốc và lỗi được log; lỗi shortener không làm mất email nghiệp vụ.
- Destination URL được mã hóa khi lưu DB vì có thể chứa candidate/token information.

### Hiện trạng đã trace

- Invitation truyền `branch->registration_link` trực tiếp từ `CandidateService::sendInvitationEmail()`.
- `MailSenderAccessor::send()` là điểm chung resolve template, inject dữ liệu và tạo `$content` trước khi gửi.
- Rich-text email dùng `RichTextMailProcessor` để sanitize/inject placeholder; đây là nhánh duy nhất được rewrite.
- Source hiện tại chưa có short-link table, redirect route hoặc URL-shortening provider.
- Business-spec GAP-734 mô tả optional `job_id`, nhưng source hiện tại chưa có field/logic đó. GAP-743 chỉ shorten URL cuối cùng mà mail flow nhận được và không gộp GAP-734.

---

## 2. Database Design

### 2.1. Bảng mới

```
Tên bảng: `short_links`
```

| Cột | Kiểu | Nullable | Default | Mô tả |
|-----|------|----------|---------|-------|
| `id` | bigIncrements | NO | — | Primary key |
| `token_hash` | string(64) | NO | — | SHA-256 hash của token public; unique |
| `destination_url` | text | NO | — | URL gốc đã mã hóa bằng model cast |
| `expires_at` | timestampTz | YES | null | Reserved cho expiry theo link type; không tự set trong scope hiện tại |
| `created_at` | timestampTz | YES | null | Laravel timestamp |
| `updated_at` | timestampTz | YES | null | Laravel timestamp |

**Index**:

- Unique index trên `token_hash` cho redirect lookup.
- Index trên `expires_at` để hỗ trợ cleanup/expiry về sau.

**Foreign Keys**: Không tạo FK. Short link chỉ giữ destination URL tổng quát và không sở hữu candidate/job record.

**Migration rules**:

- Migration `create_short_links_table` chỉ tạo schema, không seed/backfill URL cũ.
- `destination_url` dùng `text` vì Laravel encrypted cast có thể làm giá trị dài hơn URL plaintext.
- Không lưu raw public token trong DB; service chỉ lưu token hash.
- Không tạo `click_count`, `last_clicked_at`, candidate/email hoặc analytics fields vì GAP-743 chưa yêu cầu tracking.

### 2.2. Eloquent Model

`App\Models\ShortLink`:

- `$fillable`: `token_hash`, `destination_url`, `expires_at`.
- `$casts`: `destination_url => encrypted`, `expires_at => datetime`.
- Constants cho token length/alphabet, hash algorithm và redirect status nếu cần dùng xuyên layer.
- Không chứa redirect/business workflow trong Model.

### 2.3. Quan hệ

Không có Eloquent relationship. Destination URL có thể trỏ tới nhiều domain và nhiều loại business link.

---

## 3. API Contract

Đây là public redirect contract mới, cần docs-first trước khi viết implementation. Redirect được dùng bởi rich-text email links.

### 3.1. Endpoint

```text
GET /api/r/{token}
```

**Auth**: None
**Middleware**: `api` only; không dùng `auth:*`, branch middleware hoặc rate-limit override.
**Purpose**: Resolve a backend-owned short token and redirect to the stored destination URL.

### 3.2. Request

**Route params**:

| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| `token` | string | YES | Public random token, URL-safe; không nhận raw destination URL |

Không có request body/query contract. Client không được tự chọn destination.

### 3.3. Response

**Success (302)**:

```text
HTTP/1.1 302 Found
Location: https://frontend.example/…
```

`Location` phải giữ nguyên query string và SPA fragment của destination, ví dụ `#/welcome?job_id=...`.

**Errors**:

| HTTP Code | Exception/response | Khi nào |
|-----------|--------------------|---------|
| 404 | Custom short-link not-found response | Token không tồn tại |
| 404 | Custom short-link not-found response | Token đã bị vô hiệu hóa/không resolve được |
| 500 | Existing application error handling | Chỉ khi storage/DB failure không recover được |

Không trả JSON success body khi redirect thành công. Không redirect tới scheme ngoài `http`/`https`.

### 3.4. Email rendering contract

Không đổi request/response của các API gửi email. `MailSenderAccessor` sẽ xử lý content sau template rendering:

1. Render rich-text template như hiện tại.
2. Chỉ khi `EmailTemplate::isRichText = true`, quét các clickable HTTP(S) anchor trong rendered body.
3. Tạo short-link mapping theo batch.
4. Thay `href` và chỉ thay anchor text khi text bằng đúng URL gốc.
5. Giữ nguyên image source, mailto/tel link, human-readable anchor label và toàn bộ legacy/plain-text content.

---

## 4. Business Logic (Service Layer)

### 4.1. Luồng tạo short link khi gửi email

```text
MailSenderAccessor::send()
  → resolve email template
  → nếu rich-text: RichTextMailProcessor render HTML
  → nếu rich-text: ShortLinkService::shortenRenderedBody()
      → parse clickable HTTP(S) links
      → validate allowed schemes
      → generate random token(s)
      → hash token(s)
      → batch insert short_links
      → replace href/text in rendered body
  → legacy/plain-text: giữ nguyên rendering hiện tại
  → send email with transformed content
```

### 4.2. Luồng redirect

```text
GET /api/r/{token}
  → PublicShortLinkController
  → ShortLinkService::resolve()
  → hash token
  → ShortLinkRepository::findByTokenHash()
  → validate record/expiry/destination scheme
  → return 302 Location to destination
```

### 4.3. Business rules

- Token phải được tạo bằng cryptographically secure random source và đủ entropy để không đoán được.
- Chỉ link được tạo server-side từ email content mới được phép trở thành destination.
- Chỉ `http`/`https` destination hợp lệ; reject `javascript:`, `data:`, `file:`, `mailto:` và scheme khác.
- Short link của chính backend không được shorten lặp lại.
- Legacy/plain-text template không được đi qua ShortLinkService.
- Một email có nhiều link phải được xử lý theo batch; không query/insert từng record trong loop.
- Redirect không yêu cầu authentication vì recipient chưa login.
- Redirect phải preserve fragment, query params, encoded values và token của destination.
- Nếu short-link creation fail, giữ URL gốc và log structured error; email send vẫn tiếp tục.
- Không log raw destination URL nếu URL có thể chứa PII hoặc security token.
- Short-link service không inject service khác; chỉ inject Repository và technical helpers nếu cần.
- Repository chỉ làm query/insert; URL parsing, token generation, fallback và redirect rules nằm ở Service.
- Không dùng transaction cho redirect read. Batch insert chỉ dùng transaction nếu cần atomicity cho nhiều mapping trước khi gửi email; không đặt read query trong transaction.

### 4.4. Security and operational rules

- `APP_URL`/`SHORT_LINK_BASE_URL` phải là public HTTPS URL; không dùng localhost/private backend host trong email.
- Public endpoint cần được deploy cùng route và đảm bảo web server/proxy không chặn `302` hoặc fragment-bearing `Location`.
- Không có cleanup job trong GAP-743 vì chưa chốt expiry; migration chuẩn bị `expires_at` cho scope sau.
- Không đổi destination đã được gửi nếu chưa có product requirement; mapping giữ nguyên để email cũ tiếp tục hoạt động.

---

## 5. Data Origin & Call Chain

| Biến / dữ liệu | Nguồn cung cấp | Nơi sử dụng | Confirmed? |
|---|---|---|---|
| Rendered rich-text email body | `EmailTemplateService::resolveTemplateForSending()` + `RichTextMailProcessor` + `MailSenderAccessor` | ShortLinkService | ✅ |
| Placeholder URL | Service producer data, ví dụ `CandidateService`, `AppointmentService`, `AuthenticatableService` | Template rendering | ✅ |
| Invitation URL | `Branch::registration_link` hiện tại; selected-job resolution của GAP-734 nếu source được deploy sau này | Invitation email | ✅ current branch / GAP-734 future dependency |
| Rich-text anchors | `EmailCustom.content` sau sanitize + inject | Short-link HTML scan | ✅ |
| Short-link token | ShortLinkService secure random generator | Email href + `token_hash` | Planned |
| Destination URL | Parsed `href`/raw URL từ rendered body | `short_links.destination_url` | Planned |
| Public redirect token | Route parameter `/api/r/{token}` | ShortLinkController/Service | Planned |
| Public host | `SHORT_LINK_BASE_URL` config/env | URL written into email | Needs deployment verification |

Các caller không cần tự tạo short link. `MailSenderAccessor::send()` là single integration boundary nên invitation và các email khác dùng chung behavior.

---

## 6. Constants & Enums

Dự kiến đặt constants trong Model/Contract/Service phù hợp, không hardcode trong query hoặc controller:

```php
public const TABLE = 'short_links';
public const TOKEN_HASH_ALGORITHM = 'sha256';
public const TOKEN_LENGTH = 10;
public const SHORT_LINK_PATH = '/api/r/';
public const ALLOWED_SCHEMES = ['http', 'https'];
```

Redirect status dùng `Symfony\Component\HttpFoundation\Response::HTTP_FOUND`; base URL đọc từ `app.short_link_base_url`. Allowed schemes (`http`, `https`) dùng constant; không lặp magic strings trong nhiều lớp.

---

## 7. Files cần tạo/sửa

### 7.1. Files mới — Phase 2

| File | Namespace | Mô tả |
|---|---|---|
| `database/migrations/2026_10_16_120000_create_short_links_table.php` | — | Tạo mapping table |
| `app/Models/ShortLink.php` | `App\Models` | Persist token hash/destination |
| `app/Contracts/Repositories/ShortLinkRepositoryInterface.php` | `App\Contracts\Repositories` | Data-access contract |
| `app/Repositories/ShortLinkRepository.php` | `App\Repositories` | Pure insert/find queries |
| `app/Contracts/Services/ShortLinkServiceInterface.php` | `App\Contracts\Services` | Create/resolve/render contract |
| `app/Services/ShortLinkService.php` | `App\Services` | Token, HTML link transformation, resolve/redirect rules |
| `app/Http/Controllers/Api/General/PublicShortLinkController.php` | `App\Http\Controllers\Api\General` | Public redirect controller |
| `app/Exceptions/Api/General/ShortLinkNotFoundException.php` | `App\Exceptions\Api\General` | Custom not-found failure |
| `tests/Feature/Api/General/PublicShortLinkTest.php` | — | Public redirect and error behavior |
| `tests/Feature/Api/General/RichTextMailShortLinkTest.php` | — | Central MailSender rich-text integration boundary |
| `tests/Unit/Services/ShortLinkServiceTest.php` | `Tests\Unit\Services` | Service-only token/HTML business logic |

### 7.2. Files sửa — Phase 2

| File | Thay đổi |
|---|---|
| `app/Facades/MailSenderAccessor.php` | Inject ShortLinkService; transform final rich-text rendered body before send; leave legacy branch unchanged |
| `app/Providers/RepositoryServiceProvider.php` | Bind the Repository interface/implementation |
| `app/Providers/ServiceServiceProvider.php` | Bind the Service interface/implementation |
| `routes/general.php` | Thêm unauthenticated `GET /r/{token}` dưới API prefix |
| `config/app.php` | Thêm `short_link_base_url` từ env/config |
| `.env.example` | Document public short-link base URL |
| `tests/Unit/Services/RichTextMailProcessorTest.php` | Preserve sanitizer/placeholder regression; do not alter unrelated behavior |
| Existing rich-text mail tests | Assert shortened href, original destination and fallback behavior |
| `.business-spec/backend-business-flow-spec.md` | Add current email short-link flow and redirect behavior |
| `.business-spec/backend-api-route-inventory.md` | Add public redirect route and contract |
| `.business-spec/backend-database-relationship.md` | Add `short_links` storage and security/relationship notes |

### 7.3. API docs — Phase 1, outside backend repository

| File | Thay đổi |
|---|---|
| `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/general/get-r-token.md` | Document public redirect contract, 302/404 behavior, no auth, destination preservation; mark **NOT YET DEPLOYED** |
| `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/general/index.md` | Add endpoint to General API inventory |

Không sửa GAP-734 invitation request contract trong GAP-743. Nếu URL source sau này thay đổi bởi GAP-734, chỉ verify that short-link layer wraps the final resolved URL.

---

## 8. API Contract / Docs-First Execution Gates

### Phase 1 — API docs synchronization (must pass before backend code)

**Input**: Approved contract in this plan.

**Scope**:

- Define `GET /api/r/{token}` as public redirect endpoint.
- Document route param, HTTPS/public-host requirement, `302 Location`, invalid token behavior, no-auth behavior, security constraints and not-yet-deployed status.
- Document that rich-text email body URLs are rewritten to this endpoint while legacy/plain-text email behavior and existing email API request/response schemas remain unchanged.
- Update the general API inventory/navigation.

**Validation gate**:

- Docs build/lint/check passes according to `crs-api-docs` repository convention.
- Only GAP-743 docs files are changed.
- Commit docs changes and push normally to remote `main` as required by workspace policy.
- Record actual diff, validation command/result, commit SHA and successful push here before Phase 2 starts.

**Execution record**: `PASS — 2026-10-16.` Updated only:

- `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/general/get-r-token.md`
- `/Users/nexusfrontiertech/projects/crs-api-docs/docs/api/general/index.md`

Validation: `git diff --check` passed; `npm run build` passed and generated the Docusaurus static build. Commit `7bc11da` (`docs: add GAP-743 rich-text short link contract`) was pushed successfully to `origin/main`. Phase 2 may start.

### Phase 2 — Backend implementation and verification

**Input**: Phase 1 docs commit/push passed; approved public host/config is available.

**Output**: Persisted short-link mapping, public redirect route, central email transformation, tests and updated living specs.

**Acceptance criteria**:

1. A rich-text invitation email link is shortened without changing its destination or branch/job/tracking/UTM/fragment values.
2. Supported HTTP(S) links in rich-text emails are shortened through the central mail boundary.
3. Legacy/plain-text templates remain behavior-compatible; no URL rewrite is applied to them.
4. Rich-text human-readable anchor text is preserved.
5. Images, `mailto`, `tel`, static non-clickable assets and email subjects are not modified.
6. `GET /api/r/{token}` is public, returns 302 to the exact stored destination and returns the defined not-found response for invalid tokens.
7. No open redirect is introduced; only server-created HTTP(S) destinations are stored.
8. Short-link failure falls back to original URL and records a structured non-PII error.
9. No N+1 query/insert pattern is introduced; all mapping writes are batched.
10. Affected tests and full `./vendor/bin/phpunit` pass.
11. Self-check confirms the implementation matches this plan and records CODE/DATA/CONFIG/EXTERNAL/INFRASTRUCTURE deviations.

**Execution record**: `PASS — 2026-10-16.` Implemented the migration, encrypted mapping model, Repository/Service contracts and bindings, rich-text-only mail transformation, public redirect route, fail-open handling and tests. Route verification found `GET|HEAD /api/r/{token}` under `api` middleware. `APP_ENV=testing DB_CONNECTION=sqlite DB_DATABASE=:memory: LOG_CHANNEL=single ./vendor/bin/phpunit` passed with **633 tests and 9,355 assertions**. `php -l` passed for new PHP files and `git diff --check` passed. No production deployment or persistent database migration was run.

---

## 9. Test Impact Review

### Existing tests to review

- `tests/Feature/Api/Consultant/CandidateTest.php` — invitation flow and existing response behavior; add rich-text custom-template setup only where required.
- `tests/Unit/Services/RichTextMailProcessorTest.php` — placeholder/HTML rendering regression.
- Existing mail-producing Service tests and any tests asserting serialized email payloads or mock mail files.

### New tests

| Test | Coverage |
|---|---|
| PublicShortLinkTest | 302 redirect, exact query/fragment preservation, invalid token, public/no-auth access |
| ShortLinkServiceTest | token hashing, HTTP(S) filtering, duplicate/self-shortening guard, anchor-label behavior, fallback contract |
| Mail/invitation feature coverage | Invitation email contains short URL; redirect resolves to branch registration URL |
| Rich-text integration | `<a href>` replacement, image `src` untouched, mailto/tel untouched; legacy branch does not call ShortLinkService |
| Failure-path coverage | Mapping insert/service failure keeps original URL and logs non-PII error |

Repository behavior is covered through Feature/Service call chains; no standalone Repository unit test will be added.

---

## 10. Open Decisions / Approval Required

1. Resolved: short route is `/api/r/{token}` on the BE public domain; a separate short-link domain is not required by implementation.
2. Resolved: use 302 redirect.
3. Scope is fixed to all clickable HTTP(S) links in rich-text email bodies, including external policy/meeting/map links; legacy/plain-text emails are excluded.
4. Resolved: no short-link expiry/analytics in GAP-743.
5. Resolved: fail open and send original URL when short-link creation fails.
6. Operational follow-up: set `SHORT_LINK_BASE_URL` to the public HTTPS backend/short-link host in each deployment and verify ingress/TLS; implementation defaults to `APP_URL`.

---

## 11. Checklist trước khi Approve

- [x] First-party redirect architecture approved.
- [x] Public host and route shape approved.
- [x] Scope of links to shorten approved.
- [x] Expiry/analytics decision recorded.
- [x] Fail-open behavior approved.
- [x] Database design reviewed.
- [x] API contract/docs-first phase reviewed.
- [x] Data origin/call chain reviewed.
- [x] File ownership and test impact reviewed.

