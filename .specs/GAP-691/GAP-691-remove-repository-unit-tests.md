# SPEC: Remove repository unit tests and prevent adding new ones

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-29
> **Author**: Codex

## 1. Tổng quan

Chỉ xóa unit test Repository mới được thêm trong thay đổi hiện tại và bổ sung rule vào `AGENTS.md` để không viết unit test Repository mới. Giữ nguyên toàn bộ repository unit test cũ. Kiểm tra hành vi repository thông qua test ở Service hoặc Feature layer khi phù hợp.

**Yêu cầu gốc**: “bỏ unit test repository và thêm rule ko viết unit test repository”.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

N/A — Không thay đổi API.

## 4. Business Logic (Service Layer)

N/A — Không thay đổi business logic runtime.

## 5. Data Origin & Call Chain

N/A — Không thay đổi runtime call chain.

## 6. Constants & Enums

N/A.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Mô tả |
|------|-------|
| `.specs/GAP-691/GAP-691-remove-repository-unit-tests.md` | Decision record cho thay đổi đã triển khai |

### 7.2. Files sửa/xóa sau khi approve

| File | Thay đổi |
|------|----------|
| `AGENTS.md` | Thêm rule không tạo unit test riêng cho Repository implementation/contract; kiểm thử behavior ở Service/Feature layer khi phù hợp |
| `tests/Unit/Repositories/CandidateTimingRepositoryTest.php` | Xóa test Repository mới được thêm trong thay đổi hiện tại; giữ nguyên các test Repository cũ |

## 8. Test Cases

N/A — Đây là thay đổi policy và xóa test mới theo yêu cầu. Không thêm hoặc chạy test Repository. Sau khi xóa, xác nhận các test Repository cũ vẫn nguyên trạng và test mới không còn trong thay đổi.

## 9. Checklist trước khi Approve

- [x] Phạm vi đã được làm rõ: chỉ xóa `CandidateTimingRepositoryTest.php` mới được thêm trong thay đổi hiện tại; giữ nguyên test cũ.
- [x] Rule mới chỉ cấm unit test riêng cho Repository; Service/Feature tests vẫn được dùng để kiểm tra hành vi repository khi phù hợp.
