# MatchMaker API Contract — CRS Integration

> **Đối tượng sử dụng:** đội MatchMaker/Epsilon cung cấp API và đội CRS tích hợp.
>
> **Phạm vi:** các endpoint MatchMaker mà CRS backend gọi.
>
> **Trạng thái:** bản contract được dựng từ request/response mà CRS hiện đang
> tạo và parse trong source. MM cần xác nhận các field được đánh dấu unknown
> trước khi xem đây là contract chính thức.
>
> Mỗi endpoint được mô tả theo format: mục đích, request, kiểu dữ liệu,
> success response và status lỗi. Không mô tả business flow hoặc call-chain.
> Phân loại adapter được ghi ở phần summary: `Epsilon` hoặc `Bespoke / non-Epsilon`.

## 1. API summary theo adapter

Bảng dưới đây là danh sách tổng quát. Contract request/response chi tiết nằm ở
các section tương ứng bên dưới.

Phân loại dựa trên call path thực tế trong source:

- **Epsilon**: endpoint được gọi qua `App\Externals\EpsilonApi`, là implementation
  được bind cho `MatchMakerApiInterface`.
- **Bespoke / non-Epsilon**: endpoint được gọi trực tiếp bằng Guzzle trong
  `MatchMakerService` hoặc qua `App\Externals\BespokeMatchMaker`, dùng
  `config('matchmaker.api_setting.*')`.

### 1.1. Epsilon

| ID | Method | Path | Mục đích | Trạng thái |
|---|---|---|---|---|
| MM-R01 | GET | /api/Accounts/GetAccessToken | Cấp master token cho CRS | ACTIVE |
| MM-R02 | GET | /api/General/Ping | Health check MatchMaker | ACTIVE |
| MM-R03 | GET | /api/Onboarding/CheckForDuplicate?peo_no={peo_no} | Kiểm tra duplicate theo peo_no | ACTIVE |
| MM-R05 | GET | /api/Candidates/GetDetails | Lấy thông tin cơ bản candidate | ACTIVE |
| MM-R06 | GET | /api/Candidates/GetPicture | Lấy profile picture | ACTIVE |
| MM-R07 | GET | /api/Candidates/GetCareer | Lấy career history | ACTIVE |
| MM-R08 | GET | /api/Candidates/GetEducation | Lấy education history | ACTIVE |
| MM-R09 | GET | /api/Candidates/GetCandidatesByStatusDate?dt={YYYY-MM-DD} | Lấy candidate có status thay đổi | ACTIVE |
| MM-R10 | GET | /api/General/GetMarketingUpdates?sinceDate={YYYY-MM-DD} | Lấy marketing preference thay đổi | ACTIVE |
| MM-R11 | GET | /api/General/GetCandsOnPlan?startDate={YYYY-MM-DD} | Lấy candidate đang on-plan | ACTIVE |
| MM-R12 | POST | /api/General/GetCandsOnPlan?startDate={YYYY-MM-DD}&endDate={YYYY-MM-DD} | Kiểm tra batch candidate đang on-plan | ACTIVE |
| MM-W02 | PUT | /api/Candidates/UpdateCandidateMain | Cập nhật profile hoặc mark Live | ACTIVE |
| MM-W03 | PUT | /api/Candidates/UpdatePaymentDetails | Cập nhật payment và NI | ACTIVE |
| MM-W04 | POST | /api/Candidates/UpdateBankDetails | Cập nhật bank details trực tiếp | ACTIVE |
| MM-W05 | POST | /api/Candidates/UpdateSource?source={peo_source} | Cập nhật recruitment source | ACTIVE |
| MM-W06 | POST | /api/Candidates/AddCandidateCodes | Cập nhật skill codes | ACTIVE |
| MM-W07 | PUT | /api/Candidates/SavePenPicture?pen_picture={value} | Cập nhật pen picture | ACTIVE |
| MM-W08 | PUT | /api/Candidates/UpdateCandidateStarterDeclaration?starterDeclaration={value} | Cập nhật starter declaration | ACTIVE |
| MM-W09 | PUT | /api/Candidates/UpdateCandidateConsultant?conInitials={value} | Cập nhật consultant MM ID | ACTIVE |
| MM-W10 | DELETE | /api/Candidates/DeleteCandidateCareer?emp_no={emp_no} | Xóa career | ACTIVE |
| MM-W11 | POST | /api/Candidates/AddCandidateCareer | Thêm career | ACTIVE |
| MM-W12 | DELETE | /api/Candidates/DeleteCandidateEducation?edu_no={edu_no} | Xóa education | ACTIVE |
| MM-W13 | POST | /api/Candidates/AddCandidateEducation | Thêm education | ACTIVE |
| MM-F02 | POST | /api/Onboarding/SavePictureString/{peo_no} | Upload profile picture existing/duplicate | ACTIVE |
| MM-F04 | POST | /api/Onboarding/UploadAnswer/{peo_no}?chk_no=1 | Gửi RTW answer existing/duplicate | ACTIVE |
| MM-F06 | POST | /api/Onboarding/UploadAttachment/{peo_no}?chk_no=1 | Upload RTW certificate existing/duplicate | ACTIVE |
| MM-F08 | POST | /api/Onboarding/AddToContactLog?peo_no={peo_no} | Tạo contact log existing/Permanent/compliance | ACTIVE |
| MM-F09 | POST | /api/Candidates/UploadAttachment | Gắn file vào contact log | ACTIVE |
| MM-D01 | GET | /api/Candidates/GetPenPicture | Đọc pen picture | RESERVED — chưa có caller |
| MM-D02 | GET | /api/Candidates/GetContactLogAttachments?logNo={log_no} | Lấy contact-log attachments | RESERVED — chưa có caller |
| MM-D03 | POST | /api/Accounts/CandidateLoginPost?platform=Epsilon | Candidate authentication | RESERVED — chưa có caller |
| MM-D04 | POST | /api/Accounts/ClientLoginPost?platform=Epsilon | Client authentication | RESERVED — chưa có caller |
| MM-D05 | POST | /api/Onboarding/UploadAppPack/{peo_no} | Upload App Pack vào contact log đầu tiên | RESERVED — chưa có caller |

