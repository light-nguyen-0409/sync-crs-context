# CRS Context Sync

Repository này lưu các file context dùng chung của project CRS:

- `AGENTS.md`
- `.agents/`
- `.business-spec/`
- `.specs/`

## Cấu hình máy local

Tạo file `.env` từ file mẫu:

```bash
cp .env.example .env
```

Sau đó sửa `PROJECT_DIR` thành đường dẫn tuyệt đối tới project
`gap-web-backend` trên máy hiện tại:

```dotenv
PROJECT_DIR=/Users/nexusfrontiertech/projects/gap-web-backend
```

File `.env` là cấu hình riêng của từng máy và không được commit.

## Đồng bộ từ repository về project

Chạy trong repository này:

```bash
./sync-to-project.sh
```

Script sẽ copy `AGENTS.md`, `.agents/`, `.business-spec/` và `.specs/` về
project được khai báo trong `PROJECT_DIR`. Script không xóa các file dư thừa ở
project đích.

## Đồng bộ từ project lên repository

Sau khi chỉnh sửa context trong project backend, chạy script export ở thư mục
`~/projects`:

```bash
~/projects/sync-crs-context.sh
```

Script này sẽ copy các file context vào repository, tạo commit và push lên
remote `origin` của branch hiện tại. Nếu không có thay đổi, script không tạo
empty commit.

## Thiết lập trên máy mới

```bash
cd ~/projects
git clone git@github.com:light-nguyen-0409/sync-crs-context.git sync-crs-context
cd sync-crs-context
cp .env.example .env
```

Sửa `PROJECT_DIR` trong `.env`, sau đó chạy:

```bash
./sync-to-project.sh
```

Các script yêu cầu Bash, Git và `rsync`.
