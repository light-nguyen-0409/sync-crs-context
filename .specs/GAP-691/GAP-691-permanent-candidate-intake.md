# GAP-691 — Tiếp nhận ứng viên Permanent và tích hợp MatchMaker

> **Trạng thái**: `APPROVED` — yêu cầu/thiết kế được duyệt; chưa bắt đầu triển khai
> **Cập nhật lần cuối**: 2026-09-29
> **Lưu ý về visibility**: Yêu cầu ban đầu trong tài liệu này về việc ẩn Permanent khỏi mọi bề mặt CRS đã được điều chỉnh. Phạm vi hiện hành được ghi tại [GAP-691-implementation-plan.md](GAP-691-implementation-plan.md) và amendment được duyệt [GAP-691-permanent-filter-scope-adjustment.md](GAP-691-permanent-filter-scope-adjustment.md): chỉ Candidate list/filter đã chốt loại Permanent; lookup theo ID và luồng không phải list filter không lọc chỉ vì `is_permanent`.
> **Nguồn**: GAP-691 và các quyết định đã trao đổi trong quá trình thiết kế giao tiếp API

## 1. Mục tiêu và phạm vi

Tạo luồng tiếp nhận ứng viên Permanent được chọn bằng tham số `RT=P` trên URL Sourceflow. Candidate tiếp tục đăng ký tài khoản theo luồng hiện tại; sau signup, FE gọi `POST /api/candidate/me/jobs` trước khi mở form để tạo `candidate_job`. API này nhận external job/branch IDs từ invitation và trả internal `jobs.id`; FE dùng ID nội bộ cho config/click và gửi trong body submit dưới key `job_id`. Form bổ sung thông tin ứng viên và CV vào Candidate đã có trong GAP. Biểu mẫu yêu cầu các trường đã xác nhận, gồm `journey_type`, nhưng không thực hiện xác minh RTW. CV được tải trước bằng API upload file hiện có; biểu mẫu submit gửi `file_id`. Candidate phải tích checkbox Work Finder Agreement; frontend kiểm soát việc click link trước khi tiếp tục, còn GAP chỉ ghi nhận lần click đầu tiên/thời gian/IP trên form. Checkbox phải `true` khi submit nhưng không lưu boolean hay thời điểm đồng ý. GAP không lưu nội dung hoặc tự sinh PDF Agreement. URL Agreement có thể cấu hình theo branch; nếu branch không có URL riêng thì dùng URL entity trong `legal_entities`. Sau khi GAP lưu dữ liệu và commit, backend gọi MatchMaker trực tiếp bằng timeout mặc định của HTTP client. Timeout/lỗi kết nối/5xx chuyển cùng thao tác đồng bộ sang queue retry; lỗi nghiệp vụ 4xx không retry. Candidate được đánh dấu Permanent và không hiển thị trên các bề mặt Candidate thông thường của CRS.

Tài liệu này mô tả luồng mục tiêu đề xuất, không mô tả hành vi đang chạy. Điểm cuối API GAP-691 hiện chưa tồn tại. Các nội dung được phân loại như sau:

- **Định hướng đã xác nhận** — được người dùng yêu cầu/chấp thuận rõ trong trao đổi về công việc này.
- **Đề xuất** — khuyến nghị kỹ thuật để rà soát khi triển khai; không phải câu hỏi nghiệp vụ còn mở.
- **Điều kiện triển khai** — dữ liệu/cấu hình cần chuẩn bị khi thực hiện, không phải câu hỏi mở về nghiệp vụ.

## 2. Luồng tổng thể đề xuất

```text
Liên kết Sourceflow
  ├─ Có tham số `RT=P`
  │    → giữ nguyên luồng đăng ký tài khoản Candidate hiện tại và `job_ref`
  │    → sau signup, gọi `POST /api/candidate/me/jobs` với external job/branch IDs từ invitation
  │    → tạo `candidate_job`, nhận internal `jobs.id` trong `data.id`
  │    → sau khi liên kết job thành công, mở biểu mẫu Permanent cho Candidate đã đăng ký
  │    → thu thập các trường bắt buộc, gồm `journey_type`; địa chỉ theo logic hiện có
  │    → upload CV qua API file hiện tại, lấy `file_id`
  │    → frontend kiểm soát click link Agreement; GAP ghi first-click time/IP và link công khai mở
  │      theo cấu hình branch → entity fallback (URL lưu ở `branches` và `legal_entities`)
  │    → yêu cầu tích checkbox đồng ý Agreement
  │    → gửi biểu mẫu để cập nhật Candidate đã tồn tại trong GAP; không tạo Candidate mới
  │    → lưu DB thành công, sau commit gọi trực tiếp tích hợp MatchMaker hiện có (timeout theo HTTP client mặc định), status `PERM`
  │      ├─ thành công → lưu MatchMaker identity/status
  │      ├─ timeout/lỗi kết nối/5xx → đưa cùng thao tác vào queue retry
  │      └─ lỗi nghiệp vụ 4xx → không retry, ghi log/báo lỗi
  │    → không hiển thị Candidate này trong các màn hình/đầu ra Candidate thông thường của CRS
  └─ Không có tham số chọn Permanent
       → giữ nguyên luồng đăng ký hiện tại, không mở biểu mẫu Permanent
```

