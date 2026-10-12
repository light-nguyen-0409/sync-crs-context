# SPEC: Permanent Intake API File Payload

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-29
> **Author**: Codex

## 1. Tổng quan

Làm rõ tài liệu API cho payload file của `POST /api/candidate/me/permanent-intake` để phân biệt CV với tài liệu bổ sung có thể phát sinh khi candidate chọn `journey_type = other`.

**Yêu cầu gốc**: Thay đổi tài liệu API theo hướng mỗi file có `file_id` và loại/mục đích, tránh payload chỉ có một `file_id` không xác định được vai trò file.

## 2. API Contract đề xuất

### 2.1. Request body

```json
{
  "files": [
    { "file_id": 123, "type": "cv" },
    { "file_id": 456, "type": "other" }
  ]
}
```

- `files` thay cho field `file_id` đơn lẻ và là danh sách file được gửi cùng yêu cầu intake.
- Mỗi phần tử chỉ rõ `file_id` và `type` (`cv` hoặc `other`).
- `cv` xác định CV cần đính kèm vào MatchMaker contact log.
- `other` xác định tài liệu bổ sung theo lựa chọn journey; không coi là CV.
- Tài liệu cần nói rõ backend phải xác thực file thuộc candidate đang đăng nhập và loại file lưu tương ứng phải khớp với `type`.

## 3. Phạm vi cập nhật tài liệu

- Ghi schema đề xuất ở tài liệu API/task-specific; không ghi endpoint như route runtime hiện hữu trong `.business-spec/backend-api-route-inventory.md` vì source hiện tại không khai báo route này.
- Ghi chú rằng `.business-spec` mô tả code hiện hành: source đang có service/job permanent sync nhận một `fileId` làm CV, nhưng chưa có route permanent-intake.
- Chưa sửa code, route, validation, service/job hoặc test.

## 4. Kiểm tra trước khi cập nhật

- Đối chiếu request field names, enum file type và journey type với quyết định API đã được duyệt.
- Giữ rõ khác biệt giữa API contract dự kiến và hành vi code hiện tại.
- Không chạy formatter hoặc test vì chỉ thay đổi tài liệu.

## 5. Rủi ro / điểm cần xác nhận

- Giá trị chính xác của `type` và cấu trúc `files` chưa tồn tại trong implementation hiện tại; đây là schema đề xuất dựa trên yêu cầu phân biệt CV và file bổ sung.
- Nếu muốn `.business-spec/backend-api-route-inventory.md` liệt kê endpoint trước khi route được implement, tài liệu sẽ không còn là inventory runtime chính xác.

## 6. Hoàn tất

- Đã cập nhật OpenAPI contract tại `documents/Gap-API-Candidate.yaml` với endpoint và request schema `files: [{file_id, type}]`.
- Giữ nguyên `.business-spec/backend-api-route-inventory.md` vì route chưa được khai báo trong source hiện tại.
- Không chạy test; thay đổi chỉ cập nhật tài liệu.
