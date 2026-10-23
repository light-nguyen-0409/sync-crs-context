# SPEC: MatchMaker API Contract Static Swagger SPA

> **Trạng thái**: DRAFT
> **Ngày tạo**: 2026-10-02
> **Author**: Codex

---

## 1. Tổng quan

Tạo một repository riêng trong thư mục projects để chứa OpenAPI contract của
MatchMaker và Swagger UI dạng static SPA. Repository sẽ được publish bằng
GitHub Pages, không cần backend server runtime.

**Yêu cầu gốc**: Tách MatchMaker API contract khỏi backend CRS, cung cấp một
trang Swagger để đội MM/CRS cùng sử dụng và review.

**Phạm vi**:

- Chuyển contract hiện tại từ
  .business-spec/backend-matchmaker-api-call-inventory.md thành openapi.yaml.
- Tạo static Swagger UI có thể mở trực tiếp từ GitHub Pages.
- Tạo GitHub Actions workflow để publish static artifact.
- Khởi tạo Git repository riêng, commit và push lên GitHub repository đích.

**Thông tin cần xác nhận trước Phase 2**:

- Tên local folder dự kiến:
  /Users/nexusfrontiertech/projects/matchmaker-api-contract
- GitHub owner/repository name.
- Repository visibility: public hoặc private.
- Remote repository đã tồn tại hay cho phép tạo mới bằng GitHub CLI.

Không đưa credential, Basic Auth value thật hoặc secret của MM vào repository.

## 2. Database Design

Không thay đổi database CRS hoặc MatchMaker database.

## 3. API Contract

### 3.1. OpenAPI source

- Dùng OpenAPI 3.0.3 để tương thích rộng với Swagger UI.
- openapi.yaml là source of truth của repository mới.
- Contract bao gồm 36 endpoint active và 5 endpoint reserved hiện có trong
  tài liệu CRS.
- Các field chưa xác định giữ type object/array với
  additionalProperties: true hoặc description unknown, không tự suy đoán
  thành contract chính thức.
- Khai báo Basic Auth và các request multipart.
- Khai báo response body, status code và error behavior theo contract hiện tại.

### 3.2. Static Swagger UI

- index.html load openapi.yaml.
- Dùng Swagger UI static assets; không cần API server riêng.
- Try it out mặc định disabled nếu site public.
- Không nhúng credential vào UI hoặc file OpenAPI.

## 4. Business Logic

Không có business logic runtime. Repository chỉ hiển thị tài liệu API.

## 5. Data Origin & Call Chain

Nguồn dữ liệu contract:

1. .business-spec/backend-matchmaker-api-call-inventory.md
2. app/Externals/EpsilonApi.php
3. app/Services/MatchMakerService.php
4. app/Externals/BespokeMatchMaker.php
5. config/matchmaker.php

Không tạo call-chain mới trong backend CRS.

## 6. Implementation Phases

### Phase 1 — Contract extraction và static SPA skeleton

**Input**:

- Contract Markdown đã được duyệt trong .business-spec.
- Danh sách endpoint, payload, response và data type hiện tại.

**Files sở hữu**:

- Repository mới tại /Users/nexusfrontiertech/projects/matchmaker-api-contract.
- openapi.yaml
- index.html
- Swagger UI static assets.
- README.md

**Công việc**:

1. Khởi tạo folder và Git repository local.
2. Chuyển từng endpoint thành OpenAPI path/operation.
3. Tách reusable schemas trong components.schemas.
4. Khai báo security scheme, query/path parameters, JSON và multipart body.
5. Tạo Swagger UI static page trỏ tới openapi.yaml.
6. Thêm hướng dẫn local preview và quy ước cập nhật contract.

**Dependencies**:

- Không cần thay đổi code hoặc database backend.
- Cần contract Markdown hiện tại làm input.

**Acceptance criteria**:

- Swagger UI mở được từ file/static server.
- Tất cả endpoint trong bảng summary xuất hiện trong OpenAPI.
- Không có secret thật.
- Payload và response schema khớp contract Markdown; unknown giữ nguyên unknown.

**Test gate**:

- Validate OpenAPI bằng OpenAPI linter/parser.
- Kiểm tra Swagger UI không có broken reference.
- Kiểm tra manual các endpoint JSON và multipart.

### Phase 2 — GitHub Pages deployment và remote push

**Input**:

- Repository local từ Phase 1.
- GitHub owner/repository name và visibility đã được xác nhận.