`job_ref` trong liên kết đăng ký hiện tại được giữ lại. `POST /api/candidate/me/jobs` nhận external job/branch IDs, tạo hoặc tìm Job nội bộ và tạo `candidate_job`; `data.id` trong response là internal `jobs.id`. FE gọi API này sau signup và trước khi mở form. `RT=P` chỉ quyết định có mở biểu mẫu mới hay không. Máy chủ resolve branch/entity từ job liên kết đã xác thực, không nhận URL Agreement hoặc branch/entity tùy ý từ payload biểu mẫu.

### 2.1. Lựa chọn loại RTW

Biểu mẫu chỉ lưu loại RTW mà Candidate chọn (`journey_type`). GAP-691 không xác minh RTW, không thu thập share code/hồ sơ chứng minh, không cấp token tiếp tục RTW và không đặt trạng thái chờ/đã xác minh dựa trên lựa chọn này.

### 2.2. Quan hệ Candidate với công việc/chi nhánh

Luồng ứng tuyển hiện tại gọi `POST /api/candidate/me/jobs`; GAP-691 gọi bước này sau signup và trước form submit để tạo `candidate_job` cho công việc ứng tuyển được xác định từ invitation. Request truyền `external_id` (invitation job ID), `branch_id` (invitation branch ID), `title`, `job_ref` và tracking fields; response `data.id` là internal `jobs.id`. Không tạo thêm quan hệ giả với vacancy khác. Quan hệ Candidate–Job hiện được dùng cho tìm kiếm theo chi nhánh, quyền truy cập của tư vấn viên và trạng thái công việc.

Quan hệ này cần được giữ vì:

- Tìm kiếm ứng viên theo chi nhánh lọc qua `candidateJobs → job → branch`.
- Phân quyền xem/cập nhật chi tiết của tư vấn viên kiểm tra Candidate có công việc thuộc chi nhánh được yêu cầu hay không.

Invitation cung cấp external `job_id`, external `branch_id` và `job_ref`; `POST /api/candidate/me/jobs` dùng các giá trị đó để tạo `candidate_job` và trả internal `jobs.id`. Config nhận internal ID qua query `job_id`, click nhận internal ID trên path; submit nhận internal ID trong body `job_id`. Backend xác minh liên kết CandidateJob rồi dùng branch/entity tương ứng để chọn Work Finder Agreement.

### 2.3. Trạng thái MatchMaker và khả năng hiển thị trong CRS

Permanent là loại tiếp nhận/phân loại hồ sơ; `PERM` là trạng thái phía MatchMaker. Cần có dấu hiệu Permanent riêng trong GAP (ví dụ `is_permanent`) và loại hồ sơ khỏi **mọi màn hình/đầu ra Candidate thông thường của CRS**: danh sách/tìm kiếm Consultant, Compliance, Admin, SMS selectors, escalated-issue queues, appointments, detail theo ID và exports. Hồ sơ không bị xóa; dedicated Permanent intake và xử lý nền/queue vẫn hoạt động. Không dùng `match_maker_status` làm cờ hiển thị, vì MM sync có thể chưa hoàn tất khi form được lưu.

Không đánh dấu Permanent là `LIVE` và không mở rộng các rule nghiệp vụ vốn chỉ cho `LIVE`/`RRR`. Permanent không thuộc luồng chính; nếu có nhu cầu hiển thị hoặc hỗ trợ thêm thao tác cho nhóm này thì sẽ được bổ sung theo yêu cầu riêng. `match_maker_status` hiện chưa có mapping `PERM`, nên cần khai báo mapping để lưu trạng thái MM thật, nhưng không đổi các guard hiện có để coi `PERM` như `LIVE`.

## 3. Lựa chọn loại RTW

Candidate được tạo trong luồng đăng ký hiện tại; sau đó `POST /api/candidate/me/jobs` tạo quan hệ công việc trước khi form được mở. Biểu mẫu chỉ lưu lựa chọn `journey_type`; lựa chọn này không phải kết quả xác minh và không kích hoạt bước kiểm tra RTW trong GAP-691.

## 4. Work Finder Agreement

### 4.1. Hành vi đã xác nhận

- Client sở hữu nội dung và cung cấp URL truy cập Agreement. GAP không proxy, tạo hoặc lưu bản PDF Agreement.
- Link ưu tiên URL riêng của branch; nếu branch chưa cấu hình thì dùng URL entity của Candidate/job. URL branch được lưu trong `branches`, URL fallback trong `legal_entities`. Không nhận URL tùy ý từ payload submit.
- Link đích công khai cho bất kỳ ai có URL. Candidate click link trên form thì GAP ghi nhận sự kiện gắn Candidate hiện tại; truy cập link ở ngoài form không được GAP ghi nhận.
- Form có checkbox đồng ý bắt buộc và backend yêu cầu giá trị `true` khi submit. Frontend chịu trách nhiệm yêu cầu click link trước khi tiếp tục; backend ghi audit click khi nhận click event. Click và đồng ý vẫn là hai việc riêng; checkbox chỉ dùng để validate và không lưu boolean hoặc thời điểm đồng ý.
- Dùng Candidate token đã cấp trong bước đăng ký; không tạo `intake_token` mới. Thời điểm click do backend ghi theo múi giờ backend hiện hành; IP do request backend xác định, không nhận từ payload form.

