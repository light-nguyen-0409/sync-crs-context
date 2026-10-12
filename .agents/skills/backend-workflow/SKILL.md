---
name: backend-workflow
description: >-
  Quy trình phát triển feature Backend cho Laravel project gap-web-backend.
  Sử dụng skill này khi user yêu cầu phát triển feature mới, tạo API mới,
  thêm module, hoặc bất kỳ task nào cần viết code theo quy trình chuẩn
  "Phân tích trước, code sau". Skill này ép buộc thứ tự 5 bước không nhảy cóc.
---

# Backend Development Workflow

Quy trình phát triển feature chuẩn cho project `gap-web-backend` (Laravel).
**Nguyên tắc cốt lõi: Phân tích trước, code sau.**

---

## Giai đoạn 1: Lập Contract (SPEC)

Áp dụng cho **MỌI thay đổi code** (feature mới, API, enhancement, bugfix, refactor, template/mail/view — bất kể kích thước). **TUYỆT ĐỐI KHÔNG ĐƯỢC** tự ý bỏ qua bước lập plan với lý do task nhỏ.

Trước khi viết bất kỳ dòng code nào, **PHẢI** chốt bản thiết kế với user:

1. **Copy template**: Đọc file `.specs/SPEC_TEMPLATE.md` làm cấu trúc gốc.
2. **Tạo spec file**: Lưu vào `.specs/<TASK-KEY>/<tên-feature>.md` (ví dụ: `.specs/GAP-700/user-profile-api.md`). Không tạo plan trực tiếp dưới `.specs/`; nếu chưa xác định được task key, dùng `.specs/UNTRACKED/` tạm thời.
3. **Fill đầy đủ** các section áp dụng. Bỏ qua section không liên quan (ghi "N/A" hoặc xóa).
4. **Đặc biệt chú ý**:
   - Section 3 (API Contract): Phải ghi rõ validation rules cho FormRequest.
   - Section 5 (Data Origin): Phải trace call chain, chứng minh mọi biến có nguồn gốc.
   - Section 6 (Constants): Mọi magic value phải được khai báo const.
   - Section 7 (Files): Dùng đúng naming convention: `*Interface` cho contracts, `$columns` pattern cho Resource.

> **STOP sau bước này.** Chờ user review và approve plan trước khi code.

---

## Giai đoạn 2: Thực thi 5 bước (Sau khi plan được approve)

Sau khi user approve plan, thực thi **tuần tự** theo 5 bước sau. **KHÔNG nhảy cóc.**

### Bước 1: Đọc lại Contract & Scan codebase

- Đọc lại plan đã approve.
- Scan các file liên quan trong codebase để hiểu pattern hiện tại:
  - Tìm Controller/Service/Repository tương tự để follow convention.
  - Kiểm tra existing Models, Contracts (interfaces), Migrations.
  - Xác nhận đúng namespace, naming convention đang dùng.

### Bước 2: Database & Types

- Tạo Migration file (nếu cần thay đổi DB).
- Tạo/cập nhật Model với `$fillable`, `$casts`, relationships, constants.
- Tạo DTO class nếu cần (trong `App\Dto`).
- Định nghĩa constants cho statuses, types, cache keys trong Model hoặc Contract.

### Bước 3: Repository & Contract (Data Access Layer)

- Tạo/cập nhật Contract interface trong `App\Contracts\Repositories`.
- Tạo/cập nhật Repository implementation trong `App\Repositories`.
- Repository **CHỈ** chứa database queries thuần. **KHÔNG** có business logic.
- Register binding trong ServiceProvider nếu tạo mới.

### Bước 4: Service & Business Logic

- Tạo/cập nhật Contract interface trong `App\Contracts\Services`.
- Tạo/cập nhật Service implementation trong `App\Services`.
- Service chứa **100% business logic**: validation rules, data transformation, cache, workflow.
- Inject Repository qua constructor (dependency injection).
- Register binding trong ServiceProvider nếu tạo mới.

### Bước 5: Controller, FormRequest & Routes

- Tạo FormRequest cho input validation (trong `App\Http\Requests`).
- Tạo/cập nhật Controller (trong `App\Http\Controllers`).
- Controller chỉ gọi Service, **KHÔNG** chứa logic.
- Đăng ký route trong file routes phù hợp.
- Tạo Resource class nếu cần format response (trong `App\Http\Resources`).

---

## Giai đoạn 3: Self-Check (Sau khi code xong)

Sau khi hoàn thành code, tự kiểm tra:

1. **Architecture compliance**: Controller -> FormRequest -> Service -> Repository, đúng thứ tự.
2. **No magic values**: Mọi số/string cố định đều là `const`.
3. **No N+1**: Không có query trong loop. Dùng eager loading, `whereIn`, batch operations.
4. **Transaction scope**: Transaction chỉ wrap write operations, không có read bên trong.
5. **Exception handling**: Chỉ dùng custom exceptions từ `App\Exceptions`.
6. **Visibility**: Helper methods internal phải là `private`.
7. **Đối chiếu plan**: So sánh code cuối cùng với plan ban đầu, đảm bảo không thiếu sót.
8. **Data Origin Verification**: Đảm bảo không có biến nào được giả định có sẵn trong View/DTO/Service mà không có caller thực sự truyền vào.

---

## Giai đoạn 4: Context Hygiene

- Khi hoàn thành 1 feature/API, suggest user commit và mở session mới.
- Không dán raw log dài vào prompt. Tóm tắt lỗi thành 1-2 dòng nguyên nhân + file + line.
- Khi context session dài, ưu tiên tham chiếu file thay vì copy paste code blocks lớn.