**Files sở hữu**:

- .github/workflows/deploy-pages.yml

**Công việc**:

1. Tạo workflow deploy static artifact bằng GitHub Pages.
2. Cấu hình permissions contents: read, pages: write,
   id-token: write.
3. Commit với message rõ ràng.
4. Tạo hoặc kết nối remote GitHub repository.
5. Push branch mặc định.
6. Kiểm tra deployment URL và Swagger UI production.

**Dependencies**:

- GitHub authentication hợp lệ.
- Quyền tạo repository hoặc quyền push vào remote.
- GitHub Pages được phép sử dụng cho repository.

**Acceptance criteria**:

- Push thành công lên remote đã xác nhận.
- GitHub Actions hoàn tất không lỗi.
- GitHub Pages phục vụ được index.html và openapi.yaml.
- URL production hiển thị đúng API contract.

**Test gate**:

- Kiểm tra workflow run thành công.
- Kiểm tra HTTP response của Pages URL.
- Kiểm tra Swagger UI load được spec và không báo lỗi parse.
- Try it out chỉ bật khi đã xác nhận CORS và cơ chế auth của MM.

## 7. Files cần tạo/sửa

### 7.1. Files trong repository mới

| File | Mô tả |
|---|---|
| openapi.yaml | OpenAPI 3.0.3 contract |
| index.html | Static Swagger UI entry point |
| swagger-ui-bundle.js | Swagger UI runtime asset |
| swagger-ui.css | Swagger UI styles |
| README.md | Cách preview, deploy và cập nhật contract |
| .github/workflows/deploy-pages.yml | GitHub Pages deployment workflow |

### 7.2. Files CRS hiện tại

Không sửa source code CRS trong task này.

## 8. Rollout và giới hạn

- Public GitHub Pages chỉ phù hợp nếu contract không chứa thông tin nhạy cảm.
- Không lưu Basic Auth credentials, API password hoặc token trong OpenAPI/UI.
- Browser Try it out gọi trực tiếp MM sẽ phụ thuộc CORS.
- Error envelope và một số response field hiện vẫn là unknown; cần MM review
  sau khi publish bản đầu tiên.

## 9. Approval gate

Chưa tạo folder/repository mới, chưa tạo file implementation và chưa push
remote cho đến khi plan này được user duyệt và cung cấp GitHub repository đích
hoặc xác nhận owner/name/visibility để tạo repository mới.

---

# Addendum: Postman collection theo category

## 10. Mục tiêu bổ sung

Tạo một Postman collection có thể import vào Postman, bao gồm toàn bộ các
operation được khai báo trong `openapi.yaml` của repository
`~/projects/matchmaker-api-contract`, và chia request thành folder theo
category/tag của contract.

Phạm vi mặc định là CRS integration inventory hiện có trong `openapi.yaml`
(Epsilon và Bespoke/non-Epsilon). File snapshot chính thức
`epsilon-openapi.json` không được tự động trộn vào collection này vì nó là
catalog chính thức lớn hơn contract runtime của CRS; nếu cần toàn bộ catalog
chính thức, đó là một collection riêng cần được duyệt thêm.

## 11. Thiết kế collection

- Tên collection dự kiến: `MatchMaker API - CRS Integration`.
- Tạo folder theo tag/category hiện có: Authentication, Epsilon, Health,
  Candidate read, Candidate registration, Candidate update, Compliance and
  files, Reserved và Bespoke/non-Epsilon khi operation có tag tương ứng.
- Giữ method, path, query/path parameters, request body, response examples và
  security scheme từ `openapi.yaml`; không tự thêm endpoint ngoài contract.
- Dùng biến Postman, không ghi credential thật vào file:
  - `{{epsilon_base_url}}`
  - `{{epsilon_username}}` và `{{epsilon_password}}` dạng secret
  - `{{master_user_auth}}`, `{{client_user_auth}}`, `{{candidate_user_auth}}`
    dạng secret khi endpoint cần.
- Epsilon request dùng Basic Auth và các custom auth headers conditional theo
  contract. Bespoke request chỉ dùng Basic Auth riêng của Bespoke.
- Thêm mô tả ở collection/folder để ghi rõ Postman không đại diện cho browser
  call trực tiếp; Epsilon CORS và credential exposure vẫn phải được xử lý qua
  backend proxy.
