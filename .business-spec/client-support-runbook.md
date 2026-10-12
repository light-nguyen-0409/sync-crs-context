# Client Support Runbook — GAP Personnel Nexus

> **Trạng thái**: `LIVING_SUPPORT_RUNBOOK`
> **Ngày cập nhật**: 2026-09-22
> **Mục đích**: Hướng dẫn support client theo một quy trình ngắn, có evidence, có kiểm tra business flow và có bước xác nhận sau xử lý.

## 1. Phạm vi và nguồn dữ liệu

Runbook này được xây dựng từ:

- 1.000 message gần nhất trong Slack channel `#gappersonnel-nexus`.
- 485 message của Brian và Simone Blackburn; 325 message được đánh dấu là yêu cầu support.
- 275 thread có reply, tổng cộng 1.420 reply đã được đọc để đối chiếu cách dev support thực tế.
- Business spec hiện tại, route inventory, database relationship và source code của backend.

Tên candidate, email và dữ liệu định danh trong ví dụ đã được lược bỏ. Slack example chỉ chứng minh cách support đã được thực hiện; không thay thế cho việc kiểm tra runtime DB, `api_result_logs`, application log hoặc hệ thống external.

## 2. Quy trình triage nhanh

### 2.1. Evidence bắt buộc phải xin từ client

1. Candidate ID hoặc email đã được mask.
2. Branch, job và consultant/user đang thao tác.
3. Thời điểm lỗi kèm timezone.
4. Màn hình, thao tác ngay trước khi lỗi và exact error message.
5. Screenshot hoặc video nếu là UI issue.
6. HTTP status, request/response từ browser Network nếu có.
7. Với external integration: request time, candidate reference, email/file/payload đã gửi và response nhận được.

### 2.2. Thứ tự kiểm tra

1. Xác định flow: MatchMaker, RTW/GBG, bank/OnePay, file/PDF, email, progress, appointment, access hoặc UI.
2. Đọc dữ liệu nguồn trước: `candidates`, `candidate_jobs`, `jobs`, `branches`, files, progress, answers, appointments, escalated issues và bank account tương ứng.
3. Kiểm tra precondition của flow; không coi trạng thái hiển thị `Completed` là bằng chứng dữ liệu đã hợp lệ.
4. Với MatchMaker, resolve legal entity → API setting → `db_source` (`GAP`/`GAP_EAST`) → current/previous `peo_no` → snapshot `match_maker_candidates`.
5. Tra `api_result_logs` và application log theo cùng một time window. Đọc cả URL, HTTP code, message/body và `extra_info`.
6. Phân loại nguyên nhân: `CODE`, `DATA`, `CONFIG`, `EXTERNAL` hoặc `INFRASTRUCTURE`.
7. Chỉ thực hiện mutation/retry sau khi đã kiểm tra post-state external; không retry MatchMaker khi chưa biết worker hiện tại là record nào.
8. Đóng case khi local state, external state, dependent records và client retest đều xác nhận đúng.

## 3. Query template chỉ đọc

Thay placeholder bằng parameter binding của công cụ DB. Không copy candidate email, token hoặc account number đầy đủ vào Slack. Các query dưới đây chỉ để điều tra; không chạy `UPDATE`, `DELETE` hoặc sửa trực tiếp DB để chữa lỗi nghiệp vụ.

### 3.1. Candidate, job và progress

```sql
SELECT
    c.id,
    c.email,
    c.match_maker_people_number,
    c.prev_match_maker_people_number,
    c.match_maker_status,
    c.progresses,
    c.right_to_work_approval_status,
    c.right_to_work_face_matching_approval_status
FROM candidates c
WHERE c.id = :candidate_id OR c.email = :email;

SELECT
    cj.id,
    cj.candidate_id,
    cj.job_id,
    cj.status,
    cj.progresses,
    cj.contract_document_status,
    cj.updated_at
FROM candidate_jobs cj
WHERE cj.candidate_id = :candidate_id
  AND cj.deleted_at IS NULL
ORDER BY cj.updated_at DESC;
```

### 3.2. Files và escalated issues

