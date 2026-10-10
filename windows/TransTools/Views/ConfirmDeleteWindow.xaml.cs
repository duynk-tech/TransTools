using System.Windows;
namespace TransTools.Views;
public partial class ConfirmDeleteWindow : Window
{
    public ConfirmDeleteWindow(string title, bool all = false, bool currentMeeting = false) { InitializeComponent(); RecordName.Text = title; if (all) { Title = "Xóa tất cả bản ghi"; Question.Text = "Xóa tất cả bản ghi đã lưu?"; Detail.Text = "Thao tác áp dụng cho toàn bộ cuộc họp và trò chuyện, kể cả các mục bị ẩn bởi bộ lọc. Từ vựng và mô hình được giữ nguyên."; ConfirmButton.Content = "Xóa tất cả"; } if (currentMeeting) { Title = "Xóa nội dung cuộc họp"; Question.Text = "Xóa nội dung đang hiển thị?"; Detail.Text = "Nếu đang thu âm, cuộc họp sẽ được dừng và lưu trước khi dọn màn hình. Các bản ghi đã lưu trong Sổ tay được giữ nguyên."; ConfirmButton.Content = "Xóa nội dung"; } }
    private void Confirm_Click(object sender, RoutedEventArgs e) => DialogResult = true;
    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();
}