### 1.2. Bespoke / non-Epsilon

Đây là các call path không đi qua `EpsilonApi`. Nhóm này gồm các endpoint
standard legacy được gọi trực tiếp trong `MatchMakerService` và skill master
data được gọi qua `BespokeMatchMaker`.

| ID | Method | Path | Mục đích | Trạng thái |
|---|---|---|---|---|
| MM-R04 | GET | /api/Candidates/CheckForDuplicate?peo_email={email}&peo_forename={forename}&peo_surname={surname}&peo_other_tel={tel}&peo_postcode={postcode} | Kiểm tra duplicate trước khi register | ACTIVE |
| MM-R13 | GET | /api/General/GetClassAndCodes/3 | Lấy skill master data | ACTIVE |
| MM-W01 | POST | /api/Candidates/RegisterCandidate | Register candidate standard/Permanent | ACTIVE |
| MM-F01 | POST | /api/Candidates/SavePictureString/{peo_no} | Upload profile picture standard | ACTIVE |
| MM-F03 | POST | /api/Compliance/UploadAnswer/{peo_no}?chk_no=1 | Gửi RTW answer standard | ACTIVE |
| MM-F05 | POST | /api/Compliance/UploadAttachment/{peo_no}?chk_no=1 | Upload RTW certificate standard | ACTIVE |
| MM-F07 | POST | /api/Candidates/AddToContactLog?peo_no={peo_no} | Tạo contact log standard | ACTIVE |
| MM-F10 | POST | /api/Candidates/UploadAppPack/{peo_no} | Upload application pack standard | ACTIVE |

## 2. Quy ước chung

### 2.1. Base URL

Các path trong tài liệu là path tương đối:

- Với **Epsilon**, `GAP` và `GAP_EAST` lần lượt dùng
  `matchmaker.epsilon.api_url_gap` và `matchmaker.epsilon.api_url_gap_east`.
- Với **Bespoke / non-Epsilon**, `GAP` và `GAP_EAST` dùng API setting tương ứng
  trong `matchmaker.api_setting.*`.

### 2.2. Authentication và headers

Request JSON:

~~~http
Authorization: Basic <base64(username:password)>
Content-Type: application/json
~~~

Request multipart:

~~~http
Authorization: Basic <base64(username:password)>
Content-Type: multipart/form-data; boundary=<generated-by-client>
~~~

Các header authentication mà CRS có thể gửi:

