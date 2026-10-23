# SPEC: GAP-748 - URGENT - 48 Hour Opt Out Link

> **Trạng thái**: `DRAFT` (Awaiting User Approval)
> **Ngày tạo**: 2026-10-22
> **Task Key**: GAP-748
> **Author**: Codex / Antigravity

---

## 1. Tổng quan & Bối cảnh

### 1.1. Yêu cầu gốc từ Jira GAP-748 (Reporter: Brian Halstead)
- **Background**:
  - Trong phần Declarations của Candidate Portal, có link dẫn đến tài liệu "48 hour opt out". Link hiện tại trỏ tới: `https://apply.gap-personnel.com/downloads/48_hour.pdf`.
  - Do các sự cố PHP gần đây, hệ thống cũ `apply.gap-personnel.com` đã bị gỡ bỏ (taken down) và hiện tại không có kế hoạch khôi phục lại domain/server này.
- **Yêu cầu thực hiện**:
  - File tài liệu đính kèm trên Jira ticket: `48 Hour Opt out.pdf` (Attachment ID: `16365`, dung lượng 294.4KB).
  - Cần host file này tại cùng vị trí với các tài liệu hiện đang được hệ thống host, và cập nhật/redirect link trỏ về vị trí mới này.

### 1.2. API Contract / API Docs Assessment (STRICT GATE)
- **Đánh giá**: Nhiệm vụ này chỉ liên quan đến việc bổ sung 1 static asset PDF vào thư mục public của Candidate Portal và cập nhật URL liên kết trong UI component (FE) cùng hàm sinh nội dung PDF Application Pack (BE).
- **Kết luận**: **N/A — no API contract/API docs change**. Không có endpoint API mới, không thay đổi request/response schema, routing hay error code nào.

---

## 2. Phân tích Hiện trạng Codebase

### 2.1. Candidate Portal (`gap-web-frontend`)
- **Vị trí lưu trữ tài liệu tĩnh hiện tại**:
  - Thư mục `packages/gap-frontend/public/downloads/` đang lưu trữ các tài liệu chính sách của ứng viên:
    - `1675682820-PRIVACY-NOTICE-CANDIDATES.pdf`
    - `TERMS_OF_USE.pdf`
- **Component hiển thị link**:
  - `packages/gap-frontend/src/containers/RegistrationJourney/components/DeclarationFields/DeclarationFields.tsx`:
    - Dòng 296–302 (Question 5.1 - Time Regulations 48 Hour Opt Out):
      ```tsx
      <Trans
        i18nKey={`registrationJourney:declarations.body.question_5_${
          index + 1
        }`}
        t={t}
      >
        <a
          href="https://apply.gap-personnel.com/downloads/48_hour.pdf"
          target="_blank"
          rel="noreferrer"
        >
          here
        </a>
      </Trans>
      ```
    - Trong khi đó, Question 5.4 (Data Protection) tại dòng 321–324 sử dụng đường dẫn tương đối (relative path) trỏ trực tiếp vào thư mục `/downloads/`:
      ```tsx
      <a
        href="/downloads/1675682820-PRIVACY-NOTICE-CANDIDATES.pdf"
        target="_blank"
        rel="noreferrer"
      >
        here
      </a>
      ```
- **Hệ thống đa ngôn ngữ (i18n)**:
  - Tất cả các locale (`packages/gap-frontend/src/locales/*/registrationJourney.json`) đều đã định nghĩa key `question_5_1` dạng:
    `"... please click <0>here</0>"` (hoặc bản dịch tương ứng với tag `<0>`).
  - Do component `<Trans>` tự động tiêm thẻ con `<a>` vào vị trí `<0>`, việc đổi `href` trong `DeclarationFields.tsx` là hoàn toàn độc lập và không cần chỉnh sửa bất kỳ file locale JSON nào.

### 2.2. Backend (`gap-web-backend`)
- **Nơi tham chiếu URL cũ**:
  - File `app/Services/ApplicationPackService.php` (dòng 1491) tại hàm `getTimeRegulationExplanation()`:
    ```php
    private function getTimeRegulationExplanation(): string
    {
        ...
        $text .= 'For more information on the 48 Hour Opt Our and your rights to withdraw your consent please click';
        $text .= ' ';
        $text .= '<a href="https://apply.gap-personnel.com/downloads/48_hour.pdf" target="_blank">here</a>';

        return $text;
    }
    ```