- Ưu tiên Postman filesystem-first/git-native v3; nếu người dùng cần file
  import trực tiếp vào Postman UI, tạo thêm artifact import tương thích sau khi
  xác nhận CLI hỗ trợ export/convert, nhưng không lưu secret thật.

## 12. Files dự kiến

| File | Mục đích |
|---|---|
| `postman/collections/matchmaker-api-crs-integration/.resources/definition.yaml` | Metadata, collection variables và auth mặc định |
| `postman/collections/matchmaker-api-crs-integration/<category>/*.request.yaml` | Một file cho mỗi request theo schema v3 |
| `postman/environments/matchmaker-api.environment.yaml` | Base URL và placeholder/secret variables, không có giá trị credential thật |
| `README.md` | Hướng dẫn import/sync, set secret variables và giới hạn CORS |

Nếu Postman CLI yêu cầu một file import v2.1 riêng, file đó sẽ được tạo ở
đường dẫn được CLI hỗ trợ và được kiểm tra không chứa secret; không sửa
`openapi.yaml` chỉ để phục vụ format import.

## 13. Validation và acceptance criteria

- Số operation trong collection khớp số operation nguồn trong `openapi.yaml`.
- Không có duplicate method + path trong cùng category ngoài trường hợp
  contract nguồn cố ý khai báo khác operation.
- Folder/category không chứa request ngoài scope hoặc thiếu request nguồn.
- Collection/environment lint pass bằng Postman CLI hoặc validator tương ứng.
- Import vào Postman thành công và hiển thị đúng folder hierarchy.
- Không có Basic password, access token, private environment value hoặc secret
  thật trong git diff.
- Không chạy request thật tới Epsilon trong bước generate/validation; chỉ chạy
  integration test sau khi user cung cấp target và explicit approval.

## 14. API contract/docs impact gate

Task này không thay đổi endpoint, request/response schema hoặc error contract;
collection là artifact dẫn xuất từ contract hiện tại. Ghi nhận
`~/projects/crs-api-docs`: **N/A — no API contract/API docs change**, trừ khi
trong lúc triển khai phát hiện phải sửa contract nguồn. Nếu contract nguồn bị
thay đổi, phải dừng collection generation, cập nhật docs-first theo
`AGENTS.md`, rồi regenerate collection.

## 15. Execution gate

Chưa tạo `postman/` files, chưa sửa `openapi.yaml`, chưa import/push collection
lên Postman Cloud và chưa gọi Epsilon cho đến khi user explicitly approve
addendum này. Sau approval mới kiểm tra Postman CLI, generate collection,
validate, review diff và bàn giao file import/folder structure.

## 16. Addendum implementation result

**Status**: PASS — generated and validated locally; Postman Cloud push chưa thực hiện.

### Files đã tạo/cập nhật trong `~/projects/matchmaker-api-contract`

- `postman/MatchMaker API - CRS Integration.postman_collection.json` — file
  Postman Collection v2.1 để import trực tiếp.
- `postman/MatchMaker API.postman_environment.json` — environment v2.1 để
  import trực tiếp trong Postman UI và resolve host variables.
- `postman/collections/matchmaker-api-crs-integration/.resources/definition.yaml`
  — metadata collection v3.
- `postman/collections/matchmaker-api-crs-integration/` — 41 request v3, chia
  theo adapter (`Epsilon`, `Bespoke - non-Epsilon`) và category/tag.
- `postman/environments/matchmaker-api.environment.yaml` — environment
  template, secret variables để trống/disabled.
- `README.md` — hướng dẫn import và cảnh báo credential/CORS.

### Validation evidence

- `openapi.yaml` operations: 41.
- Generated v3 request files: 41.
- v2.1 import items: 41.
- `postman collection lint ... --fail-severity warning --reporter json`:
  PASS — 41 files scanned, 0 errors, 0 warnings.
- `postman environment lint ... --fail-severity warning --output json`:
  PASS — 1 file scanned, 0 errors, 0 warnings.
- Environment JSON import audit: PASS — 31 variables, gồm
  `epsilon_base_url` và `bespoke_base_url`; không có secret thật.
- Postman UI rendering fix: file v2.1 request URLs now include `raw`, `host`,
  `path` và `query`; `postman collection migrate` PASS sau khi regenerate.
- `postman collection migrate` trên file v2.1 vào thư mục tạm: PASS.
- Placeholder audit: PASS — không có credential/token thật; mọi placeholder
  đều có trong environment template.