### 4.2. Luồng ghi nhận click và lưu trữ đề xuất

1. Candidate và `candidate_job` đã có. Resolve Agreement URL theo branch của job; nếu branch URL rỗng thì fallback về legal entity của branch.
2. Frontend kiểm soát yêu cầu click link trước khi Candidate tiếp tục. Khi click trên form, frontend gọi endpoint audit bằng Candidate token hiện có; GAP ghi nhận click trước khi trình duyệt mở URL công khai.
3. Ghi thời gian backend và IP của lần click đầu vào các cột Agreement riêng trên row `candidate_timings` theo Candidate/job. Không dùng lại các cột KID/ToE/medical; không lưu URL click tùy ý hoặc nội dung Agreement.
4. Khi gửi form, backend yêu cầu checkbox đồng ý là `true` nhưng không lưu giá trị hoặc thời điểm đồng ý. Không suy diễn rằng click link đồng nghĩa với đồng ý; thứ tự/thao tác click được frontend kiểm soát.
5. Nếu endpoint click được gọi lại, giữ nguyên thời gian/IP lần đầu; không ghi đè. Không ghi sự kiện khi Candidate truy cập URL công khai bên ngoài form.

### 4.3. Mô hình dữ liệu đã cập nhật

Tái sử dụng row `candidate_timings` hiện có theo Candidate/job, nhưng chỉ bằng các cột riêng `work_finder_agreement_link_clicked_at` và `work_finder_agreement_link_clicked_ip` (IP dài 45 ký tự để hỗ trợ IPv6). Không tạo bảng click riêng vì yêu cầu hiện tại chỉ cần lưu lần click đầu, không phải lịch sử mọi lần click. URL branch là override nullable trên `branches`; nếu không có thì URL entity trong `legal_entities` là fallback bắt buộc. Không tạo brand-level URL. Không lưu boolean/`accepted_at`, không thêm intake table, CV reference hoặc sync-status columns; dùng `candidates.is_permanent`, file `type=cv` hiện có và cơ chế queue/failed jobs. Không lưu view token mới, nội dung Agreement hay PDF trong GAP.

## 5. Luồng ghi nhận đã xem/xác nhận hiện tại của App Pack

Ví dụ hiện có trong App Pack là Key Information Document (KID — Tài liệu thông tin chính), không phải Work Finder Agreement:

1. Candidate đã đăng nhập và có quan hệ Candidate–Job.
2. KID phải ở trạng thái `RELEASED`. Ứng dụng Candidate gọi `POST /api/candidate/me/jobs/{jobId}/key_information_document/mark_as_read`.
3. Bộ điều khiển chuyển trạng thái sang “đã xem”. Dịch vụ ghi `kid_link_viewed` và IP của yêu cầu vào `candidate_timings`, sau đó gửi email ToE.
4. Khi tạo Application Pack (Bộ hồ sơ ứng tuyển), `getCandidateTimingHtml()` chỉ thêm PDF nhật ký thời gian khi đã có các mốc gửi email/xem/ký KID, ToE và medical theo yêu cầu. Nhật ký có dòng ghi thời gian/IP xem liên kết KID rồi được ghép vào PDF Application Pack.

Vì vậy, luồng hiện tại là mẫu tham khảo hữu ích cho việc ghi thời gian/IP ở máy chủ, nhưng không phải tài liệu một trang độc lập được sinh khi nhấn link và cũng không phải bằng chứng đồng ý/chữ ký Work Finder Agreement. GAP-691 dùng cột riêng trên row CandidateTiming để ghi click, không dùng nhầm các cột KID/ToE/medical và không tạo PDF Agreement.

## 6. Hợp đồng API đề xuất

### 6.1. Điểm cuối API

**Xác thực:** dùng Candidate token đã được cấp trong luồng đăng ký hiện tại để xác định Candidate sở hữu form và ghi nhận click Agreement. Không tạo token tiếp nhận mới. `POST /api/candidate/me/jobs` được gọi trước khi mở form; `data.id` trả về là internal `jobs.id`, dùng làm query `job_id` cho config, `{jobId}` cho click và trường `job_id` trong submit body. Backend xác minh quan hệ CandidateJob/Job/Branch/LegalEntity từ dữ liệu GAP. `job_id` invitation là external ID, không dùng trực tiếp làm internal ID.

Lấy URL/cấu hình form:

```http
GET /api/candidate/me/permanent-intake/config?job_id=501
Authorization: Bearer <candidate_token>
```

`job_id` là internal `jobs.id` từ `data.id` của `POST /api/candidate/me/jobs`; backend xác minh Candidate có `candidate_job` tương ứng rồi resolve Agreement URL theo branch → entity. Không truyền external invitation ID ở đây.

Submit thông tin Permanent:

```http
POST /api/candidate/me/permanent-intake
Content-Type: application/json
Authorization: Bearer <candidate_token>
```

Ghi nhận click Agreement riêng:

