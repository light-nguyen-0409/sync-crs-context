# SPEC: Script đồng bộ CRS Context vào Git riêng

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-07
> **Author**: Codex

## 1. Tổng quan

Tạo một shell script tại `~/projects` để đồng bộ các workspace rule và tài
liệu business logic từ project nguồn `~/projects/gap-web-backend` vào Git
repository riêng `~/projects/sync-crs-context`, sau đó commit và push các thay
đổi lên remote của repository riêng.

**Yêu cầu gốc**: User muốn tách các file spec/plan/agent rule khỏi Git chính,
đồng bộ chúng qua một repository riêng giữa nhiều máy.

## 2. Phạm vi và cách tiếp cận

- Tạo script: `~/projects/sync-crs-context.sh`.
- Source project: `~/projects/gap-web-backend`.
- Destination repository: `~/projects/sync-crs-context`.
- Đồng bộ root `AGENTS.md`.
- Đồng bộ toàn bộ các thư mục ẩn `.business-spec/`, `.specs/` và `.agents/`,
  giữ nguyên cấu trúc thư mục và nội dung.
- Không tự khởi tạo repository hoặc remote; repository đích phải tồn tại và
  đã có remote hợp lệ.
- Sau khi copy, kiểm tra thay đổi bằng `git status`.
- Nếu có thay đổi, tạo commit với commit message có thể truyền qua argument và
  push lên branch hiện tại của repository đích.
- Nếu không có thay đổi, không tạo empty commit và không push.
- Script phải dừng với mã lỗi khác 0 nếu source file/thư mục không tồn tại,
  destination không tồn tại/không phải Git repository, remote chưa cấu hình,
  hoặc thao tác copy/commit/push thất bại.
- Không xóa file dư thừa ở destination; đây là copy/update một chiều, không
  phải destructive mirror.

## 3. Trình tự thực hiện trong script

1. Xác định path tuyệt đối của `~/projects` dựa trên vị trí script và không
   phụ thuộc current working directory.
2. Kiểm tra source `AGENTS.md` và `.business-spec/` tồn tại.
3. Kiểm tra destination `~/projects/sync-crs-context` là Git repository và có
   remote push.
4. Copy `AGENTS.md` vào root destination.
5. Tạo/cập nhật destination `.business-spec/`, `.specs/` và `.agents/`, sau đó
   copy nội dung tương ứng từ source.
6. Chạy `git status --short`; nếu có thay đổi thì `git add` đúng các file thuộc
   phạm vi sync, commit và push branch hiện tại.
7. In summary kết quả đồng bộ, commit SHA hoặc trạng thái không có thay đổi,
   rồi exit `0` khi thành công.

## 4. An toàn và tương thích

- Dùng `set -euo pipefail`.
- Quote toàn bộ path để xử lý khoảng trắng an toàn.
- Không dùng lệnh xóa hoặc `--delete`.
- Không ghi đè source.
- Script có thể chạy lặp lại nhiều lần và cho kết quả ổn định.
- Chỉ stage `AGENTS.md`, `.business-spec/`, `.specs/` và `.agents/`; không
  stage các file không thuộc phạm vi trong repository sync.
- Dùng Bash và khai báo interpreter rõ ràng vì script cần xử lý exit code và
  tham số commit message.

## 5. Files cần tạo

| File | Mô tả |
|------|-------|
| `~/projects/sync-crs-context.sh` | Script sync, commit và push `AGENTS.md`, `.business-spec/`, `.specs/` và `.agents/` |

## 6. Verification sau khi được duyệt

- Kiểm tra syntax shell bằng `bash -n`.
- Chạy thử với repository đích đã xác định; không xóa dữ liệu đích.
- Xác nhận repository đích có `AGENTS.md` và nội dung tương ứng của
  `.business-spec/`, `.specs/` và `.agents/`.
- Kiểm tra script có quyền executable.
- Kiểm tra lần chạy không có thay đổi không tạo empty commit.
- Kiểm tra commit mới được push thành công lên remote branch hiện tại.
- Không chạy PHPUnit vì không thay đổi code runtime.

## 7. Acceptance criteria

- Có file `.sh` đúng vị trí trong `~/projects`.
- Chạy từ bất kỳ current working directory nào cũng copy đúng source →
  repository đích.
- Copy được `AGENTS.md` và toàn bộ `.business-spec/`, `.specs/`, `.agents/`.
- Có thể commit và push các thay đổi lên repository riêng; không commit khi
  không có thay đổi.
- Lỗi được báo rõ và không báo thành công khi thiếu source, repository đích,
  remote hoặc copy/commit/push thất bại.
