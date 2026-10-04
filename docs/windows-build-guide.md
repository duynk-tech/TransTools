# Hướng dẫn Build và Phát hành Trans Tools cho Windows (.exe)

Trans Tools phiên bản Windows được xây dựng dựa trên nền tảng **.NET 9 + WPF (Windows Presentation Foundation)** và **Direct WASAPI Audio Loopback**, chuyển đổi toàn bộ tính năng cốt lõi từ phiên bản macOS sang môi trường Windows chuẩn native.

---

## 1. Kiến trúc hệ thống phiên bản Windows

- **Giao diện người dùng (UI):** WPF + Modern Fluent Design, hỗ trợ đầy đủ chế độ nền tối (Dark mode) và hiệu ứng trong suốt (Acrylic/Mica).
- **Thu âm thanh cuộc họp (System Loopback):** Sử dụng `NAudio.Wasapi` để bắt luồng âm thanh trực tiếp từ loa/tai nghe máy tính (từ Zoom, Google Meet, YouTube, Teams...).
- **Nhận diện giọng nói (STT):** Sử dụng `Whisper.net` chạy trực tiếp mô hình GGML Whisper đa ngôn ngữ ngoại tuyến trên CPU/GPU.
- **Giọng đọc (TTS):** 
  - Microsoft Edge TTS thông qua giao thức WebSocket (giọng Hoài My, Nam Minh, Jenny, Guy...).
  - Windows Media Speech Synthesizer tích hợp sẵn trong hệ điều hành.
- **Dịch thuật & Trò chuyện:** Google Translate (nhanh, miễn phí) + Bộ gọi API LLM (OpenAI, Gemini, Claude, DeepSeek, Ollama).
- **Cửa sổ nổi (Floating Windows):**
  - **Phụ đề nổi:** Cửa sổ không viền, nền mờ, luôn nổi trên cùng (`TopMost`), hỗ trợ kéo thả tự do.
  - **Mascot Chip Chip:** Thú cưng nổi trên màn hình với nền trong suốt, bong bóng thoại tương tác.
- **Sổ tay:** Lưu trữ cục bộ dạng JSON tại `%APPDATA%\TransTools\`, xuất biên bản cuộc họp ra file Word (`.docx`) chuẩn Microsoft OpenXML và file phụ đề (`.srt`).

---

## 2. Cách Build tự động bằng GitHub Actions (Không cần máy Windows)

Vì bạn đang làm việc trên máy Mac, hệ thống đã được thiết lập sẵn workflow **GitHub Actions** (`.github/workflows/build-windows.yml`) để tự động biên dịch trên máy ảo Windows của GitHub.

### Cách 1: Chạy thủ công trên GitHub (1-Click)
1. Đẩy code lên GitHub:
   ```bash
   git add .
   git commit -m "feat: Add full-featured Windows version (.NET 9 WPF)"
   git push origin main
   ```
2. Mở repository trên trình duyệt GitHub ➔ Chọn tab **Actions**.
3. Ở menu bên trái, chọn workflow **Build TransTools Windows (.exe)**.
4. Bấm **Run workflow** ➔ Chọn nhánh `main` ➔ Bấm **Run workflow**.
5. Sau khoảng 2-3 phút, GitHub Actions sẽ hoàn thành và bạn có thể tải về ngay tại mục **Artifacts**:
   - `TransTools.exe` (Bản chạy ngay Portable - Single File)
   - `TransTools-Setup.exe` (Bộ cài đặt Windows tự động tạo Desktop Shortcut)
   - `TransTools-Windows-Portable.zip`

### Cách 2: Tự động đính kèm khi phát hành Release tag
Khi bạn tạo tag mới (ví dụ `v1.4.0`):
```bash
git tag v1.4.0
git push origin v1.4.0
```
Workflow sẽ tự động build và upload file `TransTools-Setup.exe` trực tiếp vào trang **GitHub Releases** của bạn.

---

## 3. Cách Build thủ công trên máy tính Windows

Nếu bạn mở project trên một máy chạy hệ điều hành Windows:

### Yêu cầu:
- Windows 10 (bản 19041 trở lên) hoặc Windows 11.
- [.NET 9.0 SDK](https://dotnet.microsoft.com/download/dotnet/9.0).
- (Tùy chọn) [Inno Setup 6](https://jrsoftware.org/isinfo.php) nếu muốn đóng gói file Setup.

### Các bước thực hiện:
1. Mở PowerShell trong thư mục gốc của project:
   ```powershell
   cd windows/scripts
   ./build-windows.ps1
   ```
2. File chạy sẽ được tạo tại `windows/build/TransTools.exe`.
3. Để tạo bộ cài đặt:
   - Mở Inno Setup ➔ Chọn file `windows/installer/installer.iss` ➔ Bấm **Compile** (hoặc chạy lệnh `iscc windows/installer/installer.iss`).
   - File bộ cài `TransTools-Setup.exe` sẽ xuất hiện trong thư mục `windows/build/`.
