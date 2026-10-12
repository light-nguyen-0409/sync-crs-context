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
