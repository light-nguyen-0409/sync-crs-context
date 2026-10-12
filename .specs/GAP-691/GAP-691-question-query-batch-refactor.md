# SPEC: GAP-691 — Batch query cho Permanent intake questions

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-09-30
> **Author**: Codex

## 1. Tổng quan

Refactor phần đọc ba Question theo `category` trong `PermanentCandidateIntakeService::submit()`.
Thay ba lần gọi `firstByFilter()` bằng một lần `allByFilter()` dùng `WHERE IN`, sau đó nhóm kết quả theo category trong memory.

**Yêu cầu gốc**: Chỉ áp dụng refactor query đã review cho GAP-691; không thay đổi business behavior hoặc các refactor phụ khác.

## 2. Database Design

N/A. Không thay đổi schema, migration, index hoặc repository implementation. Cột `questions.category` đã có index hiện hữu.

## 3. API Contract

N/A. Không thay đổi route, request, response, status code hoặc validation.

## 4. Business Logic (Service Layer)

### 4.1. Luồng xử lý chính

1. `PermanentCandidateIntakeService::submit()` tạo danh sách ba category đã được định nghĩa bởi các constant của `Question`.
2. Gọi `QuestionRepositoryInterface::allByFilter(['category' => $categories], 'id', 'asc')` một lần.
3. Group kết quả theo `category` và lấy record đầu tiên cho mỗi category.
4. Giữ nguyên cách lấy AnswerOption, persistence transaction, lưu Answer, gọi MatchMaker và xử lý queue hiện tại.

### 4.2. Business Rules

- Không thay đổi các category hoặc mapping field hiện tại.
- `groupBy(...)->first()` được dùng thay cho `keyBy()` vì `questions.category` không có unique constraint; cách này giữ semantics lấy record đầu tiên nếu dữ liệu duplicate.
- Không chuyển các lời gọi `saveAnswer()` vào loop vì mỗi lời gọi thực hiện database write và project cấm database query/write trong loop.
- Không thay đổi behavior khi một Question hoặc AnswerOption không tồn tại.

### 4.3. Side Effects

Không có side effect mới. Không thay đổi transaction, file persistence, MatchMaker sync, queue fallback hoặc logging.

## 5. Data Origin & Call Chain

```
POST /api/candidate/me/permanent-intake
  → PermanentCandidateIntakeController::submit()
    → PermanentCandidateIntakeRequest::validated()
      → PermanentCandidateIntakeService::submit()
        → QuestionRepositoryInterface::allByFilter()
        → answer/address/file repositories
        → transaction writes
        → MatchMakerService / fallback job
```

| Biến / Key | Nguồn cung cấp | Confirmed? |
|---|---|---|
| Question categories | `Question::PRIMARY_METHOD_OF_TRANSPORT`, `Question::WILLING_TO_TRAVEL`, `Question::WHERE_DID_YOU_HEAR_ABOUT_US_CANDIDATE_ANSWER` | ✅ |
| `$data` | `PermanentCandidateIntakeRequest::validated()` | ✅ |
| Question records | `QuestionRepositoryInterface::allByFilter()` theo category list | ✅ |

## 6. Constants & Enums

Không thêm constant. Tái sử dụng các category constants đã có trong `App\Models\Question`.

## 7. Files cần tạo/sửa

### 7.1. Files mới

| File | Mô tả |
|---|---|
| N/A | Không tạo runtime file mới |

### 7.2. Files sửa

| File | Thay đổi |
|---|---|
| `app/Services/PermanentCandidateIntakeService.php` | Gộp ba Question query thành một batch query; giữ nguyên phần còn lại của service |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Cập nhật mock expectation từ ba `firstByFilter()` sang một `allByFilter()` để phản ánh query contract mới |

Không sửa Controller, FormRequest, Repository implementation/contract, routes, migration, MatchMaker flow, answer-option flow hoặc các refactor phụ đã nêu trong review.

## 8. Test Cases

| Test File | Kiểm tra |
|---|---|
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Service vẫn persist và queue fallback như hiện tại khi Question records được trả về từ một batch query |

Không thêm behavior/API test mới vì contract nghiệp vụ không thay đổi.

## 9. Checklist trước khi Approve

- [x] Chỉ thay đổi batch query Question trong Service.
- [x] Không thay đổi API response hoặc business side effects.
- [x] Không query database trong loop.
- [x] Giữ thứ tự record đầu tiên cho duplicate category bằng `id asc` + `groupBy()->first()`.
- [x] Cập nhật service test mock expectation.
- [x] Chạy affected PHPUnit suite sau khi code được approve.

## 10. Implementation evidence

- `PermanentCandidateIntakeService::submit()` now loads the three Question categories with one `allByFilter()` query and maps the first row per category in memory.
- `PermanentCandidateIntakeServiceTest` now supplies category values and expects the single batch query.
- Affected PHPUnit checks passed: service unit test `1 test, 14 assertions`; Permanent intake feature suite `4 tests, 27 assertions`.
