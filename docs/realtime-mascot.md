# Mascot RealityKit prototype

Kiểu `3d` hiện dùng hình học RealityKit trực tiếp qua NSViewRepresentable/ARView, tương thích deployment target macOS 14. Kiểu `sprite` giữ bộ PNG, `pixel` giữ pixel art. Chọn trong Cài đặt → kiểu mascot.

Model được tạo trong `Sources/TransTools/RealtimeMascot.swift`: đầu oval, panel mặt, mắt nhiều lớp, tai nghe với quai mesh liên tục, thân và tay, hai chân giải khớp hông/gối. Không cần tải model hay kết nối mạng.

Chuyển động cập nhật theo SceneEvents.Update: pha chân lấy từ quãng đường ở Dock, bàn chân trụ giữ độ cao cố định, chân vung được nâng; xoay yaw theo cung ngắn, nội suy tốc độ vào/ra đi bộ. Có thở, chớp mắt, wink và tư thế cúi đầu khi làm việc/ngủ. Giảm chuyển động vô hiệu bước chân/thở/chớp tự động.

Đây là prototype dựng bằng code, chưa phải model được nghệ sĩ dựng/rig: ngoại hình đơn giản hơn ảnh tham chiếu; dáng viết chỉ đặt tay, dáng ngủ chỉ cúi đầu. Chưa có sổ/bút, pose nằm ngủ hay contact shadow vật lý. Bộ sprite có thể chọn lại trong cài đặt.

Đã kiểm tra build release và hiển thị thực tế trên nền sáng và tối ở cửa sổ Bộ chuyển động mascot (menu Window → Xem bộ chuyển động mascot). Có ba mẫu RealityKit đứng/đi trái/đi phải để so sánh với PNG. Hiệu năng GPU và pin chưa được đo trên nhiều cấu hình máy.
