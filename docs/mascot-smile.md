# Nét cười mascot PNG

Dùng công cụ imagegen tích hợp để tạo nét cười từ `Resources/Mascot3D.png`. Prompt: “Add ONLY a tiny elegant closed curved smile centered below its eyes, muted soft plum-gray, rounded thin ends, subtle inset shading matching ceramic face. Keep identical character, eyes, headphones, silhouette, pose, lighting, proportions and composition. Preserve true transparent background.”

Ảnh AI đầy đủ có đốm nền, nên không được dùng để thay toàn bộ mascot. `scripts/prepare-mascot-smile.py` lấy riêng nét miệng, ghép lên 10 PNG đã duyệt và kiểm tra alpha cùng mọi pixel ngoài nét miệng không thay đổi. Python xử lý theo quyền người dùng đã cho phép. Original được giữ tại `work/mascot-mouth/originals`, master AI tại `work/mascot-mouth/generated-smile.png`.

Preview: `docs/assets/mascot-smile-preview.png`. Đã sửa ảnh chính, body, writing cũ, góc front/front_left/front_right và activity coffee/writing/thinking/flowers. Giữ nguyên góc sau, profile, chu kỳ đi bộ, ngủ và strolling (đã có nét miệng); chưa có lip-sync hoặc biểu cảm động theo âm thanh.

Chạy lại: `python3 scripts/prepare-mascot-smile.py`, sau đó `zsh scripts/build-app.sh`. Không chạy lại các script tái tạo sprite/activity khác mà không ghép lại nét miệng vì chúng tạo từ master cũ.
