# Dịch nhanh và Đọc văn bản

## Bố cục
- Hai công cụ: Dịch & Ngữ pháp và Đọc văn bản.
- Ô nhập và kết quả dịch đặt cạnh nhau. Ngữ cảnh và mẫu câu mở theo nhu cầu.
- Đọc văn bản dùng chung nội dung ô nhập, chọn ngôn ngữ trước khi phát.

## Đọc văn bản
- Hỗ trợ ngôn ngữ hiện có của app; tối đa 5.000 ký tự mỗi lần.
- Phát, đọc lại và dừng; mở Giọng & Tốc độ để dùng cấu hình TTS hiện có.
- Dừng/đóng mục đọc chỉ dừng audio thuộc mục này, không dừng nhầm nội dung khác.
- Lưu WAV qua Supertonic, VieNeu hoặc Qwen đã cài; MP3 qua Edge. Có thể hủy trước khi tạo xong; chỉ ghi file khi người dùng chọn nơi lưu.
- WAV Local không cần mạng/API key. Giọng cơ bản không có xuất audio. Công cụ xuất theo cấu hình ngôn ngữ, không tự chuyển model. Không lưu file khi tổng hợp lỗi.

## Kiểm chứng ngày 2026-10-03
- Build và kiểm tra chữ ký app thành công; cập nhật /Applications/TransTools.app.
- UI xác nhận hai chế độ, nhập đoạn văn, trạng thái nút đọc/dừng, menu MP3/WAV và giới hạn ký tự.
- Đoạn mẫu tiếng Việt phát bằng giọng macOS khi thiếu key Gemini.
- Kiểm tra mapping giọng cho cả chín locale của app và locale không hỗ trợ; kiểm tra chuẩn hóa tiếng Anh và quyền dừng audio đã qua.
- Thử MP3 trực tiếp: Edge trả bad response; giao diện báo lỗi, không tạo file. Chưa xác nhận xuất MP3 thành công trên endpoint hiện tại.
- Cập nhật 04/10: đã kiểm thử WAV thực tế từ VieNeu và Qwen bằng Python/SDK riêng; kiểm thử parser PCM16 và khôi phục hủy tác vụ.

Danh sách voice tham chiếu: [Microsoft Learn](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts). Danh sách Azure không bảo đảm endpoint Edge consumer luôn khả dụng.

### Chuẩn hóa cách đọc bằng AI

Trong Đọc văn bản, khi đã có API key, bật **Chuẩn hóa cách đọc số bằng AI** để chuẩn bị cách phát âm số La Mã, ngày tháng, phần trăm và tỷ lệ trước khi nghe hoặc lưu audio. App gửi đoạn văn tới AI đã cấu hình để xác định ngữ cảnh, nhưng chỉ áp dụng đề xuất vào các cụm số được liệt kê; văn bản gốc trong ô nhập không thay đổi. Không dịch, sửa ngữ pháp hay diễn đạt lại phần còn lại. Cụm không rõ nghĩa giữ nguyên. Nếu AI lỗi hoặc phản hồi không hợp lệ, app dùng văn bản gốc và hiển thị thông báo. Việc chuẩn bị có thể tăng thời gian chờ; có thể tắt tùy chọn khi muốn đọc trực tiếp.
