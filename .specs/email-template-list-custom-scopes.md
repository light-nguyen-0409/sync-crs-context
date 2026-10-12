# SPEC: Email template list — custom entity/branch

> **Trạng thái**: DONE
> **Ngày tạo**: 2026-09-18

## 1. Tổng quan

Yêu cầu: API list email templates trả thêm thông tin entity, branch được custom.
Đề xuất đã cập nhật theo feedback: mỗi template trả hai mảng `custom_entities` và `custom_branches` để FE hiển thị trực tiếp, không cần tự phân loại scope. Hai mảng chứa toàn bộ entity/branch có custom riêng trong `email_customs`, không chỉ phạm vi của lần cập nhật mới nhất. Contract đã được user duyệt, cho phép triển khai.

## 2. Database Design

Không thay đổi schema, không migration. Tận dụng relationships `EmailCustom::legalEntity()`, `branch()`, `last_update_user()` hiện có.

## 3. API Contract

Endpoint: `GET /api/compliance/email_templates`.
Auth/middleware giữ nguyên: `auth:userApi`, `detectBranchForCompliance`.
Query hiện có giữ nguyên: `filter`, `order` (mặc định `id`), `direction` (`asc`), `offset` (0), `limit` (20).
FormRequest hiện tại là `Api/Compliance/Request`, không có rules riêng cho list. Không thêm input hoặc validation mới trong task này.

Response giữ `email_templates`, `count` và các field hiện có. Mỗi phần tử list bổ sung:

```json
{
  "custom_entities": [
    {"id": 1, "name": "Entity A"}
  ],
  "custom_branches": [
    {"id": 10, "name": "Branch A"},
    {"id": 20, "name": "Branch B"}
  ]
}
```

- Hai mảng luôn tồn tại; không có phần tử phù hợp thì trả `[]`.
- `custom_entities`: chỉ lấy custom có `legal_entity_id != null` và `branch_id = null`.
- `custom_branches`: lấy custom có `branch_id != null`, bất kể `legal_entity_id` có null hay không.
- Entity chỉ có branch custom không tự xuất hiện trong `custom_entities`; chỉ xuất hiện nếu có bản custom cấp entity riêng.
- Custom mặc định (cả hai ID null) không thuộc hai mảng này, vẫn được xét khi lấy metadata cập nhật mới nhất.
- ID lấy từ `email_customs`, tên lấy từ relationship tương ứng. Relation thiếu hoặc branch soft delete: vẫn trả `{ "id": ID_đã_lưu, "name": null }`.
- Loại trùng theo ID trong từng mảng. Sắp theo thứ tự custom `updated_at` giảm dần, `id` giảm dần khi trùng thời gian; giữ lần xuất hiện đầu tiên. Reindex để JSON luôn là array.
- Không thay đổi response detail/update. Lỗi/auth giữ nguyên, không phát sinh exception mới.

## 4. Business Logic (Service Layer)

1. Lấy trang template và count theo filter hiện tại.
2. Repository batch-fetch toàn bộ custom của template IDs trên trang, eager-load entity/branch/user, sắp xếp tại DB; không query trong loop.
3. Service group custom theo template ID, lấy custom mới nhất để giữ metadata cập nhật hiện tại và phân loại/map custom thành `custom_entities` và `custom_branches` theo rules ở trên.
4. Service luôn gán cả `custom_entities` và `custom_branches` cho từng template, kể cả mảng rỗng; giữ nội dung/title/placeholders template gốc.
5. Collection resource chỉ bổ sung `custom_entities` và `custom_branches` cho list item, không tác động resource dùng chung của detail/update.

Repository chỉ truy vấn dữ liệu; grouping/chọn bản mới nhất/map response nằm ở Service. Không cần transaction, cache mới hoặc side effect.

## 5. Data Origin & Call Chain

`routes/compliance.php:61` → `EmailTemplateController::index()` → `EmailTemplateService::getEmailTemplates()` → `EmailTemplateRepository::getByFilter()` / `countByFilter()` → `EmailTemplates` collection resource → `EmailTemplate` item resource.

Đã kiểm tra:

| Dữ liệu | Nguồn thực tế |
|---|---|
| Template IDs | Collection lấy từ repository, giới hạn theo trang |
| Custom và metadata | Hiện lấy qua `EmailCustomRepository::getLatestByTemplateIds()`; query đã lấy mọi custom nhưng group/map chỉ giữ bản mới nhất |
| Entity ID, branch ID | Cột của `email_customs`; `saveCustom()` chuẩn hóa entity theo branch khi ghi |
| Entity/branch name | `EmailCustom::legalEntity()` / `branch()` nối tới model có thuộc tính `name` |
| `custom_entities`, `custom_branches` (mới) | Service tạo từ kết quả batch query trước khi controller truyền collection cho resource |

