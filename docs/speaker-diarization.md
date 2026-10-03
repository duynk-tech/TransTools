# Tách người nói trên máy

FluidAudio 0.12.4 (pinned SwiftPM), CoreML Pyannote segmentation + WeSpeaker embedding. Tài liệu gốc: https://github.com/FluidInference/FluidAudio/blob/v0.12.4/Documentation/Diarization/GettingStarted.md

Bật tại Cài đặt → Dịch & Phụ đề → Tách người nói. Lần đầu tải mô hình từ kho chính thức của FluidAudio; audio không gửi lên máy chủ. Khoảng audio 10 giây xử lý trên serial queue nền, tracking giọng xuyên suốt một cuộc họp. Có giới hạn queue để không chặn luồng Speech; tải nặng có thể khiến nhãn thiếu, không làm rơi audio của Apple Speech.

Nhãn Người nói 1, 2… không phải danh tính thật. Quality score thư viện là chỉ số chất lượng embedding, không phải xác suất chính xác đã hiệu chuẩn. Giọng ngắn, nhạc nền, nói chồng và giọng gần nhau có thể sai hoặc không có nhãn.

Apple Speech cung cấp thời điểm từ. Chỉ tách caption đã chốt, đang trong cuộc họp, nếu toàn bộ từ khớp hypothesis và có ít nhất hai nhãn khác nhau. Sau tách, dịch lại từng đoạn. Không cắt đoán hoặc bỏ từ nếu chưa đủ timing; trường hợp đó giữ đoạn và nhiều nhãn. Đoạn đang nói tiếp tục hiển thị như cũ, chờ phân tích; nhãn trễ khoảng 10 giây cộng thời gian inference. Nhãn lưu vào Sổ tay, TXT/SRT; trường optional tương thích sổ tay cũ.

Kiểm thử model dùng JFK WAV công khai của whisper.cpp và audio A–Z đã tải trên máy; đây là smoke test không thay thế benchmark diarization bằng audio cuộc họp có ground truth. Chưa xác nhận chất lượng cuộc họp Teams thực tế.

## Sửa độ ổn định 03/10/2026

- Giữ tối đa 30 giây audio khi mô hình đang nạp, thay vì bỏ mọi buffer trước khi mô hình sẵn sàng.
- Cửa sổ 10 giây giữ lại 2 giây ngữ cảnh; chốt 8 giây rồi nối cửa sổ tiếp theo. Kết thúc phiên xử lý phần còn lại. Khoảng ngắt capture giữ đúng trục thời gian.
- Chờ kết quả tách giọng phủ toàn bộ thời điểm từ trước khi chia caption đã chốt. Dùng thời điểm từ thay vì chỉ thời điểm UI nhận câu để tìm khoảng giọng.
- Gán từ theo thời lượng phủ trội; không đoán ở điểm giữa khi hai giọng chồng nhau. Không cộng trùng thời lượng của interval lặp.
- Giữ nhãn cũ nếu đợt kết quả mới chưa có interval phù hợp.

Bốn kiểm thử gán từ, hai kiểm thử CoreML và một kiểm thử luồng audio nạp mô hình/cửa sổ nối đã đạt với hai tệp thử trên máy. Những tệp này chưa đại diện cho mọi giọng và điều kiện họp thực tế. Không cam kết tách chính xác khi nói chồng, câu cực ngắn hoặc microphone nhiều tiếng vọng.