| Header | Data type | Trạng thái trong CRS hiện tại | Format | Mục đích |
|---|---|---|---|---|
| `Authorization` | string | Bắt buộc | `Basic ` + base64(`username:password`) | Basic authentication của MatchMaker API. |
| `MasterUserAuth` | string | Conditional | base64(`peo_no:usr_token`) | Master/session token lấy từ `GET /api/Accounts/GetAccessToken`; Epsilon adapter gửi khi master token đã có trong state/cache. |
| `CliUserAuth` | string | Conditional/reserved | base64(`peo_no:usr_token`) | Client session token sau `ClientLoginPost`; method login hiện là private và chưa có runtime caller. |
| `CanUserAuth` | string | Conditional/reserved | base64(`peo_no:usr_token`) | Candidate session token sau `CandidateLoginPost`; method login hiện là private và chưa có runtime caller. |

Notes:

- `MasterUserAuth`, `CliUserAuth` và `CanUserAuth` đều là **string header** trên
  wire; CRS không gửi object hoặc JSON trong các header này.
- `Conditional` nghĩa là header được thêm khi token tương ứng đã được tạo/cache;
  không phải mọi call path hiện tại đều gửi đủ cả ba header.
- Một request có thể có `Authorization` cùng một hoặc nhiều custom auth header
  tùy adapter/state. MM cần xác nhận header nào là bắt buộc cho từng endpoint.
- Các endpoint theo candidate dùng `peo_no` trong path/query hoặc candidate
  context/auth headers theo từng endpoint.

### 2.3. Kiểu dữ liệu và ngày giờ

- Query/path parameter sau khi gửi qua HTTP là string.
- JSON boolean dùng true/false, không dùng chuỗi "true"/"false".
- Ngày không có giờ dùng YYYY-MM-DD.
- Ngày có giờ dùng string ISO-8601 hoặc datetime string theo payload cụ thể.
- ID từ MM nên trả về nhất quán một kiểu. CRS hiện xử lý peo_no chủ yếu dưới
  dạng string.
- unknown nghĩa là CRS chưa có type/schema đủ chắc chắn để công bố.
- Endpoint không có response body bắt buộc được ghi là empty/ignored body.

### 2.4. Status và error

- Nếu không ghi khác, HTTP 2xx là success.
- Các direct call trong standard flow hiện yêu cầu HTTP 200.
- CRS không dùng một error envelope cố định; body lỗi hiện được log dưới dạng
  text hoặc JSON và không được deserialize thành DTO chung. MM nên trả body lỗi
  có message dễ đọc.
- Status lỗi dự kiến: 400, 401/403, 404, 409, 422 hoặc 5xx tùy endpoint.
  Schema error response: unknown đối với CRS hiện tại.

## 3. Read, health và inbound sync

### MM-R01 — GET /api/Accounts/GetAccessToken

**Mục đích**

Cấp master token cho CRS gọi các endpoint Epsilon.

**Request**

- Authentication: Basic Auth.
- Query: none.
- Body: none.

**Success response — HTTP 200**

~~~json
{
  "usr_token": "string"
}
~~~

- usr_token: string, required.
- Các field khác nếu có sẽ không được CRS sử dụng.

**Lỗi**

- HTTP 4xx/5xx: body unknown; CRS coi request là failed.

### MM-R02 — GET /api/General/Ping

**Mục đích**

Health check khả năng kết nối tới MatchMaker.

**Request**

- Authentication: Basic Auth.
- Query: none.
- Body: none.

**Success response — HTTP 2xx**

Body không bắt buộc. CRS chỉ kiểm tra HTTP status; response body bị bỏ qua.

**Lỗi**

HTTP non-2xx hoặc network error được coi là health check failed.

### MM-R03 — GET /api/Onboarding/CheckForDuplicate

**Mục đích**

Kiểm tra candidate đã tồn tại theo peo_no.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| peo_no | string | yes |

Body: none.

CRS gửi `peo_forename` và `peo_surname` sau khi normalize name boundary: ký tự
ngay sau `'` hoặc `’` được uppercase rồi dấu nháy bị loại bỏ. Đây là giá trị
dùng cho duplicate check, không thay đổi name fields lưu trong CRS.

**Success / duplicate response**

Một trong hai dạng sau được CRS hiểu là duplicate:

- HTTP 409, body unknown.
- HTTP 2xx với body chính xác là JSON string ProfileExists.

~~~json
"ProfileExists"
~~~

**Non-duplicate response**

HTTP 2xx với body khác ProfileExists được CRS hiểu là not duplicated.

### MM-R04 — GET /api/Candidates/CheckForDuplicate

**Mục đích**

