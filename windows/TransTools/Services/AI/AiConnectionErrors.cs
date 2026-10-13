using System.Net;
using System.Net.Http;
namespace TransTools.Services.AI;
public static class AiConnectionErrors
{
    public static string Describe(Exception error) => error switch {
        HttpRequestException { StatusCode: HttpStatusCode.Unauthorized } => "Khóa API không hợp lệ hoặc đã hết hiệu lực (401).",
        HttpRequestException { StatusCode: HttpStatusCode.Forbidden } => "Tài khoản chưa được phép dùng dịch vụ hoặc mô hình này (403).",
        HttpRequestException { StatusCode: HttpStatusCode.NotFound } => "Không tìm thấy mô hình hoặc địa chỉ dịch vụ (404).",
        HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests } => "Đã chạm hạn mức hoặc dịch vụ đang giới hạn yêu cầu (429).",
        HttpRequestException { StatusCode: HttpStatusCode.BadRequest } => "Mô hình không chấp nhận yêu cầu này (400). Thử mô hình hỗ trợ trò chuyện.",
        HttpRequestException { StatusCode: null } => "Không kết nối được dịch vụ. Kiểm tra mạng, proxy hoặc tường lửa.",
        OperationCanceledException => "Dịch vụ trả lời quá lâu hoặc yêu cầu đã được hủy.",
        _ => error.GetBaseException().Message
    };
}
