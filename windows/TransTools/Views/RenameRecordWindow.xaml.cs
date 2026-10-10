using System.Windows;
namespace TransTools.Views;
public partial class RenameRecordWindow : Window
{
    public string RecordTitle => TitleInput.Text.Trim();
    public RenameRecordWindow(string title) { InitializeComponent(); TitleInput.Text = title; Loaded += (_, _) => { TitleInput.Focus(); TitleInput.SelectAll(); }; }
    private void Save_Click(object sender, RoutedEventArgs e) { if (string.IsNullOrWhiteSpace(RecordTitle)) { ErrorLabel.Text = "Nhập tên bản ghi trước khi lưu."; return; } DialogResult = true; }
    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();
}
