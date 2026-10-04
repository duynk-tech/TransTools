# Trans Tools

Dịch cuộc họp, lưu kiến thức và luyện giao tiếp cùng Chip Chip.

[Website](https://trans-tools.vercel.app/) · [Tải ứng dụng](https://trans-tools.vercel.app/releases) · [Hướng dẫn](https://trans-tools.vercel.app/guide)

## Tính năng

- **Cuộc họp:** chọn nguồn âm thanh trước khi bắt đầu; nhận diện giọng nói, dịch theo đoạn và xem tiếng gốc, bản dịch hoặc song ngữ. Phụ đề nổi hoạt động khi đóng cửa sổ chính.
- **Dịch nhanh:** dịch theo chuyên ngành, sửa ngữ pháp, dịch Việt → Anh theo phong cách đã chọn, nhận diện chữ trong ảnh và đọc văn bản thành audio.
- **Sổ tay:** lưu phụ đề và hội thoại, tìm kiếm, ghi chú và xuất Word/TXT/SRT. Có key AI thì có thể tóm tắt nội dung cuộc họp.
- **Học ngôn ngữ:** tiếng Anh, Nhật, Trung và Hàn; mục tiêu hằng ngày, từ vựng theo ngôn ngữ, flashcard, Chữ & Viết và luyện giao tiếp. Cùng Chip Chip mở bảng học riêng cạnh mascot.
- **Trò chuyện:** tab riêng, hỗ trợ cả tiếng Việt; chọn chủ đề công việc, du lịch, phỏng vấn, công nghệ, học tập hoặc chủ đề riêng. Prompt bổ sung xác định vai trò và tình huống. Chủ đề/prompt được lưu cùng hội thoại; có thể tạo mới, mở tiếp và xóa buổi đã lưu. Cần key AI.
- **Giọng đọc theo ngôn ngữ:** Supertonic 3, **VieNeu-TTS v3 Turbo** cho tiếng Việt, **Qwen3-TTS 0.6B** cho tiếng Trung và ngôn ngữ được hỗ trợ; giọng cơ bản và Edge dự phòng. Cài mô hình một lần rồi dùng Local offline. Mỗi ngôn ngữ có công cụ và giọng riêng, dùng chung cho trò chuyện, phụ đề, từ vựng/flashcard và đọc văn bản. Xuất WAV Local hoặc MP3 Edge khi công cụ hỗ trợ.
- **Lưu trữ & Dữ liệu:** xem dung lượng mô hình và cache, mở thư mục, dọn hoặc gỡ vào Thùng rác; giữ Sổ tay, từ vựng và API key.
- **Cấu hình AI:** tải danh sách model văn bản từ nhà cung cấp, chọn và lưu riêng cho từng dịch vụ.
- **Chip Chip:** trợ lý nổi, dịch văn bản đã chọn, hoạt cảnh thư giãn, đi dạo và bảng học.
- **Cập nhật:** nguồn công khai trên Vercel; tải ZIP để cập nhật hoặc DMG để cài bằng kéo thả.

## Bản phát triển và bản tải xuống

Bản v1.4.0 gồm các tính năng được mô tả dưới đây. Bộ cài ZIP và DMG được phát hành riêng với website; push nội dung website không tự tạo bộ cài mới.

Trò chuyện hiện là **hội thoại theo lượt**, không phải audio hai chiều đồng thời. Chọn chờ 0,8 / 1,2 / 2 giây sau câu nói; dùng Nói tiếp để ngắt phần đọc và chuyển lượt. Gợi ý mặc định tắt. Bật **Dịch Tiếng Việt** để xem bản dịch dưới câu; tùy chọn ẩn khi nói tiếng Việt.

## Cài đặt

Yêu cầu macOS 14 trở lên; Apple Translate cần macOS 15 trở lên và bộ ngôn ngữ được hỗ trợ. Quy trình build và Local TTS đã kiểm thử trên Apple Silicon.

Tải [DMG hoặc ZIP](https://trans-tools.vercel.app/releases). Với DMG, kéo Trans Tools vào Applications. Cấp quyền phù hợp cho nguồn âm thanh; chọn nguồn rồi bấm Bắt đầu. Kết nối AI và giọng trực tuyến phụ thuộc mạng, key và hạn mức nhà cung cấp.

## Quyền riêng tư

API key được mã hóa cục bộ bằng CryptoKit AES-GCM, không dùng Keychain. Mã hóa không thay thế việc bảo vệ tài khoản và máy đang đăng nhập.

Nhận diện có chế độ Local; khả năng tùy ngôn ngữ và hệ thống. Apple Translate dùng bộ ngôn ngữ Local. Giọng tự nhiên Local xử lý audio trên máy sau khi tải mô hình. Khi chọn Google hoặc AI trực tuyến, nội dung cần dịch/đọc được gửi tới dịch vụ tương ứng. OCR nhận diện bằng Apple Vision; kiểm tra chữ trước khi dịch.

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

- [Quản lý lưu trữ](docs/storage-management.md)
- [Trò chuyện và chủ đề](docs/conversation-topics.md)
- [Dịch nhanh và đọc văn bản](docs/quick-translation-and-text-reader.md)
- [Giọng tự nhiên Local](docs/local-natural-tts.md)
- [Mô hình theo ngôn ngữ, quản lý bộ nhớ và kiểm thử VieNeu/Qwen](docs/language-voice-routing.md)
- [Dịch cuộc họp Local](docs/local-meeting-translation.md)
- [Bảng học cùng Chip Chip](docs/learning-studio.md)
- [Rà soát giao diện](docs/ui-design-audit.md)
- [Hướng dẫn phiên bản Windows (.exe)](docs/windows-build-guide.md)
- [Hướng dẫn website](docs/guide.html)

© 2026 DuyNK-Tech · [GitHub](https://github.com/duynk-tech/TransTools) · [Email](mailto:khacduy90@gmail.com)
