# SPEC: Remove Processing-Time Logging

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-22
> **Author**: Codex

---

## 1. Tổng quan

Loại bỏ instrumentation dùng để đo và ghi log thời gian xử lý trong
`WorkerWelfareCheckService.php`. Giữ nguyên các log nghiệp vụ/lỗi hiện có, không
thay đổi business flow, API response hoặc database behavior.

**Yêu cầu gốc**: Bỏ log đo thời gian xử lý.

---

## 2. Database Design

N/A — Không thay đổi schema, migration hoặc query behavior.

---

## 3. API Contract

N/A — Không thay đổi endpoint, request, response hoặc status code.

---

## 4. Business Logic (Service Layer)

### 4.1. Phạm vi loại bỏ

- Xóa phase timing trong `WorkerWelfareCheckService`, gồm `hrtime()`, các
  phase constants và `logPhaseDuration()`.

### 4.2. Phạm vi giữ nguyên

- Giữ `Log::error()` cho lỗi gửi failure email và lỗi đồng bộ MatchMaker.
- Giữ nguyên thứ tự xử lý, queue dispatch, file cleanup, exception behavior,
  response và mọi query nghiệp vụ.
- Giữ nguyên timing logs trong `TestCommand`, middleware slow API, DB listener và
  các logging channels/config liên quan vì nằm ngoài phạm vi yêu cầu.

---

## 5. Data Origin & Call Chain

Call chain nghiệp vụ không thay đổi. Chỉ bỏ các nhánh phase instrumentation
trong Worker Welfare Check Service:

```text
Worker Welfare Check
  → business processing
  → không còn ghi phase duration log
```

Request metrics, DB query metrics và tổng duration trong các thành phần khác
không thay đổi.

---

## 6. Constants & Enums

Xóa các constants chỉ phục vụ phase timing trong
`WorkerWelfareCheckService`. Không thêm magic values mới.

---

## 7. Files cần sửa/xóa

| File | Thay đổi |
|------|----------|
| `app/Services/WorkerWelfareCheckService.php` | Xóa phase timing instrumentation, giữ nguyên business logic và error logs |
| `specs/worker-welfare-check-performance-breakdown.md` | Ghi nhận phase timing trong Service đã retire |

`specs/remove-processing-time-logs.md` sẽ được cập nhật trạng thái sau khi
implementation và verification hoàn tất.

---

## 8. Test Cases

- Chạy syntax check cho toàn bộ file PHP đã sửa.
- Chạy các test liên quan đến Worker Welfare Check.
- Chạy toàn bộ `./vendor/bin/phpunit` và đảm bảo không còn test fail.
- Search lại các marker phase timing trong `WorkerWelfareCheckService.php` để
  xác nhận instrumentation đã được loại bỏ.

Không chạy formatter/linter tự động.

---

## 9. Checklist trước khi Approve

- [x] Đã xác định phase timing log trong `WorkerWelfareCheckService.php`.
- [x] Đã phân biệt timing logs với error logs cần giữ lại.
- [x] Đã xác nhận các timing logs ngoài Service nằm ngoài phạm vi.
- [x] Đã xác định không thay đổi API/database/business behavior.
- [x] User approve plan.
- [x] Implementation hoàn tất.
- [x] Test suite pass.
