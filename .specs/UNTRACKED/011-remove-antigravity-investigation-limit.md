# SPEC: Remove Investigation Tool Call Limit for Antigravity Agent in `slack-issue-investigator`

> **Trạng thái**: `COMPLETED` (Đã gỡ bỏ giới hạn tool calls & nâng timeout lên 1800s, đã reload qua PM2)  
> **Ngày tạo**: 2026-10-23  
> **Task Key**: `UNTRACKED` (Sequence: `011`)  
> **Target Project**: `~/projects/slack-issue-investigator`  
> **Author**: Antigravity & User (`light.nguyen`)  

---

## 1. Hiện trạng & Xác nhận (Findings)

Khi kiểm tra thư mục `~/projects/slack-issue-investigator`, **chính xác là bot đang bị giới hạn số lượt gọi công cụ / kiểm tra** ở các vị trí sau:

### 1.1. Giới hạn cứng trong Prompt của Antigravity Headless Agent (`antigravity_agent.py`)
- **Vị trí**: [`antigravity_agent.py` (dòng 76)](file:///Users/nexusfrontiertech/projects/slack-issue-investigator/antigravity_agent.py#L76)
- **Nội dung hiện tại**:
  ```python
  - GIỚI HẠN BẮT BUỘC (HARD CEILING): Chỉ được gọi TỐI ĐA 10 LẦN CÔNG CỤ (tool calls). Khi đã xác định được đoạn code xử lý hoặc sau tối đa 10 lần gọi công cụ, BẮT BUỘC DỪNG LẠI NGAY LẬP TỨC và xuất structured JSON, TUYỆT ĐỐI KHÔNG tiếp tục đọc thêm các file phụ hoặc đào sâu toàn bộ frontend.
  ```
- **Hệ quả**: Mặc dù `agy` CLI bình thường có khả năng suy luận và gọi công cụ nhiều lượt không giới hạn để điều tra triệt để, prompt này ép `agy` phải phanh gấp sau tối đa 10 tool calls, làm dừng quá trình trace code hoặc tra cứu DB sâu.

### 1.2. Giới hạn Subprocess Timeout (`timeout_seconds`)
- **Vị trí**: 
  - [`config.json` (dòng 14)](file:///Users/nexusfrontiertech/projects/slack-issue-investigator/config.json#L14): `"timeout_seconds": 600` (10 phút)
  - [`bot_daemon.py` (dòng 194)](file:///Users/nexusfrontiertech/projects/slack-issue-investigator/bot_daemon.py#L194) & [`manual_test.py` (dòng 62)](file:///Users/nexusfrontiertech/projects/slack-issue-investigator/manual_test.py#L62): fallback default 180s.
- **Hệ quả**: Nếu gỡ giới hạn tool calls để Antigravity đào sâu như lúc tương tác trực tiếp trên CLI, cuộc điều tra có thể chạy nhiều lượt phức tạp. Cần nâng ngưỡng timeout để tránh bị `subprocess.TimeoutExpired` ngắt ngang.

### 1.3. Giới hạn của Legacy Engine (`investigator.py` - chỉ áp dụng khi fallback)
- **Vị trí**: [`config.json` (dòng 28)](file:///Users/nexusfrontiertech/projects/slack-issue-investigator/config.json#L28) và [`investigator.py` (dòng 34, 322)](file:///Users/nexusfrontiertech/projects/slack-issue-investigator/investigator.py#L322): `"max_steps": 15`.

### 1.4. Trạng thái Daemon hiện tại
- Process `bot_daemon.py --daemon` đang chạy ngầm trên máy với PID `54059`. Bất kỳ thay đổi code nào cần khởi động lại daemon này để có hiệu lực.

---

## 2. API Contract & Docs Gate

- **Đánh giá ảnh hưởng API Contract / API Docs (`crs-api-docs`)**:
  - `N/A — no API contract/API docs change`.
  - Đây là script nội bộ hỗ trợ điều tra sự cố (`slack-issue-investigator`), không thay đổi API backend CRS/CRM.

---

## 3. Thiết kế Giải pháp (Proposed Solution)

### 3.1. Gỡ bỏ hoàn toàn giới hạn Tool Calls trong Prompt (`antigravity_agent.py`)
- Thay thế chỉ thị `HARD CEILING` 10 lần gọi công cụ bằng hướng dẫn điều tra tự do, chuyên sâu và toàn diện (tương tự trải nghiệm hỏi trực tiếp trên `agy` CLI):
  - Cho phép Antigravity tự quyết định số lượt công cụ cần thiết để định vị chính xác nguyên nhân gốc rễ và kiểm chứng dữ liệu DB.
  - Yêu cầu chỉ dừng lại và xuất JSON khi đã hoàn thành đầy đủ phân tích và có đủ dữ kiện kết luận.

### 3.2. Cấu hình Timeout linh hoạt và an toàn
- Nâng `timeout_seconds` trong [`config.json`](file:///Users/nexusfrontiertech/projects/slack-issue-investigator/config.json) từ `600` lên `1800` (30 phút) hoặc `0` (không giới hạn nếu dùng `--print-timeout 0` và subprocess timeout thích hợp).
- Đồng bộ giá trị fallback trong [`bot_daemon.py`](file:///Users/nexusfrontiertech/projects/slack-issue-investigator/bot_daemon.py) và [`manual_test.py`](file:///Users/nexusfrontiertech/projects/slack-issue-investigator/manual_test.py) từ 180s lên 1800s.

### 3.3. Khởi động lại Bot Daemon
- Dừng process daemon cũ (PID `54059`).
- Khởi động lại `python3 bot_daemon.py --daemon` bằng môi trường python thích hợp để bot nhận cấu hình mới.

---

## 4. Kế hoạch Thực hiện (Execution Steps)

1. **Bước 1**: Sửa file `~/projects/slack-issue-investigator/antigravity_agent.py`:
   - Xóa bỏ dòng ép giới hạn 10 tool calls.
   - Cập nhật prompt: yêu cầu Antigravity điều tra thấu đáo, tự động gọi công cụ cho đến khi xác định rõ căn nguyên sự cố mà không bị giới hạn bước.
2. **Bước 2**: Sửa file `~/projects/slack-issue-investigator/config.json`:
   - Nâng `"timeout_seconds": 1800`.
3. **Bước 3**: Cập nhật fallback timeout trong `bot_daemon.py` và `manual_test.py`.
4. **Bước 4**: Kiểm thử thử nghiệm với `manual_test.py --no-slack` để đảm bảo Antigravity chạy mượt mà, không gặp lỗi cú pháp hay timeout.
5. **Bước 5**: Restart `bot_daemon.py --daemon` để áp dụng vào hệ thống thực tế.