- Không xóa dữ liệu hiện có ở destination.

## 8. Kết quả thực hiện

- Đã tạo executable script tại
  `/Users/nexusfrontiertech/projects/sync-crs-context.sh`.
- `bash -n` không phát hiện lỗi cú pháp.
- Đã sync `AGENTS.md`, `.business-spec/`, `.specs/` và `.agents/` vào
  `/Users/nexusfrontiertech/projects/sync-crs-context`.
- Đã tạo commit `92911b2` với message `chore: sync CRS context`.
- Đã push thành công commit lên remote `origin`, branch `main`.
- Đã chạy lại script; script báo không có thay đổi và không tạo empty commit.
- Script không dùng thao tác xóa hoặc `--delete`.

## 9. Phạm vi cập nhật theo yêu cầu mới

- Repository sync đã được tạo tại `/Users/nexusfrontiertech/projects/sync-crs-context`.
- Script phải hoạt động từ thư mục `~/projects` và không phụ thuộc thư mục
  hiện tại khi chạy.
- Việc commit/push chỉ áp dụng cho repository `sync-crs-context`, không commit
  hoặc push repository backend `gap-web-backend`.

## 10. Mở rộng: đồng bộ từ context repository về project

Đã tạo thêm script import ngay trong repository
`~/projects/sync-crs-context`, để copy context từ repository riêng về project
backend được cấu hình trong `.env`.

### 10.1. Files đã tạo

| File | Mô tả |
|------|-------|
| `~/projects/sync-crs-context/sync-to-project.sh` | Copy `AGENTS.md`, `.business-spec/`, `.specs/` và `.agents/` về project đích |
| `~/projects/sync-crs-context/.env` | Cấu hình local `PROJECT_DIR`; không commit |
| `~/projects/sync-crs-context/.env.example` | Mẫu cấu hình được commit |
| `~/projects/sync-crs-context/README.md` | Hướng dẫn clone, cấu hình `.env`, sync về project và sync ngược lên remote |
| `~/projects/sync-crs-context/.gitignore` | Ignore `.env` và file local `.DS_Store` |

### 10.2. Thiết kế script import

- Xác định `SYNC_DIR` từ vị trí script, không phụ thuộc current working
  directory.
- Đọc biến bắt buộc `PROJECT_DIR` từ `SYNC_DIR/.env`.
- Kiểm tra project đích tồn tại và không trỏ ngược vào sync repository.
- Copy `AGENTS.md`, `.business-spec/`, `.specs/` và `.agents/` từ sync repo về
  project đích bằng `rsync`.
- Không dùng `--delete`, không xóa file khác ở project đích.
- Không commit/push project backend; đây chỉ là thao tác import một chiều.

### 10.3. Verification và kết quả

- `bash -n` không phát hiện lỗi cú pháp ở cả hai script.
- Đã chạy import thành công về project backend.
- `.env` được tạo local với `PROJECT_DIR=/Users/nexusfrontiertech/projects/gap-web-backend`
  và không được stage/commit.
- Đã commit và push các file dùng chung lên `origin/main` với commit
  `82f8056` (`feat: add context import script and README`).
- Đã chạy lại export để đồng bộ thay đổi cuối cùng của plan; commit cập nhật
  plan là `dbf251e` (`chore: sync CRS context`).

## 11. Cập nhật README sang tiếng Anh

### Phạm vi

- Chuyển toàn bộ nội dung `~/projects/sync-crs-context/README.md` sang tiếng
  Anh.
- Giữ nguyên cấu trúc và hướng dẫn kỹ thuật hiện tại: cấu hình `.env`, import
  context về project, export context lên repository, thiết lập trên máy mới,
  và các yêu cầu Bash/Git/rsync.
- Không thay đổi hành vi của hai script hoặc nội dung các file context.

### Verification

- Đọc lại README để xác nhận không còn nội dung tiếng Việt trong tài liệu.
- Kiểm tra các command, path, tên file và remote repository vẫn chính xác.
- Commit và push chỉ file `README.md` cùng plan sync cập nhật; không commit
  `.env`.

### 11.1. Kết quả thực hiện

- Đã chuyển toàn bộ `README.md` sang tiếng Anh, giữ nguyên các command, path,
  tên file và hướng dẫn kỹ thuật.
- `git diff --check` và kiểm tra ký tự không phát hiện lỗi.
- Đã commit và push README với commit `b0dc7d6`
  (`docs: translate README to English`).
- `.env` tiếp tục được ignore và không được commit.
