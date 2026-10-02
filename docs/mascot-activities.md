# Bộ hoạt động mascot

Sáu PNG trong Resources/MascotActivities: coffee, writing, thinking, strolling, flowers (kèm bướm), sleeping. Canvas 621 × 783, alpha trong suốt, khuôn mặt và vật liệu theo mascot PNG đã duyệt. Master: work/mascot-activities/approved-sheet.png. Chạy scripts/prepare-mascot-activities.py để tách/chuẩn hóa; manifest có checksum. Đây là ảnh UI và tham chiếu tạo hình, chưa phải dữ liệu huấn luyện Vision/Core ML.

Kiểu Mascot ảnh sử dụng ảnh hoạt động khi uống cà phê, ghi chép, suy nghĩ, hái hoa/bắt bướm và ngủ; đi bộ vẫn dùng sprite animation. Ghi chép và Suy nghĩ đã thêm vào menu hoạt động và vòng tự động.

RealityKit dùng texture mắt cắt từ PNG chính diện (EyeLeft/EyeRight) trên bề mặt riêng đặt trước đầu, đầu oval rộng hơn. Sửa pha chân trụ từ cos(phase) thành -cos(phase): chân trụ lùi tương đối với thân; mũi chân hướng +Z cùng hướng mặt. Gót và mũi là hai khối riêng. Có cốc/cà phê, sổ/bút, hoa, bướm bay và gối ngủ; đạo cụ gắn vào torso/tay để di chuyển cùng nhân vật. Tắt đạo cụ overlay 2D trong kiểu 3D để không hiển thị trùng.

Cửa sổ preview có lựa chọn sáu hoạt động 3D. Hình học vẫn là prototype dựng bằng code: các động tác uống, viết, suy nghĩ/hái hoa còn cách điệu, chưa có animation cầm nắm chuyên nghiệp hay mô phỏng vải của gối. PNG thể hiện chi tiết tạo hình tốt hơn; cần model được dựng và rig riêng để đạt mức đó từ mọi góc 3D.

## Lựa chọn hiển thị hiện tại

Mascot ảnh là mặc định. Lựa chọn `3d` cũ được chuyển sang `sprite` khi khởi động; Pixel được giữ nguyên nếu đã chọn. Menu tạo hình và nút đổi nhanh chỉ còn Mascot ảnh/Pixel. RealityKit chỉ còn trong công cụ preview để tham khảo, không dùng trong mascot chính.
