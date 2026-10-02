# Chuyển động hoạt động PNG

Hai clip `flowers` và `butterfly`, mỗi clip 64 PNG RGBA 310×391, 16 fps, vòng 4 giây. Asset nằm trong `Resources/MascotActivities/animations`, manifest ghi fps, frame list và SHA256. Preview tại `docs/assets/mascot-activity-animation-preview.gif`.

Imagegen tích hợp tạo sheet 4×2 từ PNG flowers có nét cười: cùng robot ceramic pearl, mắt teal/violet, tai nghe mint, hàng đầu tương tác daisy, hàng sau tương tác bướm cyan, nền magenta đồng nhất. Prompt yêu cầu tư thế nối tiếp nhẹ, toàn thân trong cell, chân cùng baseline, không chữ. Master đầy đủ tại `work/mascot-activity-animation/keyframe-sheet.png`.

Nội suy optical flow giữa các tư thế thay đổi đầu nhiều gây ghost mắt nên bị loại. Bản sử dụng chỉ lấy một master rõ nét cho mỗi clip rồi tạo chuyển động cục bộ liên tục của đầu, tay/hoa và cánh bướm bằng remap premultiplied RGBA; giữ chân cố định. Đây là chuyển động ngắm/nâng hoa và tương tác bướm nhẹ, chưa phải chuỗi cúi xuống nhổ hoa hoặc chạy đuổi bướm hoàn chỉnh. Các pose khác giữ nguyên.

App phát theo Timeline sẵn có, có fallback ảnh tĩnh nếu clip thiếu; Reduce Motion giữ frame đầu. Khi clip chạy, bỏ bob/tilt toàn thân cũ và bướm overlay thứ hai để không bị chồng chuyển động. Các PNG chuyển về 310×391 để giảm bộ nhớ nhưng vẫn dư độ phân giải cho mascot 80pt.

Tạo lại: `python3 scripts/prepare-mascot-activity-animation.py`, sau đó `zsh scripts/build-app.sh`.

Tiểu cảnh ngoài trời: `MascotOutdoorSky` thêm gradient xanh nhạt, biên mềm và hai cụm mây phía trên mascot PNG khi hoạt động hoa/bướm/đi dạo/câu cá. Mây trôi chậm biên độ 3pt, đứng yên với Reduce Motion. View không nhận hit test, không thay đổi vùng kéo mascot.
