# Rà soát giao diện TransTools

Ngày: 03/10/2026. Phạm vi: giao diện macOS, không thay đổi dữ liệu học tập.

## Các chỉnh sửa

| Khu vực | Điều chỉnh | Kiểm tra |
|---|---|---|
| Điều hướng chính | Tab có thể cuộn ngang khi thiếu chiều rộng; tăng vùng bấm của các nút tiện ích; bổ sung trạng thái selected cho accessibility | Mã nguồn, giao diện cửa sổ rộng |
| Cuộc họp | Nền mint toàn vùng được cắt theo góc bo; nhãn Translate Tiếng Việt | Mã nguồn và trạng thái giao diện |
| Dịch nhanh | Hàng chọn ngôn ngữ cao 40 pt; nút sửa ngữ pháp gọn, bỏ mũi tên trùng | Đã xem trực tiếp bản build |
| Sổ tay | Tách tiêu đề khỏi hàng thao tác; hàng nút cuộn ngang thay vì ép chữ xuống dòng; thống nhất chiều cao nút | Đã xem trực tiếp bố cục; chiều cao hoàn thiện đã build |
| Trò chuyện | Tách tiêu đề và điều khiển thành hai hàng; nút 40 pt; nội dung trạng thái trống phù hợp khi tắt gợi ý | Đã xem trực tiếp bố cục; nội dung hoàn thiện đã build |
| Cài đặt | Nút thao tác tối thiểu 40 pt; trạng thái sidebar rõ; mô tả dịch ngoại tuyến chính xác hơn | Mã nguồn, các trang đã mở trong đợt rà soát |
| Từ điển | Dùng kiểu nút thao tác chung để đồng bộ khoảng đệm | Mã nguồn |
| Học ngôn ngữ | Tab có trạng thái selected; chưa có từ thì mời bắt đầu thay vì báo đã ôn đủ | Đã xem Hôm nay, Chữ & Viết tiếng Anh, Từ vựng, Luyện giao tiếp, Trò chuyện và Tiến bộ |

## Quy tắc bố cục

- Nút thao tác thường tối thiểu 40 pt, nhãn ngắn và đủ khoảng đệm.
- Tiêu đề và thao tác tách hàng khi cạnh tranh chiều rộng.
- Dùng mint cho hành động và trạng thái chính, giữ nền nội dung nhẹ.
- Toggle cài đặt nằm ở mép phải của hàng; nhãn có vùng giãn riêng.
- Điều khiển dài được cuộn ngang khi cần, tránh ép nhãn thành nhiều dòng.

## Xác minh và giới hạn

Build macOS thành công; git diff --check đạt; đã chép bản mới vào /Applications/TransTools.app và xác minh chữ ký.

Máy bị khóa ở lần kiểm tra cuối nên chưa khởi động lại và xem trực tiếp các thay đổi hoàn thiện cuối cùng. Cần mở lại ứng dụng để dùng bản mới. Chưa xác minh toàn bộ trạng thái cửa sổ hẹp, dark mode, lỗi mạng, bộ dữ liệu có nhiều flashcard và toàn bộ bố cục Nhật/Trung/Hàn trong đợt này. Rà soát giao diện không chứng nhận độ chính xác học liệu hoặc chất lượng phát âm.