```http
POST /api/candidate/me/jobs/{jobId}/work_finder_agreement/click
Authorization: Bearer <candidate_token>
```

Endpoint này lấy Candidate từ token, xác minh job thuộc Candidate, chỉ ghi first-click time/IP vào CandidateTiming và không nhận `candidate_id`, thời gian, IP hoặc URL từ request body. Gọi lại không ghi đè lần click đầu. Frontend chỉ điều hướng tới link công khai sau khi audit được ghi nhận thành công. Config endpoint chỉ trả URL Agreement đã resolve; trạng thái submit và các thông tin khác lấy từ API/luồng tương ứng, không trả ở endpoint này.

### 6.2. Các trường yêu cầu đề xuất

Dùng lại khóa hiện có khi ngữ nghĩa giống nhau. Trường bắt buộc theo danh sách dấu `*` đã được cung cấp; địa chỉ tiếp tục theo logic hiện có của GAP. Tên key, enum và định dạng payload cần khớp endpoint đồng bộ MatchMaker hiện tại khi triển khai.

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| `job_id` | Bắt buộc | Internal `jobs.id` từ `data.id` của `POST /api/candidate/me/jobs`; phải thuộc Candidate hiện tại qua `candidate_job` |
| `title` | Bắt buộc | Khớp lựa chọn trên form |
| `first_name`, `last_name` | Bắt buộc | Định danh ứng viên |
| `email` | Bắt buộc | Candidate đã được tạo ở signup; giữ duplicate check hiện có và cập nhật đúng Candidate của token |
| `phone_number` | Bắt buộc | Dùng key hiện có |
| `date_of_birth` | Bắt buộc | Đề xuất `YYYY-MM-DD` |
| Các trường địa chỉ hiện có | Bắt buộc theo Address* và validation hiện tại | Dùng cấu trúc/key hiện có (`building`, `street`, `town_city`, `county`, `postcode`); không tạo logic/Data8 mới |
| `contact_dates[]`, `contact_times[]` | Bắt buộc | Dùng ngữ nghĩa/giá trị hiện có, không đổi thành ngày/giờ cuộc hẹn |
| `transportation_method` | Bắt buộc | “What’s your primary method of transport?”; enum khớp form hiện có |
| `transportation_distance` | Bắt buộc | “How far are you willing to travel?”; enum khớp form hiện có |
| `recruitment_source` | Bắt buộc | “Where did you hear about us?”; enum khớp form hiện có |
| `journey_type` | Bắt buộc | Lựa chọn loại RTW; chỉ lưu và gửi sang MM, không xác minh RTW |
| `work_finder_agreement_accepted` | Bắt buộc và phải là `true` | Checkbox dùng để validate submit; không lưu boolean hoặc thời điểm đồng ý |
| `file_id` | Bắt buộc | ID trả về từ API upload CV hiện tại; file phải thuộc Candidate token hiện tại và có type `File::TYPE_CV` |

CV được tải trước bằng `POST /api/candidate/me/files/cv` với file multipart; API hiện tại trả resource có `id`. Endpoint submit nhận `file_id`, không nhận lại binary CV. Giữ đề xuất CV PDF/DOC/DOCX tối đa 10 MiB (MIME kiểm tra phía server và ClamAV); API upload hiện tại cho phép extension rộng hơn và chưa có giới hạn size tại validator nên cần thêm CV-specific validation khi triển khai. Thời gian/IP click do backend ghi qua endpoint audit; không nhận các giá trị này từ payload submit.

### 6.3. Quy trình xử lý và phản hồi đề xuất

1. Xác thực Candidate token hiện có; nhận internal `job_id` từ body, xác minh Job có `candidate_job` thuộc Candidate rồi resolve branch/entity; không tạo Candidate mới.
2. Kiểm tra danh sách trường bắt buộc, `journey_type`, checkbox Agreement và `file_id`. Xác minh file thuộc Candidate hiện tại, có type CV và qua validation CV.
3. Đọc/kiểm tra quyền sở hữu và dữ liệu cần thiết trước transaction. Cập nhật Candidate, địa chỉ, `journey_type` và dấu Permanent bằng transaction chỉ chứa thao tác ghi; không gọi `updatePersonalInfo()`/`updateCandidateAddress()` nguyên trạng nếu các method đó đọc DB trong transaction hoặc có side effect không mong muốn. Chỉ validate checkbox là `true`, không lưu boolean/`accepted_at`. Không chạy lại các kiểm tra duplicate tạo escalated issue; chỉ giữ mapping/persistence và set `first_applied_at` nếu đang trống. Candidate được loại khỏi màn hình/đầu ra thông thường ngay khi GAP lưu thành công.
4. Sau commit, gọi MatchMaker trực tiếp với timeout mặc định của HTTP client, gửi toàn bộ trường form (bao gồm `journey_type`) với status đích `PERM`; không gọi xác minh RTW và không đặt `LIVE`. Chỉ sau phản hồi thành công mới persist MatchMaker identity/status.
5. Phân loại lỗi rõ ràng bằng custom exceptions dưới `App\Exceptions\Services`: lỗi MM 4xx (bao gồm response nghiệp vụ từ chối/duplicate) là `MatchMakerNonRetryableException`, không enqueue/retry, log/báo lỗi và trả `502`; timeout, lỗi kết nối, MM 5xx và lỗi tích hợp tạm thời là `MatchMakerTransientException`, enqueue cùng sync operation và trả `202`. GAP data vẫn đã commit. Queue giữ số lần thử cố định hiện tại (3 lần) trong giai đoạn này; chỉ retry `MatchMakerTransientException`, còn `MatchMakerNonRetryableException` phải fail ngay, không thử lại.
6. Nếu enqueue fallback thất bại sau GAP commit, trả `503` và log/alert Candidate/job/file IDs để vận hành enqueue lại. Không tạo sync attempt mới khi submit lại vì Candidate đã Permanent.
7. Không yêu cầu thêm idempotency/upsert contract phía MM trong phạm vi hiện tại; timeout có thể xảy ra sau khi MM đã tạo hồ sơ, nên retry fallback có rủi ro duplicate đã chấp nhận tạm thời. Không lưu cột sync status riêng trên Candidate/CandidateJob/intake table; response body không thêm `sync_status`.
8. Trả `200` khi direct call thành công hoặc `202` khi fallback queue nhận job; cả hai response xác nhận form đã submit (`submission_status=submitted`).
9. Không gọi luồng xác minh RTW hoặc đánh dấu RTW approved chỉ từ `journey_type`.

