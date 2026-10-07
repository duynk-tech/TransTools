# Website và cập nhật ứng dụng

Website: https://trans-tools.vercel.app

Vercel chỉ phục vụ website và API thông tin phiên bản. Bộ cài Mac và Windows được lưu trên GitHub Releases; không upload bộ cài lên Vercel hoặc Vercel Blob.

- `/updates/latest.json` lấy thông tin từ GitHub Release ổn định mới nhất.
- `/download` chuyển hướng đến file trên GitHub Releases.
- Các nút tải trên website trỏ trực tiếp về GitHub Releases.
- Ứng dụng xác minh checksum trước khi cài bản cập nhật.

## Phát hành

1. Tăng phiên bản ứng dụng và thêm ghi chú phát hành.
2. Push tag `vX.Y.Z`; workflow build và upload bộ cài vào GitHub Release.
3. Deploy website lên Vercel khi nội dung website thay đổi. `.vercelignore` loại trừ bộ cài và thư mục build Windows.

Không cần `BLOB_READ_WRITE_TOKEN`. Script upload Vercel cũ đã bị vô hiệu hóa để tránh tải bộ cài lên nhầm nơi.
