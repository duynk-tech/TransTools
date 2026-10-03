# Hội thoại và OCR · cập nhật 03/10/2026

## Luyện hội thoại nhanh hơn

Mở tab Trò chuyện riêng, chọn ngôn ngữ, chủ đề và Prompt nếu cần; dùng menu thời gian chờ. Chọn nhịp 0,8 giây để gửi nhanh, 1,2 giây mặc định hoặc 2 giây nếu cần suy nghĩ. Khoảng chờ ngắn dễ chia câu khi người học ngập ngừng; chọn nhịp phù hợp thay vì luôn dùng mức nhanh nhất.

Khi AI đang phát giọng, bấm Nói tiếp để dừng giọng và mở microphone. Văn bản phản hồi đã nhận vẫn giữ trong chat. Bản dịch Apple và gợi ý tải riêng, không chặn phản hồi chính. Hiện chưa stream từng token hoặc dùng Gemini Live; nút Nói tiếp là thao tác chủ động, chưa tự ngắt lời qua giọng nói.

## Mở lại buổi đã lưu

Vào Sổ tay → chọn buổi có nguồn Luyện nói với AI → Tiếp tục trò chuyện. Kiểm tra lịch sử rồi bấm Tiếp tục nói. App giữ ID buổi, người nói, bản dịch, ngôn ngữ, trình độ, chủ đề và prompt đã lưu; nội dung mới được cập nhật vào cùng buổi. Thời lượng cộng thời gian luyện mới, không tính khoảng nghỉ giữa hai lần mở. Menu điều chỉnh có Buổi trò chuyện mới để bắt đầu riêng.

Góp ý đã lưu giữ trong ghi chú. Sổ cũ vẫn đọc được; không thay đổi định dạng JSON bắt buộc. Lưu thất bại có thông báo và không xóa phiên đang có.

## Chụp và dịch màn hình

1. Bấm Option + S hoặc chọn Chụp & Dịch màn hình.
2. Kéo chọn vùng có chữ. Escape để hủy.
3. App nhận diện bằng Apple Vision, đoán ngôn ngữ và mở cửa sổ xem trước.
4. Sửa chữ nếu cần, kiểm tra Từ / Sang, rồi bấm Dịch.
5. Sao chép bản dịch để dùng trong công việc.

Đã kiểm tra bộ nhận diện ngôn ngữ bằng câu mẫu Anh, Việt, Nhật, Trung và Hàn. Chữ rất ngắn, tên riêng hoặc trộn nhiều ngôn ngữ có thể đoán sai; luôn có lựa chọn sửa ngôn ngữ. Ngôn ngữ OCR thực tế được đối chiếu với danh sách Vision hỗ trợ trên máy.

Apple dịch trên máy khi cặp ngôn ngữ sẵn sàng; nếu chưa khả dụng, app thử AI đã cấu hình rồi Google. Nội dung chỉ được gửi đi sau khi bấm Dịch. Dịch vụ giọng đọc trực tuyến gửi câu cần đọc tới nhà cung cấp tương ứng.

## Kiểm tra

- Build release và xác minh chữ ký app.
- `scripts/test-conversation-save.py`: ghi/đọc lại, giữ người nói, bản dịch, góp ý, phục hồi lịch sử, tiếp tục cùng ID, giữ timestamp cũ và bảo toàn dữ liệu khi ghi lỗi.
- `scripts/test-ocr-language.py`: năm ngôn ngữ và đầu vào trống.
- Kiểm tra trực tiếp Sổ tay → Tiếp tục trò chuyện trong app.
- Edge dùng SHA-256 cho cache và deadline bao quanh thao tác nhận WebSocket. Chưa đo độ trễ Edge trên nhiều mạng hoặc xác minh hội thoại microphone đầu cuối trong lượt này.

Các thay đổi hiện thuộc bản phát triển, chưa phát hành gói ZIP/DMG mới.

## Tùy chọn hội thoại

Gợi ý mặc định tắt. Bật Dịch Tiếng Việt để xem bản dịch; tùy chọn ẩn và không gửi yêu cầu dịch khi hội thoại bằng tiếng Việt. Chọn chủ đề hoặc Prompt trước khi bắt đầu. Tạo mới để đổi bối cảnh của một buổi đã có nội dung. Xem [Trò chuyện theo chủ đề](conversation-topics.md).
