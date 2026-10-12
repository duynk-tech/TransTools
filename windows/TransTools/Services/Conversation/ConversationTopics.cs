namespace TransTools.Services.Conversation;
public static class ConversationTopics
{
    public static string Normalize(string topic) => topic switch {
        "Phỏng vấn xin việc (Job Interview)" => "Phỏng vấn",
        "Du lịch & Nhận phòng khách sạn" => "Du lịch & Khám phá",
        "Công nghệ & Lập trình viên" => "Công nghệ & Lập trình",
        "Giao tiếp xã giao hàng ngày" => "Giao tiếp hằng ngày",
        _ => topic
    };
    public static string Instructions(string topic) => Normalize(topic) switch {
        "Giao tiếp hằng ngày" => "Daily life: hobbies, food, family and everyday plans. Be a friendly conversation partner.",
        "Công việc & Cuộc họp" => "Workplace conversation. Be a colleague discussing progress, meetings and clarifying tasks.",
        "Du lịch & Khám phá" => "Travel role-play: asking directions, ordering food, hotels and local culture.",
        "Phỏng vấn" => "Be a job interviewer. Ask one question at a time about experience and career goals.",
        "Công nghệ & Lập trình" => "Be a developer colleague discussing software, debugging and explaining technical decisions.",
        "Học tập" => "Discuss learning, school and study plans as a supportive study partner.",
        "Chủ đề riêng" => "Follow the learner's custom conversation scenario.",
        _ => topic
    };
}
