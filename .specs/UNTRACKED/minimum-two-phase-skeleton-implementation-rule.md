# SPEC: Minimum two-phase skeleton-first implementation rule

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex

## 1. Tổng quan

Bổ sung quy tắc planning cho các task có code implementation: mỗi plan phải
được chia tối thiểu thành hai phase độc lập. Phase 1 tạo skeleton compile được
và chuẩn bị đầy đủ contract/call signature/import/binding cần thiết; các phase
sau triển khai lần lượt phần business logic được đánh dấu `TODO` trong
skeleton.

**Yêu cầu gốc**: Khi lên plan code, luôn có ít nhất hai phase. Phase 1 tạo
khung Controller, Request, Response, Exception và Service; các phần xử lý chi
tiết được ghi rõ bằng `// TODO: ...` để phase sau hoàn thiện.

## 2. Phạm vi áp dụng

- Áp dụng cho mọi task cần tạo, sửa hoặc xóa code trong backend, không phụ
  thuộc kích thước task.
- Không áp dụng cho task chỉ đọc/giải thích, tài liệu không có implementation,
  hoặc test-data-only command nếu không thay đổi production runtime behavior.
- Rule được ghi vào `AGENTS.md`; không thay đổi business spec hiện tại.

## 3. Thiết kế phase bắt buộc

### Phase 1 — Skeleton / Integration Boundary

Plan phải mô tả và implementation phải chuẩn bị, tùy scope feature:

- Controller và route wiring cần thiết.
- FormRequest với validation shape và nguồn dữ liệu đã trace.
- Response/Resource/DTO với contract output.
- Custom Exception và error mapping cần thiết.
- Service Contract/Interface, Service method signature và dependency injection.
- Repository Contract/Implementation hoặc binding cần thiết cho call chain.
- Các import, method signature, return type và constant cần thiết để các phase
  sau có thể dùng trực tiếp.
- Phần business logic chưa hoàn thiện phải có comment `// TODO: ...` mô tả rõ
  phase/mục tiêu sẽ xử lý, không dùng placeholder mơ hồ.

Skeleton phải compile được, không được trả success giả hoặc làm thay đổi
business state như thể feature đã hoàn tất. Nếu route phải được wire từ Phase
1, phải có behavior an toàn và rõ ràng cho trạng thái chưa implement, ví dụ
custom exception/response phù hợp hoặc feature gate theo convention hiện tại.

### Phase 2 — Core Business Logic

- Implement các `TODO` của service/repository theo dependency order.
- Hoàn thiện business rules, transformation, side effects và error mapping.
- Bổ sung hoặc cập nhật unit/feature tests tương ứng.

### Phase 3 trở đi — Chỉ khi scope cần

Có thể tách thêm phase cho external integration, queue/retry, migration,
backfill, performance hoặc rollout. Mỗi phase phải có file ownership, input/
output và tiêu chí hoàn thành riêng; không tạo phase giả chỉ để tăng số lượng.

### Các theme bắt buộc trong plan

- **Phase contract**: mỗi phase phải ghi rõ input, output, file ownership,
  dependency và acceptance criteria.
- **TODO registry**: TODO phải có phase/owner/mục tiêu cụ thể, ví dụ
  `TODO[GAP-691-P2]: ...`; không để TODO production code không có phase owner,
  expected behavior và test case.
- **API/contract freeze**: public signature của Controller, Request, Response,
  Exception và Service được chốt ở Phase 1; phase sau không đổi breaking
  contract nếu plan chưa cập nhật và được approve.
- **Layer applicability**: chỉ tạo các layer phù hợp scope; task chỉ sửa Job,
  Repository hoặc Command không bắt buộc tạo đủ Controller/Request/Response.
- **Data contract**: migration, DTO, external payload và seed data cần thiết
  phải được xác định trước khi implement business logic phụ thuộc vào chúng.
- **Integration safety**: external API, queue, retry, idempotency và rollout
  nên tách phase riêng khi có rủi ro; retry phải có post-state/idempotency
  check trước khi chạy lại side effect.
- **Independent phase**: mỗi phase phải compile/test được và có thể review/
  merge độc lập trong giới hạn dependency đã ghi rõ; phase sau chỉ bắt đầu sau
  khi phase trước qua gate.

## 4. Gate giữa các phase

- Phase sau chỉ bắt đầu khi phase trước đã đạt acceptance criteria và test gate
  được ghi trong plan.
- Mỗi phase phải nêu rõ file tạo/sửa, public contract, dependency với phase
  trước và các TODO được đóng.
- Không để TODO production code chưa có phase owner, expected behavior và test
  case tương ứng.
- Nếu Phase 1 thay đổi route hoặc public contract, phải ghi rõ behavior tạm
  thời và behavior cuối cùng để tránh client hiểu skeleton là feature hoàn tất.

## 5. Test và self-check

- Plan phải có test cases cho từng phase, tối thiểu compile/contract/smoke
  coverage cho Phase 1 và behavior coverage cho Phase 2+.
- Sau khi hoàn tất toàn bộ phase, thực hiện test impact review, chạy affected
  suites và full `./vendor/bin/phpunit` theo rule hiện hành.
- Self-check phải xác nhận mọi `TODO` thuộc scope đã được xử lý hoặc có decision
  record được user approve để defer.

## 6. File dự kiến sửa

| File | Thay đổi |
|---|---|
| `AGENTS.md` | Bổ sung rule bắt buộc plan tối thiểu hai phase và skeleton-first. |

Không tạo hoặc sửa file production code trong phạm vi thay đổi quy trình này.

## 7. Acceptance criteria

- `AGENTS.md` mô tả rõ minimum two-phase rule.
- Phase 1 được định nghĩa là skeleton compile được với Controller, Request,
  Response, Exception và Service/call signatures phù hợp scope.
- Phase sau có trách nhiệm đóng TODO và không được bỏ qua test gate.
- Rule không yêu cầu chia phase giả hoặc thay đổi business spec hiện tại.
- Không có file production code nào bị sửa khi chỉ thêm rule planning.

## 8. Self-check trước khi hoàn thành

- [x] User đã approve plan.
- [x] Rule đã được bổ sung vào `AGENTS.md` sau approval.
- [x] Không có production code ngoài phạm vi bị thay đổi.
- [x] Test/documentation impact của rule đã được kiểm tra.

## 9. Implementation evidence

- Đã bổ sung rule minimum two-phase skeleton-first và các theme phase contract,
  TODO registry, contract freeze, layer applicability, data contract,
  integration safety, independent phase và test gates vào `AGENTS.md`.
- Chỉ thay đổi plan và `AGENTS.md`; không thay đổi production code.
