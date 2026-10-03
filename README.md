# TransTools

Dịch cuộc họp, lưu kiến thức và luyện giao tiếp cùng Chip Chip.

[Website](https://trans-tools.vercel.app/) · [Tải ứng dụng](https://trans-tools.vercel.app/releases) · [Hướng dẫn](https://trans-tools.vercel.app/guide)

## Tính năng

- **Cuộc họp:** chọn nguồn âm thanh trước khi bắt đầu; nhận diện giọng nói, dịch theo đoạn và xem tiếng gốc, bản dịch hoặc song ngữ. Phụ đề nổi hoạt động khi đóng cửa sổ chính. Tách người nói bằng mô hình Local, với nhãn Người nói 1, 2…; không xác định danh tính.
- **Dịch nhanh:** dịch theo chuyên ngành, sửa ngữ pháp, dịch Việt → Anh theo phong cách đã chọn, nhận diện chữ trong ảnh và đọc văn bản thành audio.
- **Sổ tay:** lưu phụ đề và hội thoại, tìm kiếm, ghi chú và xuất Word/TXT/SRT. Có key AI thì có thể tóm tắt nội dung cuộc họp.
- **Học ngôn ngữ:** tiếng Anh, Nhật, Trung và Hàn; mục tiêu hằng ngày, từ vựng theo ngôn ngữ, flashcard, Chữ & Viết và luyện giao tiếp. Cùng Chip Chip mở bảng học riêng cạnh mascot.
- **Trò chuyện:** tab riêng, hỗ trợ cả tiếng Việt; chọn chủ đề công việc, du lịch, phỏng vấn, công nghệ, học tập hoặc chủ đề riêng. Prompt bổ sung xác định vai trò và tình huống. Chủ đề/prompt được lưu cùng hội thoại; có thể tạo mới, mở tiếp và xóa buổi đã lưu. Cần key AI.
- **Giọng đọc:** Giọng tự nhiên **Local**, Giọng cơ bản **Local**, Giọng AI trực tuyến **Edge** và Gemini khi được cấu hình. Giọng tự nhiên cần tải mô hình và đồng ý giấy phép trước khi dùng offline. Khả năng ngôn ngữ tùy công cụ; giọng Local hiện hỗ trợ Việt, Anh, Nhật, Hàn, tiếng Trung dùng giọng cơ bản.
- **Chip Chip:** trợ lý nổi, dịch văn bản đã chọn, hoạt cảnh thư giãn, đi dạo và bảng học.
- **Cập nhật:** nguồn công khai trên Vercel; tải ZIP để cập nhật hoặc DMG để cài bằng kéo thả.

## Bản phát triển và bản tải xuống

Mã nguồn hiện có các thay đổi mới hơn bản phát hành v1.3.1. Push code không tạo bản ZIP/DMG mới. Những tính năng mới trên website được ghi rõ là thuộc bản phát triển; bản tải xuống có thể khác.

Trò chuyện hiện là **hội thoại theo lượt**, không phải audio hai chiều đồng thời. Chọn chờ 0,8 / 1,2 / 2 giây sau câu nói; dùng Nói tiếp để ngắt phần đọc và chuyển lượt. Gợi ý mặc định tắt. Bật **Dịch Tiếng Việt** để xem bản dịch dưới câu; tùy chọn ẩn khi nói tiếng Việt.

Tách người nói chờ khoảng 10 giây cộng thời gian xử lý. Cửa sổ audio có ngữ cảnh nối, giữ tối đa 30 giây khi mô hình đang nạp và chờ đủ timing trước khi chia caption. Nói chồng, câu ngắn, tiếng vọng và giọng gần nhau vẫn có thể thiếu hoặc sai nhãn. Kiểm thử bằng bản ghi mẫu không thay thế kiểm tra cuộc họp thực tế.

## Cài đặt

Yêu cầu macOS 14 trở lên; Apple Translate cần macOS 15 trở lên và bộ ngôn ngữ được hỗ trợ. Quy trình build và Local TTS đã kiểm thử trên Apple Silicon.

Tải [DMG hoặc ZIP](https://trans-tools.vercel.app/releases). Với DMG, kéo TransTools vào Applications. Cấp quyền phù hợp cho nguồn âm thanh; chọn nguồn rồi bấm Bắt đầu. Kết nối AI và giọng trực tuyến phụ thuộc mạng, key và hạn mức nhà cung cấp.

## Quyền riêng tư

API key được mã hóa cục bộ bằng CryptoKit AES-GCM, không dùng Keychain. Mã hóa không thay thế việc bảo vệ tài khoản và máy đang đăng nhập.

Nhận diện có chế độ Local; khả năng tùy ngôn ngữ và hệ thống. Apple Translate dùng bộ ngôn ngữ Local. Tách người nói và giọng tự nhiên Local xử lý audio trên máy sau khi tải mô hình. Khi chọn Google hoặc AI trực tuyến, nội dung cần dịch/đọc được gửi tới dịch vụ tương ứng. OCR nhận diện bằng Apple Vision; kiểm tra chữ trước khi dịch.

Bản ghi phát âm cơ bản dùng nguồn thu âm tham chiếu; xem [tài liệu nguồn](docs/letter-pronunciation.md) và phần Giới thiệu trong app. Không xem TTS là nguồn chứng nhận phát âm cơ bản.

## Build và phát hành

```bash
git clone https://github.com/duynk-tech/TransTools.git
cd TransTools
./scripts/build-app.sh
open build/TransTools.app
```

```bash
./scripts/package-release.sh
```

Lệnh đóng gói tạo ZIP, DMG và SHA256. Workflow `.github/workflows/release.yml` chạy khi push tag phiên bản, tạo GitHub Release và cập nhật Vercel Blob theo cấu hình secret. Xem [nguồn cập nhật](docs/vercel-updates.md). Chữ ký build hiện tại là ad hoc.

## Tài liệu

- [Trò chuyện và chủ đề](docs/conversation-topics.md)
- [Dịch nhanh và đọc văn bản](docs/quick-translation-and-text-reader.md)
- [Giọng tự nhiên Local](docs/local-natural-tts.md)
- [Tách người nói](docs/speaker-diarization.md)
- [Dịch cuộc họp Local](docs/local-meeting-translation.md)
- [Bảng học cùng Chip Chip](docs/learning-studio.md)
- [Rà soát giao diện](docs/ui-design-audit.md)
- [Hướng dẫn website](docs/guide.html)

© 2026 DuyNK-Tech · [GitHub](https://github.com/duynk-tech/TransTools) · [Email](mailto:khacduy90@gmail.com)