```sql
SELECT id, candidate_id, job_id, type, status, expiry_date, converted_file_url, updated_at
FROM files
WHERE candidate_id = :candidate_id
  AND job_id = :job_id
ORDER BY updated_at DESC;

SELECT id, candidate_id, type, status, category, content, updated_at
FROM escalated_issues
WHERE candidate_id = :candidate_id
ORDER BY updated_at DESC;
```

### 3.3. MatchMaker mapping và user branch permission

```sql
SELECT peo_no, email, status, db_source, has_crs_account, updated_at
FROM match_maker_candidates
WHERE email = :email
   OR peo_no = :current_peo_no
   OR peo_no = :previous_peo_no
ORDER BY updated_at DESC;

SELECT user_id, branch_id, match_maker_people_number, roles, permissions
FROM user_branches
WHERE user_id = :user_id AND branch_id = :branch_id;
```

### 3.4. External API log

```sql
SELECT id, api_name, url, type, http_code, message, extra_info, created_at
FROM api_result_logs
WHERE created_at BETWEEN :from_time AND :to_time
  AND (url ILIKE :url_pattern OR message ILIKE :message_pattern)
ORDER BY id DESC;
```

Với MatchMaker, ưu tiên lọc `api_name` theo constant `MATCH_MAKER`. Với GBG hoặc adapter khác, dùng đúng `api_name` của adapter trong source. OnePay mailbox ingestion còn phải kiểm tra application log và Outlook/Graph vì không phải mọi mailbox parsing failure đều có cùng loại API log.

### 3.5. Bank/OnePay

```sql
SELECT id, candidate_id, bank_name, account_name, account_number,
       bank_sort_code, is_uk_bank_account, updated_at
FROM candidate_bank_accounts
WHERE candidate_id = :candidate_id
ORDER BY updated_at DESC;

SELECT id, email, date_of_birth, nationality_code, updated_at
FROM candidates
WHERE id = :candidate_id;
```

### 3.6. Email template và appointment

```sql
SELECT id, type, name
FROM email_templates
WHERE type = :template_type;

SELECT email_template_id, legal_entity_id, branch_id,
       include_header, include_footer, updated_at
FROM email_customs
WHERE email_template_id = :email_template_id
  AND (branch_id = :branch_id
       OR legal_entity_id = :legal_entity_id
       OR (branch_id IS NULL AND legal_entity_id IS NULL));

SELECT id, candidate_id, type, method, location_detail, status, updated_at
FROM appointments
WHERE candidate_id = :candidate_id
ORDER BY updated_at DESC;
```

## 4. Case playbooks

### 4.1. Move candidate sang MatchMaker: Axios 400

**Check**: candidate thuộc đúng branch/job; progress, appointment, approved RTW còn hạn, signed contract/medical và escalated issue đã đúng; sau đó đối chiếu payload với tên, DOB, email, nationality, address, bank và skills.

**API**: `POST /api/consultant/candidates/{id}/match_maker` sau khi đã kiểm tra read-only. Không retry liên tục.

**Log**: `api_result_logs` với `api_name = MATCH_MAKER`, URL `Candidates/RegisterCandidate` hoặc endpoint cuối cùng, HTTP code, body và request context.

**Khắc phục**: nếu dữ liệu ký tự đặc biệt bị external từ chối, sửa qua flow hợp lệ, retry một lần và kiểm tra worker/post-state. Nếu tái hiện với dữ liệu hợp lệ, tạo code/integration ticket.

**Slack example**: Simone báo tên có apostrophe gây Axios 400 khi move sang MM ngày 21/09/2026; dev loại bỏ ký tự, sau đó client xác nhận.

### 4.2. MatchMaker báo `worker not found`

**Check**: branch → legal entity → `db_source`; kiểm tra `match_maker_people_number`, `prev_match_maker_people_number` và `match_maker_candidates` theo email + `db_source` + `peo_no`. Tra endpoint cuối cùng trong `api_result_logs` và kiểm tra worker trực tiếp trên đúng MM database trước khi retry.

**Command**: `candidates:sync-matchmaker-status` chỉ dùng sau khi xác định mapping và cấu hình sync phù hợp; command này không thay thế việc xác minh worker.

**Khắc phục**: dùng `peo_no` hiện tại, sửa snapshot/local mapping qua service, kiểm tra external worker rồi mới retry. Không dùng `peo_no` cũ đã bị merge/delete.