## 6. Constants & Enums

Không thêm status/type/TTL/identifier cố định. Scope biểu diễn bằng nullable IDs hiện có, không thêm magic string để phân loại scope.

## 7. Files cần tạo/sửa

Không tạo file implementation mới.

| File | Thay đổi |
|---|---|
| `app/Contracts/Repositories/EmailCustomRepositoryInterface.php` | Thay method latest-only bằng `getByTemplateIds(array $templateIds)`; đã xác nhận chỉ list service gọi method cũ |
| `app/Repositories/EmailCustomRepository.php` | Trả collection custom đầy đủ và eager-load quan hệ; bỏ grouping/business selection khỏi repository |
| `app/Services/EmailTemplateService.php` | Group/map trong bộ nhớ, giữ latest metadata, phân loại và thêm hai mảng entity/branch |
| `app/Http/Resources/Api/Compliance/EmailTemplates.php` | Serialize thêm field cho riêng list item, giữ các field của item resource hiện tại |
| `tests/Feature/Api/Compliance/EmailTemplatesTest.php` | Cập nhật strict key assertion cho list và thêm regression cases |
| `tests/Unit/Services/EmailTemplateServiceTest.php` | Cập nhật/bổ sung kiểm tra mapping dữ liệu thực từ repository |

## 8. Test Cases

- List không có custom hoặc chỉ default custom: cả hai mảng rỗng. Entity custom chỉ vào `custom_entities`, branch custom chỉ vào `custom_branches`.
- Entity chỉ có branch custom không vào mảng entity; entity có custom riêng và branch custom thì cả hai mảng có phần tử tương ứng.
- Một template có nhiều entity/branch custom: trả đầy đủ đúng mảng và đúng tên, không chỉ bản cập nhật mới nhất; không lặp ID.
- Branch custom có entity null (dữ liệu legacy), relation thiếu/branch soft delete: branch vẫn được phân loại đúng; relation thiếu trả ID và name null.
- Nhiều template: không trộn scope giữa template, không lấy custom ngoài trang.
- Metadata vẫn từ custom mới nhất; title/content/placeholders vẫn từ master.
- Filter/order/pagination/count, auth và scope query bị bỏ qua giữ nguyên.
- Detail/update giữ nguyên strict response contract.
- Kiểm tra số query không tăng theo số template/custom (không N+1).

Test audit đã xác định strict helper `assertTemplateContract()` đang dùng chung list/detail/update; chỉ thêm key cho list. Unit suite `EmailTemplateServiceTest` có test gọi `getEmailTemplates()` cần cập nhật theo contract mới. Rà lại references sau thay đổi để xác định đầy đủ suite chịu ảnh hưởng.

Sau implementation, chạy `./vendor/bin/phpunit tests/Feature/Api/Compliance/EmailTemplatesTest.php` và `./vendor/bin/phpunit tests/Unit/Services/EmailTemplateServiceTest.php`, cùng mọi suite bị ảnh hưởng thêm qua audit. Ghi rõ nếu môi trường chặn việc chạy; không coi hoàn tất khi test còn lỗi.

## 9. Checklist trước khi Approve

- [x] Không thay đổi database.
- [x] Đề xuất request/response và business rules.
- [x] Đã trace nguồn dữ liệu và caller thực tế.
- [x] Không thêm magic value.
- [x] Xác định file và test chịu ảnh hưởng.
- [x] User duyệt response contract mới với `custom_entities` và `custom_branches`.

Sau approve: đọc lại plan và code, thực hiện tuần tự theo backend-workflow, self-check với plan, giữ diff tối thiểu, không tự chạy formatter/linter.


## 10. Kết quả implementation và self-check

- Đã triển khai hai mảng riêng theo contract; eager loading entity/branch chỉ lấy id/name.
- Grouping, phân loại và deduplicate nằm trong Service; repository chỉ truy vấn dữ liệu.
- Đã kiểm tra caller thực và resource list; detail/update giữ nguyên contract.
- Không thêm migration, transaction, query trong loop hoặc formatter/linter.
- Audit references xác nhận method repository cũ không còn caller; hai suite chịu ảnh hưởng đã chạy thành công.
- `./vendor/bin/phpunit tests/Unit/Services/EmailTemplateServiceTest.php`: PASS, 18 tests / 118 assertions.
- `./vendor/bin/phpunit tests/Feature/Api/Compliance/EmailTemplatesTest.php`: PASS, 18 tests / 116 assertions.
- Regression test xác nhận 10 template / 50 custom dùng cùng số query như 1 template, tối đa 7 query trong service; serialization không phát sinh query.
- Các thay đổi có sẵn ngoài phạm vi được giữ nguyên.
