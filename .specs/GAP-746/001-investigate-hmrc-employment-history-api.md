# SPEC-GAP-746: INVESTIGATE - Candidate - Pull Employment History HMRC API

> **Trạng thái**: `ANALYSIS_COMPLETE`
> **Ngày tạo**: 2026-10-21
> **Task Key**: [GAP-746](https://gappersonnel.atlassian.net/browse/GAP-746)
> **Author**: Antigravity & Engineering Team
> **Mục tiêu**: Khảo sát tính khả thi, năng lực, cơ chế hoạt động, chi phí và các giải pháp thay thế cho việc tích hợp HMRC API nhằm tự động điền Employment History cho ứng viên qua National Insurance (NI) number.

---

## 1. Tóm tắt yêu cầu từ Task GAP-746

- **Bối cảnh hiện tại**: Ứng viên khi đăng ký/onboarding vào hệ thống CRS (GAP Personnel) hiện phải tự nhập thủ công toàn bộ lịch sử làm việc (Employment History) và cung cấp thông tin của 2 người tham chiếu (References).
- **Đề xuất từ Product (Simone & Brian Halstead)**:
  - Khảo sát API của HMRC (His Majesty's Revenue and Customs): [HMRC Individual Employment API v1.2](https://developer.service.hmrc.gov.uk/api-documentation/docs/api/service/individual-employment/1.2).
  - Đánh giá khả năng (capabilities), chức năng (function) và chi phí (cost).
  - Tìm hiểu các API tương tự khác.
  - Kỳ vọng nghiệp vụ: Điều chỉnh trang "Employment History" để trước tiên hỏi National Insurance (NI) number của ứng viên. Khi submit, hệ thống sẽ tự động kéo và điền lịch sử công việc trong 5 năm gần nhất (hoặc tất cả các năm có sẵn nếu chưa đủ 5 năm). Sau đó ứng viên chỉ cần chỉnh sửa và bổ sung thông tin references.

---

## 2. Kết quả khảo sát chuyên sâu về HMRC API (`Individual Employment API`)

### 2.1. Bản chất dữ liệu & Năng lực (Capabilities & Functions)
- **Nguồn dữ liệu**: Dữ liệu lịch sử việc làm của HMRC được cập nhật tự động từ các kỳ báo cáo thuế **PAYE (Pay As You Earn) Real Time Information (RTI)** do các công ty/nhà tuyển dụng tại Vương quốc Anh nộp định kỳ lên HMRC khi chi trả lương.
- **Thông tin API trả về**:
  - Tên pháp nhân / Nhà tuyển dụng (`employerName`, `payeSchemeReference`).
  - Ngày bắt đầu và kết thúc công việc (`startDate`, `endDate` / `leaveDate`).
  - Lịch sử thu nhập và thuế đã nộp (`taxablePay`, `taxDeducted`).
- **Khoảng thời gian hỗ trợ**: Có thể truy vấn theo từng năm tính thuế (Tax Year) hoặc khoảng thời gian, đáp ứng tốt yêu cầu **5 năm gần nhất** (thậm chí lên tới 6 năm).
- ⚠️ **Hạn chế dữ liệu cốt lõi (Data Gap)**:
  - Báo cáo RTI của HMRC **KHÔNG chứa chức danh công việc cụ thể (`job_title`)** của người lao động.
  - Báo cáo RTI **HOÀN TOÀN KHÔNG có thông tin người tham chiếu (`reference_name`, `reference_email`, `reference_phone`)**.
  - **Kết luận về dữ liệu**: Ứng viên vẫn bắt buộc phải điền bổ sung chức danh công việc (nếu cần) và thông tin liên hệ của người tham chiếu.

### 2.2. Chi phí sử dụng (Cost & Pricing)
- **Miễn phí 100% (Free of charge)**: HMRC không thu bất kỳ khoản phí cấp quyền, phí duy trì hay phí trên từng lượt gọi API (per-request fee) trên cả môi trường Sandbox lẫn Production.
- **Giới hạn tốc độ (Rate Limiting)**: Bị áp dụng chính sách rate limit tiêu chuẩn của HMRC Developer Hub (mặc định theo giây/phút trên mỗi Application, có thể xin tăng quota nếu có giải trình lưu lượng lớn).

### 2.3. Rào cản kỹ thuật & Pháp lý cốt lõi (CRITICAL GAP IN EXPECTATION)

> [!CAUTION]
> **Kỳ vọng "Hệ thống chỉ cần NI Number rồi Backend tự động gọi HMRC để kéo dữ liệu" là KHÔNG THỂ THỰC HIỆN ĐƯỢC thông qua API trực tiếp của HMRC.**

1. **Cơ chế xác thực là User-Restricted (OAuth 2.0 Authorization Code Flow)**:
   - Hồ sơ việc làm và tiền lương là dữ liệu cá nhân nhạy cảm đặc biệt (Confidential Personal Data) theo luật bảo vệ dữ liệu Vương quốc Anh (UK GDPR / Data Protection Act 2018).
   - HMRC **KHÔNG cung cấp API dạng Server-to-Server (Application-Restricted)** cho phép một tổ chức bất kỳ tra cứu lịch sử làm việc của một cá nhân chỉ bằng NI Number. Nếu có cơ chế này, bất kỳ ai có NI number của người khác đều có thể theo dõi trái phép lịch sử làm việc và thu nhập của họ.
   - Để truy cập dữ liệu qua HMRC API, bắt buộc phải có **sự đồng thuận và ủy quyền trực tiếp từ chính cá nhân đó (User Consent)**:
     - Ứng viên phải bấm vào liên kết xác thực (ví dụ: *"Connect to HMRC / GOV.UK"*).
     - Ứng viên được chuyển hướng (redirect) sang trang đăng nhập chính phủ Anh (**GOV.UK One Login** hoặc **Government Gateway**).
     - Ứng viên tự đăng nhập bằng tài khoản cá nhân của họ và xác nhận cấp quyền truy cập phạm vi `read:employment` cho ứng dụng GAP Personnel.
     - HMRC sau đó redirect về hệ thống của GAP kèm theo Authorization Code để đổi lấy `access_token`.
2. **Yêu cầu Fraud Prevention Headers khắt khe**:
   - Tất cả các lệnh gọi đến User-Restricted API của HMRC bắt buộc phải gửi kèm bộ headers chống gian lận (Fraud Prevention Headers) theo chuẩn HMRC, bao gồm: thông tin thiết bị của ứng viên (`gov-client-device-id`), địa chỉ IP công khai, timezone, client screen dimensions, user agent headers...
3. **Quy trình kiểm duyệt Production (Production Application Review & Software Recognition)**:
   - Để đưa ứng dụng lên Production trên HMRC Developer Hub, GAP Personnel phải:
     - Đăng ký pháp nhân doanh nghiệp tại UK trên HMRC Developer Portal.
     - Vượt qua quy trình thẩm định bảo mật phần mềm (Security Checklist & Production Verification) của HMRC.
     - Ký cam kết bảo mật thông tin và tuân thủ các điều khoản dữ liệu của chính phủ Anh. Quy trình thẩm định này thường mất từ **4 đến 8 tuần**.

---

## 3. Các phương án giải pháp & So sánh (Alternative Solutions)

### Phương án A: Tích hợp nền tảng kiểm tra lý lịch chuyên dụng (Third-Party Vetting Provider - KHUYẾN NGHỊ CAO NHẤT)

Thay vì GAP Personnel tự xây dựng và duy trì kết nối trực tiếp với HMRC cùng quy trình thẩm duyệt phức tạp của chính phủ, các tổ chức tuyển dụng tại UK thường sử dụng các nền tảng kiểm tra lý lịch đã được cấp chứng nhận **DIATF (Digital Identity and Attributes Trust Framework)**:

1. **Konfir (konfir.com)**:
   - **Đặc điểm**: Nền tảng chuyên biệt hàng đầu tại UK về xác thực lịch sử việc làm và thu nhập tự động dành cho các recruitment agencies và ATS.
   - **Cơ chế**: Cung cấp **"Verification Waterfall"**: Kết hợp trực tiếp hồ sơ **HMRC PAYE**, tích hợp cổng phần mềm tính lương (**Payroll providers** như Sage, Workday, BrightPay) và **Open Banking**.
   - **Tích hợp**: Cung cấp sẵn REST API và UI Widget (iframe/popup) nhúng trực tiếp vào trang web đăng ký của ứng viên. Ứng viên chỉ cần 60 giây để xác nhận, hệ thống kéo tối đa 6 năm lịch sử làm việc.
   - **Chi phí**: Trả theo lượt check (Pay-per-check) hoặc gói hợp đồng B2B.
2. **Veremark / EBC Global / Zinc Work / VettingGateway**:
   - Các nền tảng tổng thể về screening ứng viên, có sẵn module xác thực việc làm qua HMRC và tự động đối soát khoảng trống thời gian (employment gaps).

**Đánh giá**:
- *Ưu điểm*: Thời gian tích hợp nhanh (vài ngày), UI/UX mượt mà, tự xử lý toàn bộ pháp lý/bảo mật, hỗ trợ thêm cả nguồn dữ liệu ngoài HMRC (phòng trường hợp HMRC chưa kịp cập nhật kỳ khai thuế).
- *Nhược điểm*: Có chi phí dịch vụ bên thứ ba trên mỗi lượt xác minh.

---

### Phương án B: Tích hợp trực tiếp HMRC API (Direct OAuth 2.0 Integration)

Xây dựng module kết nối chính thức giữa GAP-web-backend và HMRC Developer Hub.

- **Luồng người dùng (User Flow)**:
  1. Trên trang *Employment History*, ứng viên thấy nút **"Auto-fill with HMRC"**.
  2. Bấm nút -> Chuyển sang trang **GOV.UK One Login / Government Gateway**.
  3. Ứng viên đăng nhập tài khoản chính phủ của mình và đồng ý chia sẻ thông tin việc làm với GAP Personnel.
  4. Hệ thống nhận callback -> gọi HMRC API `v1.2/individuals/employments` -> tự động tạo các bản ghi vào bảng `employment_histories` (với `company_name`, `start_date`, `end_date`, `source = 'hmrc'`).
  5. Ứng viên quay lại màn hình, thấy danh sách công ty đã được điền sẵn, chỉ cần bổ sung `job_title` và thông tin `references`.

**Đánh giá**:
- *Ưu điểm*: Hoàn toàn miễn phí chi phí API từ phía nhà nước.
- *Nhược điểm*:
  - Cần quy trình xin duyệt Production dài ngày từ HMRC.
  - Phải xử lý luồng OAuth 2.0 và Fraud Prevention Headers phức tạp.
  - Ứng viên bắt buộc phải nhớ tài khoản GOV.UK/Government Gateway (nếu không có hoặc quên mật khẩu thì vẫn phải fallback về nhập tay).

---

### Phương án C: Tải lên báo cáo thuế HMRC PDF (Document Upload + AI/OCR Parsing - Low Tech / No API)

Phương pháp này tương tự như cách **VettingGateway** và nhiều cơ quan chính phủ đang áp dụng:
- **Luồng người dùng**:
  1. Hướng dẫn ứng viên đăng nhập vào tài khoản cá nhân trên GOV.UK (https://www.gov.uk/check-income-tax-current-year).
  2. Tải file PDF chính thức: **5-year Employment History / PAYE record (Form OCA41)**.
  3. Upload file PDF này lên trang Employment History của GAP.
  4. Backend dùng Document Parser / AI Text Extractor trích xuất danh sách công ty, ngày bắt đầu, ngày kết thúc và điền vào form.

**Đánh giá**:
- *Ưu điểm*: Không cần đăng ký hay xin cấp phép từ HMRC, triển khai nội bộ 100% được ngay, chi phí gần như bằng 0.
- *Nhược điểm*: Trải nghiệm người dùng phụ thuộc vào việc ứng viên tải file và độ chính xác của bộ trích xuất PDF.

---

## 4. Tác động lên Kiến trúc Hệ thống CRS (Technical & Architectural Impact)

Nếu dự án quyết định đi tiếp với việc tự động điền lịch sử làm việc:

### 4.1. Cơ sở dữ liệu (Database)
- Bảng `candidates`: Đã có sẵn cột `national_insurance_number` và `unable_to_provide_national_insurance_number`.
- Bảng `employment_histories`:
  - Đã có các trường cần thiết: `company_name`, `start_date`, `end_date`, `candidate_id`.
  - Nên bổ sung thêm cột:
    - `is_verified` (boolean, default false): Đánh dấu bản ghi đã được xác thực qua HMRC/Konfir.
    - `source` (string, ví dụ: `'manual'`, `'hmrc'`, `'konfir'`): Truy vết nguồn gốc dữ liệu.
- Bảng mới (nếu làm Direct OAuth HMRC):
  - `candidate_hmrc_tokens` (để quản lý access token, refresh token tạm thời trong phiên lấy dữ liệu).

### 4.2. Backend Services
- Xây dựng Service chuyên biệt:
  - Trường hợp Direct HMRC: `HMRCIntegrationService` (quản lý OAuth 2.0 handshake, fraud headers, gọi `individual-employment` endpoint).
  - Trường hợp Third-party: `KonfirService` hoặc `VettingService`.
- Tránh gọi API loop, mapping dữ liệu an toàn và validate dữ liệu trước khi insert vào `employment_histories`.

### 4.3. Tuân thủ Quy chuẩn Dự án (Compliance with AGENTS.md / GEMINI.md)
- Phải áp dụng cấu trúc phân lớp chuẩn: `Controller -> FormRequest -> Service -> Repository`.
- Quản lý các mã trạng thái, hằng số kết nối bằng `public const` trong Service/Model.
- Bắt buộc cập nhật API docs tại `~/projects/crs-api-docs` trước khi code backend nếu có thay đổi route hoặc API payload.

---

## 5. Kết luận & Đề xuất phản hồi cho Jira Task GAP-746

Dưới đây là nội dung đúc kết để phản hồi trực tiếp cho Brian Halstead và Simone trên ticket Jira:

1. **Khả năng đáp ứng yêu cầu gốc**:
   - HMRC API (`Individual Employment API v1.2`) cung cấp được đúng dữ liệu công ty và ngày bắt đầu/kết thúc trong 5 năm gần nhất.
   - **Tuy nhiên, KHÔNG THỂ thực hiện theo cách "ứng viên chỉ nhập NI number rồi hệ thống tự kéo từ backend"**. HMRC coi đây là dữ liệu bảo mật và yêu cầu người dùng phải trực tiếp đăng nhập qua **GOV.UK One Login / Government Gateway** để cấp quyền (OAuth 2.0).
   - Dữ liệu từ HMRC **không có chức danh (`job_title`)** và **không có thông tin người tham chiếu (`references`)**, nên ứng viên vẫn phải thao tác bổ sung sau khi dữ liệu được kéo về.
2. **Chi phí (Cost)**:
   - HMRC API là **miễn phí 100%**.
3. **Khuyến nghị hướng đi (Recommendation)**:
   - Nếu công ty muốn trải nghiệm mượt mà, tự động và sẵn sàng chi trả mức phí nhỏ trên mỗi ứng viên: **Nên chọn giải pháp Third-party chuyên nghiệp như Konfir** (có sẵn HMRC + Payroll + Open Banking widget).
   - Nếu công ty muốn hoàn toàn miễn phí và giữ dữ liệu in-house: **Triển khai luồng Direct HMRC OAuth 2.0** với nút *"Sign in with GOV.UK to auto-fill"*, nhưng cần tính đến thời gian chờ HMRC thẩm định cấp quyền Production (khoảng 1 - 2 tháng).
   - Nếu muốn làm nhanh để kiểm thử quy trình: **Áp dụng phương án cho ứng viên upload file PDF báo cáo thuế 5 năm từ HMRC cá nhân**.
