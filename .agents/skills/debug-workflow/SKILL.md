---
name: debug-workflow
description: >-
  Quy trình debug và xử lý lỗi cho project gap-web-backend.
  Sử dụng skill này khi user gặp lỗi, bug, hoặc cần troubleshoot.
  Ép buộc quy trình phân tích lỗi có cấu trúc thay vì sửa mò.
---

# Debug & Error Handling Workflow

Quy trình debug có cấu trúc cho project `gap-web-backend`.

---

## Nguyên tắc: KHÔNG sửa mò

Khi user báo lỗi, tuân thủ thứ tự sau:

### Bước 1: Thu thập thông tin lỗi

- Yêu cầu user cung cấp: error message, file, line number.
- **KHÔNG** yêu cầu user paste toàn bộ stack trace hay log dài.
- Nếu user paste log dài, tự tóm tắt thành: `[Loại lỗi] tại [File:Line] — [Nguyên nhân 1 dòng]`.

### Bước 2: Trace Call Chain

- Từ error location, trace ngược call chain: Controller -> Service -> Repository.
- Kiểm tra:
  - Input data đúng type/format chưa?
  - Service logic có edge case nào chưa handle?
  - Repository query có đúng không?
  - Database data có consistent không?

### Bước 3: Xác định Root Cause

- Phân biệt rõ: lỗi do **code logic**, **data**, hay **infrastructure** (DB connection, cache, queue).
- Trình bày root cause cho user trước khi sửa.

### Bước 4: Fix có phạm vi nhỏ nhất

- Chỉ sửa đúng file/method gây lỗi.
- **KHÔNG** refactor lan man các file không liên quan.
- Giữ git diff nhỏ nhất có thể.

### Bước 5: Verify

- Giải thích cho user cách verify fix (test case, request mẫu).
- Nếu lỗi liên quan đến data, suggest SQL query để kiểm tra.

---

## Context Hygiene khi Debug

- Mỗi bug fix nên là 1 session ngắn, tập trung.
- Sau khi fix xong, suggest user commit và mở session mới cho task tiếp theo.
- Nếu debug kéo dài > 3 lần qua lại, suggest user mở session mới với summary ngắn gọn.
