# SPEC: Prevent unrelated edits to existing methods

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex

## 1. Tổng quan

Bổ sung rule vào `AGENTS.md` yêu cầu không tự ý sửa hàm/phương thức cũ nếu thay đổi đó không phục vụ trực tiếp logic của task đang xử lý. Thay đổi tới hàm dùng chung vẫn được phép khi cần thiết để hoàn thành logic task hoặc giữ đúng contract của call chain bị ảnh hưởng.

**Yêu cầu gốc**: “Thêm rule không tự ý sửa hàm cũ nếu không có liên quan gì đến logic task hiện tại đang xử lý”.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

N/A — Không thay đổi API.

## 4. Business Logic (Service Layer)

N/A — Không thay đổi runtime business logic.

## 5. Data Origin & Call Chain

N/A — Không thay đổi runtime call chain.

## 6. Constants & Enums

N/A.

## 7. Files cần sửa

| File | Thay đổi |
|------|----------|
| `AGENTS.md` | Thêm rule về phạm vi sửa hàm hiện có: chỉ sửa khi liên quan trực tiếp logic task hoặc cần để hoàn thành contract/call chain bị ảnh hưởng; không tiện tay refactor/cleanup hàm không liên quan |

## 8. Test Cases

N/A — Chỉ cập nhật hướng dẫn tác nghiệp, không đổi runtime code.

## 9. Checklist trước khi Approve

- [x] Rule mới không cấm sửa helper/hàm dùng chung khi chính task cần thay đổi đó.
- [x] Rule cấm các thay đổi tiện tay, refactor hoặc cleanup hàm không liên quan task.
