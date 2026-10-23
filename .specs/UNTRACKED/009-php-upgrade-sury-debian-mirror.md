# SPEC: Nâng cấp PHP 8.2 qua Debian Mirror (packages.sury.org)

> **Trạng thái**: `DRAFT`  
> **Ngày tạo**: 2026-10-22  
> **Author**: Antigravity  
> **Plan liên quan (Phương án 2)**: [.specs/UNTRACKED/010-php-upgrade-official-base-image.md](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/UNTRACKED/010-php-upgrade-official-base-image.md)

---

## 1. Tổng quan

### 1.1. Mục tiêu
Giải quyết lỗi HTTP 503 khi kéo PHP từ PPA Ubuntu (`ppa.launchpadcontent.net/ondrej/php/ubuntu`) trong quá trình AWS CodeBuild build image `Dockerfile.production` (PHP 8.2.35).

### 1.2. Hướng tiếp cận (Phương án 1)
* Chuyển base image từ `ubuntu:22.04` sang `debian:bookworm-slim`.
* Sử dụng mirror trực tiếp chính thức của Ondrej Sury tại `https://packages.sury.org/php/` (được bảo trợ CDN bởi Fastly, khắc phục hoàn toàn lỗi 503 của Launchpad).
* Giữ nguyên cơ chế cài đặt `.deb` qua `apt-get`, bảo toàn **100%** các đường dẫn runtime hiện có (`/usr/sbin/php-fpm8.2`, `/etc/php/8.2/fpm/...`, `/usr/bin/php`).

---

## 2. API Contract & API Docs Assessment

* **Đánh giá thay đổi API / Docs**: `N/A — no API contract/API docs change`.
* Đây là task cấu hình hạ tầng container Docker và nâng cấp minor patch runtime PHP, không thay đổi bất kỳ route, request/response schema hay contract API nào.

---

## 3. Phân tích chi tiết thay đổi (Delta Analysis)

### 3.1. File cấu hình Dockerfile (`docker/8.2/Dockerfile.production`)
| Thành phần | Trước thay đổi (`ubuntu:22.04`) | Sau thay đổi (`debian:bookworm-slim`) |
| :--- | :--- | :--- |
| **Base Image** | `FROM ubuntu:22.04` | `FROM debian:bookworm-slim` |
| **GPG Key & Repo PHP** | PPA Launchpad Ubuntu `ppa.launchpadcontent.net` | `https://packages.sury.org/php/apt.gpg`<br>`deb https://packages.sury.org/php/ bookworm main` |
| **Repo PostgreSQL** | `jammy-pgdg` | `bookworm-pgdg` |
| **Repo Nginx** | Repo Ubuntu `nginx.org/packages/ubuntu jammy nginx` | Cài đặt trực tiếp từ Debian repo `apt-get install -y nginx` hoặc `nginx.org/packages/debian bookworm nginx` |
| **Node.js 18 & Yarn** | NodeSource script Ubuntu | NodeSource setup script (hỗ trợ hoàn toàn Debian) |
| **Chrome & Driver** | File `.deb` tải từ S3 | File `.deb` cài qua `dpkg -i` / `apt-get install` (tương thích Debian) |
| **Cài PHP Extensions** | `apt-get install -y php8.2-*` | **Giữ nguyên 100% cú pháp `apt-get install -y php8.2-*`** |

### 3.2. File cấu hình Runtime phụ trợ
| File | Trạng thái | Ghi chú |
| :--- | :--- | :--- |
| `docker/8.2/supervisord.production.conf` | **Giữ nguyên** | Lệnh `/usr/sbin/php-fpm8.2 -F` không đổi |
| `docker/8.2/cron/cron.root` | **Giữ nguyên** | Đường dẫn `/usr/bin/php` không đổi |
| `docker/8.2/php.ini` | **Giữ nguyên** | Đường dẫn đích `/etc/php/8.2/fpm/php.ini` không đổi |
| `docker/8.2/php-fpm/*.conf` | **Giữ nguyên** | Đường dẫn đích `/etc/php/8.2/fpm/pool.d/` không đổi |
| `docker/8.2/nginx.conf` | **Giữ nguyên** | Socket kết nối `127.0.0.1:9000` không đổi |
| `docker/8.2/start-container` | **Giữ nguyên** | Script khởi động không đổi |

---

## 4. Kế hoạch triển khai (Step-by-step)

### Bước 1: Cập nhật `docker/8.2/Dockerfile.production`
1. Thay đổi base image sang `debian:bookworm-slim`.
2. Thay thế khối PPA Launchpad bằng:
   ```dockerfile
   curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
       && echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ bookworm main" > /etc/apt/sources.list.d/php.list
   ```
3. Điều chỉnh repo PostgreSQL thành `bookworm-pgdg`.
4. Điều chỉnh gói Nginx và Chrome tương thích Debian 12.

### Bước 2: Test Build Local & Xác thực Container
1. Chạy lệnh build image local:
   ```bash
   docker build --no-cache -t gap-backend-test:sury -f ./docker/8.2/Dockerfile.production .
   ```
2. Chạy container ở chế độ test:
   ```bash
   docker run -d --name test-sury -p 8080:80 gap-backend-test:sury
   ```
3. Kiểm tra các tiêu chí:
   * `docker exec test-sury php -v` (kết quả hiển thị PHP 8.2.x / 8.2.35).
   * `docker exec test-sury php -m` (so sánh đầy đủ 17 extensions).
   * `docker exec test-sury supervisorctl status` (đủ 3 service: `php-fpm`, `nginx`, `crond` RUNNING).
   * `curl -I http://localhost:8080` (nhận response HTTP bình thường).
4. Dọn dẹp container test:
   ```bash
   docker rm -f test-sury
   ```

---

## 5. Đánh giá Ưu & Nhược điểm của Phương án 1

* **Ưu điểm**:
  * Tác động tối thiểu: không cần chỉnh sửa bất kỳ file config phụ trợ nào (`supervisord`, `php-fpm`, `php.ini`, `cron`).
  * Khắc phục triệt để lỗi 503 nhờ mạng lưới Fastly CDN của `packages.sury.org`.
  * Thời gian build nhanh do chỉ kéo pre-compiled `.deb`.
* **Hạn chế**:
  * Về lâu dài, repo Sury thường cuốn chiếu (rolling) lên bản patch mới nhất của nhánh 8.2. Khi có bản 8.2.36+, việc rebuild có thể tự động nhận bản mới nếu không ghim cứng version deb cụ thể.
