# Phụ đề, phiên âm và từ điển

- Menu Phụ đề nổi trên dashboard: bật ở Top/Bottom, hoặc ẩn/hiện vị trí đã lưu. Trong HUD cũng có menu đổi vị trí. Căn giữa màn hình đang chứa HUD, dùng visibleFrame để tránh menu bar và Dock.
- Sổ tay → Sổ từ vựng → Siêu từ điển: Anh–Anh, Anh–Việt, Việt–Anh. Có định nghĩa, từ loại, ví dụ, đồng/trái nghĩa khi nguồn trả về, IPA, phát âm và lưu từ. Việt–Anh dùng bản dịch làm mục từ tiếng Anh để tra tiếp, nên có thể không tìm được một cụm hoặc từ đa nghĩa.
- Nguồn: https://dictionaryapi.dev/ cho định nghĩa/IPA, Google Dịch cho nghĩa dịch. Có Apple Dictionary trên máy làm dự phòng, tùy bộ từ điển đã cài. Không phải bộ từ điển offline song ngữ đầy đủ. Định nghĩa Việt trong Anh–Việt dịch tối đa 8 nghĩa đầu.
- Các từ tiếng Anh đơn đã lưu nhưng thiếu IPA được bổ sung khi mở sổ từ vựng; CSV có cột Phonetic. Nếu dịch vụ không phản hồi, giữ dữ liệu hiện có.

# Nhận diện live

Giữ ring audio 2 giây và phát lại khi đổi recognition request; PCM microphone được sao chép riêng vì buffer của engine có thể bị tái sử dụng. Đối chiếu đuôi phiên trước với đầu phiên mới để bỏ phần lặp. Tách phần đã chốt bằng nội dung thay vì số từ, giữ live row khi partial tạm rút ngắn và tách row mới khi recognizer đổi utterance. Sử dụng thời điểm kết quả nhận diện để chọn lúc đổi phiên, thay cho thời điểm audio buffer luôn chạy kể cả im lặng. Chốt đoạn hiện tại trước khi Stop. Bỏ xử lý error thứ hai nếu cùng callback đã có final.

Validation: release build, codesign và 9 regression checks bằng `zsh scripts/test-speech-text.sh` đã qua. Native UI xác nhận menu Top/Bottom và cửa sổ từ điển. Apple Dictionary tra hello thành công. API từ điển ngoài timeout trên kết nối hiện tại; thông báo tiếng Việt và đường dự phòng đã thêm. Chưa đo WER hoặc độ bỏ sót trên cuộc họp dài, âm thanh nhiễu hay nhiều người nói. Replay 2 giây giảm mất âm thanh tại ranh giới request; không bảo đảm khôi phục mọi lỗi dịch vụ hoặc nhận diện.