Các trường phản hồi đề xuất:

```json
{
  "data": {
    "candidate_id": 123,
    "job_id": 501,
    "candidate_job_id": 808,
    "submission_status": "submitted"
  },
  "message": "Đã gửi thông tin ứng viên thành công"
}
```

Các lỗi có thể có: `401/403` Candidate token không hợp lệ; `422` trường bắt buộc, checkbox, `file_id` hoặc CV không hợp lệ; `409` Candidate đã submit Permanent; `502` MM trả lỗi nghiệp vụ 4xx (không retry); `503` enqueue fallback thất bại sau khi GAP đã lưu. Cấu trúc JSON cuối cần theo quy ước API GAP; không trả sync-status.

## 7. Quyền sở hữu dữ liệu và tác động lưu trữ

| Thông tin | Nơi lưu hiện có hoặc đề xuất | Điểm cần làm rõ |
|---|---|---|
| Candidate và trường hồ sơ hiện có | `candidates`; địa chỉ trong `candidate_addresses` qua logic `CandidateService::updateCandidateAddress()` | Field mapping của Sourceflow phải dùng lại mô hình/validation hiện có |
| CV | Binary trong storage đã cấu hình; metadata trong `files`, gắn Candidate, loại `File::TYPE_CV`; API submit nhận `file_id` | File upload qua API hiện tại; đề xuất PDF/DOC/DOCX, tối đa 10 MiB |
| Dấu phân loại Permanent trong GAP | Cột riêng trên Candidate, ví dụ `is_permanent`; set khi GAP chấp nhận form và loại khỏi mọi đầu ra Candidate thường | Tồn tại độc lập với `match_maker_status` và trạng thái queue |
| Trạng thái và đồng bộ MatchMaker | `match_maker_people_number`/`match_maker_status` phản ánh MM; direct call sau commit, fallback queue/failed job chỉ cho timeout, connection, 5xx | Status đích `PERM`; không coi là `LIVE`; không yêu cầu MM idempotency riêng trong phạm vi hiện tại |
| Loại RTW Candidate chọn | Trường `journey_type` trên Candidate | Bắt buộc và gửi sang MM; chỉ là lựa chọn, không phải xác minh RTW |
| Work Finder Agreement URL | Cột nullable mới trên `branches` làm URL override; `legal_entities.work_finder_agreement_url` làm fallback | Branch URL có thể chỉnh qua Branch CRUD; entity URL được seed theo CSV và được bảo đảm có dữ liệu |
| Click link Agreement | Các cột riêng `work_finder_agreement_link_clicked_at` và `work_finder_agreement_link_clicked_ip` trên `candidate_timings` theo Candidate/job | Chỉ giữ first click; không dùng lại cột KID/ToE/medical; IP tối đa 45 ký tự |
| Checkbox Agreement | Không lưu DB; request phải gửi `work_finder_agreement_accepted=true` | Chỉ validate khi submit; frontend yêu cầu click link trước khi cho tiếp tục |
| Submit marker | `candidates.is_permanent` | Đánh dấu hồ sơ Permanent/ẩn khỏi CRS và chặn submit enqueue trùng |
| CV selection | Row `files` hiện có (`type=cv`), ID được truyền trong request và queue payload | Không thêm `permanent_cv_file_id` hoặc file type riêng |
| MM sync attempt/failure | Direct call sau commit; fallback queue, `failed_jobs`, application log và ops alert | Dùng timeout mặc định HTTP client; 4xx không retry; số lần thử queue cố định hiện tại là 3; không thêm `permanent_sync_status` hoặc bảng intake |

Candidate và `candidate_job` tồn tại trước khi gửi biểu mẫu, nên không cần Candidate tạm, token mới hoặc bảng intake riêng. Candidate fields hiện có được lưu trước khi queue; không giữ DB transaction trong lúc gọi hệ thống ngoài.

## 8. Ranh giới tích hợp MatchMaker