Kiểm tra duplicate trước khi CRS register candidate mới.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| peo_email | string | yes |
| peo_forename | string | yes |
| peo_surname | string | yes |
| peo_other_tel | string | yes |
| peo_postcode | string | yes |

Body: none.

**Success response — HTTP 200**

Body không có schema bắt buộc đối với CRS; CRS chỉ dùng HTTP 200 để xác nhận
request thành công.

**Lỗi**

HTTP non-200 hoặc network error; body error unknown.

### MM-R05 — GET /api/Candidates/GetDetails

**Mục đích**

Trả thông tin cơ bản của candidate theo candidate context.

**Request**

- Authentication: Basic Auth và candidate context/auth headers.
- Query: none.
- Body: none.

**Success response — HTTP 200**

JSON object:

| Field | Type |
|---|---|
| peo_no | string hoặc unknown |
| peo_title | string |
| peo_forename | string |
| peo_surname | string |
| peo_establish | string |
| peo_town | string |
| peo_county | string |
| peo_postcode | string |
| peo_country | string |
| peo_date_birth | string datetime |
| peo_other_tel | string |
| peo_email | string |
| peo_status | string |
| peo_status_date | string datetime hoặc unknown |
| peo_nationality | string |

CRS map trực tiếp các field trên vào candidate DTO.

### MM-R06 — GET /api/Candidates/GetPicture

**Mục đích**

Lấy profile picture của candidate.

**Request**

- Authentication: Basic Auth và candidate context/auth headers.
- Query: none.
- Body: none.

**Success response — HTTP 200**

- Content: string base64 của image.
- Wrapper JSON: none.
- CRS decode body thành file JPG tạm.

**Lỗi**

Body error unknown; CRS trả empty string.

### MM-R07 — GET /api/Candidates/GetCareer

**Mục đích**

Trả danh sách career hiện tại của candidate.

**Request**

- Authentication: Basic Auth và candidate context/auth headers.
- Query: none.
- Body: none.

**Success response — HTTP 200**

~~~json
{
  "careers": [
    {
      "emp_no": "string-or-unknown",
      "emp_cli_name": "string",
      "emp_job_title": "string",
      "emp_responsibilities": "string",
      "emp_from": "string",
      "emp_to": "string"
    }
  ]
}
~~~

- careers: array<object>, required.
- emp_no: candidate career ID; type hiện chưa được CRS enforce.
- emp_cli_name, emp_job_title, emp_responsibilities: string.
- emp_from, emp_to: date string; format external chưa được CRS validate.

### MM-R08 — GET /api/Candidates/GetEducation

**Mục đích**

Trả danh sách education hiện tại của candidate.

**Request**

- Authentication: Basic Auth và candidate context/auth headers.
- Query: none.
- Body: none.

**Success response — HTTP 200**

~~~json
[
  {
    "edu_no": "string-or-unknown",
    "peo_no": "string-or-unknown",
    "edu_school": "string",
    "edu_quals": "string",
    "edu_from": "string",
    "edu_to": "string"
  }
]
~~~

- Response root: array<object>.
- edu_no, peo_no: ID; type hiện chưa được CRS enforce.
- edu_school, edu_quals: string.
- edu_from, edu_to: date string; format external chưa được CRS validate.

### MM-R09 — GET /api/Candidates/GetCandidatesByStatusDate

**Mục đích**

Trả các candidate có status thay đổi từ ngày được yêu cầu.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| dt | string, YYYY-MM-DD | yes |

Body: none.

**Success response — HTTP 200**

~~~json
[
  {
    "Id": "string",
    "Value": "string"
  }
]
~~~

- Response root: array<object>.
- Id: peo_no, expected string.
- Value: raw MatchMaker status, expected string.

### MM-R10 — GET /api/General/GetMarketingUpdates

**Mục đích**

Trả marketing preference thay đổi từ ngày được yêu cầu.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| sinceDate | string, YYYY-MM-DD | yes |

Body: none.

**Success response — HTTP 200**

~~~json
[
  {
    "Id": "string",
    "Value": true
  }
]
~~~

- Id: peo_no, expected string.
- Value: boolean hoặc string boolean; CRS normalize bằng boolean parser.

### MM-R11 — GET /api/General/GetCandsOnPlan

**Mục đích**

Trả danh sách candidate đang on-plan từ ngày được yêu cầu.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| startDate | string, YYYY-MM-DD | yes |

Body: none.

**Success response — HTTP 200**

~~~json
[
  {
    "Id": "string",
    "Value": "unknown"
  }
]
~~~

