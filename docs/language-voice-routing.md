# Giọng đọc theo ngôn ngữ

Trong Cài đặt → Giọng đọc & Phát âm, chọn ngôn ngữ, công cụ và giọng mô hình. Lựa chọn lưu riêng theo mã ngôn ngữ, áp dụng cho Trò chuyện, đọc phụ đề, sổ tay, từ vựng, flashcard và Đọc văn bản. Nghe chậm không thay đổi tốc độ đã lưu.

## Mô hình đã tích hợp

| Công cụ | Bộ xử lý | Phạm vi |
| --- | --- | --- |
| VieNeu-TTS v3 Turbo | Swift + ONNX CPU FP32, SEA-G2P native | Tiếng Việt, 25 giọng preset |
| Qwen3-TTS 0.6B CustomVoice | MLX Audio 0.5.7, trọng số 8-bit | Tiếng Trung và các ngôn ngữ model hỗ trợ; cần Apple Silicon |
| Supertonic 3 | ONNX native | Việt, Anh, Nhật, Hàn |
| Giọng cơ bản | Bộ đọc hệ thống | Dự phòng |
| Edge | Dịch vụ trực tuyến | Cần mạng, xuất MP3 |

Supertonic là lựa chọn mặc định cho bản cài mới; sau khi người dùng đồng ý giấy phép, tải bộ dữ liệu một lần. Những lựa chọn đã lưu được giữ nguyên.

**VieNeu native:** Nút **Tải & Cài** chỉ tải trọng số, streaming codec và từ điển SEA-G2P (~583 MB). ONNX Runtime và phonemizer native universal đã có trong app (~10 MB cho SEA-G2P). Không dùng Python, pip hay môi trường SDK. Tệp từ bản cũ được tái sử dụng sau khi kiểm tra SHA-256; đánh dấu đã cài chỉ sau khi tạo audio thật thành công. SDK VieNeu cũ có thể dọn trong Lưu trữ.

**Qwen tùy chọn:** Chỉ cài khi người dùng yêu cầu; dùng Python và MLX Audio riêng, khoảng 1,8 GiB trọng số chưa tính bộ xử lý. Không tự tải mô hình khi bấm đọc.

Chọn **Dùng cho Tiếng Việt/Tiếng Trung** sau khi cài hoặc chọn công cụ cho từng ngôn ngữ. Chưa cài hoặc sai ngôn ngữ sẽ thông báo và dùng giọng dự phòng. Bài học âm/chữ cơ bản vẫn dùng bản ghi người thật, không thay bằng TTS.

## Tài nguyên và hủy tác vụ

- Chỉ giữ một bộ xử lý mô hình nặng tại một thời điểm. VieNeu và Supertonic chạy native; Qwen dùng worker riêng. Chuyển công cụ phải chờ bộ xử lý cũ giải phóng.
- Giọng và tốc độ được chốt cho từng lượt đọc/xuất. Đổi cấu hình áp dụng cho lượt tiếp theo, không đổi giọng giữa đoạn.
- Đổi lựa chọn không nạp trọng số. Model giữ ấm giữa các câu, giải phóng sau 120 giây không dùng hoặc khi có áp lực bộ nhớ. Khi đọc bằng công cụ cơ bản/Edge, model Local được giải phóng.
- Tối đa hai gói WAV chờ phát. Backpressure chặn nhà sản xuất khi hàng đợi đầy. Không tạo toàn bộ audio dài trong RAM.
- Đọc, tải model, xuất và gỡ dữ liệu được kiểm tra trạng thái bận; hủy tải kết thúc nhóm tiến trình cài SDK.
- Worker giao tiếp qua pipe riêng, không mở HTTP server. Khi đọc, truy cập Hugging Face chuyển sang offline; kiểm tra checksum dữ liệu khi khởi động worker.
- Streaming dùng PCM liên tục, điều chỉnh tốc độ qua AVAudioUnitTimePitch giữ cao độ. VieNeu xuất WAV đổi tốc độ bằng bộ render native, không cần Python/JIT. Qwen vẫn dùng bộ xử lý riêng khi xuất.
- Lỗi trước khi có audio có thể dùng giọng cơ bản; lỗi sau khi đã phát báo gián đoạn để tránh lặp toàn đoạn.