- Candidate được lưu trong GAP trước khi đồng bộ với hệ thống ngoài; không giữ transaction mở trong lúc gọi MM.
- Dùng lại tích hợp/API đồng bộ Candidate sang MatchMaker hiện có; gọi trực tiếp sau commit với timeout mặc định HTTP client. Payload gồm toàn bộ trường form, `journey_type` và trạng thái đích `PERM`.
- Luồng `sendCandidateToMatchMaker()` hiện tại yêu cầu interview/readiness liên quan RTW, gửi các RTW files, cập nhật job/appointment state và cuối cùng đặt Candidate thành `LIVE`. Không gọi luồng Consultant transfer nguyên trạng cho GAP-691; tái sử dụng API đồng bộ Candidate hiện có nhưng giữ nhánh Permanent không xác minh RTW, không đặt `LIVE` và không bật các chức năng `LIVE`.
- `MatchMakerCandidate::getStatusMappings()` chưa khai báo `PERM`; `getReverseStatusValue()` trả nguyên status uppercase nếu không có mapping. Cần khai báo mapping/constant rõ ràng để sync không ghi giá trị lạ vào `candidates.match_maker_status`.
- MM status phản ánh trạng thái MM thật; dấu Permanent dùng để phân loại/ẩn trong GAP, còn retry/failure chỉ dùng fallback queue/failed jobs. Không thêm queue status column và không đánh dấu `LIVE` khi MM trả `PERM`.
- Dùng custom exceptions riêng dưới `App\Exceptions\Services` để phân biệt `MatchMakerTransientException` (timeout/connection/5xx và lỗi tích hợp tạm thời) với `MatchMakerNonRetryableException` (mọi 4xx, kể cả duplicate/business rejection). Chỉ lỗi transient mới dispatch fallback queue và được retry; giữ số lần thử cố định hiện tại là 3 trong giai đoạn này. Nếu fallback job nhận lỗi non-retryable thì fail ngay, không retry. Sau lần retry cuối phải giữ failed job/lỗi và báo qua cơ chế reporting hiện có. Không thêm cột sync state hay MM idempotency/upsert contract trong phạm vi hiện tại.
- `journey_type` được gửi sang MM nhưng không kích hoạt xác minh RTW.

## 9. Ràng buộc code hiện tại và điểm khác biệt

