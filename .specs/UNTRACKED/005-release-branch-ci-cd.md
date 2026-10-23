# SPEC: Release branch CI/CD promotion (`release/v*`)

> **Trạng thái**: `IMPLEMENTING`
> **Ngày tạo**: 2026-10-14
> **Author**: Codex

## 1. Tổng quan

Thiết lập bổ sung quy trình CI/CD theo release branch để nhiều phiên bản có thể
tồn tại đồng thời, ví dụ `release/v1.6.9` đang chờ PROD trong khi
`release/v1.7.0` tiếp tục nhận feature. Các branch và trigger cũ như
`master/develop` vẫn được giữ nguyên; pattern `release/v*` chỉ được bổ sung,
không thay thế migration hiện tại.

Mục tiêu là review và chạy full test tại PR vào `release/v*` một lần, sau đó
promote cùng commit/artifact qua STG và PROD với kiểm tra nhẹ, approval và
không chạy lại toàn bộ pipeline không cần thiết.

## 2. Hiện trạng đã xác minh

- `.github/workflows/unittest.yml` hiện chạy `pull_request` vào `master` và
  `develop`; các trigger này phải tiếp tục hoạt động.
- `.github/workflows/claude-review.yml` hiện review PR target `develop`; trigger
  này phải tiếp tục hoạt động.
- Chưa tìm thấy workflow deploy STG/PROD trong `.github/workflows/`.
- Repository hiện có các remote branch `release/dev`, `release/stg` và
  `release/production`, nhưng không có deployment workflow tương ứng trong
  working tree; không thể suy đoán lệnh deploy hoặc secret ngoài repo.
- Branch production thực tế (`master` hay tên khác), cơ chế deploy hiện tại,
  GitHub environments, secrets và branch rulesets cần được xác minh trước khi
  implementation; không tự suy đoán tên secret hoặc lệnh deploy.

## 3. Mô hình branch và promotion

```text
production branch (hiện cần xác minh: master/main)
  ├── release/v1.6.9
  │     └── feature/fix-...  → PR vào release/v1.6.9
  └── release/v1.7.0
        └── feature/new-...  → PR vào release/v1.7.0
```

### 3.1. Quy tắc branch

- Pattern release chuẩn: `release/v*`, ví dụ `release/v1.6.9`.
- Giữ nguyên các branch legacy/current `master` và `develop` cùng các CI/review
  trigger đang chạy; chỉ bổ sung release branch vào cùng workflow hoặc workflow
  tương ứng.
- Không merge feature trực tiếp vào production branch.
- Không merge `release/v1.6.9` với `release/v1.7.0` một cách tự động.
- Bugfix chỉ thuộc v1.6.9 phải vào `release/v1.6.9`; nếu v1.7.0 cần cùng
  thay đổi thì cherry-pick/PR riêng sang `release/v1.7.0`.
- Nếu v1.7.0 phải bao gồm code đang chờ release của v1.6.9, branch v1.7.0
  phải được tạo từ `release/v1.6.9` hoặc nhận các commit cần thiết bằng
  cherry-pick; không tạo mù từ production branch cũ.
- Sau khi PROD thành công, merge release branch về production branch và tag
  version immutable.

### 3.2. Promotion rules

| Event | Target | Hành vi dự kiến |
|---|---|---|
| PR vào `master`/`develop` | legacy/current branch | Giữ nguyên PHPUnit và code review hiện tại |
| PR vào `release/v*` | release branch | PHPUnit/feature tests, static checks, AI/code-owner review |
| Merge/push vào `release/v*` | STG | Build một artifact/commit và deploy STG |
| QA STG pass | PROD | Manual approval; promote đúng artifact/commit đã test |
| Push tag `v*` | PROD hoặc workflow được approval | Deploy production, không build lại khác nội dung |

Single release branch chỉ được có một version; không dùng một `dev` environment
duy nhất để test đồng thời hai release. Nếu cần test đồng thời, DEV/STG phải
có deployment target/namespace riêng hoặc STG được chọn rõ release đang test.

## 4. Files/configuration dự kiến

### 4.1. Files sửa

| File | Thay đổi dự kiến |
|---|---|
| `.github/workflows/unittest.yml` | Bổ sung `release/v*` vào branch filter hiện tại; giữ nguyên `master` và `develop`, event PR và job check hiện hữu. |
| `.github/workflows/claude-review.yml` | Bổ sung `release/v*` vào target branch filter hiện tại; giữ nguyên `develop`, điều kiện bỏ qua draft/Dependabot và cơ chế review hiện tại. |

### 4.2. File có thể tạo

| File | Thay đổi dự kiến |
|---|---|
| `.github/workflows/release-promotion.yml` | Deploy STG khi release branch merge/push; promote PROD qua tag hoặc `workflow_dispatch` có environment approval, tùy cơ chế deploy hiện tại đã xác minh. |

Không tạo workflow deploy mới nếu repository đã có cơ chế deploy ở hệ thống khác
hoặc reusable workflow có thể gọi lại; khi đó chỉ kết nối đúng entry point và
ghi rõ external dependency trong plan implementation result.

## 5. GitHub repository settings ngoài file

Thiết lập bằng Branch protection/rulesets, không thể hoàn tất chỉ bằng commit:

