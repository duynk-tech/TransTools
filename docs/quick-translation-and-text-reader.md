# Dịch nhanh và Đọc văn bản

## Bố cục
- Hai công cụ: Dịch & Ngữ pháp và Đọc văn bản.
- Ô nhập và kết quả dịch đặt cạnh nhau. Ngữ cảnh và mẫu câu mở theo nhu cầu.
- Đọc văn bản dùng chung nội dung ô nhập, chọn ngôn ngữ trước khi phát.

## Đọc văn bản
- Hỗ trợ ngôn ngữ hiện có của app; tối đa 5.000 ký tự mỗi lần.
- Phát, đọc lại và dừng; mở Giọng & Tốc độ để dùng cấu hình TTS hiện có.
- Dừng/đóng mục đọc chỉ dừng audio thuộc mục này, không dừng nhầm nội dung khác.
- Lưu MP3 qua Edge hoặc WAV qua Gemini. Có thể hủy trước khi tạo xong; chỉ ghi file khi người dùng chọn nơi lưu.
- Xuất audio cần mạng; WAV cần key Gemini. Không tự lưu audio giả khi dịch vụ lỗi.

## Kiểm chứng ngày 2026-10-03
- Build và kiểm tra chữ ký app thành công; cập nhật /Applications/TransTools.app.
- UI xác nhận hai chế độ, nhập đoạn văn, trạng thái nút đọc/dừng, menu MP3/WAV và giới hạn ký tự.
- Đoạn mẫu tiếng Việt phát bằng giọng macOS khi thiếu key Gemini.
- Kiểm tra mapping giọng cho cả chín locale của app và locale không hỗ trợ; kiểm tra chuẩn hóa tiếng Anh và quyền dừng audio đã qua.
- Thử MP3 trực tiếp: Edge trả bad response; giao diện báo lỗi, không tạo file. Chưa xác nhận xuất MP3 thành công trên endpoint hiện tại.
- Chưa thử WAV thực tế vì máy chưa có key Gemini.

Danh sách voice tham chiếu: [Microsoft Learn](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts). Danh sách Azure không bảo đảm endpoint Edge consumer luôn khả dụng.