## Xuất và xóa

Đọc văn bản xuất WAV cho mô hình Local đã cài, MP3 cho Edge. Giọng cơ bản không xuất. Xuất theo công cụ đã chọn, không tự chuyển sang model khác. WAV ghi từng đoạn vào file tạm, giới hạn 60 MiB và xác minh sample format. Chỉ ghi file đích sau khi hoàn thành.

Lưu trữ & Dữ liệu hiển thị riêng dữ liệu VieNeu, Qwen, bộ xử lý Qwen, Python và nhật ký cài. SDK VieNeu cũ có mục dọn riêng; VieNeu native không cần môi trường này. Gỡ mô hình chờ bộ xử lý giải phóng rồi chuyển dữ liệu vào Thùng rác.

## Kết quả kiểm thử ngày 04/10/2026

11 kiểm thử đã qua, gồm đối chiếu phonemizer/tokenizer với SDK chính thức trên sáu mẫu văn bản, tổng hợp VieNeu native, streaming, xuất WAV chậm, đổi VieNeu ↔ Qwen, hủy và phục hồi, định tuyến và parser WAV. Chưa đo RAM cực đại hoặc kiểm thử trên máy Intel. Chất lượng sư phạm/phát âm cần người bản ngữ đánh giá; TTS không thay nguồn bản ghi người thật cho chữ cái.

Nguồn: [VieNeu](https://github.com/pnnbao97/VieNeu-TTS), [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS), [MLX Audio](https://github.com/Blaizzy/mlx-audio). Revision và bộ phụ thuộc nằm trong Resources/SpeechRuntime. Không hỗ trợ tải mã Python/model tùy ý từ giao diện.

## VieNeu native (04/10/2026)

- Bộ sinh frame, speaker projection, byte-level BPE và MOSS streaming decoder được triển khai trong Swift, dùng ONNX Runtime đã có trong app.
- SEA-G2P 0.10.0 được biên dịch thành C ABI không bật Python; giữ nguyên quy tắc chuẩn hóa số, ngày tháng, tỷ lệ và tiếng Anh xen kẽ. Nguồn khóa ở `e825173f235d08ea19315b2b279fb11153b44cea`; script `scripts/build-native-phonemizer.sh` phục vụ máy build, không chạy trên máy người dùng.
- Mô hình/codec khóa revision trong `Resources/SpeechNative/vieneu-native-manifest.json`; kiểm tra SHA-256 khi cài và khi nạp phiên ONNX đầu tiên. Không tải encoder/denoiser vì hiện chỉ dùng 25 giọng preset, chưa cung cấp clone giọng.
- Âm thanh được phát nối tiếp trên cùng audio engine. Export dùng AVAudioUnitTimePitch ở chế độ offline, giữ cao độ khi đổi tốc độ; không cần librosa.
- Cụm ngắn giữ audio đến khi EOS hợp lệ, có trần frame theo số âm tiết và tối đa hai lần thử lại để giảm hiện tượng nói thêm. Không cam kết mọi câu tạo sinh đều đúng tuyệt đối; bản ghi người thật cho âm/chữ cơ bản vẫn là nguồn học chuẩn riêng.
- Dùng chung router với Supertonic và Qwen, một mô hình nặng tại một thời điểm; hủy giữa các graph, giải phóng khi thiếu bộ nhớ hoặc sau 120 giây không dùng.
- Các mẫu SDK đối chiếu gồm câu thường, ngày tháng, tỷ lệ, số La Mã và từ Anh xen kẽ. Kiểm thử thêm streaming, xuất WAV chậm, hủy/phục hồi và chuyển VieNeu ↔ Qwen.

Nguồn: [VieNeu-TTS](https://github.com/pnnbao97/VieNeu-TTS), [SEA-G2P C ABI](https://github.com/pnnbao97/sea-g2p/blob/e825173f235d08ea19315b2b279fb11153b44cea/include/sea_g2p.h). Giấy phép Apache-2.0 đi kèm ứng dụng.
