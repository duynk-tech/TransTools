# TransTools — v1.3.0

> **Bộ công cụ dịch thuật trực tiếp âm thanh cuộc họp, phụ đề nổi song ngữ & trợ lý AI thông minh trên macOS.**  
> 🌐 **Website giới thiệu:** [duynk-tech.github.io/TransTools](https://duynk-tech.github.io/TransTools/)  
> 👤 **Phát triển bởi:** **DuyNK-Tech** ([khacduy90@gmail.com](mailto:khacduy90@gmail.com)) • GitHub: [duynk-tech/TransTools](https://github.com/duynk-tech/TransTools)

---

## 🌟 Tính năng nổi bật

- 🌐 **Hỗ trợ 9 ngôn ngữ & giọng điệu chuyên biệt**:
  - Tiếng Anh (Mỹ/UK `en-US`), **Tiếng Anh Ấn Độ (Indian English `en-IN`)** với bộ nhận diện giọng điệu chuyên sâu.
  - **Tiếng Ý (`it-IT`)**, Tiếng Việt (`vi-VN`), Tiếng Trung (`zh-CN`), Tiếng Nhật (`ja-JP`), Tiếng Hàn (`ko-KR`), Tiếng Pháp (`fr-FR`), Tiếng Đức (`de-DE`).
- ⚡ **Dịch thuật đa động cơ (Multi-engine AI)**:
  - **Apple Native Translation**: Dịch on-device hoàn toàn miễn phí, 0 token, siêu tốc ~15ms và bảo mật tuyệt đối.
  - **Cloud AI Engines**: Hỗ trợ Google Gemini, OpenAI GPT-4o, Anthropic Claude, DeepSeek API (mã hóa an toàn cục bộ bằng Apple CryptoKit AES-256 gắn với phần cứng).
- 💬 **Trợ lý AI Meeting Co-Pilot**:
  - Tự động phân tích ngữ cảnh hội thoại cuộc họp.
  - Gợi ý câu trả lời chuyên nghiệp theo chuyên ngành (Developer/Kỹ thuật, Kinh doanh/Sales, Quản lý/PM, Học thuật, Y tế, v.v.).
- 🤖 **Trợ lý nổi Chip Chip (Desktop Companion)**:
  - Mascot hoạt họa đáng yêu luôn ở trên màn hình.
  - Tự động thay đổi biểu cảm: viết chép khi cuộc họp đang diễn ra, chớp mắt tự nhiên, nháy mắt tương tác.
  - Hộp nhập liệu dịch nhanh (Quick Translate) 2 chiều (Anh ⇄ Việt), bấm Enter tự động chép bản dịch vào Clipboard.
- 🪟 **Phụ đề nổi thông minh (HUD Subtitle Overlay)**:
  - Cửa sổ nổi xuyên suốt màn hình (Always-on-top), hỗ trợ kéo thả tự do, ẩn/hiện tức thì.
  - Hiển thị song ngữ (Tiếng Anh - Tiếng Việt) hoặc chỉ tiếng Việt.
- 📓 **Sổ tay cuộc họp (Meeting Notebook)**:
  - Tự động lưu toàn bộ nội dung phụ đề sau mỗi phiên làm việc.
  - Tìm kiếm, lọc, chỉnh sửa tiêu đề/ghi chú, và xuất báo cáo dưới dạng Text hoặc phụ đề chuẩn SRT.
- 🔄 **Tự động cập nhật (Auto-Update from GitHub Releases)**:
  - Tự động kiểm tra bản cập nhật mới từ kho lưu trữ GitHub `duynk-tech/TransTools`.
  - Tải xuống và tự động cập nhật, khởi động lại chỉ với 1 click.

---

## 🚀 Hướng dẫn cài đặt & Chạy ứng dụng

### 1. Yêu cầu hệ thống
- macOS 14.0 (Sonoma) hoặc mới hơn.
- Chip Apple Silicon (M1/M2/M3/M4) hoặc Intel.

### 2. Tải về bản đóng gói sẵn
Tải bản phát hành mới nhất (`TransTools.dmg` hoặc `TransTools.zip`) tại mục [GitHub Releases](https://github.com/duynk-tech/TransTools/releases), mở DMG và kéo TransTools vào Applications; hoặc giải nén ZIP và đưa app vào `/Applications`.

### 3. Tự biên dịch từ mã nguồn
```bash
# Clone mã nguồn
git clone https://github.com/duynk-tech/TransTools.git
cd TransTools

# Đóng gói ứng dụng release
./scripts/build-app.sh

# Mở ứng dụng
open build/TransTools.app
```

---

## 📦 Đóng gói bản phát hành & Tự động cập nhật

Để đóng gói phiên bản mới phát hành:
```bash
./scripts/package-release.sh
```
Lệnh trên sẽ tự động build release, đóng gói cả `build/TransTools.zip` và `build/TransTools.dmg` (kéo thả vào Applications), cùng tệp SHA256 cho mỗi định dạng. App dùng chữ ký ad hoc của quy trình build hiện tại.

Khi bạn push một git tag mới (ví dụ: `v1.3.0`), GitHub Actions trong file `.github/workflows/release.yml` sẽ tự động kích hoạt, build và tạo GitHub Release đính kèm `TransTools.zip`, `TransTools.dmg` và hai tệp SHA256. Auto-Update dùng ZIP; DMG dành cho cài đặt kéo thả.

---

## 🛡️ Quyền riêng tư & Bảo mật
- Tất cả API Key được lưu trữ mã hóa cục bộ bằng **Apple CryptoKit AES-256-GCM**, gắn với Hardware UUID của máy (không chia sẻ, không đồng bộ ra ngoài).
- Dữ liệu nhận diện giọng nói và dịch Apple hoàn toàn được xử lý cục bộ trên thiết bị của bạn.
- Không thu thập hay chia sẻ âm thanh/hình ảnh ra bất kỳ máy chủ trung gian nào.

---

## 📄 Bản quyền & Tác giả
© 2026 **DuyNK-Tech**. Toàn quyền sở hữu.  
Email: [khacduy90@gmail.com](mailto:khacduy90@gmail.com)  
Website/GitHub: [https://github.com/duynk-tech/TransTools](https://github.com/duynk-tech/TransTools)
