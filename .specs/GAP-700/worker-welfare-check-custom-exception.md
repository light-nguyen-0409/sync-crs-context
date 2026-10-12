# SPEC: Worker Welfare Check Custom Exception

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-18
> **Author**: Codex

## 1. Tổng quan

Thay thế việc sử dụng trực tiếp `App\Exceptions\Api\APIErrorException` trong
`WorkerWelfareCheckService` bằng `App\Exceptions\Api\Consultant\APIErrorException`,
theo cùng pattern với `App\Exceptions\Api\Compliance\APIErrorException`. Custom
exception sẽ kế thừa exception API nền tảng để giữ cơ chế xử lý lỗi hiện tại,
đồng thời trả về format lỗi của Consultant API.

**Yêu cầu gốc**: Tạo custom exception riêng thay vì dùng trực tiếp
`App\Exceptions\Api\APIErrorException`.

## 2. Database Design

N/A — Không thay đổi database.

## 3. API Contract

Không thay đổi endpoint, request hoặc success response.

### 3.1. Error contract

Các error key và HTTP status hiện tại được giữ nguyên:

| Error key | Khi xảy ra | HTTP status |
|-----------|------------|-------------|
| `notFound` | Candidate, welfare image hoặc file storage không tồn tại | Theo `../../config/api.php` |
| `operationNotAllowed` | Candidate chưa đủ điều kiện thực hiện welfare check | Theo `../../config/api.php` |

Custom exception sử dụng `App\Http\Resources\Api\Consultant\Status` để giữ format
lỗi của Consultant API. Middleware hiện tại tiếp tục nhận diện được exception vì
custom exception kế thừa `App\Exceptions\Api\APIErrorException`.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý

1. `WorkerWelfareCheckService` phát hiện lỗi nghiệp vụ.
2. Service ném `App\Exceptions\Api\Consultant\APIErrorException`.
3. Exception resolve error config từ `config('api.errors')`.
4. Laravel/middleware trả response lỗi theo Consultant API contract.

### 4.2. Business rules

- Chỉ thay đổi loại exception; không thay đổi điều kiện lỗi, error key hoặc user message.
- Các service khác đang dùng `App\Exceptions\Api\APIErrorException` không nằm trong phạm vi thay đổi.

## 5. Data Origin & Call Chain

```text
routes/consultant.php
  → CandidateController@performWorkerWelfareCheck
    → WorkerWelfareCheckRequest
    → WorkerWelfareCheckService@performCheck
      → throw Consultant\APIErrorException khi business rule thất bại
    → Laravel exception handling / ErrorHandling middleware
    → Consultant API error response
```

| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|----------------|------------|
| `$error` | Custom exception constructor | Service truyền error key hiện tại | ✅ |
| `$message` | Custom exception constructor | Service truyền user message hiện tại | ✅ |
| `$extraData` | Custom exception constructor | Optional constructor argument | ✅ |

## 6. Constants & Enums

N/A — Không thêm magic value hoặc error key mới; sử dụng các error key hiện có
trong `../../config/api.php`.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|------|-----------|-------|
| `../../app/Exceptions/Api/Consultant/APIErrorException.php` | `App\Exceptions\Api\Consultant` | Custom API exception theo pattern Compliance, kế thừa API exception nền tảng và trả Consultant `Status` |
| `tests/Unit/Exceptions/ConsultantAPIErrorExceptionTest.php` | `Tests\Unit\Exceptions` | Kiểm tra custom exception, error metadata và response contract |

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `../../app/Services/WorkerWelfareCheckService.php` | Đổi import và các điểm `throw` sang `App\Exceptions\Api\Consultant\APIErrorException` |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | Cập nhật expected exception sang custom exception và bổ sung assertion domain exception |

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `tests/Unit/Exceptions/ConsultantAPIErrorExceptionTest.php` | custom exception metadata | Xác nhận error name, user message, extra data và kế thừa exception API nền tảng |
| `tests/Unit/Exceptions/ConsultantAPIErrorExceptionTest.php` | consultant error response | Xác nhận response dùng Consultant `Status` và giữ error code/status hiện tại |
| `../../tests/Unit/Services/WorkerWelfareCheckServiceTest.php` | existing exception scenarios | Xác nhận các nhánh candidate không tồn tại, candidate không hợp lệ và thiếu ảnh interview ném đúng custom exception |

Sau khi code xong sẽ chạy toàn bộ test suite bằng `./vendor/bin/phpunit` theo
quy định của project.

## 9. Checklist trước khi Approve

- [x] Không thay đổi database.
- [x] API success contract không thay đổi.
- [x] Error key, message và status hiện tại được giữ nguyên.
- [x] Call chain đã trace từ route tới service và exception handler.
- [x] Không thêm magic value.
- [x] Đã liệt kê file mới, file sửa và test impact.
- [x] User approve plan.