- **Đặc thù file PDF được sinh bởi Backend**:
  - Hàm trên dùng để tạo trang PDF Application Pack ký kết của Candidate.
  - Khác với trình duyệt Web (tự động ghép relative URL với domain hiện tại), khi ứng viên tải file Application Pack PDF về máy cá nhân hoặc mở bằng phần mềm đọc PDF ngoài trình duyệt (như Adobe Acrobat Reader), một đường dẫn relative `/downloads/...` sẽ không có context domain và sẽ bị lỗi (hoặc biến thành `file:///downloads/...`).
  - Do đó, trong file PDF, link bắt buộc phải là một **Absolute URL** đầy đủ (có scheme `https://` và domain).
  - Đối chiếu hiện tại: Privacy Notice trong `ApplicationPackService.php` (dòng 1506) đang trỏ tới: `https://candidates-dev.gap-personnel.com/downloads/1675682820-PRIVACY-NOTICE-CANDIDATES.pdf`.
  - Để chuẩn hóa và hỗ trợ đa môi trường (local, dev, stg, prod), backend nên cấu hình hoặc sử dụng base URL của frontend (bỏ phần hash fragment `/#`) để build absolute URL tới file tĩnh `/downloads/48_hour.pdf`.

---

## 3. Đề xuất Giải pháp Kỹ thuật

### 3.1. Phía Frontend (`gap-web-frontend`)
1. **Lưu trữ tài liệu tĩnh**:
   - Lấy file `48 Hour Opt out.pdf` đính kèm từ Jira GAP-748 (đã tải về từ attachment ID 16365).
   - Đặt file vào: `packages/gap-frontend/public/downloads/48_hour.pdf`.
2. **Cập nhật Component `DeclarationFields.tsx`**:
   - Sửa dòng 297:
     ```tsx
     // Trước:
     href="https://apply.gap-personnel.com/downloads/48_hour.pdf"
     // Sau:
     href="/downloads/48_hour.pdf"
     ```
   - Cách này đảm bảo tính nhất quán hoàn toàn với `TERMS_OF_USE.pdf` và `1675682820-PRIVACY-NOTICE-CANDIDATES.pdf`, chạy đúng trên mọi môi trường và domain của Frontend mà không bị hardcode domain.

### 3.2. Phía Backend (`gap-web-backend`)
1. **Cập nhật URL trong `ApplicationPackService.php`**:
   - Cập nhật hàm `getTimeRegulationExplanation()` để thay thế URL đã chết `https://apply.gap-personnel.com/downloads/48_hour.pdf`.
   - Có thể xác định absolute URL động:
     - Sử dụng base URL trích xuất từ `config('app.frontend_url')`: loại bỏ trailing hash/slash và nối với `/downloads/48_hour.pdf`.
     - Ví dụ: `rtrim(preg_replace('/#.*$/', '', (string) config('app.frontend_url')), '/') . '/downloads/48_hour.pdf'`
     - Hoặc thêm key cấu hình `config('app.candidate_48_hour_opt_out_link')` trong `config/app.php` tương tự các document link khác như `candidate_key_information_document_link`, `candidate_contract_document_link`.

---

## 4. Kế hoạch Triển khai & Verification

### 4.1. Các file bị ảnh hưởng
| Repository | File Path | Mục đích thay đổi |
|---|---|---|
| `gap-web-frontend` | `packages/gap-frontend/public/downloads/48_hour.pdf` | Thêm file PDF đính kèm từ Jira |
| `gap-web-frontend` | `packages/gap-frontend/src/containers/RegistrationJourney/components/DeclarationFields/DeclarationFields.tsx` | Đổi `href` sang `/downloads/48_hour.pdf` |
| `gap-web-backend` | `app/Services/ApplicationPackService.php` | Đổi link chết sang absolute URL mới |
| `gap-web-backend` (optional) | `config/app.php` | Định nghĩa link cấu hình nếu dùng config |

### 4.2. Kế hoạch kiểm thử (Test & Verification)
1. **Kiểm tra Frontend**:
   - Chạy build/lint: `yarn lint:gap-frontend` để đảm bảo không có lỗi linter/formatting.
   - Kiểm tra UI: Truy cập Registration Journey -> Declarations, click vào link "here" của mục "Time Regulations - 48 Hour Opt Out", xác nhận tab mới mở file PDF đúng nội dung.
2. **Kiểm tra Backend**:
   - Chạy test suites hiện có: `./vendor/bin/phpunit` để đảm bảo 100% pass và không gây regression.
   - Xác nhận hàm sinh PDF `ApplicationPackService` tạo link hợp lệ.

---

## 5. Kết luận & Đề xuất

- Giải pháp trên đáp ứng chính xác 100% mong muốn của khách hàng Brian Halstead trong Jira GAP-748:
  - File được host cùng vị trí với các tài liệu hiện có của Candidate Portal (`public/downloads/`).
  - Link trong mục Declarations được chuyển hướng sang vị trí mới mà không phụ thuộc vào server `apply.gap-personnel.com` đã tắt.
  - Đồng thời xử lý triệt để nguy cơ tiềm ẩn liên kết chết trong file Application Pack PDF do Backend sinh ra.
