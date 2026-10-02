# Viết vào sổ và ngủ — mascot PNG

Imagegen tích hợp chỉnh hai ảnh: writing dùng sổ mint mở, đầu bút vàng chạm trang giấy kem; sleeping nằm nghiêng trên gối ngà, chăn lavender nhẹ, mắt nhắm và nét cười. Master gốc giữ trong `work/mascot-write-sleep`, PNG trước thay đổi giữ tại thư mục `originals` bên trong.

`scripts/prepare-mascot-write-sleep.py` key nền magenta, chuẩn hóa canvas và tạo 64 frame mỗi clip ở 16 fps, vòng 4 giây. Writing giữ sổ và chân ổn định, tay/bút tạo nét ngắn với khoảng nhấc bút cuối vòng; sleeping chỉ thở nhẹ ở vùng ngực/chăn, giữ gối cố định. Đây là chuyển động cục bộ từ một master, không phải rig 3D hay animation lật trang.

App dùng clip writing cả khi làm việc và khi chọn hoạt cảnh Viết; sleeping dùng ảnh/clip mới. Có fallback ảnh tĩnh và hỗ trợ Reduce Motion. Bỏ bút overlay thứ hai khi clip writing chạy; mascot PNG ngủ không còn mặt bàn cũ.

Nguồn PNG: `Resources/MascotActivities/writing.png`, `sleeping.png`; clip và checksum ở `Resources/MascotActivities/animations/manifest.json`. Sleeping dùng canvas ngang 900×650 (clip 450×325) để tư thế nằm không bị nhỏ trong khung mascot. Writing dùng 621×783 (clip 310×391).

Preview: `docs/assets/mascot-write-sleep-preview.gif`. Chạy lại: `python3 scripts/prepare-mascot-write-sleep.py`, sau đó `zsh scripts/build-app.sh`. Các script tái tạo từ master cũ có thể ghi đè PNG, vì vậy chạy script này sau cùng để giữ phiên bản mới.
