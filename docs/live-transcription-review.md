# Stream transcription review

Các nguyên nhân trong code được xác định:
- Dấu kết câu từ partial hypothesis chốt caption trước khi Apple Speech sửa lại câu.
- Tự cắt tại 22 từ và fallback 18 từ khi không có dấu ngắt.
- Final ngắn hơn có thể ghi đè các từ đã nhận.
- Đổi request khi timeout/rotation chốt và thay ID đoạn đang nói.
- Khử overlap một từ có thể xóa từ lặp hợp lệ.

Bản sửa: không chốt theo dấu kết câu partial; đoạn dài chỉ cắt ở dấu phẩy/chấm phẩy/hai chấm, từ 36 từ; giữ hypothesis dài khi bản ngắn là tiền tố; giữ ID và nội dung đang nói qua rotation; khử overlap từ hai từ trở lên.

11 kiểm tra hồi quy SpeechTextReconciler đã qua. Chưa đối chiếu audio gốc hoặc đo mất từ end-to-end. Replay 2 giây và khử overlap vẫn có thể trùng nội dung khi Apple sửa hypothesis; nhận diện tên riêng phụ thuộc engine. Không khẳng định độ chính xác 100%.
