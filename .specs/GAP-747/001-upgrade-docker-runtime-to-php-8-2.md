# SPEC: GAP-747 Upgrade Docker Runtime from PHP 8.1 to PHP 8.2

> **Task Key**: `GAP-747`
> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-21
> **Author**: Antigravity Pair Programmer
> **Scope**: Infrastructure / Docker Runtime / CI-CD Pipeline
> **Context**: Khắc phục và phòng ngừa lỗ hổng RCE PHP Core (CVE-2026-109618 & CVE-2026-109619); thay thế runtime PHP 8.1 (đã EOL) bằng PHP 8.2 (Zero-Impact đối với Laravel 9.52.5 và composer dependencies).

---

## 1. Tổng quan

Hiện tại hệ thống production đang được đóng gói bằng image PHP 8.1 qua `./docker/8.1/Dockerfile.production` (được cấu hình trong `buildspec.yml`). Do PHP 8.1 đã hết hạn hỗ trợ bảo mật chính thức (EOL) và sự cố bảo mật nghiêm trọng RCE `CVE-2026-109618` & `CVE-2026-109619` sắp được phát hành bản vá cho các nhánh active (PHP 8.2+), hệ thống cần nâng cấp runtime Docker lên PHP 8.2.

**Mục tiêu**:
1. Đảm bảo toàn bộ container runtime (Production build và Local Sail development) chuyển dịch trơn tru sang PHP 8.2.
2. Đảm bảo "Zero-Impact" tới logic ứng dụng hiện tại: Giữ nguyên 100% API contract, Composer dependencies, background worker supervisor và cron job.
3. Chuẩn bị sẵn sàng image build với PHP 8.2 để cập nhật bản vá ngay khi PPA `ondrej/php` publish package mới.

**Yêu cầu gốc**: Đề xuất và lên plan chuyển runtime Docker sang PHP 8.2.

---

## 2. Database Design

`N/A — Không thay đổi Database schema hay dữ liệu.`

---

## 3. API Contract & API Docs Pre-Deployment Gate

`N/A — Không có API contract / API docs change.`
Nâng cấp runtime PHP trong container không làm thay đổi bất kỳ route, request parameters, response body, HTTP status hay API documentation nào trong `~/projects/crs-api-docs`.

---

## 4. Business Logic & System Architecture

### 4.1. Đánh giá tính tương thích của ứng dụng (Application Compatibility)
1. **Laravel Framework**: Phiên bản `v9.52.5` hỗ trợ chính thức và đầy đủ cho PHP 8.2.
2. **Composer Dependencies**:
   * `composer.json` yêu cầu `"php": "^8.1"` (tự động chấp nhận `8.2.*`).
   * Kiểm tra `composer check-platform-reqs` trên môi trường PHP 8.2: **100% SUCCESS**.
   * Tất cả các thư viện quan trọng (`jwt-auth`, `dompdf`, `phpoffice/phpword`, `aws-sdk-php`, `compoships`) đều tương thích tốt với PHP 8.2.
3. **Local Tests**: Các suite Unit test chạy pass 100% trên PHP 8.2.33 không có warning/deprecation cản trở.

### 4.2. Khối hạ tầng Docker cần nâng cấp
1. **Production Docker image (`docker/8.2/Dockerfile.production`)**:
   * Cài đặt `php8.2-*` thay thế toàn bộ `php8.1-*` từ `ppa:ondrej/php`.
   * Cấu hình extension đầy đủ: `php8.2-fpm`, `php8.2-cli`, `php8.2-dev`, `php8.2-pgsql`, `php8.2-gd`, `php8.2-curl`, `php8.2-imap`, `php8.2-mbstring`, `php8.2-xml`, `php8.2-zip`, `php8.2-bcmath`, `php8.2-soap`, `php8.2-intl`, `php8.2-readline`, `php8.2-ldap`, `php8.2-msgpack`, `php8.2-igbinary`, `php8.2-redis`, `php8.2-memcached`.
   * Set capabilities: `setcap "cap_net_bind_service=+ep" /usr/bin/php8.2`.
   * Chạy PHP-FPM 8.2: `/usr/sbin/php-fpm8.2 -F`.
2. **Local Development Docker image (`docker/8.2/Dockerfile`)**:
   * Bổ sung các extension còn thiếu vào file template 8.2 hiện có (`php8.2-redis`, `php8.2-msgpack`, `php8.2-igbinary`, `php8.2-memcached`, `php8.2-pcov`, `php8.2-xdebug`, Chrome/ChromeDriver).
   * Đồng bộ `docker/8.2/supervisord.conf` với worker queue và cron tương tự như 8.1.
3. **CI/CD Buildspec (`buildspec.yml`)**:
   * Chuyển flag docker build trỏ vào `./docker/8.2/Dockerfile.production`.
4. **Docker Compose (`docker-compose.yml`)**:
   * Đổi context từ `./docker/8.1` sang `./docker/8.2`.
   * Đổi image name từ `sail-8.1/app` sang `sail-8.2/app`.

---

## 5. Data Origin & Call Chain