- Branch pattern: `release/v*`.
- Giữ nguyên rules/required checks hiện có cho `master` và `develop`.
- Require pull request trước khi merge.
- Require ít nhất một approval và CODEOWNERS phù hợp.
- Require checks: PHPUnit job và code-review job phải pass.
- Disable direct push/force push/delete cho release branch.
- Production branch chỉ nhận promotion từ release branch hoặc tag theo policy.
- Tạo GitHub Environments `stg` và `prod`; `prod` có required reviewers.
- Xác định các secrets/variables thật sự dùng cho deploy; không ghi secret vào
  repository hoặc plan.

## 6. CI/CD tối ưu và tính đúng đắn

- Full PHPUnit chạy ở PR vào `release/v*`.
- Push sau merge chỉ build/deploy artifact; không mặc định chạy lại full suite
  nếu commit đã pass cùng required checks.
- STG và PROD dùng cùng commit SHA hoặc artifact digest; PROD không rebuild từ
  branch khác.
- Dùng `concurrency` theo environment/release để tránh hai lần deploy đồng thời.
- PROD phải yêu cầu manual approval và smoke check sau deploy.
- Hotfix release phải trigger lại affected tests và promotion từ release branch.
- Sau production release, đồng bộ các bugfix cần thiết về các release branch
  đang mở bằng PR/cherry-pick có traceability.

## 7. Data/API contract gate

`N/A — no API contract/API docs change.`

Task chỉ thay đổi GitHub Actions và repository branch/promotion policy; không
đổi route, request/response schema, API examples hoặc backend business flow.

## 8. Test và validation plan

- Parse/lint các workflow YAML bằng công cụ sẵn có, không chạy formatter.
- Kiểm tra event/branch filters bằng static audit cho `master`, `develop`,
  `release/v*` và tag `v*`; xác nhận các branch cũ vẫn còn trigger sau thay đổi.
- Kiểm tra job dependency, environment approval, concurrency và artifact SHA.
- Dùng temporary/test branch hoặc workflow validation để xác nhận:
  - PR vào `release/v1.6.9` chạy review + test.
  - push release chạy STG path.
  - tag `v1.6.9` chỉ chạy PROD path có approval.
  - push/PR không thuộc scope không chạy nhầm release deployment.
- Review toàn bộ test cases hiện hữu không bị ảnh hưởng; vì đây là CI/config
  change, không thêm feature test runtime. Theo project gate, chạy affected
  checks và `./vendor/bin/phpunit` nếu môi trường dependency cho phép.
- Chạy `git diff --check` và self-check theo plan trước khi hoàn tất.

## 9. Rollback

- Revert commit workflow nếu trigger/deploy sai.
- Tắt hoặc rollback GitHub Environment deployment protection nếu cấu hình sai.
- Không rollback bằng cách force-push release/prod branch.
- Không xóa release branch đang có artifact hoặc audit trail.

## 10. Acceptance criteria

- Có thể mở đồng thời `release/v1.6.9` và `release/v1.7.0` mà feature không bị
  trộn giữa hai version.
- PR vào `master`, `develop` vẫn nhận đúng CI/review như hiện tại.
- PR vào bất kỳ `release/v*` nào đều nhận thêm đúng test và code review.
- Một release được deploy STG rồi promote PROD từ cùng commit/artifact.
- Full test/review không bị lặp vô ích ở bước promotion.
- PROD không thể deploy tự động ngoài approval policy đã thống nhất.
- Branch protection/ruleset và required checks được ghi nhận rõ, không phụ thuộc
  vào việc người dùng nhớ cấu hình thủ công.

## 11. Implementation result

### Phase 1 — Additive CI/review branch detection

**Status**: `PASS` — đã cập nhật:

- `.github/workflows/unittest.yml`: giữ `master`, `develop`; bổ sung
  `release/v*` cho `pull_request`.
- `.github/workflows/claude-review.yml`: giữ `develop`; bổ sung `release/v*`
  cho `pull_request`.

Không thay đổi job, permissions, draft/Dependabot guard, cache hoặc test command.

Validation:

- Ruby YAML parse: PASS cho cả hai workflow.
- Static audit: PASS; `master`, `develop` vẫn giữ nguyên và `release/v*` đã
  được thêm vào cả PHPUnit/code-review workflow.
- `git diff --check`: PASS.
- `actionlint`: UNAVAILABLE — binary chưa được cài trong môi trường hiện tại.
- `./vendor/bin/phpunit`: đã chạy đủ 630 tests / 9,324 assertions nhưng chưa
  PASS: 2 errors và 3 failures tại `CandidateArchiveTest`, gồm thiếu
  `App\Models\CandidateArchiveLog` và HTTP 405 cho bulk archive. Đây là code/
  route hiện có trong working tree, không nằm trong diff workflow này.

### Phase 2 — STG/PROD promotion

**Status**: `BLOCKED — external deployment contract not present in repository`.

Chưa tạo `.github/workflows/release-promotion.yml` vì chưa xác minh được
deployment command/reusable workflow, GitHub Environment names, artifact store,
required secrets hoặc cơ chế deploy hiện tại. Tạo workflow placeholder sẽ có
nguy cơ báo thành công giả hoặc deploy sai môi trường. Cần bổ sung các thông tin
đó trước khi triển khai phase này.

## 12. Approval gate

Plan đã được user approve. Phase 1 đã được triển khai theo hướng additive;
branch protection/rulesets và phase promotion deploy vẫn chưa được thay đổi.