- Contract source diff: `openapi.yaml`, `openapi-bundle.json` và
  `epsilon-openapi.json` không bị sửa.
- API contract/docs gate: **N/A — no API contract/API docs change**; collection
  chỉ là artifact dẫn xuất. Không cập nhật hoặc commit/push `~/projects/crs-api-docs`.
- Không gọi request thật tới Epsilon và không push lên Postman Cloud.

## 17. Addendum: tự động tạo `master_user_auth`

### Mục tiêu

Sau khi chạy `GET /api/Accounts/GetAccessToken`, Postman phải tự động đọc
`usr_token` từ response, đọc `peo_no` từ environment và set environment
variable:

```text
master_user_auth = base64(peo_no:usr_token)
```

Các request Epsilon đang dùng `{{master_user_auth}}`, nên những request tiếp
theo có thể dùng token vừa nhận mà không cần copy thủ công.

### Thiết kế

- Thêm `afterResponse` script vào request `getAccessToken` trong collection v3.
- Thêm script tương đương dạng `test` event vào file Collection v2.1 để Postman
  UI import trực tiếp giữ nguyên behavior.
- Đọc `peo_no` bằng `pm.environment.get('peo_no')`.
- Parse JSON response và đọc `usr_token`.
- Encode bằng Base64 và ghi bằng
  `pm.environment.set('master_user_auth', encodedValue)`.
- Không log token hoặc giá trị `master_user_auth` ra Postman Console.
- Nếu response không hợp lệ hoặc thiếu `peo_no`/`usr_token`, tạo test failure
  rõ ràng và không ghi giá trị rỗng vào environment.

### Variable mapping dùng chung

Request không được hardcode hoặc yêu cầu nhập lại các giá trị dùng chung. Quy
ước variable:

| Variable | Scope chính | Secret | Dùng cho |
|---|---|---:|---|
| `epsilon_base_url` | Collection fallback + Environment override | Không | Tất cả request Epsilon |
| `bespoke_base_url` | Collection fallback + Environment override | Không | Tất cả request Bespoke/non-Epsilon |
| `epsilon_username` | Environment | Có | Basic Auth của Epsilon |
| `epsilon_password` | Environment | Có | Basic Auth của Epsilon |
| `bespoke_username` | Environment | Có | Basic Auth của Bespoke |
| `bespoke_password` | Environment | Có | Basic Auth của Bespoke |
| `peo_no` | Environment | Không | Candidate context và script tạo master auth |
| `master_user_auth` | Environment | Có | Header Epsilon sau khi lấy token |

Các request chỉ tham chiếu `{{epsilon_base_url}}`,
`{{bespoke_base_url}}`, `{{epsilon_username}}`, `{{epsilon_password}}`,
`{{bespoke_username}}`, `{{bespoke_password}}` và `{{master_user_auth}}`;
không tạo bản copy credential riêng ở từng request. Environment override được
ưu tiên để người dùng đổi target/credential theo môi trường mà không phải sửa
collection.

### Validation gate

- Static audit xác nhận script chỉ nằm trên `getAccessToken`.
- Static audit xác nhận dùng đúng response key `usr_token`, environment key
  `peo_no` và output key `master_user_auth`.
- Static audit xác nhận URL/auth của mọi request dùng shared variables, không có
  credential hoặc host hardcode trong từng request.
- Postman collection/environment lint pass.
- Không gọi Epsilon thật trong validation; manual run chỉ thực hiện khi user
  đã set credential và target environment.

### Implementation result

**Status**: PASS.

- v3 script cập nhật tại
  `postman/collections/matchmaker-api-crs-integration/Epsilon/Authentication/getAccessToken.request.yaml`.
- v2.1 `test` event cập nhật trong
  `postman/MatchMaker API - CRS Integration.postman_collection.json`.
- README đã ghi rõ thứ tự chạy `GetAccessToken` trước các request Epsilon khác.
- Static audit: đúng 1 request có script; request này dùng `peo_no`, `usr_token`,
  `btoa` và set `master_user_auth`; không có token logging.
- Shared auth audit: 41/41 request dùng các variable credential chung; không có
  username/password hardcode trong request.
- Collection lint: PASS — 41 files scanned, 0 errors, 0 warnings.
- Environment lint: PASS — 1 file scanned, 0 errors, 0 warnings.
- v2.1 `postman collection migrate`: PASS.
- Không gọi Epsilon thật và không push lên Postman Cloud.
