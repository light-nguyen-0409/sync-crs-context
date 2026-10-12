# SPEC: [Tên Feature / API]

> **Trạng thái**: `DRAFT` | `APPROVED` | `IMPLEMENTING` | `DONE`
> **Ngày tạo**: YYYY-MM-DD
> **Author**: [Tên người viết]

---

## 1. Tổng quan

<!-- Mô tả ngắn gọn mục tiêu của feature/API này (2-3 câu) -->

**Yêu cầu gốc**: <!-- Link hoặc mô tả yêu cầu từ user/PM -->

---

## 2. Database Design

<!-- Bỏ qua section này nếu không thay đổi DB -->

### 2.1. Bảng mới

```
Tên bảng: `table_name`
```

| Cột | Kiểu | Nullable | Default | Mô tả |
|-----|------|----------|---------|-------|
| `id` | bigIncrements | NO | — | PK |
| `column_name` | string(255) | YES | null | Mô tả |
| `created_at` | timestamp | YES | null | — |
| `updated_at` | timestamp | YES | null | — |

**Index**: `column_name` (cho WHERE/ORDER BY)
**Foreign Keys**: `column_name` → `other_table.id` (onDelete: cascade)

### 2.2. Bảng sửa đổi

```
Bảng: `existing_table`
Migration: add_column_to_existing_table
```

| Thay đổi | Cột | Kiểu | Mô tả |
|----------|-----|------|-------|
| ADD | `new_column` | string(100) | Mô tả |
| MODIFY | `existing_column` | text | Lý do sửa |

### 2.3. Eloquent Relationships

```
ModelA hasMany ModelB (foreign key: model_a_id)
ModelB belongsTo ModelA
```

---

## 3. API Contract

<!-- Bỏ qua section này nếu không tạo/sửa API -->

### 3.1. Endpoint

```
[METHOD] /api/v1/resource-name
```

**Auth**: Required / Optional / None
**Middleware**: `auth:api`, `role:admin`, ...
**Tags**: `Feature Group Name`

### 3.2. Request

**Headers**:
```
Authorization: Bearer {token}
Content-Type: application/json
```

**Route Params** (nếu có):
| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| `id` | integer | YES | Resource ID |

**Query Params** (nếu GET):
| Param | Type | Required | Default | Mô tả |
|-------|------|----------|---------|-------|
| `page` | integer | NO | 1 | Trang |
| `per_page` | integer | NO | 15 | Số item/trang |

**Request Body** (nếu POST/PUT):
```json
{
    "field_name": "string, required, max:255",
    "field_email": "string, required, email",
    "field_type": "integer, required, in:1,2,3"
}
```

**FormRequest Validation Rules**:
```php
[
    'field_name'  => 'required|string|max:255',
    'field_email' => 'required|email',
    'field_type'  => 'required|integer|in:1,2,3',
]
```

### 3.3. Response

**Success (200)**:
```json
{
    "data": {
        "id": 1,
        "field_name": "value",
        "created_at": "2024-01-15T10:00:00Z"
    },
    "message": "Success"
}
```

**Error Responses**:

| HTTP Code | Exception | Error Name (config key) | Khi nào |
|-----------|-----------|------------------------|---------|
| 400 | `App\Exceptions\Api\{Domain}\APIErrorException` | `error_name_here` | Business rule violation |
| 401 | `App\Exceptions\Api\{Domain}\APIErrorException` | `unauthorized` | Token invalid hoặc expired |
| 404 | `App\Exceptions\Api\{Domain}\APIErrorException` | `not_found` | Resource không tồn tại |

> Error code & HTTP status được resolve từ `config('api.errors.{error_name}')`.
> Constructor: `new APIErrorException($errorName, $userMessage, $extraData = [])`

---

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

