# SPEC: GAP-691 — Cập nhật test cho mapping branch Hawk3

> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-13
> **Author**: Codex

## 1. Tổng quan

Đồng bộ test với thay đổi production mapping trong `config/work_finder_agreement.php`,
trong đó branch ID `182` chọn template `pdf.work_finder_agreements.hawk3`.

Phạm vi chỉ gồm test coverage và assertion liên quan đến template resolution; không
thay đổi API contract, business flow ngoài mapping, database hoặc production service.

**Yêu cầu gốc**: Rà soát và update test cho mapping Work Finder Agreement của branch Hawk3.

## 2. Database Design

N/A — không thay đổi schema, migration, model hoặc dữ liệu database.

## 3. API Contract / API Documentation

N/A — route, request, response, error contract và API documentation không thay đổi.

## 4. Business Logic / Test Scope

- Cập nhật assertion production mapping để phản ánh branch `182` → template Hawk3.
- Bổ sung hoặc điều chỉnh Feature test để xác nhận branch mapping được resolve trước
  `legal_entities` mapping.
- Xác minh constant/fixture `HAWK3_BRANCH_ID` trong test không mâu thuẫn với branch ID
  production `182`; nếu constant đang đại diện cho branch khác thì đổi tên hoặc giữ
  nguyên và tạo fixture rõ ràng cho branch `182`.
- Giữ nguyên các test fallback theo legal entity và các test template khác.
- Không dùng mock data tách rời call chain; coverage phải đi qua resolver/generation
  flow hiện tại hoặc assertion config trực tiếp khi phù hợp.

## 5. Data Origin & Call Chain

```text
POST /api/candidate/me/permanent-intake/work-finder-agreement
  → PermanentCandidateIntakeController::generateWorkFinderAgreement
  → PermanentCandidateIntakeService::generateWorkFinderAgreement
  → Job → Branch (branch_id = 182)
  → resolveTemplate(): branch mapping wins over legal entity mapping
  → pdf.work_finder_agreements.hawk3
  → Dompdf/File response
```

Các dữ liệu cần verify:

| Dữ liệu | Nguồn | Xác nhận |
|---|---|---|
| Branch ID `182` | `config/work_finder_agreement.php` và test fixture/config override | Chưa thực thi |
| Hawk3 view identifier | Production config mapping | Đã xác nhận từ source |
| Branch-over-entity priority | `PermanentCandidateIntakeService::resolveTemplate()` | Đã xác nhận từ source |

## 6. Files cần sửa

| File | Thay đổi |
|---|---|
| `tests/Feature/Api/Candidate/PermanentCandidateIntakeTest.php` | Cập nhật expected mapping và coverage branch Hawk3/priority nếu cần |
| `.specs/GAP-691/017-update-hawk3-branch-mapping-tests.md` | Plan và execution record |

Không sửa production config trong scope này vì mapping đã có trong working tree.

## 7. Verification / Acceptance Criteria

- Test không còn kỳ vọng `work_finder_agreement.branches` là mảng rỗng.
- Có assertion xác nhận branch `182` resolve đúng view Hawk3.
- Có coverage xác nhận branch mapping thắng entity mapping, nếu test fixture cho phép.
- Chạy test Feature liên quan đến `PermanentCandidateIntakeTest`.
- Chạy toàn bộ `./vendor/bin/phpunit` theo workspace rule.
- Chạy `git diff --check`; không chạy formatter/linter.
- Không thay đổi các file unrelated đang dirty trong working tree.

## 8. Approval

- [x] User review và approve plan (2026-10-13).
- [x] Implementation bắt đầu sau khi được approve.

## 9. Execution Record

- Đã cập nhật `PermanentCandidateIntakeTest` để expected production mapping chứa
  `182 => pdf.work_finder_agreements.hawk3`.
- Đổi `HAWK3_BRANCH_ID` từ `14` thành `182` để không mâu thuẫn với config production.
- Negative entity-mapping test override branch mapping về rỗng để test đúng riêng
  fallback theo legal entity, không phụ thuộc branch ID của fixture.
- Existing `testAdditionalAgreementTemplatesGenerateSourcePdf` đã có coverage qua
  production request chain cho branch override thắng entity mapping; không thêm test
  trùng lặp.
- Focused Feature suite PASS: `69 tests, 6599 assertions`.
- Full PHPUnit PASS: `613 tests, 9286 assertions`.
- PHP syntax check PASS cho `PermanentCandidateIntakeTest.php`.
- `git diff --check` PASS; không chạy formatter/linter.
- API docs/contract: `N/A — no API contract/API docs change`.
- Các thay đổi test/config đã có trong commit `adb448447666d3824496e08da9db31e9897a5045`
  (`#691: add mapping branch hawk3update`); không tạo thêm commit.
