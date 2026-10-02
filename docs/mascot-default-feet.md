# Chân PNG mặc định

Bộ mặc định đã cập nhật 8 góc trong `Resources/MascotSprites/angles`, cùng `Resources/Mascot3D.png` và `Resources/MascotBack.png`. Chân ngắn, bo mềm, mũi chân hướng theo góc nhìn; bỏ cổ chân xếp tầng và đế dày. Bộ đi bộ và các hoạt cảnh riêng không thuộc lần sửa này.

Ảnh được chỉnh bằng công cụ imagegen tích hợp, từ 5 PNG gốc: front, front_right, right, back_right, back. Ba góc trái được đối xứng từ góc phải. Python làm sạch nền magenta và ghép vùng chân, giữ nguyên pixel phần trên vùng ghép của 5 ảnh gốc.

Prompt chung: “Edit ONLY the lower legs and feet. Preserve everything above the hips, the head, eyes, smile, mint headphones, hands, camera and lighting. Short soft pearl chibi legs flow into compact flattened oval feet. Toes point in the same direction as the face; the right profile faces right. No boots, thick soles, stacked ankle joints or reversed toes. Keep the same baseline and full character. Solid magenta background for matting. No text or props.” Mỗi ảnh bổ sung tên góc tương ứng.

Master: `work/mascot-default-feet/*-master.png`. Bản gốc được giữ tại `work/mascot-default-feet/originals/Resources`. Xem bộ hoàn chỉnh tại `docs/assets/mascot-default-angles.png`.

Chạy `python3 scripts/prepare-mascot-default-feet.py` sau các script tạo sprite hoặc thêm miệng, rồi `zsh scripts/build-app.sh`. Script kiểm tra pixel phía trên vùng ghép, cập nhật SHA256 trong manifest và tạo lại ảnh tổng hợp.
