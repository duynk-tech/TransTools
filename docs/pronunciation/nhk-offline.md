# NHK kana cá nhân offline

104 bản ghi, 910685 byte, tải từ URL HLS được script letters.js và hai trang Hiragana/Katakana NHK công khai tham chiếu. Hai bảng dùng cùng 104 ID audio. Audio AAC được giữ nguyên khi chuyển container M4A, không tạo TTS, cắt âm hoặc đổi tốc độ.

Lưu riêng tại Application Support/TransTools/Pronunciation/NHKJapanese. Không đưa audio/hình cá nhân vào Resources hoặc bản release; chưa xác lập quyền phân phối lại. Thông tin nguồn hiển thị ở Giới thiệu.

Catalog kiểm SHA256, tên file an toàn, nguồn và số lượng. Ghép ký tự theo ID dữ liệu NHK; hai alias dji → ji2, dzu → zu2 đối chiếu hàng Da của trang gốc. Từ ví dụ không được ghép giả từ bản ghi ký tự và không có fallback giọng hệ thống. UI hiện có 82 mục kana, không khẳng định đã trình bày đủ 104 mục nguồn.

Hình thứ tự nét tải theo đúng URL figure của trang, 104 Hiragana và 104 Katakana. Đã sửa đường dẫn Katakana từ kata sang kana theo HTML thật.

Kiểm giải mã từng audio và chuẩn bị AVAudioPlayer không thay thế nghe duyệt phát âm bởi người có chuyên môn.
