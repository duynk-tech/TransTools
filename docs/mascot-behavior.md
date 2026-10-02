# Nguồn âm thanh và hành vi mascot

Nguồn âm thanh khởi động ở trạng thái chưa chọn. Refresh danh sách không tự chọn Teams/hệ thống, kể cả khi refresh lỗi. Start chặn nguồn trống trước mọi yêu cầu Speech/Microphone/ScreenCapture, hiển thị thông báo trên dashboard. Chọn nguồn hợp lệ áp dụng cho phiên app hiện tại.

Hoạt cảnh nghỉ và đi dạo Dock đợi ít nhất 45 giây không có input chuột/bàn phím toàn hệ thống; dùng CGEventSource để đọc thời gian idle, không đọc nội dung phím. Dừng nghỉ khi thao tác lại, hover mascot, mở quick menu/bóng thoại hoặc app bận. Hoạt cảnh viết khi đang nhận diện cuộc họp vẫn chạy để biểu thị công việc.

Chế độ Tự động thông minh dùng giờ trong ngày, thời gian idle, bundle ID ứng dụng foreground, Low Power Mode/thermal state và thời điểm audio gần nhất. Ưu tiên ghi chép/suy nghĩ trong ứng dụng công việc, cà phê vào buổi sáng, ngủ muộn khi đã nghỉ lâu, hoạt cảnh nhẹ khi máy tiết kiệm pin/nóng. Giữ slot 75 giây; không dùng AI mạng. Lựa chọn cảnh cụ thể của người dùng vẫn được giữ, chỉ xuất hiện sau ngưỡng nghỉ.

Menu popover và chuột phải cùng có Tiện ích Chip Chip → Dịch & chỉnh câu, Sổ từ vựng & Flashcards, Đưa Chip Chip về góc thuận tiện. Nhãn ẩn mascot: Tạm biệt Chip Chip.

Validation: release build và codesign strict thành công; kiểm tra 8 kịch bản policy cùng query idle thật; UI khởi động hiển thị Chọn nguồn âm thanh, bấm Bắt đầu giữ Sẵn sàng và hiển thị Hãy chọn nguồn âm thanh trước khi bắt đầu.

Tạo hình hiện chỉ còn Mascot ảnh và Pixel Art. Lựa chọn 3d cũ được chuyển về sprite khi khởi động; bỏ menu/cửa sổ review model và tham số model-preview. Source model vẫn giữ trong workspace. Dáng mặc định PNG có bệ oval mint nhẹ dưới chân; nhịp nhìn quanh 24 giây ưu tiên chính diện, liếc qua góc 3/4 và nghiêng trái/phải, dùng bộ PNG 8 góc sẵn có. Preview góc: `docs/assets/mascot-default-angles.png`.

Bệ mặc định có hai cụm cỏ nhỏ, hoa hồng bên trái và hoa trắng bên phải, đặt ở mép để không che chân. Tất cả là SwiftUI shape, nằm sau PNG và không nhận hit test.

Đi dạo Dock có dải vườn cố định dài theo vùng màn hình hiện tại: nền mint, cụm cỏ/hoa mỗi khoảng 95pt, bướm ở vài đoạn và hai chim nhỏ chuyển động theo cung giới hạn. NSPanel cảnh đặt dưới mascot, trong suốt, ignoresMouseEvents, không kích hoạt app. Chỉ hiện khi đi dạo và idle ≥45 giây; ẩn khi thao tác, họp, hover/bóng thoại, tắt đi dạo hoặc ẩn mascot. Timeline giải phóng lúc panel ẩn và đứng yên nếu Reduce Motion. Dải dùng chiều rộng visibleFrame, không đọc kích thước/nội dung Dock thật.
