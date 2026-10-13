# SPEC: GAP-723 — Prevent database tests from running against PostgreSQL

> **Trạng thái**: `IMPLEMENTED`
> **Ngày tạo**: 2026-10-12
> **Ngày cập nhật**: 2026-10-12
> **Author**: Codex
> **Jira**: [GAP-723](https://gappersonnel.atlassian.net/browse/GAP-723)

## 1. Tổng quan

Bổ sung fail-safe cho database test bootstrap để các test có `$useDatabase = true` chỉ được chạy `migrate:fresh` khi runtime database connection là SQLite in-memory. Nếu config cache hoặc environment trỏ sang PostgreSQL/local database, test phải dừng trước khi thực hiện bất kỳ migration destructive nào.

**Yêu cầu gốc**: Sau sự cố PHPUnit dùng cached config và drop các bảng trong PostgreSQL `database_name`, thêm điều kiện SQLite cho mục bảo vệ database test.

## 2. Phạm vi và quyết định

- Chỉ thay đổi test bootstrap; không thay đổi business runtime, API contract, route, migration hoặc schema.
- Giữ nguyên việc `migrate:fresh` và `db:seed` cho test dùng SQLite in-memory.
- Fail closed: không silently skip database setup khi driver không hợp lệ, vì test giả lập thành công trên database sai sẽ che giấu lỗi cấu hình.
- Điều kiện bảo vệ gồm SQLite driver và database `:memory:` trước khi gọi `migrate:fresh`.
- Không coi `phpunit.xml`, `config:clear` hoặc config cache là lớp bảo vệ duy nhất.

## 3. API Contract / Documentation Impact

**N/A — không thay đổi API contract, endpoint, request/response schema, error contract hoặc API documentation.**

## 4. Business Logic / Runtime Behavior

Không thay đổi business flow production. Chỉ ảnh hưởng test bootstrap:

```text
TestCase::setUp()
  → nếu test không dùng database: giữ nguyên
  → nếu dùng database:
      kiểm tra driver = sqlite và database = :memory:
      nếu sai: fail trước migration
      nếu đúng: migrate:fresh → db:seed
```

## 5. Data Origin & Call Chain

- `$useDatabase` được khai báo ở `tests/TestCase.php` và override tại các test base class như `tests/Feature/Api/TestCase.php`.
- Runtime database driver/name được đọc từ active Laravel database connection sau khi application bootstrap hoàn tất; không đọc riêng từ `.env` để tránh tin vào environment khi config cache đang active.
- `migrate:fresh` và `db:seed` chỉ được gọi sau khi safety check pass.

## 6. Files cần sửa

| File | Thay đổi |
|---|---|
| `tests/TestCase.php` | Thêm SQLite in-memory safety guard trước `migrate:fresh`; fail closed nếu driver/database không đúng. |

Không sửa `phpunit.xml`, `.env`, `config/database.php`, migration hoặc production code trong scope này.

## 7. Test Cases & Verification

| Case | Kỳ vọng |
|---|---|
| Database test với SQLite `:memory:` | Tiếp tục chạy migration và seed như hiện tại. |
| Database test với PostgreSQL do cached config | Fail trước `migrate:fresh`; không phát sinh `DROP TABLE`. |
| Test không dùng database | Không chạy safety guard destructive setup ngoài flow hiện tại. |
| Syntax/diff checks | PHP syntax và `git diff --check` pass. |

Sau khi implement, chạy test phù hợp trong môi trường SQLite; không chạy lại full suite trên container đang dùng PostgreSQL nếu chưa xác nhận config runtime đã tách khỏi database thật.

## 8. Acceptance Criteria

 - [x] Database tests không thể gọi `migrate:fresh` khi active driver không phải SQLite.
 - [x] Database tests không thể gọi `migrate:fresh` khi SQLite không phải `:memory:`.
 - [x] Config cache trỏ tới PostgreSQL phải làm test fail trước destructive query.
 - [x] Không thay đổi production runtime hoặc API contract.
 - [x] PHP syntax và targeted verification pass.

## 9. Implementation Result

- Updated `tests/TestCase.php` to require SQLite `:memory:` before `migrate:fresh` or `db:seed`.
- PHP syntax check passed.
- `git diff --check` passed.
- Targeted referee Feature test intentionally failed fast with `driver [pgsql]` and `database [database_name]` at the new guard; no `migrate:fresh` or `DROP TABLE` was reached.
- Full PHPUnit was not rerun because the active container config still points to the local PostgreSQL database and the safety guard correctly blocks it.

