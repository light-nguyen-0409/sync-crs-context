# SPEC: Laravel Docker cache script

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-09
> **Author**: Codex

## 1. Tổng quan

Yêu cầu gốc: viết file `.sh` clear cache, optimize Laravel trong Docker service `laravel.test`.
Tạo script Bash `laravel-cache.sh` tại repository root, chạy được từ mọi working directory. User đã approve trước khi viết script.

## 2. Database Design

N/A — không thay đổi schema hoặc dữ liệu nghiệp vụ.

## 3. API Contract / Documentation Assessment

N/A — no API contract/API docs change. Không đổi routes, request/response schemas, examples, error contracts hoặc endpoint documentation; không cần đồng bộ `~/projects/crs-api-docs` hoặc deployment.

## 4. Luồng xử lý và quy tắc

- Interface: `bash laravel-cache.sh [clear|optimize|refresh|--help]`; mặc định `refresh`.
- Xác định repository root từ vị trí script, chuyển vào root trước khi gọi Compose.
- Dùng `docker compose`, fallback `docker-compose` nếu máy chỉ có Compose v1; kiểm tra Docker/Compose và service đang chạy. Không tự start/build container.
- Tất cả Artisan commands chạy trong service `laravel.test`, working directory `/var/www/html`, bằng `exec -T`.
- `clear`: lần lượt `config:clear`, `route:clear`, `view:clear`, `event:clear`, `cache:clear`, `clear-compiled`.
- `optimize`: lần lượt `config:cache`, `route:cache`, `view:cache`.
- `refresh`: thực hiện toàn bộ clear rồi optimize.
- Gọi từng command trực tiếp thay vì chỉ `optimize` / `optimize:clear`: Laravel đang dùng gom các tác vụ nhưng có thể không trả exit code lỗi từ command con. Script phải dừng ngay khi một command thất bại và trả exit code khác 0.
- Báo bước đang chạy, chỉ báo thành công sau khi tất cả command thành công. Argument sai trả lỗi và usage; help không cần Docker.
- `cache:clear` xóa application cache của store cấu hình; ghi rõ tác động trong help/comment. Không thêm `event:cache`, composer install/dump-autoload, migrations hoặc queue restart vào scope.

## 5. Data Origin & Call Chain

- `docker-compose.yml`: xác nhận service `laravel.test` và mount repository vào `/var/www/html`.
- `composer.json`: Laravel `^9.19`.
- `vendor/laravel/framework/src/Illuminate/Foundation/Console/OptimizeCommand.php`: optimize có config và route caching.
- `vendor/laravel/framework/src/Illuminate/Foundation/Console/OptimizeClearCommand.php`: các command clear tương ứng.
- Script -> Compose exec -> PHP Artisan trong container. Không thay đổi Controller/Service/Repository hoặc business workflow.

## 6. Constants

Giá trị cố định của shell đặt trong biến readonly: service `laravel.test`, container working directory `/var/www/html`. Không tạo PHP constants hoặc layers không liên quan.

## 7. Files

- Tạo `laravel-cache.sh`, executable, chứa usage và mô tả các mode.
- Tạo `tests/Unit/Scripts/LaravelCacheScriptTest.php`: test shell qua fake Docker executable, không dùng Docker thật hoặc xóa cache thật.
- Cập nhật plan này với kết quả verification và self-check.
- Giữ nguyên toàn bộ thay đổi có sẵn; không sửa README/Compose đang dirty.

## 8. Test Impact Review & Verification

- Rà soát test hiện có liên quan scripts/Artisan cache trước khi implementation; cập nhật nếu có contract bị ảnh hưởng.
- Test mới: default refresh và thứ tự command; clear-only; optimize-only; help; argument sai; service không chạy; lỗi command phải dừng và trả nonzero; chạy từ directory khác; fallback Compose v1.
- `bash -n laravel-cache.sh` phải PASS.
- Chạy affected PHPUnit suite `./vendor/bin/phpunit tests/Unit/Scripts/LaravelCacheScriptTest.php`, phải 100% PASS.
- Không chạy cache commands trên container thật trong verification; kiểm tra invocation bằng fake Docker.
- Không tự chạy formatter/linter.

## 9. Acceptance / Approval

- [x] User approve plan trước implementation (user: `ok`, 2026-10-09).
- [x] Script chạy đúng modes và Docker service.
- [x] Command failure được propagate, không báo thành công giả.
- [x] Test impact review, syntax check, affected PHPUnit suite PASS.
- [x] Self-check đối chiếu scope và minimal diff.

## 10. Kết quả triển khai và verification

