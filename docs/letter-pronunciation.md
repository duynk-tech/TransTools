# Luyện đọc trong Chữ & Viết

- Chọn chữ ở bảng bên trái, sau đó chọn Chữ, Từ/Âm tiết hoặc Trong câu.
- Nghe mẫu, bật Nghe chậm nếu cần, dừng rồi tự đọc lại.
- Tiếng Anh đọc tên chữ trong cụm “The letter …”, không xem tên chữ là âm vị trong từ. X dùng ví dụ box.
- Tiếng Hàn đọc tên phụ âm bằng Hangul; bước 2 dùng khối âm tiết. Tiếng Trung dùng chữ Hán và từ chứa chữ, không gọi đó là bảng chữ cái.
- Dùng synthesizer macOS riêng với tốc độ từng lượt; không lưu hoặc thay đổi tốc độ TTS toàn app. Đổi chữ/ngôn ngữ hoặc rời màn hình sẽ dừng bài mẫu.
- Mẫu tổng hợp không phải bản ghi giáo viên và chưa có chấm điểm phát âm, ghi âm hay nhận diện khẩu hình.
- Nguồn tham khảo tiếng Anh: [IPA](https://www.internationalphoneticassociation.org/IPAcharts/IPA_charts_TI/IPA_charts_TI.html), [Sounds of Speech — University of Iowa](https://soundsofspeech.uiowa.edu/). Chỉ liên kết tới nguồn; không sao chép video. Nội dung tiếng Anh của Sounds of Speech có thể cần app riêng.

## Đối chiếu hướng dẫn tiếng Anh — 2026-10-03
Đã đọc [trang Audiolang người dùng gửi](http://audiolang.info/vi/english-alphabet/) qua trình duyệt. Trang có 26 chữ và audio riêng, nhưng cách ghi gần âm bằng tiếng Việt không dùng làm dữ liệu chuẩn. Không sao chép hay đóng gói audio từ trang vì chưa có thông tin cấp phép phân phối lại.

Tham chiếu bổ sung: [Cambridge pronunciation](https://dictionary.cambridge.org/us/pronunciation/), [A–Z UK/US](https://dictionary.cambridge.org/pronunciation/english/a-z), [British Council Sounds Right](https://learnenglish.britishcouncil.org/apps/learnenglish-sounds-right), [hướng dẫn luyện phát âm](https://learnenglish.britishcouncil.org/comment/192336).

Đã bổ sung IPA tên 26 chữ thay cho chữ thường ở bảng; chọn UK/US trong bài nghe (bảng ô chữ mặc định hiển thị IPA US). O/R/Z có biến thể UK; âm trong từ được giải thích riêng. Dùng IPA trên utterance tên chữ, giọng khớp locale; không dùng câu “The letter …” làm audio tên chữ. Cách luyện và nguồn nằm trong phần mở rộng để giữ gọn vùng viết. Audio vẫn tổng hợp; không chứng nhận tương đương bản ghi người bản ngữ.

Kiểm tra chữ I: dữ liệu /aɪ/ và eye đúng theo Cambridge. Chuyển audio tên I sang đọc trực tiếp từ eye, tránh phụ thuộc IPA override của từng giọng macOS. Đồng thời lọc giọng hiệu ứng và chọn giọng ổn định. Chưa xác nhận chất lượng nghe bằng đánh giá người nghe.

Kiểm tra phản ánh B nghe như bi–i: chưa thể nghe trực tiếp audio trong phiên công cụ. B chuyển sang từ bee không IPA override, giữ IPA /biː/ để hiển thị; cần người nghe xác nhận. Không kết luận audio cũ sai chỉ từ mã nguồn.

## Bộ dữ liệu offline
Đã tích hợp 30 mẫu IPA tham khảo do Ruben Schachtenhaufen công bố theo CC0 tại https://github.com/NewDanishPhonetics/IPA-sound-files, cố định commit 81c8086257d84f5e434790603bb39b901df8143c. Khoảng 1.01 MB, chuyển mono PCM16 22.05kHz. Manifest lưu URL, SHA256 nguồn và file chuyển đổi, thời lượng, tác giả và giấy phép. Đã kiểm tra đủ 30 WAV, checksum và frame âm thanh. Có mục mở rộng Bản ghi âm IPA offline trong Chữ & Viết, phát AVAudioPlayer từ bundle, không cần key/mạng.
Đây là âm IPA chung, chưa được thẩm định như bộ luyện tên chữ/giọng Anh–Anh hoặc Anh–Mỹ. Không ghép i và b thành tên B, không thay các âm đôi bằng chuỗi file rời. Bộ tên 26 chữ có bản ghi người thật vẫn chưa hoàn thành. Không thể xác nhận chất lượng âm bằng nghe trực tiếp trong phiên công cụ.
Nguồn toàn bảng chữ cái trên Commons CC BY-SA đã tìm thấy nhưng tải bị HTTP403; chưa tích hợp hay đóng gói file đó.

## Bộ bản ghi nguồn 03/10/2026

Đã thêm phần Chú âm offline riêng (37 WAV gốc của Bộ Giáo dục Đài Loan, CC BY 4.0) trong Chữ & Viết tiếng Trung. Không gán vào 12 chữ Hán; không thay giọng đọc bài học bằng TTS. Bộ 46 Kana và bản ghi toàn bảng chữ cái Anh được tải vào thư mục source-review, chưa bật trong app. Xem [tình trạng và điều kiện duyệt](pronunciation/verified-recordings-plan.md).

Kiểm tra: build macOS thành công, codesign hợp lệ, kiểm tra mapping nguồn/checksum/PCM 37 WAV, giải mã 46 MP3 và OGG tiếng Anh. Không xác nhận đã nghe duyệt hoặc độ chuẩn 100%. App đang có phiên phụ đề nên chưa thay bản đang chạy.
