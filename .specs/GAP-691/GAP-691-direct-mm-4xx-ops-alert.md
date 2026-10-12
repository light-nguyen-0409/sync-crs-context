# SPEC: GAP-691 — Cảnh báo vận hành khi MatchMaker từ chối direct sync (4xx)

> **Trạng thái**: `DONE` — resolved by configured Slack log threshold; production delivery unverified
> **Ngày tạo**: 2026-09-29
> **Author**: Codex

## 1. Tổng quan

Phase 5 audit xác nhận Permanent intake đã log MatchMaker 4xx bằng `Log::error`, nhưng logging Slack chỉ nhận mức `critical`, nên nhánh direct rejection không được bảo đảm phát ops alert. Plan này đề xuất dùng cùng cơ chế critical logging đã có cho terminal queue failure, giữ nguyên response/API contract, dữ liệu đã commit và chính sách không retry 4xx.

**Yêu cầu gốc**: GAP-691 implementation plan yêu cầu MatchMaker 4xx được ghi nhận/cảnh báo vận hành; phát hiện tại Phase 5 audit.

## 2. Database Design

Không đổi schema hoặc tạo bảng alert/sync state.

## 3. API Contract

Không đổi endpoint, response body, HTTP status hoặc quy tắc retry. Direct MatchMaker 4xx vẫn trả `502`, không enqueue/retry; Candidate GAP đã persist và submit sau vẫn trả `409`.

## 4. Business Logic

1. Trong nhánh `MatchMakerNonRetryableException` của Permanent intake, nâng sự kiện rejection lên critical log để đi theo configured ops logging stack như terminal queue failure.
2. Bao gồm các identifier vận hành an toàn hiện có (Candidate ID, job ID, file ID nếu sẵn có), HTTP status/error class; không log PII, auth/token, payload, CV hoặc Agreement URL.
3. Bảo toàn log hiện tại và semantics của exception/response; không retry lỗi 4xx.
4. Nếu logging channel không cấu hình hoặc Slack delivery thất bại, GAP response vẫn theo contract; ghi rõ deployment channel/webhook là operational prerequisite, không khẳng định alert delivery chỉ từ source.

## 5. Data Origin & Call Chain

```text
MatchMakerService direct request
  → MatchMakerNonRetryableException (4xx)
  → PermanentCandidateIntakeService catch
  → critical log with candidate/job/file context
  → configured Laravel logging stack / Slack handler
```

Candidate/job/file IDs phải lấy từ intake flow đã xác minh ownership trước external call. Error status/class lấy từ exception; không ghi request payload/credentials.

## 6. Constants & Enums

Không dự kiến thêm constants/enums.

## 7. Files dự kiến

| File | Mục đích |
|---|---|
| `app/Services/PermanentCandidateIntakeService.php` | Cập nhật mức/metadata failure log cho nhánh direct 4xx |
| `tests/Unit/Services/PermanentCandidateIntakeServiceTest.php` | Xác nhận 4xx vẫn không enqueue, trả lỗi contract hiện tại và ghi đúng critical event không chứa PII |

Chốt chính xác logger channel sau khi xem test patterns và app logging config trong implementation.

## 8. Test Cases / Acceptance

- 4xx không enqueue/retry; response vẫn là `502`; persisted Permanent data không đổi.
- Logger nhận một sự kiện `critical` với context IDs/status/error class cần thiết.
- Không ghi email, tên, phone, token, MatchMaker payload, CV content/path hoặc Agreement URL.
- Full `LOG_CHANNEL=single ./vendor/bin/phpunit` đạt theo workspace rules.
- Production Slack webhook/channel/alert delivery được xác minh riêng trước release; test không coi source config là bằng chứng deployment.

## 9. Checklist trước khi duyệt

- [x] User updated Slack threshold to `error`; effective Laravel config verified as `error`, with `stack` channels `single,slack`.
- [x] Permanent intake `Log::error` now meets the source-level alert routing requirement when default stack and webhook are active; no runtime/test file modification was needed.
- [ ] Production `LOG_CHANNEL`, `LOG_SLACK_LEVEL`, webhook presence and alert delivery still require deployment verification.