- Workflow step 1: đọc lại approved plan, Compose và PHPUnit configuration; scan tests hiện có. Không có test cũ liên quan shell cache script hoặc Artisan cache commands cần cập nhật.
- Workflow steps 2–5: database/types, Repository, Service, Controller/Request/routes đều N/A cho standalone shell script. Không tạo layer không liên quan.
- Đã tạo executable `laravel-cache.sh` và `tests/Unit/Scripts/LaravelCacheScriptTest.php`.
- `bash -n laravel-cache.sh`: PASS.
- `./vendor/bin/phpunit tests/Unit/Scripts/LaravelCacheScriptTest.php`: PASS, 10 tests / 32 assertions.
- Tests chạy từ temporary working directory, xác nhận Compose nhận repository root; Docker fake xác nhận service, container directory, commands và exit codes. Có thêm case Compose status query lỗi phải dừng trước Artisan.
- Self-check: đúng scope approved, fixed shell values readonly, không sửa file hiện có ngoài task plan; không thêm queries/transactions/API contracts hoặc business logic; không chạy formatter hoặc mutate cache thật.
- API docs: N/A — no API contract/API docs change; không có deployment trong task.

## 11. Follow-up: Compose obsolete version (DONE)

Yêu cầu 2026-10-09: update version và đánh giá ảnh hưởng route trùng sau runtime test.

### Thiết kế và file ownership

- Chỉ bỏ dòng top-level `version: '3'` trong `docker-compose.yml`. Compose hiện tại dùng Compose Specification; tăng version lên số khác không giải quyết obsolete warning.
- Giữ nguyên toàn bộ user edits đang có trong Compose, services, images, ports, volumes và networks.
- Không sửa route trong scope follow-up này: user hỏi đánh giá ảnh hưởng, chưa yêu cầu fix route.
- Database/types, Repository, Service, Controller và API docs: N/A — no API contract/API docs change.

### Verification gate

- Trước/sau edit: so sánh normalized output `docker compose config --format json` trong bộ nhớ, không in secrets; phải tương đương.
- Sau edit: `docker compose config --quiet` PASS và không còn obsolete version warning.
- Rà soát tests ảnh hưởng: thay đổi Compose metadata không đổi PHP runtime contract; chạy lại affected shell PHPUnit suite (10 tests hiện tại). Không tạo PHPUnit test cho metadata do không có behavior mới để assert; dùng Compose validation/comparison làm kiểm chứng cấu hình.
- Không tự restart/build container hoặc chạy lại clear cache.
- Self-check minimal diff: chỉ một dòng Compose được xóa; ghi kết quả vào plan.

### Kết quả runtime test và route diagnosis (read-only)

- `./laravel-cache.sh` trên container thật: clear commands và config:cache PASS; route:cache FAIL (exit 1); view:cache chưa chạy. Script propagate exit code đúng.
- `[LogicException] tại vendor/laravel/framework/src/Illuminate/Routing/AbstractRouteCollection.php:247 — nhiều route có tên api.user.auth.`
- CODE deviation/limitation chưa ghi trong living baseline: `routes/user.php` group auth đặt `as => auth`, các child routes không thêm tên riêng; RouteServiceProvider ghép `api.` và `user.` thành cùng tên `api.user.auth` cho 6 endpoints. Đây là trùng route name, không phải trùng method/URI.
- HTTP matching theo method/URI vẫn phân biệt login/logout/refresh. Named lookup giữ route ghi sau; route('api.user.auth') có thể sinh URL endpoint không mong muốn. Scan app/routes/resources/tests không thấy consumer dùng tên này; không chứng minh external consumers không dùng.
- Laravel từ chối cache khi trùng tên; deployment workflow dựa route:cache/optimize có thể fail. Sau run hiện tại config đã cached, route cache không được tạo.
- Candidate và các groups khác cũng có as không kết thúc bằng dấu chấm và thiếu child names; sửa riêng logout có thể chỉ làm lộ lỗi trùng tiếp theo. Nếu user yêu cầu fix, cần audit toàn bộ tên runtime và lập scope/contract riêng trước khi edit.

### Approval

- [x] User approve follow-up xóa obsolete Compose version trước khi sửa cấu hình (`ok`, 2026-10-09).

### Verification result

- Đã bỏ duy nhất dòng `version: '3'` trong Compose, giữ nguyên user edits có sẵn.
- `docker compose config --quiet`: PASS, không còn obsolete version warning.
- SHA-256 normalized Compose JSON trước/sau đều `9d55e2bc521cdaab98700b0e8f0413256ea69b7ac81ffc6488b6bd15d61c1d8c`; cấu hình resolved không đổi. Không in JSON chứa environment secrets.
- Affected suite: `./vendor/bin/phpunit tests/Unit/Scripts/LaravelCacheScriptTest.php`: PASS, 10 tests / 32 assertions.
- Self-check PASS: chỉ thay đổi metadata đã approve, không sửa routes, không restart/build container hoặc clear cache thật.
