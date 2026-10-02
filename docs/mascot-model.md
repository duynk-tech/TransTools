# Trạng thái hiện tại

Model Blender/USDZ được giữ làm nguồn thử nghiệm. App đã bỏ tùy chọn Model 3D, menu/cửa sổ review và đường chạy model-preview theo yêu cầu người dùng; mascot hiện dùng PNG hoặc Pixel. Phần hướng dẫn dưới đây ghi lại pipeline và lịch sử thử nghiệm, không mô tả UI hiện tại.

# Model 3D theo PNG — bản đứng để review

Model được dựng trong Blender 4.5.0 từ `Resources/Mascot3D.png`: đầu oval có bề mặt tùy chỉnh, panel mặt và viền mảnh, mắt teal–violet dùng chi tiết PNG, tai nghe có quai mesh liền và viền mint, thân nhỏ, tay nâng phía trước, chân ngắn. Material ceramic pearl có roughness/coat; scene chứa camera orthographic và bốn softbox để render so sánh.

- Source chỉnh sửa: `work/mascot-model/TransToolsMascot.blend`, texture và PNG chuẩn đã pack vào file.
- Model app: `Resources/MascotModel/TransToolsMascot.usdz`, texture mắt được đóng gói; manifest có checksum.
- Render: `renders/mascot-model/front.png`, `front_right.png`, `right.png`, `back.png`.
- So sánh: `renders/mascot-model/comparison.png`, cùng chiều cao hình hữu ích để đối chiếu tỷ lệ.
- App: menu Window → Xem model 3D theo PNG. Cửa sổ tải USDZ thật bằng RealityKit, có thanh xoay và nền sáng/tối; USDZ xuất Y-up để đồng bộ hệ trục. Mascot chính mặc định dùng USDZ mới. Cài đặt có Model 3D, Mascot ảnh và Pixel; lần chạy đầu sau cập nhật chuyển sang Model 3D, các lần sau giữ lựa chọn người dùng. Hướng nhìn của mascot điều khiển góc quay USDZ; chưa có animation rig cho động tác chân/tay.

Tạo lại bằng:

```sh
work/tools/Blender.app/Contents/MacOS/Blender --background --python scripts/build-mascot-model.py
python3 scripts/prepare-mascot-model-preview.py
zsh scripts/build-app.sh
```

Blender portable ở `work/tools/Blender.app`, tải từ `https://download.blender.org/release/Blender4.5/`; checksum DMG đã đối chiếu với file SHA256 chính thức. Không cài vào /Applications. Các file nguồn/tool tạm nằm trong work và bị Git ignore theo cấu hình dự án.

Phạm vi: đây là bản model đứng để review hình dáng và material, chưa có skeleton/skin rig, chưa có animation cầm cốc/sổ/ngủ. Empty đặt tên HeadPivot/Shoulder/Hip chỉ là mốc dựng rig, không được coi là rig hoàn chỉnh. Mắt sử dụng chi tiết ảnh có ánh sáng đã bake; chúng chưa phải iris vật lý hoàn toàn. USD xuất texture iris ở diffuse để tăng tương thích; cửa sổ review RealityKit dùng UnlitMaterial riêng cho mắt để giữ màu của PNG. Render Blender và RealityKit có thể khác nhau về tone/ánh sáng. Cần duyệt tạo hình trước khi làm rig và các hoạt động.

Tinh chỉnh tạo hình: đỉnh đầu nâng nhẹ 0.045 đơn vị và thu góc trên để bo tròn; thân nâng sát đầu, cổ giảm chiều cao từ 0.16 xuống 0.09; tay nhỏ hơn, palm/wrist/thumb nối bằng voxel remesh và làm mịn subdivision để bỏ các khối cầu rời. Bản trước tinh chỉnh được giữ trong `work/mascot-model/before-hand-refinement`.

Biểu cảm: bổ sung nét cười cong nhỏ màu plum dịu dưới mắt. Đường cong bám độ sâu panel mặt, đầu nét bo tròn; xuất thành mesh trong USDZ.
