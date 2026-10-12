# CRS – MatchMaker – CRM: hiện trạng dữ liệu và tích hợp

> **Trạng thái**: `LIVING_SPEC`
> **Loại tài liệu**: `CODE_FACT` hiện trạng và `PROPOSAL` cho hướng thiết kế tương lai
> **Đối chiếu source gần nhất**: 2026-09-29
> **Cập nhật ERD GAP-691**: 2026-10-05 — bỏ `work_finder_agreement_url` khỏi branches/legal_entities theo forward migration; schema production chưa xác minh, xem [database relationship](backend-database-relationship.md).
> **Phạm vi**: CRS backend hiện tại, tích hợp MatchMaker và các điểm cần chốt khi thiết kế CRM

Tài liệu này mô tả cách CRS đang quản lý dữ liệu Candidate/User và cách đồng bộ
với MatchMaker. Phần thiết kế CRM, identity dùng chung và SSO ở cuối tài liệu
là đề xuất để thảo luận, không phải hành vi đang được triển khai.

## 1. Kết luận điều hành

CRS đang quản lý hai nhóm identity khác nhau:

- `User`: nhân sự nội bộ như Consultant, Compliance và Admin.
- `Candidate`: ứng viên/người lao động bên ngoài.

MatchMaker hiện chưa được kết nối bằng một pipeline đồng bộ duy nhất. Các flow
hiện tại gồm:

1. **CRS → MatchMaker – Candidate thường**: Consultant chủ động gọi API chuyển
   Candidate sang MatchMaker.
2. **CRS → MatchMaker – Permanent Candidate**: CRS lưu hồ sơ, gọi MatchMaker
   trực tiếp, upload CV qua contact log; lỗi transient mới đưa vào queue retry.
3. **MatchMaker → CRS**: scheduler polling status, marketing preference và
   `on_plan` theo từng database source.
4. **Snapshot/duplicate**: CRS lưu bản snapshot `match_maker_candidates` để
   tìm duplicate, import và hỗ trợ mapping. Bảng này không có FK trực tiếp tới
   `candidates`.

CRS và MatchMaker hiện cũng chưa dùng chung authentication/session. Candidate
nhận JWT của CRS (`candidateApi`); CRS gọi MatchMaker bằng Basic Authentication
server-to-server. OTP, NI và profile-image verification hiện tại là cơ chế
xác minh duplicate, không phải SSO.

## 2. Hai loại identity trong CRS

| Đối tượng | Bảng/guard | Dữ liệu chính | Phạm vi sử dụng |
|---|---|---|---|
| User nội bộ | `users`, `userApi` | Email, password, roles, permissions, profile, branch access, MM consultant number trên `user_branches` | Consultant, Compliance, Admin |
| Candidate | `candidates`, `candidateApi` | Account, profile, application, compliance, progress, documents, MatchMaker mapping | Ứng viên/người lao động |

Các route/guard hiện tại:

