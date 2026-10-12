# Plan: Add Multi-Agent Rule for Long Tasks

> **Trạng thái**: `DRAFT`
> **Ngày tạo**: 2026-09-24
> **Author**: Codex

## Mục tiêu

Thêm vào `AGENTS.md` hướng dẫn cho phép chia task dài thành các phần độc lập để nhiều agent có thể triển khai song song, với ranh giới sở hữu rõ ràng nhằm tránh xung đột file và thay đổi.

## Phạm vi thay đổi

- Chỉ sửa mục `3. Workflow & Planning Guidelines` trong `AGENTS.md`.
- Không thay đổi các quy định plan/approval, skill, test hoặc kiến trúc hiện có.

## Thiết kế đề xuất

- Chỉ dùng multi-agent khi các phần có thể thực thi độc lập; xác định dependency, interface/contract chung và phạm vi file trước khi giao việc.
- Mỗi agent có phạm vi file sở hữu không chồng lấn; file dùng chung chỉ có một agent chỉnh sửa hoặc được xử lý tuần tự.
- Ưu tiên worktree/branch cô lập. Nếu cùng workspace, agent chỉ sửa file được giao và không tự ý tích hợp thay đổi của agent khác.
- Nếu các phần phụ thuộc lẫn nhau hoặc không thể bảo đảm ownership rõ ràng, thực hiện tuần tự.
- Agent điều phối chịu trách nhiệm tích hợp, review diff, kiểm tra tương thích và chạy test tổng hợp; mọi agent vẫn phải tuân thủ plan gate, skill và test audit hiện hành.

## Xác minh

- Review diff để bảo đảm chỉ bổ sung rule cần thiết trong `AGENTS.md`.
- Không chạy formatter; không cần chạy test ứng dụng vì chỉ thay đổi hướng dẫn cộng tác.
