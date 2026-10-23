# SPEC: GAP-747 Fix Code Review Findings for Docker 8.2 Runtime

> **Task Key**: `GAP-747`
> **Trạng thái**: `DRAFT`
> **Ngày tạo**: 2026-10-21
> **Author**: Antigravity Pair Programmer
> **Scope**: Docker Infrastructure / Security Hardening / Review Remediation

---

## 1. Tổng quan

Sau khi rà soát các thay đổi hạ tầng Docker PHP 8.2, có 3 vấn đề bảo mật và cấu hình (Code Review Findings) được ghi nhận cần xử lý:

1. **[Medium] Ghi đè toàn bộ file `php.ini` mặc định và bật `display_errors = on` trên production**:
   * *Hiện trạng*: Trong `docker/8.2/Dockerfile.production`, lệnh `COPY ./docker/8.2/php.ini /etc/php/8.2/fpm/php.ini` đã xóa sổ toàn bộ các thiết lập mặc định của Ubuntu (`memory_limit`, `error_reporting`, `date.timezone`, opcache defaults,...), chỉ giữ lại 6 dòng custom. Đồng thời `display_errors = on` có nguy cơ rò rỉ stack trace/query ra HTTP response trên production.
   * *Giải pháp*: Giữ nguyên `php.ini` gốc của Ubuntu, chỉ copy các directive custom vào file override `/etc/php/8.2/fpm/conf.d/99-custom.ini`. Đặt `display_errors = Off` trên production.

2. **[Medium] Block chặn file `.php` lạ trong `nginx.conf` bị dead code (không bao giờ chạy)**:
   * *Hiện trạng*: Nginx duyệt regex location theo thứ tự từ trên xuống dưới và lấy match đầu tiên. Block `location ~ \.php$` ở dòng 38 đã match và chuyển toàn bộ file `.php` vào FastCGI, khiến block `location ~ \.php$ { return 404; }` ở dòng 59 không bao giờ được kích hoạt.
   * *Giải pháp*: Giới hạn FastCGI pass chỉ dành riêng cho front controller: `location ~ ^/index\.php(/|$)`. Như vậy, mọi request trực tiếp tới file `.php` khác (nếu có) sẽ rơi vào block thứ hai và bị trả về 404 đúng như thiết kế.

3. **[High] File `/env.sh` chứa toàn bộ secrets bị cấp quyền đọc rộng rãi (`644`)**:
   * *Hiện trạng*: Lệnh `printenv | sed ... > /env.sh` trong `start-container` tạo file với umask mặc định (`644`), cho phép bất kỳ user nào trong container (kể cả `www-data`) đọc được toàn bộ biến môi trường (`DB_PASSWORD`, `APP_KEY`, AWS credentials,...). Nếu ứng dụng dính lỗi đọc file cục bộ (LFI/Path Traversal), kẻ tấn công có thể đọc trộm toàn bộ bí mật hệ thống từ `/env.sh`.
   * *Giải pháp*: Đặt `umask 077` khi tạo và chạy `chmod 600 /env.sh` ngay sau khi ghi file để chỉ có `root` đọc/ghi được file này (Cron chạy bằng quyền root nên vẫn source bình thường).

---

## 2. Database Design

`N/A — Không thay đổi Database.`

---

## 3. API Contract & API Docs Pre-Deployment Gate

`N/A — no API contract/API docs change.`
Các thay đổi cấu hình runtime không làm thay đổi API contract hay API documentation trong `~/projects/crs-api-docs`.

---

## 4. Chi tiết giải pháp kỹ thuật

### 4.1. Finding 1: Cấu hình `php.ini` và `display_errors`
* Trong `docker/8.2/php.ini`:
  ```ini
  [PHP]
  post_max_size = 100M
  upload_max_filesize = 100M
  variables_order = EGPCS
  display_errors = Off
  max_execution_time = 60
  session.upload_progress.enabled = Off
  ```
* Trong `docker/8.2/Dockerfile.production`:
  Thay vì ghi đè `/etc/php/8.2/fpm/php.ini`, copy vào thư mục conf.d:
  ```dockerfile
  COPY ./docker/8.2/php.ini /etc/php/8.2/fpm/conf.d/99-custom.ini
  COPY ./docker/8.2/php.ini /etc/php/8.2/cli/conf.d/99-custom.ini
  ```

### 4.2. Finding 2: Sửa Nginx FastCGI Routing
* Trong `docker/8.2/nginx.conf`:
  Đổi:
  ```nginx
  location ~ \.php$ {
      try_files $uri =404;
      fastcgi_index index.php;
      fastcgi_pass 127.0.0.1:9000;
      fastcgi_split_path_info ^(.+\.php)(/.*)$;
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
      fastcgi_param DOCUMENT_ROOT $realpath_root;
      fastcgi_param PATH_INFO $fastcgi_path_info;
  }
  ```
  Thành:
  ```nginx
  location ~ ^/index\.php(/|$) {
      fastcgi_pass 127.0.0.1:9000;
      fastcgi_split_path_info ^(.+\.php)(/.*)$;
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
      fastcgi_param DOCUMENT_ROOT $realpath_root;
      fastcgi_param PATH_INFO $fastcgi_path_info;
  }
  ```
  Và giữ nguyên block phía dưới:
  ```nginx
  location ~ \.php$ {
      return 404;
  }
  ```
  *(Đảm bảo chỉ `/index.php` mới được chuyển đến PHP-FPM, các file `.php` khác trả về 404).*

### 4.3. Finding 3: Phân quyền an toàn cho `/env.sh`
* Trong `docker/8.2/start-container`:
  ```bash
  # prepare environment variables for cron job with strict permissions (root only)
  (
    umask 077
    printenv | sed 's/^\(.*\)$/export \1/g' | sed 's/\$/\\\$/g' | sed 's/\([^=]\)=\([^"]*\)$/\1="\2"/g' > /env.sh
  )
  chmod 600 /env.sh
  ```

---

## 5. Files cần sửa đổi

| File | Nội dung sửa |
|------|--------------|
| `docker/8.2/php.ini` | Đặt `display_errors = Off` và thêm `session.upload_progress.enabled = Off`. |
| `docker/8.2/Dockerfile.production` | Đổi đường dẫn COPY `php.ini` vào `/etc/php/8.2/fpm/conf.d/99-custom.ini` và `/etc/php/8.2/cli/conf.d/99-custom.ini`. |
| `docker/8.2/nginx.conf` | Giới hạn FastCGI pass chỉ cho `location ~ ^/index\.php(/|$)`, đưa block `location ~ \.php$ { return 404; }` vào hoạt động thực tế. |
| `docker/8.2/start-container` | Bổ sung `umask 077` và `chmod 600 /env.sh`. |

---

## 6. Kế hoạch Verification

1. Kiểm tra quyền của file `/env.sh` trong container: Phải là `600` (`-rw-------`), user `www-data` không đọc được.
2. Kiểm tra `php.ini`: Chạy `php -i` xác nhận các directive mặc định của Ubuntu vẫn còn, `display_errors = Off`, và `session.upload_progress.enabled = Off`.
3. Kiểm tra Nginx:
   * Request bình thường tới `/api/...` trả về `200 OK`.
   * Request thử tới file php giả định (ví dụ `/test.php` hoặc `/shell.php`) phải trả về `404 Not Found` ngay tại tầng Nginx mà không chuyển tới FPM.
4. Chạy lại test suite: `./vendor/bin/phpunit`.
