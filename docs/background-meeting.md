# Cuộc họp khi đóng cửa sổ chính

Đóng bằng nút đỏ hoặc Cmd+W chỉ ẩn bảng điều khiển; không hủy cửa sổ, không dừng capture/nhận diện/dịch, không ẩn phụ đề nổi. App giữ MeetingModel ở App StateObject và không thoát khi hết cửa sổ chính.

Sửa attachMainWindow để chỉ gắn mỗi đối tượng NSWindow một lần: các cập nhật SwiftUI từ caption mới không được gọi makeKeyAndOrderFront/activate lại. Khi cần mở lại, dùng nút “Mở bảng điều khiển” trên HUD, menu bar hoặc biểu tượng Dock. Cmd+Q vẫn thoát ứng dụng.

Kiểm tra: build macOS và codesign; test-main-window-lifecycle.py kiểm tra callback đóng, 100 lượt cập nhật sau khi ẩn, mở lại chủ động và thay đối tượng cửa sổ. Kiểm tra này không mô phỏng cuộc họp audio thực tế. Chưa thay app đang mở để tránh mất phiên phụ đề hiện tại.
