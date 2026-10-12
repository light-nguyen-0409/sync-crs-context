# SPEC: Đồng bộ API contract/API docs sang crs-api-docs

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-07
> **Author**: Codex

## 1. Tổng quan

Bổ sung workspace rule cho project `gap-web-backend`: bất cứ khi nào API
contract hoặc API documentation được cập nhật, thay đổi tương ứng phải được
đồng bộ sang project `~/projects/crs-api-docs`.

**Yêu cầu gốc**: User yêu cầu thêm rule đồng bộ API contract/API docs sang
`~/projects/crs-api-docs`.

## 2. Phạm vi và cách tiếp cận

- Cập nhật `AGENTS.md` của `gap-web-backend` với một rule rõ ràng về trigger,
  project đích và trách nhiệm kiểm tra diff.
- Quy định này phải được thể hiện như một step/gate trong plan triển khai API
  và phải hoàn tất trước step triển khai code lên môi trường đích.
- Giữ nguyên các rule hiện có; không refactor hoặc format lại file ngoài dòng
  cần thêm.
- Không thay đổi route, controller, service, repository, database, test hoặc
  API runtime.
- Không tự động sửa project `~/projects/crs-api-docs` trong task này; rule chỉ
  ghi nhận nghĩa vụ phải cập nhật project đó trong các task API contract/docs
  sau này.

## 3. Step bắt buộc trong plan triển khai API

Mỗi plan triển khai API phải có step sau, đặt trước step deploy code:

### Pre-deployment gate — Đồng bộ API contract/API docs

1. Xác định thay đổi có ảnh hưởng API contract hoặc API docs hay không, gồm
   route contract, request/response schema, examples, error contract và tài
   liệu endpoint.
2. Nếu có ảnh hưởng, cập nhật bản tương ứng trong
   `~/projects/crs-api-docs` trong cùng task và kiểm tra diff của project đó.
3. Nếu không có ảnh hưởng, ghi rõ `N/A — no API contract/API docs change` vào
   plan hoặc checklist triển khai.
4. Chỉ được chuyển sang step deploy code khi gate này đã hoàn tất. Nếu project
   đích không tồn tại, không thể ghi, hoặc tài liệu chưa đồng bộ thì phải dừng
   và báo blocker; không được coi code đã sẵn sàng triển khai.

**Gate output**:

- Kết luận impact: `Updated` hoặc `N/A`.
- Nếu `Updated`: danh sách file/diff đã cập nhật trong
  `~/projects/crs-api-docs`.
- Xác nhận gate pass trước khi deploy code.

## 4. Nội dung rule dự kiến

Rule sẽ nêu tối thiểu:

1. Trigger: tạo mới hoặc sửa API contract/API docs, gồm route contract,
   request/response schema, examples, error contract và tài liệu endpoint.
2. Đồng bộ: cập nhật bản tương ứng trong
   `~/projects/crs-api-docs` trong cùng task và trước khi deploy code.
3. Verification: kiểm tra diff và trạng thái của cả hai project trước khi
   báo gate pass; nếu project đích không tồn tại hoặc không thể ghi thì phải
   báo blocker, không coi code đã sẵn sàng triển khai.
4. Scope: không áp dụng cho thay đổi backend không làm thay đổi contract hoặc
   docs, trừ khi task đó đồng thời cập nhật các tài liệu nói trên.

## 5. Files cần sửa

| File | Thay đổi |
|------|----------|
| `AGENTS.md` | Thêm workspace rule về đồng bộ API contract/API docs sang `~/projects/crs-api-docs` |

## 6. Verification sau khi được duyệt

- Kiểm tra diff chỉ chứa rule mới trong `AGENTS.md`.
- Đọc lại rule để bảo đảm trigger, project đích và điều kiện blocker không mơ
  hồ.
- Xác nhận task hiện tại không thay đổi API contract/API docs, nên pre-deployment
  gate của task này là `N/A`.
- Không cần chạy PHPUnit vì không thay đổi code runtime.

## 7. Acceptance criteria

- `AGENTS.md` có rule bắt buộc cập nhật `~/projects/crs-api-docs` khi API
  contract/API docs thay đổi.
- Rule yêu cầu đây là một step trong plan triển khai và phải pass trước khi
  deploy code.
- Rule yêu cầu xác minh cả hai project trước khi báo gate pass.
- Không có thay đổi ngoài phạm vi workspace rule.

## 8. Kết quả thực hiện

- Đã thêm rule tại `AGENTS.md:59-63`.
- Pre-deployment gate yêu cầu ghi nhận `Updated` hoặc
  `N/A — no API contract/API docs change` trước step deploy code.
- Task hiện tại không thay đổi API contract/API docs, nên gate được xác nhận
  là `N/A`.
- `git diff --check` không phát hiện whitespace lỗi.
