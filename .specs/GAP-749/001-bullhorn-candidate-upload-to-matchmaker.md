# SPEC: GAP-749 — Bullhorn Candidate Upload to MatchMaker

> **Task**: [GAP-749](https://gap-group.atlassian.net/browse/GAP-749)
> **Trạng thái**: `DRAFT`
> **Ngày tạo**: 2026-10-28
> **Cập nhật**: 2026-10-29
> **Author**: Antigravity

---

## 1. Tổng quan

### 1.1. Bối cảnh & Yêu cầu
Hawk 3 Talent Solutions đang hoàn tất quá trình chuyển đổi CRM từ Bullhorn sang MatchMaker nhằm cắt giảm chi phí bản quyền Bullhorn và đồng bộ hóa quy trình tuyển dụng Permanent (PERM) trên toàn tập đoàn. Tất cả dữ liệu Khách hàng (Clients) đã được chuyển đổi thành công sang MatchMaker, hiện còn tồn đọng tập dữ liệu Ứng viên Permanent (6,334 bản ghi) từ Bullhorn cần được import vào MatchMaker thông qua API (one-off upload) trước thời hạn cuối tuần.

Tệp dữ liệu nguồn đính kèm Jira (`1.csv` dung lượng ~1.7MB) gồm 19 cột dữ liệu:
`First Name` | `Surname` | `Address Line1` | `Address Line 2` | `Town` | `County` | `Country` | `Post Code` | `Mobile Phone` | `Email` | `Consultant ID` | `Source` | `Status` | `Position Sought` | `Last Contact` | `Registration Date` | `Industry Sector` | `Interview Notes` | `Contact Log`

### 1.2. Thống kê dữ liệu thực tế từ `1.csv` (6,334 dòng)
- **Tổng số dòng**: 6,334 ứng viên.
- **Status**: 100% là `PERM`.
- **Source**: 100% là `Bullhorn`.
- **Country**: 100% là `United Kingdom`.
- **Consultant ID**: 7 mã (`CC1`: 1445, `DG5`: 1338, `RW1`: 1316, `JL1`: 1022, `DG3`: 656, `BP1`: 471, `MT1`: 86).
- **Address Line 1**: 3,968 dòng trống (62.6%).
- **Address Line 2**: 5,894 dòng trống (93.1%).
- **Town**: 2,203 dòng trống (34.8%).
- **Post Code**: 3,397 dòng trống (53.6%).
- **County**: 2,584 dòng trống (40.8%).
- **Mobile Phone**: 172 dòng trống (2.7%).
- **Email**: 19 dòng trống (0.3%).
- **Position Sought**: 572 dòng trống (9.0%). Độ dài tối đa 99 ký tự (cần cắt an toàn về 30 ký tự theo MatchMaker `peo_seek`, đồng thời lưu nguyên văn vào Notes).
- **Registration Date**: 100% có ngày đăng ký (định dạng `M/D/YYYY` hoặc `MM/DD/YYYY`).
- **Last Contact**: 1,368 dòng trống (21.6%).
- **Industry Sector**: 20 nhóm ngành (Top: `Human Resources`, `Engineering`, `Accounts & Finance`, `Manufacturing`).
- **Interview Notes**: 6,296 dòng có dữ liệu (99.4%).
- **Contact Log**: 4,968 dòng có nhật ký liên lạc (78.4%), gồm các chuỗi phân tách bởi dấu `;` (Ví dụ: `Outbound Call - 09/18/2026 ; Parser Note - 08/19/2026`).

### 1.3. Phạm vi Nghiệp vụ: Đích đến là MatchMaker, KHÔNG tạo User trong CRS
- **Mục tiêu**: Toàn bộ dữ liệu 6,334 ứng viên này là dữ liệu CRM lịch sử của Hawk 3 trên Bullhorn, **đích đến 100% là đẩy sang MatchMaker** để các Consultant của Hawk 3 truy cập và thao tác trực tiếp trên giao diện MatchMaker.
- **TUYỆT ĐỐI KHÔNG tạo bản ghi trong bảng `candidates` của CRS**:
  - Bảng `candidates` trong CRS là tài khoản người dùng portal/app (cần password, token, quy trình xác minh RTW, ngân hàng, questionnaires, v.v.).
  - Việc insert vào bảng `candidates` sẽ làm ô nhiễm dữ liệu ứng viên CRS, làm sai lệch báo cáo compliance, pipeline tuyển dụng và kích hoạt nhầm các Cron tự động (như gửi email/SMS nhắc nhở phỏng vấn từ cron [`RemindScreeningCallCompletion`](file:///Users/nexusfrontiertech/projects/gap-web-backend/app/Console/Commands/RemindScreeningCallCompletion.php)).

### 1.4. Đánh giá API Contract Pre-Deployment Gate
- **Đánh giá ảnh hưởng API Docs**: `N/A — no API contract/API docs change`.
- **Lý do**: Đây là tác vụ one-off migration dữ liệu từ hệ thống Bullhorn sang MatchMaker thông qua Laravel Artisan Command (`candidates:upload-bullhorn-to-matchmaker`) và MatchMaker External API. Không tạo mới, sửa đổi hoặc xóa bất kỳ public API endpoint nào của CRS (`routes/api.php`, `routes/consultant.php`, `routes/candidate.php`). Do đó không ảnh hưởng tới `~/projects/crs-api-docs`.

---

## 2. Database Design

Không thay đổi cấu trúc bảng (schema migrations) của database CRS.
Tuy nhiên, để tối ưu hoá việc tra cứu, tránh duplicate và đồng bộ snapshot ngay lập tức cho các tính năng hiện tại của CRS (Duplicate check, Search):
- Sau khi MatchMaker tạo thành công và trả về `peo_no`, hệ thống sẽ lưu/cập nhật snapshot vào bảng nội bộ `match_maker_candidates` của CRS với:
  - `peo_no`: ID do MatchMaker cấp.
  - `email`: email từ CSV (nếu có).
  - `first_name`, `last_name`: tên đã chuẩn hoá.
  - `phone_number`: số điện thoại (nếu có).
  - `status`: `MatchMakerCandidate::STATUS_PERM` (`PERM`).
  - `db_source`: `MatchMakerApiInterface::DB_SOURCE_GAP` (`GAP`).
  - `has_crs_account`: `false` (xác nhận ứng viên chỉ nằm trên MatchMaker, không có tài khoản CRS).

---

## 3. Mapping Dữ Liệu: Bullhorn CSV → MatchMaker API

### 3.1. MatchMaker Endpoint & Cấu trúc Payload
MatchMaker sử dụng endpoint đăng ký candidate Bespoke:
`POST {api_url}Candidates/RegisterCandidate` (Header: `Authorization: Basic ...`, `Content-Type: application/json`).
Legal Entity áp dụng: **Hawk 3 Talent Solutions** thuộc Legal Entity ID 5 (`Gap Personnel Holdings Limited`), sử dụng cấu hình MatchMaker `default` với database target là `GAP` (theo [`config/matchmaker.php`](file:///Users/nexusfrontiertech/projects/gap-web-backend/config/matchmaker.php#L30)).

Theo schema bắt buộc của MatchMaker C# API (đã được xác thực trong GAP-691), payload gửi lên phải chứa đủ 6 blocks:
1. `candidate`: Thông tin cá nhân cơ bản của ứng viên.
2. `overview`: `transport_type`, `travel_radius`.
3. `health_and_safety`: `owns_safety_boots`, `owns_hi_viz_vest`.
4. `shift_preference`: Ca làm việc.
5. `health_and_criminal`: Khai báo y tế / tiền án.
6. `agreements`: Các thoả thuận cơ bản (`data_protection = true`).
7. `references`: Mảng rỗng `[]`.

---

### 3.2. Chiến lược xử lý các trường bị trống: Truyền rỗng (`""`) vs. Dùng Default

Qua phân tích OpenAPI model và C# validation của MatchMaker API:

#### Nhóm 1: Các trường HOÀN TOÀN TRUYỀN RỖNG (`""`) ĐƯỢC (Optional trong MatchMaker)
Các trường này không bị ràng buộc `[Required]` trong C# backend, MatchMaker chấp nhận chuỗi rỗng:
- **`Address Line 2` (`candidate.peo_street`)**: 93.1% dòng trống 👉 **Truyền `""`**.
- **`County` (`candidate.peo_county`)**: 40.8% dòng trống 👉 **Truyền `""`**.
- **`Position Sought` (`candidate.peo_seek`)**: 9.0% dòng trống 👉 **Truyền `""`** (nếu có thì cắt tối đa 30 ký tự cho `peo_seek`, đồng thời lưu nguyên văn vào `peo_pen`).
- **`Email` (`candidate.peo_email`)**: 19 dòng trống (0.3%) 👉 **Truyền `""`**.
- **`Interview Notes`**: 38 dòng trống 👉 **Truyền `""`** (các phần thông tin khác vẫn ghi vào `peo_pen`).
- **`Contact Log`**: 1,366 dòng trống (21.6%) 👉 **Bỏ qua không gọi API `AddToContactLog`** (vừa đúng nghiệp vụ vừa giảm tải HTTP request).

#### Nhóm 2: Các trường BẮT BUỘC PHẢI DÙNG DEFAULT (Không được truyền rỗng `""`)
Nếu truyền `""` hoặc `null` ở các trường này, MatchMaker C# API sẽ trả về lỗi **HTTP 400 Bad Request** và từ chối lưu:
- **`Registration Date` / Ngày sinh (`candidate.peo_date_birth`)**:
  - *Lý do*: Là kiểu C# `DateTime`. Nếu truyền chuỗi rỗng `""`, bộ parse JSON của .NET sẽ throw exception: `"Could not convert string to DateTime"`.
  - 👉 **Default**: Dùng ngày giả lập chuẩn `1900-01-01T00:00:00` hoặc format ngày đăng ký sang ISO `YYYY-MM-DDT00:00:00`. Đồng thời ghi rõ ngày đăng ký gốc vào `peo_pen`.
- **`Address Line 1` (`peo_establish`), `Town` (`peo_town`), `Post Code` (`peo_postcode`)**:
  - *Lý do*: Có thuộc tính `[Required]` trong C# `CandidateModel`. Mặc định ASP.NET không cho phép chuỗi rỗng (`AllowEmptyStrings = false`), nếu gửi `""` sẽ dính lỗi `"The ... field is required"`.
  - 👉 **Default**: Điền `'N/A'` (để vừa pass validation, vừa giúp Consultant trên giao diện MatchMaker nhận biết ngay là ứng viên chưa có địa chỉ để hỏi bổ sung khi liên hệ).
- **`Title` (`candidate.peo_title`)**:
  - *Lý do*: File CSV **hoàn toàn không có cột này** (100% dòng thiếu), nhưng MatchMaker bắt buộc có title từ 1–4 ký tự.
  - 👉 **Default**: Mặc định gán `'mr'` (theo tiền lệ ở các flow đăng ký hiện tại của CRS) hoặc `'Mx'`.
- **`Mobile Phone` (`candidate.peo_other_tel`)**:
  - *Lý do*: Có 172 dòng không có số điện thoại, nhưng MatchMaker bắt buộc `peo_other_tel`.
  - 👉 **Default**: Điền `'N/A'` hoặc `'00000000000'`.
- **5 khối Object bắt buộc ở cấp Root (`RegUploadModelV12`)**:
  - Gồm `overview`, `health_and_safety`, `shift_preference`, `health_and_criminal`, `agreements`.
  - 👉 **Default Objects**: Sử dụng cấu trúc mặc định an toàn đã kiểm chứng ở GAP-691 (SPEC-019), không để `null` hay `{}`.

---

### 3.3. Bảng ánh xạ chi tiết 19 cột CSV sang MatchMaker

| Cột CSV | Cột MatchMaker | Quy tắc xử lý khi có dữ liệu | Xử lý khi bị trống (Rỗng vs Default) |
|---|---|---|---|
| `First Name` | `candidate.peo_forename` | Chuẩn hoá tên: Viết hoa ký tự ngay sau dấu nháy (`'` hoặc `’`) và loại bỏ dấu nháy (ví dụ `O'Connor` → `OConnor`). Cắt tối đa 16 ký tự. | 100% có dữ liệu (0 dòng trống) |
| `Surname` | `candidate.peo_surname` | Chuẩn hoá tên theo quy tắc bỏ nháy tương tự, cắt tối đa 20 ký tự. | 100% có dữ liệu (0 dòng trống) |
| `Address Line1` | `candidate.peo_establish` | Cắt tối đa 30 ký tự. | 🔴 **Default `'N/A'`** (bắt buộc do `[Required]`) |
| `Address Line 2` | `candidate.peo_street` | Cắt tối đa 30 ký tự. | 🟢 **Truyền rỗng `''`** |
| `Town` | `candidate.peo_town` | Cắt tối đa 30 ký tự. | 🔴 **Default `'N/A'`** (bắt buộc do `[Required]`) |
| `County` | `candidate.peo_county` | Cắt tối đa 25 ký tự. | 🟢 **Truyền rỗng `''`** |
| `Country` | `candidate.peo_country` | Cố định `'United Kingdom'`, cắt tối đa 20 ký tự. | 100% có dữ liệu (0 dòng trống) |
| `Post Code` | `candidate.peo_postcode` | Viết hoa toàn bộ (`strtoupper`), loại bỏ khoảng trắng thừa, cắt tối đa 10 ký tự. | 🔴 **Default `'N/A'`** (bắt buộc do `[Required]`) |
| `Mobile Phone` | `candidate.peo_other_tel` | Format số điện thoại, cắt tối đa 20 ký tự. | 🔴 **Default `'N/A'`** (bắt buộc do `[Required]`) |
| `Email` | `candidate.peo_email` | Trim, lowercase, cắt tối đa 80 ký tự. | 🟢 **Truyền rỗng `''`** |
| `Consultant ID` | `candidate.peo_con` | Mã 3 ký tự của Consultant (CC1, DG5, RW1, JL1, DG3, BP1, MT1). | 100% có dữ liệu (0 dòng trống) |
| `Source` | `candidate.peo_source` | Cố định `'Bullhorn'` (tối đa 19 ký tự). | 100% có dữ liệu (0 dòng trống) |
| `Status` | `candidate.peo_status` | Cố định `'PERM'` (tối đa 15 ký tự). | 100% có dữ liệu (0 dòng trống) |
| `Position Sought` | `candidate.peo_seek` | Cắt tối đa 30 ký tự cho `peo_seek`. Đồng thời giữ nguyên văn bản đầy đủ vào `peo_pen` (Pen Picture) để Consultant xem được trọn vẹn. | 🟢 **Truyền rỗng `''`** |
| `Registration Date` | `candidate.peo_date_birth` & Notes | Vì Bullhorn không có DOB, parse sang ISO `YYYY-MM-DDT00:00:00` cho `peo_date_birth`. Ghi rõ ngày đăng ký vào `peo_pen`. | 🔴 **Default `1900-01-01T00:00:00`** (bắt buộc DateTime) |
| `Last Contact` | `candidate.peo_pen` | Ghi vào phần Pen picture: `Last Contact: MM/DD/YYYY`. | 🟢 **Bỏ qua dòng này trong Pen picture** |
| `Industry Sector` | `candidate.peo_pen` | Ghi vào phần Pen picture: `Industry Sector: {sector}`. | 🟢 **Bỏ qua dòng này trong Pen picture** |
| `Interview Notes` | `candidate.peo_pen` | Gộp chung tạo thành bản tóm tắt Pen Picture hoàn chỉnh trong MatchMaker. | 🟢 **Truyền rỗng `''`** |
| `Contact Log` | `AddToContactLog` API | Sau khi tạo thành công candidate (`peo_no`), gọi API `AddToContactLog` tạo Contact Log entries ghi lại lịch sử tiếp xúc từ Bullhorn. | 🟢 **Bỏ qua không gọi API** |

### 3.4. Định dạng `peo_pen` (Pen Picture) được tổng hợp
Nhằm đảm bảo các trường thông tin không có cột riêng trong form Candidate của MatchMaker (`Position Sought` dài > 30 chars, `Industry Sector`, `Last Contact`, `Registration Date`, `Interview Notes`) không bị thất thoát, hệ thống sẽ format `peo_pen` theo mẫu chuẩn:
```text
[Bullhorn Import Summary]
Sector: Accounts & Finance
Position Sought: Accounts Assistant Purchase Ledger Full Time
Registered: 09/18/2026 | Last Contact: 09/18/2026
Notes: Customer Service ; Bank Reconciliations
```

### 3.5. Upload Contact Log vào MatchMaker
Sau khi nhận được `peo_no` từ `RegisterCandidate`, nếu bản ghi có cột `Contact Log`, hệ thống sẽ gọi:
`POST {api_url}Candidates/AddToContactLog?peo_no={peo_no}`
- `log_action`: `'Bullhorn Migration'`
- `log_subject`: `'Bullhorn Contact Log History'`
- `log_txt`: Nội dung lịch sử liên lạc từ Bullhorn (ví dụ: `Outbound Call - 09/18/2026 ; Parser Note - 08/19/2026`).

---

## 4. Kiến trúc & Thiết kế Implementation

### 4.1. Kiến trúc phân lớp chuẩn
```
Artisan Command: candidates:upload-bullhorn-to-matchmaker
    ↓
BullhornCandidateUploadServiceInterface
    ↓
BullhornCandidateUploadService
    ↓
MatchMaker API (GuzzleHttp / Basic Auth) + MatchMakerCandidateRepository (Local Snapshot)
```

### 4.2. Chi tiết các thành phần

#### 1. Artisan Command: `app/Console/Commands/Once/UploadBullhornCandidatesToMatchMaker.php`
- **Signature**:
  ```bash
  php artisan candidates:upload-bullhorn-to-matchmaker
      {file : Đường dẫn tới tệp CSV (mặc định storage/app/bullhorn_candidates.csv)}
      {--chunk=50 : Số lượng bản ghi xử lý trong một đợt}
      {--offset=0 : Vị trí dòng bắt đầu (hỗ trợ resume khi gặp gián đoạn)}
      {--limit=0 : Giới hạn số lượng bản ghi cần upload (0 = toàn bộ)}
      {--delay=100 : Độ trễ giữa các request tính bằng milliseconds để bảo vệ MatchMaker API}
      {--dry-run : Chạy giả lập kiểm tra dữ liệu và format payload, không gửi request thật}
  ```
- **Tính năng an toàn**:
  - Có Progress Bar hiển thị trực quan tiến độ.
  - Tự động xuất tệp báo cáo kết quả chi tiết sau khi chạy tại `storage/logs/bullhorn_upload_results_{timestamp}.csv` gồm các cột: `row_index`, `email`, `name`, `status` (`SUCCESS`, `DUPLICATE`, `FAILED`), `matchmaker_peo_no`, `error_message`.
  - Hỗ trợ resume: Nếu quá trình bị ngắt ở dòng 2,450, có thể chạy lại với `--offset=2450` mà không phải chạy lại từ đầu.

#### 2. Service Layer: `App\Contracts\Services\BullhornCandidateUploadServiceInterface` & `App\Services\BullhornCandidateUploadService`
- **Nhiệm vụ**:
  - Đọc và validate từng dòng của CSV (xử lý encoding UTF-8 / BOM an toàn).
  - Chuẩn hoá họ tên (loại bỏ `'`, uppercase ký tự sau dấu nháy).
  - Áp dụng chiến lược: trường optional truyền `""`, trường bắt buộc điền giá trị default an toàn (`'N/A'`, `'mr'`, `'1900-01-01T00:00:00'`).
  - Dựng payload đăng ký `candidate`, `overview`, `health_and_safety`, `shift_preference`, `health_and_criminal`, `agreements`.
  - Thực thi gửi request sang MatchMaker với Guzzle client (`timeout`, `retry` khi gặp transient network error).
  - Bắt lỗi:
    - HTTP 200: Thành công, lấy `peo_no`, gửi tiếp Contact Log (nếu có nội dung), lưu snapshot `match_maker_candidates`.
    - HTTP 409 (Duplicated): Đánh dấu `DUPLICATE`, log cảnh báo.
    - HTTP 400 / 500: Đánh dấu `FAILED`, log chi tiết lỗi từ MatchMaker body.

#### 3. Service Provider Binding: `app/Providers/AppServiceProvider.php`
Đăng ký binding:
```php
$this->app->bind(
    \App\Contracts\Services\BullhornCandidateUploadServiceInterface::class,
    \App\Services\BullhornCandidateUploadService::class
);
```

---

## 5. Data Origin & Call Chain Verification

| Biến / Trường dữ liệu | Nơi sử dụng | Nguồn cung cấp | Đã xác thực |
|---|---|---|---|
| `row['First Name']` | `candidate.peo_forename` | CSV cột 0 | ✅ Xác thực tồn tại trong `1.csv` |
| `row['Surname']` | `candidate.peo_surname` | CSV cột 1 | ✅ Xác thực tồn tại trong `1.csv` |
| `row['Address Line1']` | `candidate.peo_establish` | CSV cột 2 | ✅ Có fallback default `'N/A'` |
| `row['Address Line 2']` | `candidate.peo_street` | CSV cột 3 | ✅ Truyền rỗng `''` khi trống |
| `row['Town']` | `candidate.peo_town` | CSV cột 4 | ✅ Có fallback default `'N/A'` |
| `row['County']` | `candidate.peo_county` | CSV cột 5 | ✅ Truyền rỗng `''` khi trống |
| `row['Country']` | `candidate.peo_country` | CSV cột 6 | ✅ Giá trị cố định `'United Kingdom'` |
| `row['Post Code']` | `candidate.peo_postcode` | CSV cột 7 | ✅ Chuyển uppercase, fallback default `'N/A'` |
| `row['Mobile Phone']` | `candidate.peo_other_tel` | CSV cột 8 | ✅ Fallback default `'N/A'` |
| `row['Email']` | `candidate.peo_email` | CSV cột 9 | ✅ Trim/lowercase, truyền rỗng `''` khi trống |
| `row['Consultant ID']` | `candidate.peo_con` | CSV cột 10 | ✅ 7 mã consultant hợp lệ |
| `row['Source']` | `candidate.peo_source` | CSV cột 11 | ✅ Giá trị cố định `'Bullhorn'` |
| `row['Status']` | `candidate.peo_status` | CSV cột 12 | ✅ Giá trị cố định `'PERM'` |
| `row['Position Sought']` | `peo_seek` & `peo_pen` | CSV cột 13 | ✅ Cắt 30 ký tự cho `peo_seek`, giữ full trong `peo_pen` (truyền `''` khi trống) |
| `row['Registration Date']` | `peo_date_birth` & `peo_pen` | CSV cột 15 | ✅ Parse ISO format `YYYY-MM-DDT00:00:00`, default `1900-01-01T00:00:00` |
| `row['Last Contact']` | `peo_pen` | CSV cột 14 | ✅ Gộp vào `peo_pen` (bỏ qua nếu trống) |
| `row['Industry Sector']` | `peo_pen` | CSV cột 16 | ✅ Gộp vào `peo_pen` (bỏ qua nếu trống) |
| `row['Interview Notes']` | `peo_pen` | CSV cột 17 | ✅ Gộp vào `peo_pen` (truyền `''` nếu trống) |
| `row['Contact Log']` | `AddToContactLog` body | CSV cột 18 | ✅ Gọi `AddToContactLog` API (bỏ qua nếu trống) |

---

## 6. Constants & Configuration

```php
// Trong App\Services\BullhornCandidateUploadService
public const DEFAULT_COUNTRY = 'United Kingdom';
public const DEFAULT_FALLBACK_FIELD = 'N/A';
public const DEFAULT_TITLE = 'mr';
public const DEFAULT_PHONE = 'N/A';
public const DEFAULT_BIRTH_DATE = '1900-01-01T00:00:00';
public const SOURCE_BULLHORN = 'Bullhorn';
public const STATUS_PERM = 'PERM';

public const CONTACT_LOG_ACTION_MIGRATION = 'Bullhorn Migration';
public const CONTACT_LOG_SUBJECT_HISTORY = 'Bullhorn Contact Log History';

public const MAX_LENGTH_FORENAME = 16;
public const MAX_LENGTH_SURNAME = 20;
public const MAX_LENGTH_ESTABLISH = 30;
public const MAX_LENGTH_STREET = 30;
public const MAX_LENGTH_TOWN = 30;
public const MAX_LENGTH_COUNTY = 25;
public const MAX_LENGTH_POSTCODE = 10;
public const MAX_LENGTH_PHONE = 20;
public const MAX_LENGTH_EMAIL = 80;
public const MAX_LENGTH_SEEK = 30;
public const MAX_LENGTH_CON = 3;
```

---

## 7. Files cần tạo / sửa

### 7.1. Files mới
| File | Namespace | Mô tả |
|---|---|---|
| `app/Console/Commands/Once/UploadBullhornCandidatesToMatchMaker.php` | `App\Console\Commands\Once` | Artisan Command thực thi batch upload với resume, dry-run, progress bar và xuất log CSV |
| `app/Contracts/Services/BullhornCandidateUploadServiceInterface.php` | `App\Contracts\Services` | Service Interface |
| `app/Services/BullhornCandidateUploadService.php` | `App\Services` | Implementation chứa toàn bộ logic parse CSV, mapping dữ liệu, sanitize, xử lý rỗng/default, gọi MatchMaker API và lưu snapshot |
| `tests/Unit/Services/BullhornCandidateUploadServiceTest.php` | `Tests\Unit\Services` | Unit Test bao phủ 100% logic transform payload, xử lý sanitize dấu nháy, fallback khi thiếu địa chỉ, xử lý HTTP 200/409/400 |

### 7.2. Files sửa
| File | Thay đổi |
|---|---|
| `app/Providers/AppServiceProvider.php` | Đăng ký binding `BullhornCandidateUploadServiceInterface` → `BullhornCandidateUploadService` |

---

## 8. Test Cases & Verification Plan

### 8.1. Service Unit Tests (`tests/Unit/Services/BullhornCandidateUploadServiceTest.php`)
1. `test_build_registration_payload_with_full_data`:
   - Dựng payload từ dòng CSV đầy đủ.
   - Assert các trường `candidate`, `overview`, `health_and_safety`, `shift_preference`, `health_and_criminal`, `agreements`.
   - Assert `peo_seek` được cắt về tối đa 30 ký tự, `peo_pen` chứa đầy đủ notes, sector, last contact.
2. `test_sanitize_candidate_name_strips_apostrophe_and_uppercases_next_letter`:
   - Test tên `O'Neil` → `ONeil`, `D'Arcy` → `DArcy`.
3. `test_fallback_values_for_missing_required_fields`:
   - Test dòng thiếu Address Line 1, Town, Postcode tự động điền default `'N/A'`.
   - Test dòng thiếu Title tự động điền `'mr'`.
   - Test dòng thiếu Phone tự động điền `'N/A'`.
   - Test dòng thiếu Address Line 2, County, Seek, Email tự động để chuỗi rỗng `''`.
4. `test_successful_registration_and_contact_log_and_local_snapshot`:
   - Mock MatchMaker HTTP client trả 200 `{"peo_no": "99901"}`.
   - Verify gọi tiếp `AddToContactLog`.
   - Verify tạo snapshot trong `match_maker_candidates` với `has_crs_account = false`.
5. `test_skips_contact_log_when_empty`:
   - Test dòng không có Contact Log thì không gọi API `AddToContactLog`.
6. `test_handles_duplicated_candidate_409`:
   - Mock MatchMaker HTTP client trả 409 Conflict.
   - Verify không crash, log trạng thái `DUPLICATE`.
7. `test_handles_validation_error_400`:
   - Mock MatchMaker HTTP client trả 400 Bad Request.
   - Verify ghi nhận lỗi vào audit log mà không dừng cả batch.

### 8.2. Verification bằng Artisan Command CLI
- Chạy thử `--dry-run`:
  ```bash
  php artisan candidates:upload-bullhorn-to-matchmaker /Users/nexusfrontiertech/.local/share/jira-cloud-mcp/workspace/1.csv --dry-run --limit=5
  ```
- Kiểm tra tính đúng đắn của payload format và output log trước khi chạy live trên môi trường Staging/Production.

---

## 9. Checklist trước khi Approve
- [x] Đã làm rõ phạm vi: Chỉ đẩy dữ liệu sang MatchMaker, KHÔNG tạo user trong bảng `candidates` của CRS.
- [x] Đã phân loại chi tiết: Trường nào truyền rỗng `""` (Optional) và trường nào bắt buộc dùng Default (`'N/A'`, `'mr'`, `1900-01-01T00:00:00'`).
- [x] Đã rà soát toàn bộ MatchMaker API OpenAPI contract và các ràng buộc schema C# từ GAP-691.
- [x] Đã xác định rõ Legal Entity và DB target (`Hawk 3` -> Legal Entity 5 -> DB `GAP`).
- [x] Đã thiết kế phương án xử lý trường thiếu và trường quá dài (`Position Sought` > 30 chars).
- [x] Đã thiết kế cơ chế bảo vệ MatchMaker API (delay, chunking, resume offset, audit CSV log).
- [x] Tuân thủ 100% nguyên tắc kiến trúc và quy định workspace.