- Response root: array<object>.
- Id: peo_no, expected string.
- Value: CRS hiện không dùng; type unknown.

### MM-R12 — POST /api/General/GetCandsOnPlan

**Mục đích**

Kiểm tra một batch peo_no có đang on-plan hay không.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| startDate | string, YYYY-MM-DD | yes |
| endDate | string, YYYY-MM-DD | yes |

Body: JSON array. Element type chưa được enforce trong CRS; giá trị được kỳ vọng
là peo_no.

~~~json
[
  "string"
]
~~~

**Success response — HTTP 200**

JSON array các peo_no đang on-plan:

~~~json
[
  "string"
]
~~~

Response element type được CRS trả nguyên từ MM và chưa validate.

### MM-R13 — GET /api/General/GetClassAndCodes/3

**Mục đích**

Lấy skill master data để CRS tạo skill list và dictionary.

**Request**

- Authentication: Basic Auth.
- Query: none.
- Body: none.

**Success response — HTTP 200**

~~~text
{
  sub_categories: array<object>
    keywords: array<object>
      keyword_no: unknown
      keyword: string
}
~~~

- sub_categories: array<object>, required.
- sub_categories[].keywords: array<object>, required.
- keyword_no: skill ID; type external chưa được CRS enforce.
- keyword: string.

## 4. Candidate registration và update

### MM-W01 — POST /api/Candidates/RegisterCandidate

**Mục đích**

Tạo candidate mới trong MatchMaker, gồm standard candidate và Permanent
candidate.

**Request**

Content-Type: application/json.

#### Standard registration body

~~~text
object
  peo_gdpr_consenttostore: boolean
  peo_gdpr_consenttoshare: boolean
  peo_gdpr_consenttomarketing: boolean
  peo_gdpr_consenttodirectcomm: boolean
  set_avail: boolean
  candidate: object
    peo_title: string
    peo_forename: string
    peo_surname: string
    peo_establish: string
    peo_town: string
    peo_postcode: string
    peo_other_tel: string
    peo_pen: string
    peo_middlename: string
    peo_con: string
    peo_gender: string, enum m/f/o
    peo_county: string
    peo_country: string
    peo_email: string
    peo_source: string
    peo_date_birth: string, YYYY-MM-DDT00:00:00
    peo_salary_sought: int
    peo_seek: string
    peo_nationality: string
    peo_ni: string
    peo_bank_name: string
    peo_bank_acc_name: string
    peo_bank_number: string
    peo_bank_sort_code: string
    peo_pay_method: string
    peo_student_load: boolean
    peo_starter_dec_byemployee: boolean
    peo_no: string, optional
  careers: array<object>
    emp_from: string date
    emp_to: string date
    emp_cli_name: string
    emp_job_title: string
    emp_responsibilities: string
  educations: array<object>
    emp_from: string date
    emp_to: string date
    edu_school: string
    edu_quals: string
  skills_numbers: array<int> hoặc unknown
  overview: object
    transport_type: string
    travel_radius: string
    currently_employed: boolean
    notice_period: string
    available_at_short_notice: boolean
    pre_booked_unavailability: string
    working_restrictions: string
  health_and_safety: object
    owns_safety_boots: object
      own: boolean
      size: string
    owns_hi_viz_vest: object
      own: boolean
      size: string
  shift_preference: object
    days: boolean
    twilights: boolean
    nights: boolean
    continental: boolean
    weekends: boolean
    rotating: boolean
    noons: boolean
  health_and_criminal: object
    any_health_issues: string
    any_convictions: string
    agree_to_check: boolean
  references: array<unknown>, hiện gửi rỗng
  agreements: object
    data_protection: boolean
    opt_out: boolean
    health_disability: boolean
    dbs: boolean
  start_declaration: string, enum A/B/C
~~~

Notes:

- peo_no chỉ được gửi khi candidate đã có MM number.
- `peo_forename`, `peo_middlename` và `peo_surname` được normalize trước khi
  gửi: ký tự sau `'` hoặc `’` được uppercase rồi dấu nháy bị loại bỏ; ví dụ
  `O'nel` → `ONel`. Candidate name trong CRS không bị mutate.
- educations trong RegisterCandidate dùng emp_from/emp_to theo payload hiện tại,
  khác với endpoint AddCandidateEducation dùng edu_from/edu_to.
- Các field được tạo từ CRS có thể là empty string; contract nullability chưa
  được MM/CRS thống nhất.