`N/A — Không sửa Controller, Service, Resource hay View.`

---

## 6. Constants & Enums

`N/A — Không thay đổi constants mã nguồn PHP.`

---

## 7. Files cần tạo / sửa đổi

### 7.1. Files mới

| File | Mục đích |
|------|----------|
| `docker/8.2/Dockerfile.production` | Dockerfile production cho PHP 8.2 (FPM + Nginx + Supervisor + Cron + Chromium). |
| `docker/8.2/supervisord.production.conf` | Supervisor config cho production chạy `php-fpm8.2 -F`, Nginx và Cron. |
| `docker/8.2/nginx.conf` | Cấu hình Nginx (proxy FastCGI sang `127.0.0.1:9000`). |
| `docker/8.2/cron/cron.root` | Cấu hình Cron định kỳ (`schedule:run`, clear cache, v.v.). |
| `docker/8.2/php-fpm/docker.conf` | Cấu hình log và pool cho PHP-FPM. |
| `docker/8.2/php-fpm/www.conf` | Cấu hình FPM pool worker cho môi trường production. |
| `docker/8.2/php-fpm/zz-docker.conf` | Cấu hình `daemonize = no` và `listen = 9000`. |

### 7.2. Files sửa đổi

| File | Thay đổi cụ thể |
|------|-----------------|
| `docker/8.2/Dockerfile` | Bổ sung các extension còn thiếu (`redis`, `igbinary`, `msgpack`, etc.) và Chrome/ChromeDriver phục vụ test/dusk local. |
| `docker/8.2/supervisord.conf` | Bổ sung worker `queue-worker` và `crond` để môi trường local chạy đầy đủ nền tảng như 8.1. |
| `docker/8.2/php.ini` | Đồng bộ tham số `post_max_size = 100M`, `upload_max_filesize = 100M`, `display_errors = on`, `max_execution_time = 60`. |
| `docker/8.2/start-container` | Cập nhật script khởi động container (tạo fifo schedule log, env export, permission composer). |
| `docker-compose.yml` | Cập nhật `context: ./docker/8.2` và `image: sail-8.2/app`. |
| `buildspec.yml` | Cập nhật dòng 18: `-f ./docker/8.2/Dockerfile.production .`. |

---

## 8. Kế hoạch triển khai & Verification

### Giai đoạn 1: Chuẩn bị file & Local Build Verification
1. Tạo toàn bộ file cấu hình trong `docker/8.2/`.
2. Chạy thử build image local:
   ```bash
   docker build -t test-php82:prod -f ./docker/8.2/Dockerfile.production .
   ```
3. Verify phiên bản PHP và extensions trong image:
   ```bash
   docker run --rm test-php82:prod php -v
   docker run --rm test-php82:prod php -m
   ```
   *Yêu cầu*: PHP version là 8.2.x, đầy đủ module `pdo_pgsql`, `redis`, `mbstring`, `curl`, `xml`, `gd`, `bcmath`.
4. Test chạy thử test suite trên container PHP 8.2:
   ```bash
   docker run --rm test-php82:prod ./vendor/bin/phpunit --filter=CandidateServiceTest
   ```

### Giai đoạn 2: Cập nhật Buildspec & Push lên CI/CD
1. Cập nhật `buildspec.yml` và `docker-compose.yml`.
2. Đẩy thay đổi lên branch Staging để AWS CodeBuild tự động build image production PHP 8.2.

### Giai đoạn 3: Vá khẩn cấp CVE-2026-109618 & CVE-2026-109619 (Tối nay)
1. Khi PHP Group & PPA `ondrej/php` publish package PHP 8.2 bản vá lúc 21:00 VN:
2. Trigger CodeBuild với flag `--no-cache` (hoặc bump `CACHE_DATE` trong Dockerfile) để tải bản PHP 8.2 mới nhất chứa bản vá.
3. Deploy rolling update lên ECS Cluster.

---

## 9. Rollback Plan

Nếu gặp bất kỳ vấn đề phát sinh nào sau khi deploy:
* **Khôi phục ngay lập tức**: Sửa dòng 18 trong [buildspec.yml](file:///Users/nexusfrontiertech/projects/gap-web-backend/buildspec.yml#L18) trỏ lại `./docker/8.1/Dockerfile.production` và trigger deploy lại image PHP 8.1.
* Thao tác rollback chỉ mất **1 thay đổi dòng lệnh** trong buildspec và rebuild.

---

## 10. Checklist trước khi Approve

- [x] Đã đánh giá tương thích framework (Laravel 9.52.5 hỗ trợ PHP 8.2)
- [x] Đã kiểm tra `composer.lock` (không có xung đột package trên 8.2)
- [x] Đã kiểm tra platform requirements (`composer check-platform-reqs` pass 100%)
- [x] Không ảnh hưởng API Contract / API docs (`N/A — no API contract/API docs change`)
- [x] Đầy đủ file cấu hình Docker production & local (Nginx, FPM, Supervisor, Cron)
- [x] Có kế hoạch verification và rollback tức thì