- **CODE:** Luồng đăng ký Candidate hiện tại yêu cầu mật khẩu/ngữ cảnh theo dõi và cấp Candidate JWT tổng quát. GAP-691 giữ nguyên bước đăng ký này; biểu mẫu Permanent được mở sau khi tài khoản Candidate đã đăng ký, không thay thế hoặc bỏ qua luồng hiện tại.
- **CODE:** Các tuyến xử lý tệp, passport và share-code hiện tại yêu cầu Candidate đã xác thực. Passport lưu theo Candidate ID; share-code dùng Candidate và chi nhánh của công việc gần nhất; thông tin tệp cần Candidate ID.
- **CODE / DEVIATION so với `.business-spec` SPEC-002:** `AuthenticatableService::signUp()` kiểm tra email, tạo Candidate và đăng nhập nhưng không tạo `candidate_job` (`app/Services/AuthenticatableService.php:83-93`); Candidate signup bổ sung dữ liệu invite/MM (`app/Services/CandidateService.php:243-263`). `candidate_job` được tạo riêng qua `POST /api/candidate/me/jobs`. Business spec hiện ghi signup tạo `candidate_jobs` (`.business-spec/backend-business-flow-spec.md:255-270`), đây là mô tả lệch code; GAP-691 giữ bước gọi endpoint job riêng như người dùng đã xác nhận.
- **CODE:** Địa chỉ hiện được lưu qua `CandidateService::updateCandidateAddress()` (`app/Services/CandidateService.php:1109-1132`); Permanent intake cần giữ mapping/persistence nhưng dùng luồng riêng nếu method hiện tại đọc DB trong transaction hoặc tạo side effect. Signup đã xử lý duplicate; cập nhật name/DOB/phone/address từ form không chạy lại duplicate checks tạo escalated issue. `first_applied_at` chỉ set nếu hiện đang trống.
- **CODE:** Search Consultant/Compliance dùng `getCandidatesByBranch()` (`app/Http/Controllers/Api/Consultant/CandidateController.php:92-150`, `app/Http/Controllers/Api/Compliance/CandidateController.php:77-143`); Admin search email dùng query riêng (`app/Http/Controllers/Api/Admin/CandidateController.php:41-49`). Consultant SMS estimate cũng gọi `getCandidatesByBranch()` (`app/Http/Controllers/Api/Consultant/SmsController.php:45-60`). Khi triển khai phải lọc Permanent ở mọi bề mặt hiển thị đã chốt, nhưng không làm hỏng luồng intake riêng hoặc xử lý đồng bộ nền.
- **CODE:** Escalated-issue queues có truy vấn Candidate riêng (`app/Services/CandidateService.php:331-367`); appointments, detail theo ID và MatchMaker export cũng có đường truy vấn riêng. Các bề mặt này đều nằm trong phạm vi ẩn đã chốt, cần rà soát độc lập thay vì chỉ thêm filter vào truy vấn tìm kiếm dùng chung.
- **CODE:** `Candidate::canApplyJob()` và tạo appointment chặn Candidate có job status `MATCHMAKER` trừ khi MM status `RRR` (`app/Services/CandidateService.php:586-590`, `app/Services/AppointmentService.php:126-131`). `Candidate::isReadyToMoveToMatchmaker()` chỉ cho MM status rỗng/`RRR`/`LIVE` và yêu cầu RTW approval (`app/Models/Candidate.php:535-563`); welfare check và bank update yêu cầu `LIVE` (`app/Models/Candidate.php:670-674`, `app/Services/GBGBankCheckService.php:206-210`). Giữ nguyên các guard này; không mở tính năng `LIVE` cho Permanent.
- **CODE:** Luồng chuyển Candidate thông thường gửi tài liệu/RTW rồi đặt status `LIVE` (`app/Services/MatchMakerService.php:354-378`). Mapping hiện có không khai báo `PERM` (`app/Models/MatchMakerCandidate.php:83-115`); status sync có thể nhận status chưa biết từ MM (`app/Console/Commands/SyncCandidatesMatchMakerStatus.php:118-126`).
- **CODE:** CV dùng `POST /api/candidate/me/files/cv`; API upload hiện quét ClamAV, cho phép extension rộng, gồm PDF, ảnh, DOC/DOCX, ZIP/RAR, và trả resource có `id` (`app/Http/Controllers/Api/Candidate/MeFileController.php:122-147`, `config/files.php:27-30`). Request chưa có max size tại validator; Docker PHP/Nginx cho 100 MiB (`docker/8.2/php.ini:2-3`, `docker/8.1/nginx.conf:14`). Triển khai cần giới hạn loại file dành riêng cho CV, kiểm tra MIME, Candidate sở hữu file và `file_id`; mức PDF/DOC/DOCX tối đa 10 MiB là đề xuất kỹ thuật, đồng thời phải đối chiếu giới hạn ingress/proxy production.
- **CODE / DATA:** Branch có API create/update (`/api/admin/branches`, `/api/compliance/branches`) và `Branch` liên kết `legal_entity_id`; hiện request/resource/model chưa có Agreement URL. GAP-691 thêm nullable `work_finder_agreement_url` vào `branches` và expose qua Branch CRUD để chỉnh URL theo branch. URL entity vẫn được seed từ CSV bằng seeder update-only; không dùng nguyên `LegalEntitySeeder` vì nó xóa/nạp lại bảng. Không thêm URL brand-level.
- **CODE / CONFIG:** Queue mặc định trong `config/queue.php` là `sync`; worker Supervisor hiện cấu hình Redis với 3 lần thử (`docker/8.1/supervisord.conf:17`), còn `after_commit` hiện tắt. Môi trường triển khai phải dùng queue bất đồng bộ, worker hoạt động, dispatch sau commit và có cảnh báo/báo lỗi khi job thất bại cuối cùng; nếu giữ `sync` thì form request sẽ thực hiện đồng bộ ngay và không đạt flow đã chốt.
- **CODE:** App Pack ghi các mốc KID/ToE/medical (`candidate_timings`); code hiện không audit click Work Finder Agreement và không tạo tài liệu một trang cho click này.
- **EXTERNAL:** Các giá trị enum cụ thể của những lựa chọn trên form và mapping tương ứng sang MatchMaker cần được lấy từ cấu hình/form Sourceflow cuối khi triển khai. Danh sách field bắt buộc đã được chốt trong mục 6.2; không chờ xác nhận lại requiredness. Tích hợp dùng API đồng bộ Candidate sang MM hiện có và gửi toàn bộ dữ liệu form cùng `journey_type` như đã thống nhất.
- **CODE:** Tuyến xử lý/bộ điều khiển/dịch vụ gửi dữ liệu GAP-691 chưa được triển khai. `.business-spec/` vẫn là cơ sở mô tả hành vi đang chạy; tài liệu công việc này chỉ ghi nhận luồng tương lai được đề xuất.

## 10. Điều kiện đầu vào và vận hành trước khi triển khai

Các quyết định nghiệp vụ/API đã chốt; không cần xác nhận lại. Những việc sau là dữ liệu đầu vào hoặc điều kiện triển khai, không làm thay đổi luồng đã duyệt:

1. Client cung cấp CSV ánh xạ entity ID với URL Work Finder Agreement; triển khai seeder cập nhật riêng, không xóa/nạp lại toàn bộ `legal_entities`. URL theo branch là tùy chọn, được lưu/chỉnh qua Branch CRUD; khi có thì branch override entity, nếu không dùng URL entity fallback.
2. Cấu hình môi trường queue bất đồng bộ và worker trước khi bật form để xử lý fallback khi direct call timeout theo HTTP client mặc định, lỗi kết nối hoặc 5xx; fallback chỉ dispatch sau khi GAP commit. Lỗi sau 3 lần thử hiện tại phải được lưu và báo cho người vận hành. Cấu hình hiện tại mặc định `sync`, vì vậy không thể xử lý fallback bất đồng bộ nếu chỉ dựa vào cấu hình mặc định.
3. Lấy enum cuối cho các lựa chọn form từ Sourceflow/client để map đúng dữ liệu gửi MatchMaker; danh sách và tính bắt buộc các trường đã chốt ở mục 6.2, gồm `journey_type`.
4. Giới hạn CV PDF/DOC/DOCX tối đa 10 MiB là đề xuất kỹ thuật; khi triển khai cần đồng bộ validator ứng dụng với giới hạn của ingress/proxy và xác minh MIME/ownership/type của `file_id`.
5. Chưa yêu cầu idempotency/upsert riêng ở MatchMaker. Vì vậy, nếu MM đã tạo record nhưng GAP không nhận phản hồi rồi queue retry, có rủi ro tạo bản ghi trùng; đây là giới hạn được chấp nhận tạm thời theo quyết định hiện tại.