#### Permanent registration body

~~~text
object
  candidate: object
    peo_title: string
    peo_forename: string
    peo_middlename: string
    peo_surname: string
    peo_email: string
    peo_other_tel: string
    peo_date_birth: string, YYYY-MM-DDT00:00:00
    peo_establish: string
    peo_town: string
    peo_county: string
    peo_postcode: string
    peo_source: string
    peo_status: string, value PERM
  overview: object
    transport_type: string
    travel_radius: string
  health_and_safety: object (Required by MatchMaker API model)
    owns_safety_boots: object { own: boolean, size: string }
    owns_hi_viz_vest: object { own: boolean, size: string }
  shift_preference: object (Required by MatchMaker API model)
    days: boolean, twilights: boolean, nights: boolean, continental: boolean,
    weekends: boolean, rotating: boolean, noons: boolean
  health_and_criminal: object (Required by MatchMaker API model)
    any_health_issues: string, any_convictions: string, agree_to_check: boolean
  agreements: object (Required by MatchMaker API model)
    data_protection: boolean, opt_out: boolean, health_disability: boolean, dbs: boolean
  references: array (Required by MatchMaker API model, empty array for Permanent)
~~~

**Success response — HTTP 200**

~~~json
{
  "peo_no": "string"
}
~~~

- peo_no: string, required.
- CRS lưu peo_no thành peopleNumber.

**Duplicate response — HTTP 409**

Body schema: unknown. CRS map status này thành DUPLICATED.

**Validation/server error**

HTTP 400 hoặc status khác ngoài 200/409. Body schema unknown đối với CRS.

### MM-W02 — PUT /api/Candidates/UpdateCandidateMain

**Mục đích**

Cập nhật thông tin chính của candidate hoặc đánh dấu candidate là Live.

**Request — profile update**

~~~text
object
  peo_title: string
  peo_forename: string
  peo_surname: string
  peo_date_birth: string datetime
  peo_nationality: string
  peo_establish: string
  peo_street: string
  peo_district: string
  peo_town: string
  peo_county: string
  peo_postcode: string
  peo_country: string
  peo_other_tel: string
~~~

Request — mark live:

~~~text
object
  peo_status: string, value Live
  peo_status_date: string datetime
  peo_date_birth: string datetime
~~~

**Success response**

HTTP 2xx. Response body không được CRS parse; empty body được chấp nhận.

Khi flow này được gọi cho standard duplicate candidate, `peo_forename` và
`peo_surname` đã được normalize từ cùng standard payload builder trước khi
Epsilon gửi request.

### MM-W03 — PUT /api/Candidates/UpdatePaymentDetails

**Mục đích**

Đồng bộ payment details và NI number trong candidate update.

**Request**

~~~text
object
  peo_bank_name: string
  peo_bank_acc_name: string
  peo_bank_number: string
  peo_bank_sort_code: string
  peo_ni: string, optional
~~~

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W04 — POST /api/Candidates/UpdateBankDetails

**Mục đích**

Cập nhật bank details trực tiếp sau compliance/GBG bank check.

**Request**

~~~text
object
  peo_bank_name: string
  peo_bank_acc_name: string
  peo_bank_number: string
  peo_bank_sort_code: string
~~~

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W05 — POST /api/Candidates/UpdateSource

**Mục đích**

Đồng bộ recruitment source của candidate.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| source | string | yes |

Body: JSON empty array [].

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W06 — POST /api/Candidates/AddCandidateCodes

**Mục đích**

Đồng bộ skill/classification codes.

**Request**

~~~text
object
  keyword_no_arr: array<unknown>
~~~

Các phần tử được kỳ vọng là numeric skill IDs, nhưng CRS không enforce element
type tại interface này.

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W07 — PUT /api/Candidates/SavePenPicture

**Mục đích**

Đồng bộ interview/pen picture.

**Request**

Query:

| Field | Type | Constraint |
|---|---|---|
| pen_picture | string | source cắt tối đa 1500 ký tự, bỏ dấu nháy đơn và URL-encode |

Body: JSON empty array [].

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W08 — PUT /api/Candidates/UpdateCandidateStarterDeclaration

**Mục đích**

Đồng bộ starter declaration.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| starterDeclaration | string | yes |

Body: JSON empty array [].

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W09 — PUT /api/Candidates/UpdateCandidateConsultant

**Mục đích**

Đồng bộ consultant MM ID.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| conInitials | string | yes |