**Slack example**: Simone xác nhận `63543` là record cũ đã merge vào `71849`; support chuyển sang cập nhật worker `71849`. Đây là case khớp với `SPEC-031`.

### 4.3. `No user branch information` hoặc không có quyền gửi MM

**Check**: `user_branches` theo `user_id + branch_id`; kiểm tra `match_maker_people_number`, roles/permissions và branch/legal entity. Đây là lỗi mapping user/branch, không phải lỗi candidate.

**API/log**: kiểm tra context của `POST /api/consultant/candidates/{id}/match_maker` và application log; chưa cần gọi external khi mapping local chưa đạt.

**Khắc phục**: bổ sung/sửa mapping qua admin flow có audit. Không sửa `candidate.match_maker_people_number` để che lỗi quyền consultant.

**Slack example**: Brian báo lỗi cho hai candidate ngày 15/09/2026; thread chưa có dev response, nên case này vẫn phải coi là chưa xác định nguyên nhân.

### 4.4. RTW expired, REFER, low face-match hoặc thiếu file

**Check**: journey type, validated file, file status, `expiry_date`, passport/share-code result, face-match rate, candidate name/DOB và unresolved escalated issue. REFER/low score không được tự động approve.

**API**: đọc `GET /api/consultant/candidates/{id}/face_matching_rates/{type}` và file endpoints; recheck passport/share code theo journey tương ứng.

**Command**: `files:expire-rtw` là batch expiry, không chạy để chữa riêng một candidate. `candidate:update-progress` chỉ chạy sau khi source state đã được xác minh và có approval.

**Khắc phục**: yêu cầu tài liệu mới/recheck, sửa expiry qua flow compliance, xử lý issue và cập nhật progress bằng service. Không chỉ reset status để làm xanh màn hình.

**Slack example**: thread ngày 21/03/2024 cho thấy support chạy face match và trả score; đây là evidence tốt hơn việc chỉ trả lời “done”.

### 4.5. Financial information stuck hoặc GBG bank check lỗi

**Check**: candidate address, account name, sort code/account number format, duplicate account, bank support, GBG result, name/address mismatch và escalated issue. Account number đầy đủ không nên đưa vào Slack.

**API**: candidate dùng `POST /api/candidate/me/bank_account/submit_financial_info`; consultant đọc candidate/issue endpoints. Không submit thay candidate nếu chưa có quyền.

**Log**: GBG request/response, `api_result_logs`, application log và issue log.

**Khắc phục**: sửa dữ liệu nguồn hoặc yêu cầu proof bank khi bank không hỗ trợ automatic check; resolve issue sau khi có evidence. Không set financial progress `Completed` chỉ vì UI đang bị kẹt.

**Slack example**: Brian hỏi wording của các GBG error ngày 20/08/2026; Simone báo financial info bị `In Progress` ngày 05/08/2026 và dev hoàn tất thủ công. Workaround đã giải quyết client nhưng cần kiểm tra nguyên nhân Edit làm progress quay lại `In Progress`.

### 4.6. OnePay account chưa trả về hoặc không cập nhật CRS

**Check**: candidate request time, payload đã gửi, Outlook/Graph message, subject có candidate number, body có đúng candidate email, DOB/name/address có khớp và candidate bank row hiện tại.

**API/command**: flow bắt đầu từ `POST /api/candidate/me/bank_account/submit_financial_info`. Có thể reprocess có giới hạn bằng:

```bash
php artisan onepay:get YYYY-MM-DD YYYY-MM-DD
```

Batch thường dùng:

```bash
php artisan runBatchProcess:GatherAlternativeBankAccountInformationFromMails
```

Đây là command có mutation; phải kiểm tra duplicate và date range trước khi chạy.

**Khắc phục**: đối chiếu request/response với OnePay, sửa external data hoặc liên hệ vendor; manual bank correction phải có audit. Financial progress chỉ hoàn tất khi account response hợp lệ đã được lưu.

**Slack example**: ngày 16/09/2026 support kiểm tra request đã gửi nhưng Outlook chưa có return; ngày 07/08/2026 email OnePay thiếu candidate number và DOB mismatch, nên support tạo bank account thủ công rồi liên hệ OnePay.

### 4.7. PDF parser, compression hoặc document không sang MM

