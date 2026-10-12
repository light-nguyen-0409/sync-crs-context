# SPEC: SonarQube local cho gap-web-backend

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-23

## 1. Tổng quan

Cài SonarQube Community Build và SonarScanner bằng Docker để phân tích chất lượng source Laravel local. User đã xác nhận muốn SonarQube/SonarScanner; plan này chờ duyệt triển khai.

Phạm vi: cấu hình local, khởi động server và thực hiện lần scan đầu. CI/CD và sửa các finding nằm ngoài phạm vi.

## 2. Database và hạ tầng

- Tạo `docker-compose.sonar.yml` độc lập, chạy với Compose project `gap-sonar`.
- Services: `sonarqube`, `sonar-db` (PostgreSQL riêng), `sonar-scanner` chạy một lần qua profile scan.
- Dashboard bind `127.0.0.1:9000`; PostgreSQL chỉ truy cập trong network Sonar.
- Named volumes lưu database, Sonar data/extensions/logs và scanner cache.
- Máy hiện tại ARM64: kiểm tra manifest các image chính thức, chọn version tương thích server/scanner/PostgreSQL và pin tag cụ thể khi triển khai. Chỉ dùng emulation nếu image cần thiết không hỗ trợ ARM64, ghi rõ trong hướng dẫn.
- Kiểm tra Docker memory và yêu cầu Elasticsearch theo phiên bản đã chọn trước khi khởi động; không tự thay cấu hình toàn máy hoặc tắt bootstrap checks.
- Credentials DB đặt trong `.env.sonar` local được ignore; cung cấp `.env.sonar.example`. Token scan truyền qua environment, không commit hoặc in token.
- Không có Laravel migration/API mới.

## 3. Luồng sử dụng và nguồn dữ liệu

1. Docker Compose khởi động PostgreSQL, sau đó SonarQube; kiểm tra readiness.
2. Thiết lập admin local và project key `gap-web-backend`; nếu cần credential do user chọn, thu nhận riêng, không ghi vào source.
3. Scanner đọc source qua bind mount repo và `sonar-project.properties`, gửi analysis tới `http://sonarqube:9000` qua network nội bộ.
4. Xác nhận background analysis hoàn tất và project xuất hiện trên dashboard.

Phạm vi source dự kiến: `app`, `routes`, `config`, `database`, `resources`; tests: `tests`. Loại dependencies, generated files, storage/cache, assets build và secrets khỏi phân tích. Kiểm tra cấu trúc thực tế khi triển khai để tránh source/test overlap.

Coverage là tùy chọn: PHPUnit hiện có coverage scope `app`; hướng dẫn xuất Clover và truyền đường dẫn khi có report hợp lệ. Không hiển thị coverage như đã đo nếu chưa có report. Không bắt buộc sửa `phpunit.xml`.

## 4. Files tạo/sửa

| File | Thay đổi |
|------|----------|
| `docker-compose.sonar.yml` | Server, DB, scanner, network và volumes độc lập |
| `sonar-project.properties` | Project key, sources/tests, encoding và exclusions |
| `.env.sonar.example` | Mẫu cấu hình local không chứa credentials thật |
| `.gitignore` | Ignore scanner output và coverage output nếu cần; cho phép example Sonar vì hiện có `.env.*` rule |
| `../../.docs/sonarqube.md` | Hướng dẫn start/stop, account/token, scan, coverage và troubleshooting local |

Giữ nguyên các thay đổi user đang có trong worktree; không cần chỉnh Compose ứng dụng hiện tại.

## 5. Verification và test impact

- Validate Compose với environment local; kiểm tra image compatibility và server readiness.
- Smoke test scanner authentication, analysis upload và trạng thái xử lý cuối cùng trên server.
- Audit PHPUnit: chỉ thay tooling/config, không thay business contract nên không thêm test PHP mô phỏng Docker. Chạy suite hiện có theo quy định repo, ghi nhận kết quả và blocker nếu có.
- `git diff --check`; không chạy formatter/linter.
- Không reset/xóa volumes; không sửa finding tự động. Quality gate không đạt do code hiện có được báo riêng với lỗi cài đặt.

## 6. Checklist

- [x] Kiểm tra Compose, architecture máy, PHPUnit và ignore rules hiện tại.
- [x] Xác định phạm vi local và files cần thay đổi.
- [x] User approve plan.
- [x] Pin image versions tương thích và validate config.
- [x] Server hoạt động và scan đầu hoàn tất.
- [x] Test impact review, verification và tài liệu sử dụng hoàn tất.

## 7. Tài liệu tham khảo

- https://docs.sonarsource.com/sonarqube-community-build/server-installation/from-docker-image/installation-overview
- https://github.com/SonarSource/docker-sonarqube/blob/master/examples.md

Plan này chỉ ghi thiết kế đề xuất, không mô tả business flow đang triển khai.

## 8. Ghi nhận triển khai

- SonarQube `26.9.0.129388-community`, PostgreSQL `17.11-alpine3.24`: xác nhận ARM64 từ image đã pull.
- Scanner CLI `8.1.0.6389`: official image AMD64, pin digest; smoke test `--version` pass qua emulation.
- User đồng ý nâng Docker VM `vm.max_map_count` từ 262144 lên 524288; đã áp dụng và giữ bootstrap checks.
- Server status `UP`; admin mặc định đã đổi sang mật khẩu ngẫu nhiên local; private project và project analysis token đã tạo. Credentials trong `.env.sonar` được ignore, permissions 600.
- Compose validation và `git diff --check`: pass. PHPUnit: 477 tests, 2080 assertions pass.
- Lần scan đầu thất bại do OOM ở khoảng 4 GB RAM. User tăng Docker Desktop lên khoảng 8 GB; sau Docker restart `vm.max_map_count` trở về 262144, đã đặt lại 524288 theo xác nhận đã có.
- Lần scan thứ hai thành công: 1132 file indexed; PHP, text/secrets, HTML, JavaScript/CSS sensors chạy xong; report upload thành công. Compute Engine task `658d0d40-f2ed-4078-92ff-b04a00cd3453` = `SUCCESS`; analysis `7836c15f-edad-43a7-adb4-7adf14ccd92b`; Quality Gate `OK` (SonarQube chưa cấu hình conditions). Coverage PHPUnit chưa có.
- Scanner cảnh báo thiếu blame cho một số file đang dirty/untracked trong worktree; các finding và metrics scan vẫn được upload.