## 11. Phạm vi kiểm thử đề xuất khi triển khai

- `RT=P` mở form sau signup Candidate hiện tại; giữ token, `job_ref` và `POST /api/candidate/me/jobs`, gắn form với Candidate/job đúng.
- Tất cả trường `*` trong mục 6.2 cùng `journey_type` bắt buộc; lưu đúng lựa chọn `journey_type` nhưng không gọi hoặc kích hoạt xác minh RTW.
- Submit chỉ cập nhật Candidate của token; duplicate xử lý thuộc signup, không chạy lại duplicate checks/escalated-issue side effects khi cập nhật profile; không tạo Candidate tạm hoặc yêu cầu token mới.
- Checkbox Agreement thiếu/false bị từ chối nhưng giá trị/thời điểm checkbox không được lưu DB; frontend bắt buộc click trước khi tiếp tục. First click trên form ghi Candidate/job context, thời gian backend và IP vào CandidateTiming; click lặp không ghi đè, mở URL bên ngoài form không tạo audit.
- URL branch được ưu tiên; branch không cấu hình thì lấy URL entity từ `legal_entities`. Kiểm thử Branch CRUD lưu/trả branch URL, resolver branch-over-entity và fallback entity khi branch URL rỗng; entity seeder chỉ cập nhật URL theo entity ID, không xóa hoặc ghi đè dữ liệu khác.
- CV upload qua `POST /api/candidate/me/files/cv`; submit nhận `file_id` đúng Candidate và loại CV. Kiểm thử loại/MIME/kích thước đã thống nhất cùng ClamAV.
- Permanent bị ẩn khỏi mọi bề mặt CRS thông thường đã liệt kê ở mục 2.3, gồm search/list, selectors, queues, appointments, detail và export; dedicated intake và xử lý queue vẫn chạy.
- MM nhận đầy đủ dữ liệu form, gồm `journey_type`, và status `PERM`; kiểm thử không xác minh RTW, không đặt `LIVE` và không mở các thao tác chỉ dành cho `LIVE`.
- GAP persistence commit trước khi gọi MM trực tiếp; kiểm thử direct success trả 200, timeout/connection/5xx enqueue fallback và trả 202, 4xx không retry và trả 502, enqueue lỗi trả 503. Kiểm thử typed exception classification và số lần retry cố định hiện tại (3), failure cuối qua failed jobs/log/cảnh báo. Không thêm/bắt buộc intake table, CV reference, checkbox persistence hay sync-status column; không kiểm thử idempotency MM như một yêu cầu bắt buộc trong phạm vi này.
- Các bộ kiểm thử đơn vị/tích hợp liên quan và toàn bộ PHPUnit bắt buộc đều đạt khi triển khai code.

## 12. Bằng chứng triển khai Phase 3

- Đã thêm config/click/submit API, validate file CV PDF/DOC/DOCX theo MIME và max 10 MiB, lưu candidate/address/answers trong transaction chỉ gồm writes; không chạy lại duplicate/escalated-issue side effects.
- Submit commit GAP trước khi gọi MM trực tiếp. 4xx dùng `MatchMakerNonRetryableException`, network/5xx dùng `MatchMakerTransientException`; transient mới dispatch job 3 lần thử. Queue enqueue failure trả 503, MM rejection trả 502. HTTP client giữ timeout mặc định như đã chốt.
- Contract OpenAPI được cập nhật tại `documents/Gap-API-Candidate.yaml`; living business flow/route inventory/database relationship cập nhật tại `.business-spec/` với SPEC-039.
- Kiểm thử liên quan đạt: PermanentCandidateIntakeTest (4), PermanentCandidateIntakeServiceTest (1), MeFileTest (8), SyncPermanentCandidateToMatchMakerJobTest (5), MatchMakerPermanentSyncTest (1), CandidateTimingRepositoryTest (1). Toàn bộ PHPUnit đã chạy 500 test với `LOG_CHANNEL=single`; còn 3 failure ở `WorkerWelfareCheckTest` (cả ba nhận HTTP 400 thay vì 200), không thuộc các file/behavior Phase 3. Hai test mới bổ sung sau lượt full suite và toàn bộ test GAP-691 liên quan đều đạt độc lập.
- Phase 3 không sửa inventory ẩn Permanent. Worktree hiện có các filter `is_permanent` ở một số repository, SMS và export, nhưng tính đầy đủ của toàn bộ bề mặt CRS chưa được xác minh trong lần triển khai này.