**Check**: candidate/job scope, file type/status, MIME/size, storage URL, `converted_file_url`, compression method và MM attachment log.

**API**: upload/status theo `POST /api/consultant/candidates/{id}/jobs/{jobId}/files/{type}` và status endpoint tương ứng.

**Command**: `application-pack:generate {candidateId} {userId}` chỉ dùng trong controlled context; command hiện có default branch/nationality/ethnicity nên không dùng như general production fix.

**Khắc phục**: yêu cầu `Save as`/export lại PDF, upload lại đúng job, xác nhận file metadata và MM attachment; nếu lặp lại, tạo parser ticket.

**Slack example**: Simone báo PDF parser ngày 11/09/2026; support yêu cầu export lại và tham chiếu GAP-711. Một case khác xác định PDF bị Adobe compression.

### 4.8. Email hiển thị sai branch address/map

**Check**: appointment method, `location_detail`, template type, branch/legal-entity/master precedence, `include_footer` và nội dung email nhận được.

**Khắc phục**: sửa logic render/footer hoặc template có scope đúng; test remote/client-site/in-branch riêng. Không chỉ sửa text `{interview_address}` nếu footer chung vẫn render branch address.

**Slack example**: Simone báo client-site email vẫn có Branch Map/Address ngày 19/08/2026. Source hiện tại truyền client location nhưng `MailSenderAccessor` luôn thêm branch information và mail base luôn render footer.

### 4.9. Progress stuck, locked hoặc cần unlock

**Check**: candidate progress và candidate-job progress; source records tương ứng; lock state; bank/RTW/file/issue/appointment. Progress là kết quả của source state, không phải source of truth duy nhất.

**API/command**: đọc `GET /api/consultant/progresses/{candidateId}/{jobId}` trước. Mutation route là `PUT /api/consultant/progresses/{candidateId}/{jobId}/{type}`. Command manual:

```bash
php artisan candidate:update-progress EMAIL PROGRESS_NAME STATUS
```

Command này thay đổi dữ liệu trực tiếp qua service; chỉ dùng sau khi đã có evidence và approval.

**Khắc phục**: sửa source record, gọi recalculation/update qua service, sau đó verify UI và dependent flow. Unlock chỉ khi xác định lock là ngoài ý muốn.

**Slack example**: Simone báo financial info còn `In Progress` dù data hợp lệ và candidate bị lock; support hoàn tất thủ công nhưng cũng phát hiện click Edit có thể làm progress quay lại `In Progress`.

### 4.10. Appointment Save không phản hồi hoặc re-registration flow lỗi

**Check**: browser Network response, appointment payload, candidate job status, snapshot/file tồn tại và candidate có thực sự từng đi qua CRS hay chưa.

**API**: `POST/PUT /api/consultant/candidates/{id}/appointments` và appointment ID tương ứng.

**Khắc phục**: sửa source/workflow hoặc tạo snapshot đúng rule; không mặc định bỏ qua re-registration nếu chưa xác minh. Sau đó kiểm tra appointment row và client retest.

**Slack example**: ngày 22/01/2026, Save interview không chạy vì candidate re-reg nhưng chưa từng có file trong CRS để snapshot; support dùng workaround ignore re-reg và ghi nhận cần fix.

### 4.11. Skills hiển thị `No Options`

**Check**: environment, branch/legal entity, response của MatchMaker skills endpoint. Consultant route hiện có `GET /api/consultant/skills/stored_skills`, nhưng source comment cho biết skills đang lấy trực tiếp từ MatchMaker thay vì local DB.

**Khắc phục**: kiểm tra MatchMaker/config/data source và deploy hotfix nếu lỗi; không tự seed local `skills` table trước khi xác nhận code đang đọc nguồn nào.

**Slack example**: Brian báo `No Options` ngày 15/11/2023; support phát hiện production local skills table rỗng trong khi flow đọc MatchMaker và tạo hotfix.

### 4.12. Portal, tag hoặc quyền consultant

**Check**: user/branch mapping, exact API response, browser Network, pagination/filter và candidate ownership. Tag issue cần xác định là FE hay BE trước khi sửa DB.

**API**: `GET /api/consultant/branches`, candidate endpoints, `POST /api/consultant/tags/candidate` và tag GET endpoint.

