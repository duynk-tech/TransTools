# Dịch phụ đề cuộc họp bằng Apple local

Ngày kiểm tra: 03/10/2026. Máy hiện tại đã cài các cặp en/ja/zh/ko → vi. Chọn Apple Translate và lưu lựa chọn rõ ràng để không bị cơ chế tự ưu tiên key AI đổi sang Gemini khi khởi động.

## Thay đổi

- Khi cuộc họp chọn Apple, AITranslator nhận allowNetworkFallback=false. Lỗi Apple được báo tại cuộc họp; không gọi Google Free hoặc AI để dịch phụ đề. Các tính năng AI như gợi ý/tóm tắt vẫn có cấu hình riêng; đây không phải chế độ tắt mạng toàn app.
- Tách cache giữa strict local và nhánh cho phép fallback; không lấy kết quả Google cũ gắn nhãn Apple local. Không gộp cache giữa văn bản khác hoa/thường.
- Tái sử dụng TranslationSession đã cài, tránh truy vấn LanguageAvailability mỗi caption. Nếu session lỗi, xóa session để lần tiếp theo có thể tạo lại.
- Đợi gom partial text cho Apple giảm từ 180 xuống 80 ms; đoạn kết thúc gửi ngay. Vẫn giữ mọi đoạn chưa được dịch trong hàng đợi.
- Chuẩn bị bộ đã cài rồi dịch một câu chào cố định local khi vào dashboard/chọn Apple hoặc đổi cặp ngôn ngữ. Đây là làm nóng mô hình, không đưa câu đó vào transcript, không dùng nội dung người dùng. Không tải pack chưa cài trong bước này.
- Trạng thái hiện Apple Translate · local thay vì nhầm Google vì không có API key. Caption đang chờ hiện đúng bộ dịch thay cho nhãn AI cố định.

## Kiểm tra

Build macOS thành công, codesign hợp lệ. test-local-translation.py chạy phương thức routing production với translator giả lập: strict Apple không gọi mạng khi thành công, lỗi hoặc kết quả giữ nguyên; cache online không được tái sử dụng ở local. Đây là kiểm tra routing, không phải network trace của toàn app.

test-native-translation.py chạy translator Apple thật trên máy: trước làm nóng, câu thử Anh–Vi đầu tiên ~1.8 giây, lần sau ~0.35–0.4 giây. Sau làm nóng (1.518 giây ở bước chuẩn bị), câu thử đầu ~376 ms, câu tiếp ~362 ms. Tốc độ phụ thuộc câu và tải máy; số này chỉ đo text → translation, chưa bao gồm audio capture, speech recognition hoặc hiển thị. Không cam kết 15 ms hay instant end-to-end.

Đã chọn Apple làm bộ dịch trên máy và xác nhận UI hiển thị Apple Translate dịch tiếng Việt. Chưa chạy một cuộc họp audio thực tế trong kiểm tra này.