```
1. Controller nhận request (đã validate qua FormRequest)
2. Gọi Service method
3. Service thực hiện logic:
   a. [Bước logic 1]
   b. [Bước logic 2]
   c. [Bước logic 3]
4. Service trả về kết quả
5. Controller return Resource/Response
```

### 4.2. Business Rules

<!-- Liệt kê các rule nghiệp vụ cần enforce -->

- Rule 1: ...
- Rule 2: ...

### 4.3. Side Effects

<!-- Bỏ qua nếu không có -->

| Loại | Trigger | Mô tả |
|------|---------|-------|
| Email | Sau khi tạo | Gửi mail xác nhận qua `App\Mail\...` |
| Event | Sau khi update | Dispatch `App\Events\...` |
| Queue Job | Async | `App\Jobs\...` |
| Cache | Invalidate | Xóa cache key `...` |

---

## 5. Data Origin & Call Chain

<!-- QUAN TRỌNG: Trace ngược để chứng minh mọi biến đều có nguồn gốc -->

```
Route (routes/api.php)
  → Controller@method
    → FormRequest (validated data)
    → Service@method($validatedData)
      → Repository@query($params)
      → Return DTO / Model / Collection
    → Resource::make($result)
  → JSON Response
```

**Biến cần verify**:
| Biến / Key | Nơi sử dụng | Nguồn cung cấp | Confirmed? |
|------------|-------------|-----------------|------------|
| `$data['field']` | Service | FormRequest validated | ✅ |

---

## 6. Constants & Enums

<!-- Liệt kê các magic value cần khai báo const -->

```php
// Trong Model hoặc Contract
public const STATUS_ACTIVE = 1;
public const STATUS_INACTIVE = 0;
public const TYPE_STANDARD = 'standard';

public const CACHE_KEY_PREFIX = 'feature_name';
public const CACHE_TTL = 3600; // seconds
```

---

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Namespace | Mô tả |
|------|-----------|-------|
| `app/Http/Controllers/{Domain}/FeatureController.php` | `App\Http\Controllers\{Domain}` | Controller |
| `app/Http/Requests/{Domain}/StoreFeatureRequest.php` | `App\Http\Requests\{Domain}` | Validation |
| `app/Http/Resources/Api/{Domain}/Feature.php` | `App\Http\Resources\Api\{Domain}` | Response (extends Resource, dùng `$columns`) |
| `app/Contracts/Services/FeatureServiceInterface.php` | `App\Contracts\Services` | Interface (extends BaseServiceInterface) |
| `app/Services/FeatureService.php` | `App\Services` | Implementation |
| `app/Contracts/Repositories/FeatureRepositoryInterface.php` | `App\Contracts\Repositories` | Interface (extends SingleKeyModelRepositoryInterface) |
| `app/Repositories/FeatureRepository.php` | `App\Repositories` | Implementation |
| `app/Dto/FeatureResult.php` | `App\Dto` | DTO (readonly properties) |
| `database/migrations/yyyy_mm_dd_HHmmss_create_features_table.php` | — | Migration |

### 7.2. Files sửa

| File | Thay đổi |
|------|----------|
| `routes/api.php` | Thêm route mới |
| `app/Providers/AppServiceProvider.php` | Register binding Contract → Implementation |

---

## 8. Test Cases

| Test File | Test Method | Mô tả |
|-----------|-------------|-------|
| `tests/Feature/FeatureTest.php` | `test_can_create_feature` | Happy path |
| `tests/Feature/FeatureTest.php` | `test_validation_fails` | Invalid input |
| `tests/Feature/FeatureTest.php` | `test_unauthorized` | No token |

---

## 9. Checklist trước khi Approve

- [ ] Database design đã review (index, FK, naming)
- [ ] API contract đầy đủ (request/response/errors)
- [ ] Business rules rõ ràng
- [ ] Call chain đã trace & verify
- [ ] Không có magic value — tất cả là const
- [ ] File list đầy đủ theo kiến trúc phân lớp
- [ ] Test cases đã liệt kê