Body: JSON empty array [].

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W10 — DELETE /api/Candidates/DeleteCandidateCareer

**Mục đích**

Xóa một career hiện tại trước khi CRS thêm career mới.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| emp_no | string trên wire; source type unknown | yes |

Body: none.

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W11 — POST /api/Candidates/AddCandidateCareer

**Mục đích**

Thêm một career vào candidate.

**Request**

~~~text
object
  emp_cli_name: string
  emp_responsibilities: string
  emp_job_title: string
  emp_from: string date
  emp_to: string date
~~~

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W12 — DELETE /api/Candidates/DeleteCandidateEducation

**Mục đích**

Xóa một education hiện tại trước khi CRS thêm education mới.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| edu_no | string trên wire; source type unknown | yes |

Body: none.

**Success response**

HTTP 2xx; body ignored by CRS.

### MM-W13 — POST /api/Candidates/AddCandidateEducation

**Mục đích**

Thêm một education vào candidate.

**Request**

~~~text
object
  peo_no: unknown
  edu_quals: string
  edu_school: string
  edu_from: string date
  edu_to: string date
~~~

**Success response**

HTTP 2xx; body ignored by CRS.

## 5. Picture, compliance, contact log và file

### MM-F01 — POST /api/Candidates/SavePictureString/{peo_no}

**Mục đích**

Upload profile image cho standard registration.

**Request**

Path:

| Field | Type |
|---|---|
| peo_no | string |

JSON body:

~~~text
object
  peo_no: string
  peo_string: string base64
~~~

**Success response**

HTTP 200. Body ignored by CRS.

### MM-F02 — POST /api/Onboarding/SavePictureString/{peo_no}

**Mục đích**

Upload profile image cho duplicate/existing candidate.

**Request**

Path peo_no: string.

JSON body:

~~~text
object
  peo_no: string
  peo_string: string base64
~~~

**Success response**

HTTP 2xx. Body ignored by CRS.

### MM-F03 — POST /api/Compliance/UploadAnswer/{peo_no}

**Mục đích**

Gửi Right to Work answer cho standard candidate.

**Request**

Path:

- peo_no: string.

Query:

- chk_no: string, current value 1.

JSON body:

~~~text
object
  peo_bool: boolean
  peo_text: string
  peo_other: string
  peo_expiry_date: string ISO-8601
  peo_issue_date: string ISO-8601
~~~

**Success response**

HTTP 200. Body ignored by CRS.

### MM-F04 — POST /api/Onboarding/UploadAnswer/{peo_no}

**Mục đích**

Gửi Right to Work answer cho duplicate/existing candidate.

**Request**

Path peo_no: string.

Query chk_no: string, current value 1.

JSON body có cùng schema MM-F03.

**Success response**

HTTP 2xx. Body ignored by CRS.

### MM-F05 — POST /api/Compliance/UploadAttachment/{peo_no}

**Mục đích**

Upload RTW certificate cho standard candidate.

**Request**

Path peo_no: string.

Query chk_no: string, current value 1.

Multipart body:

| Part | Type | Required |
|---|---|---|
| file | file/binary stream | yes |

Filename được gửi cùng multipart part.

**Success response**

HTTP 200. Body ignored by CRS.

### MM-F06 — POST /api/Onboarding/UploadAttachment/{peo_no}

**Mục đích**

Upload RTW certificate cho duplicate/existing candidate.

**Request**

Path peo_no: string.

Query chk_no: string, current value 1.

Multipart body:

| Part | Type | Required |
|---|---|---|
| file | file/binary stream | yes |

Tên part hiện tại thường là file; method vẫn nhận attachment name dạng string.

**Success response**

HTTP 2xx. Body ignored by CRS.

### MM-F07 — POST /api/Candidates/AddToContactLog

**Mục đích**

Tạo contact log cho standard flow.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| peo_no | string | yes |

JSON body:

~~~text
object
  log_action: string
  log_subject: string
  log_txt: string
~~~

**Success response**

HTTP 200. Body ignored by CRS.

### MM-F08 — POST /api/Onboarding/AddToContactLog

**Mục đích**

Tạo contact log cho duplicate, Permanent CV, bank update, welfare và
additional documents.

**Request**

Query peo_no: string.

JSON body:

~~~text
object
  log_action: string
  log_subject: string
  log_txt: string
~~~

**Success response**

HTTP 2xx. CRS dùng raw response body làm log number.

- Response type expected by CRS: string.
- Exact format: unknown; MM nên trả log number ổn định, không bọc envelope nếu
  muốn tương thích với implementation hiện tại.

