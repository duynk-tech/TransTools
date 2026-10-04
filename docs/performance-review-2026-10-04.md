# Rà soát hiệu năng và bộ nhớ — 04/10/2026

Phạm vi: luồng nhận diện/ghép văn bản, dịch, trò chuyện, TTS, mô hình Local, hàng đợi audio, lưu trữ, hình hoạt cảnh và vòng đời cửa sổ. Đây là kiểm tra mã và hồi quy trên máy phát triển, không phải chứng nhận không có lỗi trên mọi máy.

## Đã sửa

| Vấn đề | Thay đổi |
| --- | --- |
| Audio Edge giữ vô hạn trong RAM | Cache LRU giới hạn 16 MiB theo số byte; giải phóng khi có cảnh báo bộ nhớ. Gói audio mạng cũng giới hạn 16 MiB. |
| Dọn audio trên ổ đĩa vẫn còn bản trong RAM | Dọn trong Lưu trữ xóa cả cache RAM; thư mục được tạo lại và file ghi atomic khi đọc tiếp. |
| Nạp toàn bộ hoạt cảnh khi dùng một hoạt cảnh | Manifest chỉ giữ đường dẫn; chỉ giữ frame của hoạt cảnh đang dùng, giải phóng khi chuyển hoạt cảnh hoặc về hình tĩnh. |
| Cache trò chuyện tăng theo các buổi | Giới hạn 128 mục và xóa khi tạo hội thoại mới. |
| Tác vụ dịch phiên cũ kết thúc muộn | Chỉ xóa trạng thái tác vụ khi còn thuộc đúng phiên; không ghi đè trạng thái phiên mới. |
| Hình hướng dẫn nét viết thiếu giới hạn cache | NSCache giới hạn 24 hình. |
| Mascot cập nhật giao diện thừa | Giảm timeline ngoài từ 60 xuống 24 fps; sprite nhận time/distance từ cha không chạy thêm timeline riêng. |

## Các cơ chế đã kiểm tra

- VieNeu native và Supertonic dùng phiên ONNX ngoài MainActor; router chờ giải phóng bộ xử lý trước khi chuyển mô hình. Giữ ấm tối đa hai phút, có xử lý cảnh báo bộ nhớ.
- Audio có backpressure, tối đa hai gói chờ phát; xuất WAV theo đoạn ra file tạm, giới hạn 60 MiB.
- Tách người nói giới hạn audio đợi nạp ở 30 giây và số công việc audio chờ qua semaphore. Chất lượng phân biệt giọng là vấn đề riêng với hiệu năng.
- Dịch Local không chuyển sang dịch mạng ngầm; kiểm tra ghép stream giữ partial/final dài hơn và xử lý overlap.
- Quét dung lượng ở task nền. Timer đi dạo được invalidate khi dừng. Hình sprite cố định được nạp một lần.
- Qwen, SDK và Python đã gỡ trên máy này. Không chạy kiểm thử Qwen bằng cách tải lại.

## Kiểm thử

- `swift test -c release`: 33 bài, 6 bỏ qua vì yêu cầu mô hình/dữ liệu ngoài, 0 lỗi.
- VieNeu với dữ liệu cài thật: 2 bài, 0 lỗi; đối chiếu âm vị/tokenizer, streaming, xuất WAV đổi tốc độ, hủy và phục hồi.
- Kiểm thử riêng ghép văn bản stream, định tuyến dịch Local và cửa sổ ẩn.
- Kiểm thử học liệu/lịch ôn và chuẩn hóa nội dung đọc/chọn giọng đã qua.
- Script kiểm thử lưu hội thoại cũ thiếu kiểu chủ đề/ngôn ngữ mới; cập nhật fixture để dùng các kiểu production. Đã qua kiểm tra vai người nói, bản dịch, ID phiên ổn định, đọc lại từ đĩa và giữ dữ liệu khi ghi thất bại.

## Giới hạn và việc cần đo thêm

### Bổ sung: nhịp vẽ thích ứng và giải phóng cửa sổ mascot

Đã thay clock animation liên tục bằng timeline định kỳ: 8 lần/giây khi rảnh, 24 khi tương tác/học/họp, 4 khi tiết kiệm điện hoặc máy nóng. Reduce Motion dùng nhịp 1 giây và cố định thời gian chuyển động. Khi ẩn mascot, bỏ contentView để giải phóng cây SwiftUI và timer; khi bật lại tạo view mới trong panel đang có, giữ vị trí cửa sổ.

Bản đã build, xác minh chữ ký và cài tại `/Applications/Trans Tools.app`. Kiểm thử cửa sổ chính với 100 cập nhật khi ẩn vẫn qua. Mẫu CPU khi hiện sau khởi động: 13,7 / 21,0 / 14,8 / 15,8 / 13,7%; RSS cuối khoảng 141 MiB. Khi ẩn mascot: 0,0 / 0,0 / 0,0 / 0,3%, RSS khoảng 85,7 MiB. Đây là mẫu ngắn, chưa benchmark kiểm soát; chưa chứng minh giảm đáng kể CPU khi hoạt cảnh hiện. Máy khóa lại trước kiểm tra bật lại qua UI, nên phần này chưa xác minh trực quan. Chưa đo phiên họp nhiều giờ.

Mẫu đo khi màn hình Cuộc họp rảnh và Chip Chip bật: trước điều chỉnh timeline CPU 21,3–34,1%; sau điều chỉnh ba mẫu đầu 16,5–18,9%. RSS sau khoảng 157,5 MiB. Đây là mẫu ngắn khác thời điểm, không phải benchmark kiểm soát hoặc RAM cực đại. CPU vẫn đáng theo dõi khi hoạt cảnh chạy liên tục; nên thử thêm nhịp idle thích ứng và tạm dừng hoàn toàn khi không hiển thị. Stack mẫu tập trung ở cập nhật giao diện TimelineView; chưa xác định mọi nguồn CPU.

Cache Edge trên ổ đĩa vẫn do người dùng dọn trong Lưu trữ, chưa có quota tự động. NSCache số lượng hình không phải trần byte giải mã tuyệt đối. Việc nạp frame hoạt cảnh vẫn có I/O lần đầu; cần profile trên máy yếu trước khi chuyển thành pipeline preload nền. Chưa stress cuộc họp nhiều giờ, benchmark Intel hoặc xác minh độ chính xác người nói/phát âm bằng chuyên gia. Không suy ra RAM cực đại từ một mẫu RSS lúc app rảnh.
