# SPEC: Local Redis Queue Worker với Supervisor

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-21
> **Author**: Codex

---

## 1. Tổng quan

Thiết lập queue local chạy bất đồng bộ bằng Redis và được Supervisor quản lý trong container `laravel.test`. Worker sẽ tự khởi động cùng container, tự restart khi process lỗi và xử lý queue `default`.

**Yêu cầu gốc**: Chạy Laravel queue worker bằng Supervisor trong môi trường local Docker của project.

**Quyết định kỹ thuật**:

- Dùng Redis làm queue backend.
- Không dùng `database` queue vì bảng `jobs` hiện tại là bảng nghiệp vụ (`external_id`, `title`, `branch_id`), không tương thích với schema queue của Laravel.
- Chạy worker trong cùng container `laravel.test`, do container này đã khởi chạy Supervisor làm process chính.
- Không thay đổi business logic, API, migration hoặc Laravel architecture layers.

---

## 2. Database Design

N/A. Không thay đổi database schema.

Bảng `failed_jobs` hiện có tiếp tục được dùng để lưu failed queue jobs.

---

## 3. API Contract

N/A. Không tạo hoặc sửa API endpoint.

---

## 4. Business Logic (Service Layer)

N/A. Không thay đổi business logic.

### 4.1. Runtime flow

```text
docker compose up
  → laravel.test container
    → start-container
      → supervisord
        → php artisan serve
        → php artisan queue:work redis --queue=default
  → redis container
```

### 4.2. Queue worker configuration

- Connection: `redis`
- Queue: `default`
- Sleep khi queue rỗng: 3 giây
- Attempts: 3
- Worker timeout: 60 giây
- Supervisor: `autostart=true`, `autorestart=true`, một process worker

### 4.3. Side Effects

| Loại | Trigger | Mô tả |
|------|---------|-------|
| Queue | Job/Mailable được dispatch | Job được lưu trong Redis và xử lý bởi worker |
| Failed job | Worker thất bại sau số lần retry | Lưu vào bảng `failed_jobs` |

---

## 5. Data Origin & Call Chain

```text
.env
  → config/queue.php ('default' = env('QUEUE_CONNECTION'))
    → artisan queue:work redis
      → config/database.php ('redis.default' lấy REDIS_HOST/REDIS_PORT)
        → Redis service trong Docker network `sail`
```

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|-----------------|------------|
| `QUEUE_CONNECTION` | `config/queue.php` | `.env` local / `.env.example` | ✅ |
| `REDIS_HOST` | `config/database.php` | `.env`, giá trị `redis` khi chạy trong Docker | ✅ |
| `REDIS_PORT` | `config/database.php` | `.env`, giá trị `6379` | ✅ |
| `REDIS_CLIENT` | `config/database.php` | `.env`, giá trị `phpredis` | ✅ |
| `default` queue | `config/queue.php` | `REDIS_QUEUE`, mặc định `default` | ✅ |
| Failed job payload | `config/queue.php` | Bảng `failed_jobs` hiện có | ✅ |

PHP Redis extension đã có trong `docker/8.1/Dockerfile`, nên không cần bổ sung package trong Docker image.

---

## 6. Constants & Enums

Không phát sinh business constants hoặc enum mới.

Các giá trị runtime cố định của worker (`default`, `3`, `60`) sẽ nằm trong command Supervisor vì đây là operational configuration, không phải business logic.

---

## 7. Files cần tạo/sửa

### 7.1. Files mới

Không tạo file implementation mới. Redis sẽ dùng image `redis:7-alpine` trong Docker Compose.

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `docker-compose.yml` | Thêm service Redis, network `sail`, volume tùy chọn và dependency từ `laravel.test` đến Redis |
| `docker/8.1/supervisord.conf` | Thêm `[program:queue-worker]` chạy `php artisan queue:work redis` với autorestart |
| `docker/8.1/Dockerfile` | Sửa cách tìm thư mục ChromeDriver sau khi giải nén để local image build không bị chặn |
| `.env.example` | Đổi `QUEUE_CONNECTION` sang `redis`, cấu hình host Redis cho Docker |
| `.env` | Cập nhật local-only values `QUEUE_CONNECTION=redis`, `REDIS_HOST=redis`, giữ nguyên các giá trị khác |
| `README.md` | Bổ sung lệnh build/restart và kiểm tra worker local |

Không sửa `config/queue.php`, migration, Controller, Service, Repository hoặc Mail class.

---

## 8. Test Cases & Verification

| Test / Check | Mô tả |
|--------------|-------|
| `docker compose config` | Xác nhận Compose syntax và service dependency hợp lệ |
| `docker compose build laravel.test` | Build lại image để copy Supervisor config mới |
| `docker compose up -d` | Khởi động Laravel, PostgreSQL, ClamAV và Redis |
| `docker compose logs laravel.test` | Xác nhận web process và queue worker cùng start |
| `ps aux | grep '[q]ueue:work'` trong container | Xác nhận worker process đang chạy |
| `php artisan queue:failed` | Xác nhận Laravel đọc được failed jobs backend |
| Dispatch một queued Mailable/job hiện có | Xác nhận payload được xử lý bất đồng bộ bởi worker |
| `./vendor/bin/phpunit` | Chạy toàn bộ test suite sau thay đổi cấu hình |

**Kết quả verification**:

- `docker compose config --quiet`: pass.
- Docker image `sail-8.1/app`: build thành công.
- Redis: healthy, `redis-cli ping` trả về `PONG`.
- Supervisor: `queue-worker_00 entered RUNNING state`.
- Laravel worker process: `queue:work redis --queue=default` đang chạy.
- `php artisan queue:work redis --once`: kết nối Redis thành công.
- `php artisan queue:failed`: không có failed jobs.
- Closure smoke test từ Tinker không dùng được vì closure eval không có source file để Laravel serialize; không phản ánh lỗi worker.
- `./vendor/bin/phpunit`: `OK (473 tests, 2057 assertions)`.

### Tiêu chí hoàn thành

- Redis container ở trạng thái running.
- Supervisor giữ worker ở trạng thái running.
- Worker dùng connection `redis`, queue `default`.
- Worker tự khởi động lại nếu process dừng bất thường.
- Không ảnh hưởng web server và cron process hiện tại.
- Toàn bộ PHPUnit test pass.

---

## 9. Checklist trước khi Approve

- [x] Database design đã xác nhận không cần thay đổi
- [x] API contract xác nhận không liên quan
- [x] Runtime flow đã được mô tả
- [x] Call chain và nguồn biến môi trường đã trace
- [x] Không phát sinh business magic value
- [x] File list đầy đủ
- [x] Test và verification commands đã liệt kê
- [x] User approve plan