- User auth/me: [routes/user.php](../routes/user.php#L23)
- Candidate auth/me/jobs/files: [routes/candidate.php](../routes/candidate.php#L45)
- User model: [app/Models/User.php](../app/Models/User.php#L34)
- Candidate model: [app/Models/Candidate.php](../app/Models/Candidate.php#L171)

Khi nói về đồng bộ CRS–CRM–MatchMaker cần chốt trước CRM phục vụ User nội bộ,
Candidate, hay cả hai. Các phần còn lại tập trung vào Candidate vì MatchMaker
integration hiện tại chủ yếu xoay quanh Candidate.

## 3. Các nhóm dữ liệu Candidate CRS đang quản lý

| Nhóm dữ liệu | Nơi lưu | Nội dung chính | Vai trò hiện tại |
|---|---|---|---|
| Account/authentication | `candidates`, `candidate_tokens` | Email, password hash, status, token | CRS quản lý; không gửi password sang MM |
| Personal profile | `candidates` | Title, first/middle/last name, DOB, phone, gender | CRS nhập/lưu; một phần map sang MM |
| Legal/RTW | `candidates`, `files` | Journey type, nationality, NI, RTW status, expiry, reviewer, evidence | CRS quản lý workflow/compliance |
| Application | `candidate_jobs` | Candidate–job, status, progress, contract status, `job_ref`, UTM | CRS quản lý theo từng job |
| Job context | `jobs`, `branches`, `legal_entities` | Job, branch, legal entity, external IDs | Xác định application context và MM API/database |
| Address | `candidate_addresses` | Building, street, town/city, county, postcode | CRS lưu; map sang MM |
| Answers | `answers`, `questions`, `answer_options` | Transport, travel distance, recruitment source, consent và screening answers | CRS lưu; một phần map sang MM |
| Documents | `files` + storage | CV, RTW, passport, address proof, bank proof, profile image, contract | CRS/storage giữ metadata và file; MM nhận bản cần thiết |
| Employment history | `employment_histories` | Employment và education history | CRS quản lý; standard flow có thể gửi MM |
| Workflow/audit | `appointments`, `escalated_issues`, `activity_logs` | Interview, issues, contact history, audit | CRS quản lý |
| Timing | `candidate_timings` | MM timing, contract timing, Agreement click time/IP | CRS lưu metric/audit |
| MatchMaker linkage | `candidates` | `match_maker_people_number`, status, previous number | External ID/status được lưu lại ở CRS |
| MatchMaker snapshot | `match_maker_candidates` | `peo_no`, email, name, DOB, NI, status, `db_source`, `has_crs_account` | Snapshot/cache phục vụ duplicate/search/import |

## 4. Quan hệ dữ liệu chính

~~~mermaid
flowchart LR
    U[User nội bộ] --> UB[User Branch]
    UB --> B[Branch]

    C[Candidate] --> CJ[Candidate Job]
    CJ --> J[Job]
    J --> B
    B --> LE[Legal Entity]

    C --> A[Candidate Address]
    C --> ANS[Answers]
    C --> F[Files + Storage]
    C --> EH[Employment Histories]
    C --> AP[Appointments]
    C --> EI[Escalated Issues]
    C --> AL[Activity Logs]
    C --> CT[Candidate Timings]

    C --> ML[MM people number/status]
    MMC[match_maker_candidates snapshot] -. email / peo_no / db_source .-> MM[MatchMaker]
~~~

Các điểm cần giữ đúng khi thiết kế CRM:

- Một Candidate có thể có nhiều `candidate_jobs`.
- Branch và Legal Entity được suy ra qua Job của Candidate.
- Legal Entity quyết định MatchMaker database source/API (`GAP` hoặc
  `GAP_EAST`).
- `match_maker_candidates` hiện không có `candidate_id`; mapping chủ yếu dùng
  email, `peo_no` và `db_source`.
- `peo_no` là định danh do MatchMaker sinh sau khi đăng ký thành công.

Chi tiết quan hệ: [backend-database-relationship.md](backend-database-relationship.md#L351).

### 4.1. ERD database hiện tại – các bảng nghiệp vụ chính

Sơ đồ dưới đây tập trung vào các bảng chính phục vụ Candidate, application,
workflow, compliance và MatchMaker. Quan hệ dotted tới
`match_maker_candidates` là **logical mapping**, không phải foreign key thật.

~~~mermaid
erDiagram
    USERS ||--o{ USER_BRANCHES : assigned
    BRANCHES ||--o{ USER_BRANCHES : grants
    LEGAL_ENTITIES ||--o{ BRANCHES : owns
    BRANCHES ||--o{ JOBS : publishes

    CANDIDATES ||--o{ CANDIDATE_JOBS : applies
    JOBS ||--o{ CANDIDATE_JOBS : receives

    CANDIDATES ||--o| CANDIDATE_ADDRESSES : has
    CANDIDATES ||--o| CANDIDATE_BANK_ACCOUNTS : has
    CANDIDATES ||--o{ CANDIDATE_SKILLS : selects
    CANDIDATES ||--o{ FILES : owns
    JOBS ||--o{ FILES : scopes
    CANDIDATES ||--o{ CANDIDATE_TIMINGS : measures
    JOBS ||--o{ CANDIDATE_TIMINGS : scopes

    CANDIDATES ||--o{ ANSWERS : submits
    QUESTIONS ||--o{ ANSWERS : receives
    ANSWER_OPTIONS ||--o{ ANSWERS : selected_by

    CANDIDATES ||--o{ APPOINTMENTS : attends
    USERS ||--o{ APPOINTMENTS : conducts
    BRANCHES ||--o{ APPOINTMENTS : hosts
    CANDIDATE_JOBS ||--o{ CANDIDATE_JOB_APPOINTMENTS : links
    APPOINTMENTS ||--o{ CANDIDATE_JOB_APPOINTMENTS : links

    CANDIDATES ||--o{ EMPLOYMENT_HISTORIES : owns
    CANDIDATES ||--o{ ESCALATED_ISSUES : has
    USERS ||--o{ ESCALATED_ISSUES : creates_or_assigns
    CANDIDATES ||--o{ ACTIVITY_LOGS : generates
    JOBS ||--o{ ACTIVITY_LOGS : scopes
    USERS ||--o{ ACTIVITY_LOGS : performs

    CANDIDATES ||--o{ CANDIDATE_SNAPSHOTS : snapshots
    CANDIDATES ||--o| MATCH_MAKER_DUPLICATION_PROCESSES : verifies
    CANDIDATES ||--o{ CANDIDATE_WELFARE_CHECKS : checks
    USERS ||--o{ CANDIDATE_WELFARE_CHECKS : performs
    FILES ||--o{ CANDIDATE_WELFARE_CHECKS : image_or_certificate

    CANDIDATES }o..o{ MATCH_MAKER_CANDIDATES : logical_email_peo_no_db_source

    USERS {
        bigint id PK
        string email
        json roles
        json permissions
        boolean can_access_all_branches
    }
    USER_BRANCHES {
        bigint user_id FK
        bigint branch_id FK
        json roles
        string match_maker_people_number
    }
    LEGAL_ENTITIES {
        bigint id PK
        string name
    }
    BRANCHES {
        bigint id PK
        bigint legal_entity_id FK
        string external_id
        string name
    }
    JOBS {
        bigint id PK
        bigint branch_id FK
        string external_id
        string title
    }
    CANDIDATES {
        bigint id PK
        string email
        string status
        string journey_type
        string match_maker_people_number
        string match_maker_status
        boolean is_permanent
        json progresses
        string right_to_work_approval_status
    }
    CANDIDATE_JOBS {
        bigint id PK
        bigint candidate_id FK
        bigint job_id FK
        string status
        json progresses
    }
    CANDIDATE_ADDRESSES {
        bigint id PK
        bigint candidate_id FK
        string postcode
    }
    CANDIDATE_BANK_ACCOUNTS {
        bigint id PK
        bigint candidate_id FK
        string account_number
        string bank_sort_code
    }
    CANDIDATE_SKILLS {
        bigint id PK
        bigint candidate_id FK
        bigint skill_id
    }
    FILES {
        bigint id PK
        bigint candidate_id FK
        bigint job_id FK
        string type
        string status
        string url
        date expiry_date
    }
    CANDIDATE_TIMINGS {
        bigint id PK
        bigint candidate_id FK
        bigint job_id FK
        datetime work_finder_agreement_link_clicked_at
        string work_finder_agreement_link_clicked_ip
    }
    QUESTIONS {
        bigint id PK
        string category
    }
    ANSWER_OPTIONS {
        bigint id PK
        bigint question_id FK
        string value
    }
    ANSWERS {
        bigint id PK
        bigint candidate_id FK
        bigint question_id FK
        bigint answer_option_id
        text answer
    }
    APPOINTMENTS {
        bigint id PK
        bigint candidate_id FK
        bigint user_id FK
        bigint branch_id FK
        string type
        string status
    }
    CANDIDATE_JOB_APPOINTMENTS {
        bigint candidate_job_id FK
        bigint appointment_id FK
    }
    EMPLOYMENT_HISTORIES {
        bigint id PK
        bigint candidate_id FK
        string history_type
        string job_title
    }
    ESCALATED_ISSUES {
        bigint id PK
        bigint candidate_id FK
        bigint creator_user_id FK
        bigint assignee_user_id FK
        string status
    }
    ACTIVITY_LOGS {
        bigint id PK
        bigint candidate_id FK
        bigint job_id FK
        bigint user_id FK
        string type
    }
    CANDIDATE_SNAPSHOTS {
        bigint id PK
        bigint candidate_id FK
        text data
        text raw_data
    }
    MATCH_MAKER_DUPLICATION_PROCESSES {
        bigint id PK
        bigint candidate_id FK
        boolean token_verified
        boolean confirmed
    }
    CANDIDATE_WELFARE_CHECKS {
        bigint id PK
        bigint candidate_id FK
        bigint consultant_user_id FK
        bigint certificate_file_id FK
        decimal facematch_score
    }
    MATCH_MAKER_CANDIDATES {
        bigint id PK
        string peo_no
        string email
        string status
        string db_source
        boolean has_crs_account
    }
~~~

Full ERD được tách theo nhóm tại
[backend-database-relationship.md](backend-database-relationship.md): core
candidate/job, question/appointment/issue, employment/invitation/tag và
MatchMaker/audit.

## 5. Luồng signup và apply job hiện tại

~~~mermaid
sequenceDiagram
    participant FE as Candidate Frontend
    participant CRS as CRS
    participant Snapshot as MM Snapshot

    FE->>CRS: POST /candidate/auth/signup
    CRS->>CRS: Tạo Candidate và candidate token
    CRS->>CRS: Đọc invitation cookie: branch/job/job_ref/source
    CRS->>CRS: Transfer dữ liệu invitation
    CRS->>Snapshot: Tìm snapshot theo email
    Snapshot-->>CRS: Nếu có, set has_crs_account=true
    CRS-->>FE: Trả candidateApi JWT

    FE->>CRS: POST /candidate/me/jobs
    CRS->>CRS: Resolve external job/branch
    CRS->>CRS: Tạo candidate_job
    CRS-->>FE: Trả application/job context
~~~

`POST /candidate/auth/signup` tạo tài khoản CRS và token. Nó không tạo tài khoản
mới trong MatchMaker; nếu có snapshot cùng email thì chỉ cập nhật
`has_crs_account`.

Source:

- [AuthController::signup](../app/Http/Controllers/Api/Candidate/AuthController.php#L32)
- [CandidateService::signUp](../app/Services/CandidateService.php#L243)
- [MeJobController::add](../app/Http/Controllers/Api/Candidate/MeJobController.php#L47)

## 6. CRS → MatchMaker: Candidate thường

Trigger hiện tại:

~~~text
POST /api/consultant/candidates/{candidateId}/match_maker
~~~

~~~mermaid
sequenceDiagram
    participant Staff as Consultant
    participant CRS as CRS
    participant MM as MatchMaker

    Staff->>CRS: POST candidate/{id}/match_maker
    CRS->>CRS: Kiểm tra branch access và readiness
    CRS->>CRS: Load profile, job, address, answers
    CRS->>CRS: Load interview, bank, employment history
    CRS->>CRS: Kiểm tra duplicate
    CRS->>MM: Candidates/RegisterCandidate
    MM-->>CRS: Trả peo_no
    CRS->>MM: Upload profile image
    CRS->>MM: Upload RTW files
    CRS->>MM: Upload answers/contact logs/files
    CRS->>CRS: Lưu peo_no và status=live
    CRS->>CRS: Update candidate_job=matchmaker
    CRS-->>Staff: Kết quả đồng bộ
~~~

Payload standard hiện map các nhóm chính:

| CRS | MatchMaker |
|---|---|
| Title, first/middle/last name | `peo_title`, `peo_forename`, `peo_middlename`, `peo_surname` |
| Email, DOB, phone | `peo_email`, `peo_date_birth`, `peo_other_tel` |
| Address | `peo_establish`, `peo_town`, `peo_county`, `peo_postcode` |
| Job title | `peo_seek` |
| Consultant branch mapping | `peo_con` |
| Gender, nationality, NI | `peo_gender`, `peo_nationality`, `peo_ni` |
| Bank information | MM bank fields |
| Answers | Source, marketing/GDPR, transport, travel, health, shift |
| Files | Profile image, RTW, contact log, additional documents |

Trước khi gửi outbound payload, CRS xử lý `first_name`, `middle_name` và
`last_name` ở boundary MatchMaker: ký tự ngay sau ASCII apostrophe (`'`) hoặc
right single quotation mark (`’`) được viết hoa, sau đó dấu nháy bị loại bỏ.
Ví dụ `O'nel` được gửi thành `ONel`. Tên gốc trong CRS không bị mutate. Quy tắc
này áp dụng cho standard/Permanent registration và các standard duplicate
update/check-duplicate payload dùng lại mapping đó.

Đây là flow synchronous trong request của Consultant, không dùng queue chung.

Source:

- [consultant.php](../routes/consultant.php#L68)
- [CandidateController::sendCandidateToMatchMaker](../app/Http/Controllers/Api/Consultant/CandidateController.php#L408)
- [MatchMakerService::sendCandidateToMatchMaker](../app/Services/MatchMakerService.php#L333)
- [MatchMakerService::getCandidateParams](../app/Services/MatchMakerService.php#L916)

## 7. CRS → MatchMaker: Permanent Candidate

Current source (GAP-691/007 §17–21, 2026-10-09; deployment unverified):

1. Candidate submits PermanentCandidateIntakeRequest; Laravel validates it before the Controller passes the concrete Request to Intake Service.
2. Service builds the complete runtime DTO, validates business rules and writes profile/address/answers in a write-only transaction; is_permanent remains false.
3. After commit, Service directly enqueues SyncPermanentCandidateToMatchMakerJob on Redis/default with immutable scalar/value DTOs and returns HTTP202 pending. There is no Permanent submit Event/Listener registration or submission-status table.
4. Worker acquires the candidate lock, builds fresh loaded records and validates common ownership/CV/Agreement rules. Completed candidates exit before processing. It generates/reuses the snapshot PDF, then MM checks required record associations/entity/form without repeating CV/Agreement validation.
5. MM registers PERM, uploads CV -> Agreement -> generated form contact-log attachments and saves peo_no/match_maker_status=perm. Only successful processing permits completion to set is_permanent=true on the loaded Candidate.
6. Background transient failures retry; non-retryable/state/render errors fail immediately and cannot complete the candidate. Enqueue failure returns HTTP502 after local persistence; background failures do not change the already returned HTTP202. No SELECT occurs after the worker build. Independent scalar MM calls retain full entry validation.
7. New deployment has no old payloads: custom deserialization conversion is removed; Laravel SerializesModels restores typed Jobs normally. Snapshot identity/storage reuse and queue retry settings remain.

~~~mermaid
sequenceDiagram
    participant FE as Candidate FE
    participant CRS as CRS API
    participant Q as Redis default
    participant W as Worker
    participant MM as MatchMaker
    FE->>CRS: POST /candidate/me/permanent-intake
    CRS->>CRS: Build DTO, validate, save profile/address/answers
    CRS->>Q: Enqueue typed Job after commit
    CRS-->>FE: 202 pending
    Q->>W: Restore typed Job
    W->>W: Lock, build context, validate, generate/reuse PDF
    W->>MM: Register PERM and upload CV/Agreement/form
    alt Success
        MM-->>W: peo_no and successful attachments
        W->>W: Save MM status and complete candidate
    else Failure
        W->>Q: Retry transient failure or fail non-retryable
    end
~~~

Source: [Intake Service](../app/Services/PermanentCandidateIntakeService.php), [Permanent Job](../app/Jobs/SyncPermanentCandidateToMatchMakerJob.php), [MatchMaker Service](../app/Services/MatchMakerService.php). Current-flow baseline: [Backend business flow](backend-business-flow-spec.md).

## 8. MatchMaker → CRS

Các scheduled command hiện tại:

| Cron | Dữ liệu/field từ MatchMaker | Field/bảng CRS được cập nhật | Mục đích nghiệp vụ |
|---|---|---|---|
| `candidates:sync-matchmaker-status` | `Id` = MatchMaker people number (`peo_no`); `Value` = status MM (`LIVE`, `PERM`, `DNU`, `RE REG NEEDED`, `EXPIRED`, ...) | `match_maker_candidates.status` lưu raw status theo `peo_no + db_source`; `candidates.match_maker_status` lưu status nội bộ dạng lowercase | Đồng bộ trạng thái MM về CRS để filter/search, kiểm soát thao tác khi candidate đã ở MM và phát hiện candidate cần re-registration |
| `candidates:sync-marketing-preference` | `Id` = `peo_no`; `Value` = boolean marketing consent | `answers.answer` của question category `marketing` thành `['agree']` hoặc `['disagree']`; cập nhật `answers.answered_at` | Lưu consent marketing để lọc SMS và dùng làm `peo_gdpr_consenttomarketing` khi CRS gửi candidate sang MM |
| `candidates:sync-onplan` | `Id` = `peo_no`; `Value` là client name nhưng hiện không được sử dụng | `candidates.on_plan = true` cho candidate có trong danh sách; các candidate khác đang `true` được reset về `false` | Đánh dấu candidate đang có plan để loại khỏi SMS campaign; SMS còn kiểm tra on-plan real-time với MM cho candidate phù hợp |

### 8.1. Chi tiết mapping và side effect

Các cron không đồng bộ toàn bộ profile candidate như tên, email, số điện thoại,
ngày sinh, địa chỉ, RTW, files hoặc jobs. Chúng chỉ đồng bộ ba nhóm dữ liệu ở
bảng trên. Cả ba command đều bị bỏ qua khi `MATCHMAKER_SYNC_STATUSES=false`.

**Status**

- API `GetCandidatesByStatusDate?dt=YYYY-MM-DD` trả các cặp `Id`/`Value` cho
  từng database source.
- CRS cập nhật snapshot `match_maker_candidates.status` bằng raw status và map
  sang `candidates.match_maker_status` theo mapping local (`LIVE -> live`,
  `PERM -> perm`, `RE REG NEEDED -> rrr`, ...).
- Nếu status local là `rrr` và job tiến triển cao nhất đang ở trạng thái
  `matchmaker`, CRS set `candidates.reset_required=true` rồi gửi thông báo cho
  branch kèm email candidate.

**Marketing preference**

- API `GetMarketingUpdates?sinceDate=YYYY-MM-DD` trả `Id`/`Value`; trước 05:00
  command dùng ngày hôm trước, các thời điểm khác dùng ngày hiện tại.
- CRS tìm question có category `marketing`, rồi tạo hoặc cập nhật answer theo
  candidate. Nếu giá trị không thay đổi thì không ghi lại.
- Candidate không có answer hoặc có `disagree` sẽ bị loại khỏi danh sách SMS.
  Khi build payload gửi candidate sang MM, answer `agree` được map thành
  `peo_gdpr_consenttomarketing=true`.

**On-plan**

- API `GetCandsOnPlan?startDate=YYYY-MM-DD` trả `Id`/`Value`; CRS chỉ dùng
  `Id` để map candidate, không lưu `Value`/client name.
- Sau khi set các candidate có plan thành `true`, command reset các candidate
  còn lại đang `on_plan=true` về `false`.
- Đây là flag cache phục vụ lọc SMS; không nên coi `on_plan=false` là bằng
  chứng tuyệt đối candidate không còn plan vì SMS có thêm bước kiểm tra real-time.

**Database source và định danh**

- MM được gọi riêng cho `GAP` và `GAP_EAST`.
- CRS tìm candidate bằng `match_maker_people_number`, sau đó kiểm tra
  `db_source` từ Legal Entity của branch thuộc job tiến triển cao nhất.
- `match_maker_candidates` không có FK trực tiếp tới `candidates`; status
  snapshot dùng `peo_no + db_source`, còn candidate local dùng
  `match_maker_people_number`.

**Lưu ý vận hành hiện tại**

- Nếu API on-plan trả danh sách rỗng do lỗi external, command hiện vẫn chạy
  bước reset `on_plan` toàn cục. Vì vậy một candidate bị chuyển thành
  `on_plan=false` chưa đủ chứng minh MM không có plan; cần kiểm tra
  `api_result_logs` và response của cả `GAP`/`GAP_EAST`.
- Các response external và lỗi command được append vào
  `/var/log/laravel-schedule.log`; chi tiết external nằm trong
  `api_result_logs`.

Lịch mặc định:

- Status: 02:00
- Marketing preference: 02:15
- On plan: 02:30

Thời gian cấu hình qua `MATCHMAKER_*_SYNC_AT`. Các command chạy riêng cho
`GAP` và `GAP_EAST`, dựa trên Legal Entity của Candidate Job.

Source:

- [Kernel.php](../app/Console/Kernel.php#L32)
- [config/matchmaker.php](../config/matchmaker.php#L10)
- [SyncCandidatesMatchMakerStatus.php](../app/Console/Commands/SyncCandidatesMatchMakerStatus.php#L59)
- [SyncCandidatesMarketingPreference.php](../app/Console/Commands/SyncCandidatesMarketingPreference.php#L57)
- [SyncCandidatesOnPlan.php](../app/Console/Commands/SyncCandidatesOnPlan.php#L54)
- [EpsilonApi.php](../app/Externals/EpsilonApi.php#L217)
- [MatchMakerCandidate.php](../app/Models/MatchMakerCandidate.php#L93)
- [SmsService.php](../app/Services/SmsService.php#L122)
- [MatchMakerService.php](../app/Services/MatchMakerService.php#L893)

Ngoài ra có command one-off `candidates:import-mm` để import CSV MatchMaker vào
`match_maker_candidates`. Command này truncate snapshot trước khi import; nếu
email đã tồn tại trong CRS thì cập nhật status local cho Candidate.

## 9. Duplicate và identity verification hiện tại

`MatchMakerDuplicationService` tìm snapshot theo email và có thể:

- Tạo OTP gửi Candidate.
- Verify OTP.
- Lấy NI number từ snapshot/API để xác minh.
- Download profile picture từ MatchMaker để face matching.
- Khi Candidate xác nhận duplicate, pull status và employment/education history
  từ MatchMaker về CRS.

Đây là quy trình xác minh duplicate, không phải cơ chế đăng nhập một lần.

Source: [MatchMakerDuplicationService.php](../app/Services/MatchMakerDuplicationService.php#L46)

## 10. Current ownership và khoảng trống

Ownership có thể suy ra từ implementation hiện tại:

| Domain | Hệ thống đang giữ vai trò chính |
|---|---|
| Candidate account/profile | CRS |
| Application/job/progress | CRS |
| RTW/compliance workflow | CRS |
| File metadata và file gốc | CRS/storage |
| Operational status sau khi lên MM | MatchMaker có thể thay đổi; CRS polling về |
| Marketing preference | MatchMaker có thể thay đổi; CRS lưu answer |
| On-plan | MatchMaker là nguồn; CRS lưu flag |
| MatchMaker people number | MatchMaker sinh; CRS lưu mapping |
| Authentication | CRS quản lý Candidate login; MatchMaker độc lập |

Các ownership trên chưa được thể hiện bằng một field-level ownership contract hoặc
central identity table. Đây là vấn đề cần giải quyết khi đưa CRM vào.

Các gap chính:

- Chưa có `global_person_id` dùng chung giữa CRS, CRM và MatchMaker.
- `match_maker_candidates` không có FK tới `candidates`.
- Mapping còn phụ thuộc email trong một số flow.
- Không có bảng sync state chuẩn gồm `last_synced_at`, `last_error`,
  retry count và version cho từng external system.
- Standard Candidate sync là operator-triggered; inbound sync là polling.
- Permanent chưa có MM idempotency; nếu MM đã tạo record nhưng CRS timeout,
  retry có thể gặp duplicate.
- CRS chưa có module/route/integration adapter CRM trong source hiện tại.
- CRS JWT và MatchMaker authentication là hai session độc lập.

## 11. Đề xuất hướng thiết kế CRM/SSO

Đây là `PROPOSAL` theo mục tiêu đã xác định: **CRM sẽ thay thế MatchMaker về
lâu dài**. Trong giai đoạn chuyển tiếp, MatchMaker chỉ được coi là backend
legacy; Staff/Candidate không truy cập trực tiếp MatchMaker.

### 11.1. Identity mapping dùng chung

Nên có một identity mapping trung tâm:

~~~text
global_person_id
crm_contact_id
crs_candidate_id
mm_peo_no
mm_db_source
user_id (nếu là staff)
~~~

Email chỉ dùng để tìm kiếm/matching ban đầu, không dùng làm khoá liên kết lâu dài.

### 11.2. Ownership đề xuất ban đầu

| Domain | Source of truth đề xuất |
|---|---|
| Identity/account | CRM hoặc Central Identity Provider |
| Recruitment application | CRS |
| Compliance/RTW | CRS |
| Candidate/worker operational data | CRM sau khi cutover |
| Status, on-plan, marketing preference hiện đang ở MM | CRM sau khi migrate |
| Documents | CRS/document storage; CRM quản lý metadata và nghiệp vụ sau cutover |
| CRM interactions | CRM |
| External ID mapping trong giai đoạn migrate | Integration layer, sau đó lưu tại CRM |

### 11.3. Integration layer và SSO

Đã chốt phạm vi:

- Staff và Candidate có thể dùng SSO để truy cập CRS và CRM.
- MatchMaker là backend-only; Staff/Candidate không truy cập trực tiếp và không
  nhận MatchMaker token/session.
- Chỉ Integration layer/server được gọi MatchMaker API bằng service credential.
- Nếu cần hiển thị dữ liệu MatchMaker trên CRS/CRM, request phải đi qua backend
  hoặc Integration layer.
- Integration layer phải cô lập dependency với MatchMaker; không để CRM phụ
  thuộc trực tiếp vào schema hoặc API contract của MatchMaker.
- MM adapter là thành phần chuyển tiếp và sẽ được loại bỏ sau khi CRM hoàn tất
  việc thay thế dữ liệu/workflow tương ứng.

~~~mermaid
flowchart LR
    IDP[Central Identity Provider / SSO]
    CRM[CRM]
    CRS[CRS]
    INT[Integration Layer / Outbox]
    ADAPTER[MatchMaker Adapter - transitional]
    MM[MatchMaker - legacy backend]
    PERSON[Staff / Candidate]

    PERSON --> IDP
    IDP --> CRM
    IDP --> CRS
    CRM <--> INT
    CRS <--> INT
    INT <--> ADAPTER
    ADAPTER <--> MM

    PERSON -. không truy cập trực tiếp .-> MM
~~~

Integration layer nên chứa:

- Event/change record.
- External ID mapping.
- Sync status, retry count, last error.
- Idempotency key.
- Field ownership và conflict policy.
- Webhook receiver hoặc polling adapter.

SSO chỉ áp dụng cho CRS và CRM. Không cần MatchMaker hỗ trợ OIDC/OAuth2/SAML,
vì MatchMaker không nằm trong user login journey. MatchMaker chỉ cần cung cấp
API server-to-server và cơ chế xác thực/service credential cho Integration layer.

### 11.4. Lộ trình thay thế MatchMaker

1. **Discovery và identity mapping**: xác định đầy đủ dữ liệu, workflow,
   external consumer và mapping giữa `global_person_id`, CRS ID, CRM ID,
   `peo_no` và `db_source`.
2. **Import/shadow read**: import dữ liệu MM vào CRM, đối soát duplicate và
   cho CRM đọc thử dữ liệu mà chưa thay đổi source hiện tại.
3. **Controlled dual-write**: các thay đổi từ CRS được ghi vào CRM và MM qua
   adapter; ghi nhận chênh lệch để reconcile.
4. **CRM cutover**: CRM trở thành source of truth cho các domain đã migrate;
   các màn hình/API mới đọc từ CRM thay vì MM.
5. **MM read-only và final delta**: khóa ghi vào MM, xử lý phần dữ liệu thay
   đổi cuối cùng, xác nhận reconciliation và giữ MM ở chế độ archive nếu cần.
6. **Decommission**: loại bỏ MM adapter, polling/sync command cũ, credential
   và dependency MatchMaker sau khi toàn bộ consumer đã chuyển sang CRM.

Không nên thiết kế CRM bằng cách copy nguyên schema MM hoặc để frontend gọi MM.
CRM cần có domain model và API contract riêng; adapter chỉ chịu trách nhiệm
đọc/ghi dữ liệu legacy trong giai đoạn chuyển tiếp.

## 12. Các vấn đề cần confirm

1. Phạm vi CRM sẽ thay thế toàn bộ MatchMaker hay chỉ các domain Candidate/
   worker hiện đang được CRS sử dụng?
2. CRS có tiếp tục là master của RTW/compliance sau khi CRM thay thế MM không?
3. Những MatchMaker consumer/API/workflow nào bắt buộc phải được thay thế
   trước khi khóa ghi vào MM?
4. MatchMaker có cung cấp đầy đủ API server-to-server và service credential để
   phục vụ giai đoạn migrate không?
5. MatchMaker có webhook hoặc API idempotency hỗ trợ dual-write/reconciliation
   không?
6. Một người có thể có nhiều `peo_no` tại `GAP` và `GAP_EAST` không?
7. File gốc sẽ nằm ở CRS, CRM hay document service?
8. Có cần lưu audit lịch sử migrate, đồng bộ và thay đổi field giữa ba hệ thống
   không?

## 13. Tóm tắt dùng để trình bày

> Hiện tại CRS là nơi quản lý account, profile, application, compliance và
> candidate journey. Về lâu dài CRM sẽ thay thế MatchMaker; trong giai đoạn
> chuyển tiếp MatchMaker chỉ là backend legacy được gọi server-to-server, không
> có user truy cập trực tiếp. MatchMaker là hệ thống vận hành bên ngoài, nhận dữ liệu
> Candidate khi CRS chuyển sang và trả ngược một số thông tin như status,
> marketing preference và on-plan. Hai hệ thống đang liên kết chủ yếu bằng
> MatchMaker people number, email và database source, chưa có global identity
> dùng chung. CRS và MatchMaker cũng chưa có SSO; Candidate chỉ đăng nhập CRS,
> còn CRS gọi MatchMaker bằng server-to-server API. Khi thiết kế CRM cần chốt
> ownership theo từng nhóm dữ liệu, tạo identity mapping dùng chung và xây dựng
> SSO/integration layer để người dùng không phải đăng nhập lại.

## 14. Evidence và giới hạn xác minh

- **CODE**: Flow, route, payload và scheduler được trace từ source hiện tại.
- **DATA**: Quan hệ bảng được đối chiếu từ model/migration; chưa query database
  production để xác minh dữ liệu thực tế hoặc orphan record.
- **CONFIG**: Thời gian scheduler và MM API source phụ thuộc environment config.
- **EXTERNAL**: Chưa xác minh runtime response, webhook, SSO capability hoặc
  idempotency capability thực tế của MatchMaker.
- **INFRASTRUCTURE**: Chưa xác minh production queue worker, scheduler worker,
  storage và alert delivery.
