# SPEC: Nâng cấp PHP 8.2 qua Docker Official Base Image (php:8.2.35-fpm)

> **Trạng thái**: `DRAFT`  
> **Ngày tạo**: 2026-10-22  
> **Author**: Antigravity  
> **Plan liên quan (Phương án 1)**: [.specs/UNTRACKED/009-php-upgrade-sury-debian-mirror.md](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/UNTRACKED/009-php-upgrade-sury-debian-mirror.md)

---

## 1. Tổng quan

### 1.1. Mục tiêu
Nâng cấp PHP 8.2 lên bản ghim cố định `8.2.35`, loại bỏ hoàn toàn sự phụ thuộc vào các bên thứ 3 (PPA Launchpad / Sury repo), chuẩn hóa image theo chuẩn Docker Official Image.

### 1.2. Hướng tiếp cận (Phương án 2)
* Sử dụng base image chính thức từ Docker Hub: `FROM php:8.2.35-fpm-bookworm`.
* Cài đặt toàn bộ PHP extensions thông qua công cụ chuẩn `mlocati/docker-php-extension-installer` (`install-php-extensions`).
* Điều chỉnh các đường dẫn runtime theo chuẩn PHP Official (`/usr/local/sbin/php-fpm`, `/usr/local/etc/php/...`), tạo symlink `/usr/bin/php` để giữ nguyên tương thích cho Cron.

---

## 2. API Contract & API Docs Assessment

* **Đánh giá thay đổi API / Docs**: `N/A — no API contract/API docs change`.
* Đây là task cấu hình hạ tầng container Docker và nâng cấp minor patch runtime PHP, không thay đổi bất kỳ route, request/response schema hay contract API nào.

---

## 3. Phân tích chi tiết thay đổi (Delta Analysis)

### 3.1. File cấu hình Dockerfile (`docker/8.2/Dockerfile.production`)
| Thành phần | Trước thay đổi | Sau thay đổi |
| :--- | :--- | :--- |
| **Base Image** | `FROM ubuntu:22.04` | `FROM php:8.2.35-fpm-bookworm` |
| **Cơ chế cài Extension** | `apt-get install -y php8.2-*` | `COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/`<br>`RUN install-php-extensions pgsql gd curl imap mbstring xml zip bcmath soap intl readline ldap msgpack igbinary redis memcached pcov xdebug` |
| **Đường dẫn PHP CLI** | `/usr/bin/php8.2` | Tự động có `/usr/local/bin/php`, bổ sung lệnh `ln -s /usr/local/bin/php /usr/bin/php` |
| **Vị trí copy `php.ini`** | `COPY ... /etc/php/8.2/fpm/php.ini` | `COPY ... /usr/local/etc/php/php.ini` |
| **Vị trí copy `pool.d/`** | `COPY ... /etc/php/8.2/fpm/pool.d/` | `COPY ... /usr/local/etc/php-fpm.d/` |
| **Hệ thống đi kèm** | Nginx, Cron, Supervisor, Chrome | Cài đặt qua `apt-get` của Debian Bookworm |

### 3.2. File cấu hình Runtime phụ trợ
| File | Thay đổi | Chi tiết |
| :--- | :--- | :--- |
| `docker/8.2/supervisord.production.conf` | **CÓ SỬA** | Dòng 8: Sửa `command=/usr/sbin/php-fpm8.2 -F` thành `command=php-fpm -F` (hoặc `/usr/local/sbin/php-fpm -F`) |
| `docker/8.2/cron/cron.root` | **Giữ nguyên** | Nhờ có symlink `/usr/bin/php`, file cron không cần sửa |
| `docker/8.2/nginx.conf` | **Giữ nguyên** | FastCGI vẫn trỏ vào port `127.0.0.1:9000` |
| `docker/8.2/start-container` | **Giữ nguyên** | Script start supervisord giữ nguyên |

---

## 4. Danh sách PHP Extensions cần đảm bảo

Image mới sẽ được cài đầy đủ 100% các extensions hiện có:
1. `pgsql` (kèm `pdo_pgsql`)
2. `sqlite3` (kèm `pdo_sqlite`)
3. `gd`
4. `curl`
5. `imap`
6. `mbstring`
7. `xml`
8. `zip`
9. `bcmath`
10. `soap`
11. `intl`
12. `readline`
13. `ldap`
14. `msgpack`
15. `igbinary`
16. `redis`
17. `memcached`
18. `pcov`
19. `xdebug`

---

## 5. Kế hoạch triển khai (Step-by-step)

### Bước 1: Điều chỉnh file cấu hình Supervisor
* Sửa lệnh khởi chạy trong [`docker/8.2/supervisord.production.conf`](file:///Users/nexusfrontiertech/projects/gap-web-backend/docker/8.2/supervisord.production.conf#L8):
  ```ini
  [program:php-fpm]
  command=php-fpm -F
  ```

### Bước 2: Viết lại `docker/8.2/Dockerfile.production`
1. Khai báo `FROM php:8.2.35-fpm-bookworm`.
2. Tích hợp `install-php-extensions` và cài đặt danh sách extensions ở mục 4.
3. Cài đặt các gói hệ thống: `nginx`, `supervisor`, `cron`, `postgresql-client-14`, `google-chrome-stable`, `chromedriver`, `nodejs`, `yarn`.
4. Tạo symlink: `ln -s /usr/local/bin/php /usr/bin/php`.
5. Đổi đường dẫn `COPY` cấu hình FPM sang `/usr/local/etc/php-fpm.d/` và `php.ini` sang `/usr/local/etc/php/php.ini`.

### Bước 3: Test Build Local & Xác thực Container
1. Chạy lệnh build image local:
   ```bash
   docker build --no-cache -t gap-backend-test:official -f ./docker/8.2/Dockerfile.production .
   ```
2. Chạy container test:
   ```bash
   docker run -d --name test-official -p 8080:80 gap-backend-test:official
   ```
3. Kiểm tra các tiêu chí:
   * `docker exec test-official php -v` -> hiển thị chính xác `PHP 8.2.35`.
   * `docker exec test-official php -m` -> đủ 19 extensions.
   * `docker exec test-official supervisorctl status` -> cả 3 process `php-fpm`, `nginx`, `crond` đều `RUNNING`.
   * `curl -I http://localhost:8080` -> kiểm tra Nginx forward đúng sang FPM cổng 9000.
4. Dọn dẹp container test:
   ```bash
   docker rm -f test-official
   ```

---

## 6. Đánh giá Ưu & Nhược điểm của Phương án 2

* **Ưu điểm**:
  * Chuẩn hóa Docker theo Best Practice quốc tế.
  * Ghim cứng vĩnh viễn phiên bản `8.2.35` độc lập hoàn toàn với bên thứ 3.
  * Bản cập nhật bảo mật trực tiếp từ Docker Official Images team.
* **Hạn chế**:
  * Cần sửa một vài dòng trong file `supervisord.production.conf` và cập nhật đường dẫn copy cấu hình trong Dockerfile.