### MM-F09 — POST /api/Candidates/UploadAttachment

**Mục đích**

Gắn một file vào contact log đã tạo.

**Request**

Headers:

| Header | Type | Value |
|---|---|---|
| AttachRef | string | log number từ MM-F08 hoặc MM-F07 context |
| AttachType | string | 3 |

Multipart body:

| Part | Type | Required |
|---|---|---|
| attachmentName | file/binary stream | yes |

attachmentName là tên part động; trong các call hiện tại thường là file hoặc
tên file.

**Success response**

HTTP 2xx. Body ignored by CRS.

### MM-F10 — POST /api/Candidates/UploadAppPack/{peo_no}

**Mục đích**

Upload application pack cho standard candidate.

**Request**

Path peo_no: string.

Multipart body:

| Part | Type | Required |
|---|---|---|
| file | file/binary stream | yes |

**Success response**

HTTP 200. Body ignored by CRS.

## 6. Endpoint được định nghĩa nhưng chưa có integration caller hiện tại

Các endpoint dưới đây còn method/constant trong implementation nhưng chưa tìm
thấy caller runtime hiện tại. Chúng được giữ ở dạng reserved contract để MM
không hiểu nhầm là CRS đang sử dụng.

### MM-D01 — GET /api/Candidates/GetPenPicture

**Mục đích dự kiến**

Đọc pen picture của candidate.

**Request**

- Candidate context/auth headers.
- Query/body: none.

**Success response**

Raw JSON/value. Type và schema: unknown.

**Integration status**

No current CRS caller found.

### MM-D02 — GET /api/Candidates/GetContactLogAttachments

**Mục đích dự kiến**

Lấy danh sách attachment của contact log.

**Request**

Query:

| Field | Type | Required |
|---|---|---|
| logNo | string | yes |

Body: none.

**Success response**

Array được trả nguyên từ MM. Item schema: unknown.

**Integration status**

No current CRS caller found.

### MM-D03 — POST /api/Accounts/CandidateLoginPost?platform=Epsilon

**Mục đích dự kiến**

Candidate authentication.

**Request**

JSON body:

~~~text
object
  username: string
  password: string
~~~

**Success response dự kiến**

~~~text
object
  peo_no: unknown
  usr_token: string
  usr_token_expiry: string datetime
~~~

**Integration status**

Method hiện private và không có current caller.

### MM-D04 — POST /api/Accounts/ClientLoginPost?platform=Epsilon

**Mục đích dự kiến**

Client authentication.

**Request**

JSON body:

~~~text
object
  username: string
  password: string
~~~

**Success response dự kiến**

~~~text
object
  peo_no: unknown
  usr_token: string
~~~

**Integration status**

Method hiện private và không có current caller.

### MM-D05 — POST /api/Onboarding/UploadAppPack/{peo_no}

**Mục đích dự kiến**

Upload App Pack vào contact log đầu tiên.

**Request**

- Path peo_no: string.
- Body: unknown; không có caller hiện tại để xác định payload.
- Response: unknown.

**Integration status**

Chỉ còn constant/comment trong source. EpsilonApi::uploadAppPack() hiện dùng
MM-F08 và MM-F09 thay thế.

## 7. Validation items trước khi MM phát hành contract chính thức

- Xác nhận type và nullability của các ID: peo_no, emp_no, edu_no, keyword_no,
  Id và log number.
- Xác nhận format chính thức của các field date/time.
- Xác nhận response body của các endpoint hiện CRS chỉ kiểm tra HTTP status.
- Xác nhận error response envelope để CRS có thể parse thống nhất.
- Xác nhận response format của AddToContactLog có phải raw log number hay
  JSON-wrapped value.
- Xác nhận endpoint UploadAppPack của Onboarding có còn được hỗ trợ hay không.

## 8. Ghi chú implementation

- Đây là contract hướng MM/CRS, nhưng được dựng từ source CRS hiện tại; các mục
  unknown không nên được xem là official MM schema cho đến khi MM xác nhận.
- CODE deviation hiện có: EpsilonApi dùng HTTP client với withoutVerifying().
- CODE/CONFIG deviation cần kiểm tra: WorkerWelfareCheckService đọc
  config('match_maker.db'), trong khi config chính hiện tại là matchmaker.
- Chưa phát hiện DATA hoặc INFRASTRUCTURE deviation trong phạm vi rà soát này.