**Khắc phục**: reproduce bằng account/branch tương đương, giữ video/network evidence và tạo FE/BE ticket; không sửa trực tiếp pivot/tag khi chưa xác định request contract.

**Slack example**: Brian báo tag Invite Candidate không attach/remove ngày 10/09/2026; reply đã route cho FE reproduce và hotfix, nhưng chưa có evidence closure trong thread.

### 4.13. Login/IP history hoặc yêu cầu audit không có dữ liệu

**Check**: xác định hệ thống có lưu `authentication_logs` cho loại event cần tìm hay không, thời gian retention và dữ liệu thực tế.

**Khắc phục**: nếu không có historical record, trả lời rõ `UNVERIFIED/NOT STORED`, không suy diễn từ IP hiện tại. Chuyển thành feature/audit-log request nếu client cần lịch sử lâu dài.

**Slack example**: Simone hỏi IP login history ngày 24/07/2026; support cung cấp dữ liệu hiện có nhưng xác nhận hệ thống chưa lưu lịch sử login đầy đủ.

## 5. Command safety

| Command | Dùng khi nào | Cảnh báo |
|---|---|---|
| `candidate:update-progress` | Sau khi source state đã đúng và có approval | Mutation; không dùng để che lỗi dữ liệu |
| `onepay:get FROM TO` | Reprocess mailbox trong date range hẹp | Có thể upsert bank data; kiểm tra duplicate trước |
| `runBatchProcess:GatherAlternativeBankAccountInformationFromMails` | Batch OnePay thông thường | Không chạy để chữa một case chưa xác định |
| `candidates:sync-matchmaker-status` | Đồng bộ trạng thái MM khi config đã bật | Không sửa mapping `peo_no` một cách mù quáng |
| `files:expire-rtw` | Batch expiry RTW | Không chạy cho riêng một candidate |
| `application-pack:generate` | Controlled repair/test của application pack | Source command có default context; cần review trước khi chạy |
| `candidates:reset-documents` | Không dùng hiện tại | Command đang return sớm, bị disable trong source |
| `matchmaker:save-contact-logs` | Không dùng để kết luận đã sync | Method gọi thật đang bị comment trong command |

## 6. Reply template để đóng support case

Mỗi reply support nên ghi đủ:

```text
CASE:
SCOPE: candidate / branch / job / time
CLASSIFICATION: CODE | DATA | CONFIG | EXTERNAL | INFRASTRUCTURE
EVIDENCE: DB row / API status / log ID / external response
ROOT CAUSE:
ACTION TAKEN:
POST-STATE: local status + external status + dependent records
CLIENT RETEST:
FOLLOW-UP/TICKET:
```

Không dùng “Done” làm bằng chứng duy nhất. Nếu chưa có runtime evidence, ghi rõ `UNVERIFIED` và nêu chính xác evidence còn thiếu.

## 7. Known deviations cần theo dõi

1. Client-site interview email: branch footer/map đang được inject/render chung dù appointment location là client site.
2. OnePay: mailbox parser phụ thuộc candidate number trong subject và candidate email trong body; financial progress có thể được set completed ngay sau khi gửi request.
3. GBG bank validation: source hiện kiểm tra `sortCode` thay vì `accountNumber` ở một nhánh format validation.
4. MatchMaker: local candidate có thể được cập nhật trước khi application pack transfer hoàn tất; cần kiểm tra partial state trước retry.
5. Một số support workaround sửa status/progress trực tiếp nhưng chưa luôn ghi lại root cause, log và post-state.

## 8. Tài liệu nguồn

- [backend-business-flow-spec.md](backend-business-flow-spec.md)
- [backend-api-route-inventory.md](backend-api-route-inventory.md)
- [backend-database-relationship.md](backend-database-relationship.md)
- [app/Services/MatchMakerService.php](../app/Services/MatchMakerService.php)
- [app/Services/OnepayService.php](../app/Services/OnepayService.php)
- [app/Services/GBGBankCheckService.php](../app/Services/GBGBankCheckService.php)
- [app/Services/RegistrationProgressService.php](../app/Services/RegistrationProgressService.php)
- [app/Services/AppointmentService.php](../app/Services/AppointmentService.php)
- [app/Facades/MailSenderAccessor.php](../app/Facades/MailSenderAccessor.php)
