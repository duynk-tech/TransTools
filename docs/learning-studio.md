# Không gian học và Chip Chip

Hai chế độ tại Học ngôn ngữ → Chữ & Viết:

- **Tự học**: chọn chữ/nhóm âm, xem cách đọc, nghe nguồn và luyện viết.
- **Cùng Chip Chip**: bật bảng trắng nổi cạnh mascot thật trên desktop; chỉ số vị trí, mẹo học, nghe mẫu và chuyển chữ dùng chung lựa chọn với bảng chữ.

Chọn Cùng Chip Chip để hiện bảng; Tự học, Kết thúc hoặc rời không gian học sẽ đóng bảng. Bảng theo vị trí mascot và được giới hạn trong vùng màn hình. Mascot tạm dừng đi dạo, có chuyển động nhẹ và phản ứng khi đổi chữ/nghe mẫu; khi kết thúc khôi phục trạng thái hiển thị và đi dạo trước đó. Cửa sổ chính vẫn dùng để chọn chữ và luyện viết.

## Bố cục

- Tiếng Anh: Latin A–Z, phiên âm tham khảo US/UK, dòng kẻ ngang khi viết. Bộ AudioLang chưa được phân loại giọng US/UK; đổi phiên âm không đổi file.
- Tiếng Nhật: tách bộ chọn Hiragana/Katakana khỏi nhóm âm; lưới năm cột, romaji hiển thị đúng nhãn (không giả là IPA). Từ minh họa không được gắn nhãn đã được NHK xác nhận.
- Tiếng Trung: nhóm Pinyin, thanh điệu và từ minh họa; không dùng Chú âm thay cho Pinyin.
- Tiếng Hàn: ký tự phụ âm/nguyên âm Hangeul, ô viết chữ thập; cần ghép âm tiết ở bước học tiếp theo.

## Audio

LanguagePronunciationService chỉ phát bản ghi có sẵn. A–Z dùng catalog AudioLang cá nhân đã kiểm tra SHA256. Âm thiếu mở trang nguồn học, không quay về AVSpeechSynthesizer. Chọn chữ mới hoặc rời bài học sẽ dừng audio. Phát tuần tự dùng callback AVAudioPlayer và token hủy, tránh phát tiếp sau khi người dùng dừng.

Chưa có chấm điểm phát âm, kiểm tra thứ tự nét hoặc lượt nghe duyệt độc lập bởi giáo viên. Đây là bố cục hướng dẫn thực hành, không phải chứng nhận học liệu.

## Kiểm tra

Build Swift release thành công. Chạy kiểm tra với bộ phát production và file thật: âm Nhật thiếu mở nguồn; I phát offline; chuỗi A–B hoàn tất; dừng hủy hàng đợi.

Kiểm tra ảnh giao diện và cài bản mới cần mở khóa máy Mac.
