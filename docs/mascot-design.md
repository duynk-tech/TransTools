# Mascot TransTools — đầu bo tròn

## Quy chuẩn hình dáng

Đầu robot là khối oval / chữ nhật bo tròn mềm, với đường má và cằm liền mạch. Không có đuôi bong bóng thoại, góc tam giác, mỏ nhọn hoặc phần nhô dưới mặt. Quy tắc này áp dụng cho chính diện, nhìn nghiêng, phía sau, khi ngủ và mọi frame animation.

Giữ vỏ trắng ngọc trai, tai nghe mint, mắt teal–violet, thân nhỏ và tay/chân bo tròn. Không thay vị trí mắt để tránh làm lệch các biểu cảm tương tác trong app.

## Phạm vi bộ ảnh

- 5 dáng chính: đứng, viết, nhìn sau, đi bộ và ngủ.
- 8 hướng: front, front_right, right, back_right, back, back_left, left, front_left.
- 32 frame đi phải + 32 frame đi trái, cùng canvas 621 × 783, preview 40 fps.
- Thân và hai chân tách rời từ ảnh đứng mới.
- Icon PNG/ICNS và companion pixel cùng thiết kế đầu tròn.

Các hướng trái là ảnh đối xứng từ hướng phải, dùng cho hiển thị 2D. Bộ này không được xem là tập dữ liệu huấn luyện Vision/Core ML.

## Quy trình sửa

Ảnh chỉnh bằng imagegen tích hợp. Prompt trọng tâm: “Thay chỉ đường viền dưới đầu bằng má/cằm bo tròn liền mạch; bỏ toàn bộ đuôi tam giác và phần nhô nhọn; giữ canvas, vị trí mắt, tai nghe, pose, ánh sáng và mọi chi tiết khác.” Ảnh chính diện đã sửa là tham chiếu chuẩn cho các góc và dáng còn lại.

Python xử lý nền tương phản, khôi phục màu viền, chuẩn hóa frame và tạo ảnh trái đối xứng. Không dùng ngưỡng trắng để xóa nền. Đầu không được xử lý bằng cách cắt thẳng ngang hoặc che điểm nhọn bằng một mảng màu.

Nguồn cũ và Resources trước lần sửa đầu được sao lưu tại `work/head-rounding/originals/`. Ảnh nguồn mới ở `work/resource-review/masters/` và `work/mascot-sprites/masters/`.

Tạo lại PNG bằng `python3 scripts/prepare-resources.py`, rồi `python3 scripts/prepare-mascot-sprites.py`; tạo ICNS từ iconset, sau đó build app. Hai preview trong `docs/assets/resources-preview.png` và `docs/assets/mascot-sprites-preview.png` phải được kiểm tra trước khi sử dụng.

## Điều chỉnh bước đi

Chu kỳ ở Dock lấy pha từ quãng đường đã đi (26 pt cho một chu kỳ ở chiều cao 80 pt), thay vì chạy theo đồng hồ riêng. Khi hover hoặc dừng, pha chân cũng dừng. Tốc độ dùng thời gian thực giữa các tick, giảm dần gần mép màn hình; các frame được căn theo bàn chân chạm đất để tránh trồi sụt. Preview riêng vẫn phát 10 fps.

## Bổ sung frame trung gian

Mỗi hướng có 8 keyframe nguồn và 24 frame nội suy, tổng cộng 32 frame/chu kỳ. Nội suy optical flow hai chiều dùng màu premultiplied alpha và trường khoảng cách đường viền để hạn chế bóng chân mờ; có nội suy cả đoạn cuối về đầu. Đây là frame nội suy, không phải 32 tư thế vẽ độc lập. Góc nhìn khi quay đầu chuyển opacity 0,18 giây; không tạo thêm góc camera 3D.
