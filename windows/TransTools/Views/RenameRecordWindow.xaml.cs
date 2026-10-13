using System.Windows;
namespace TransTools.Views;
public partial class RenameRecordWindow : Window
{
    public string RecordTitle => TitleInput.Text.Trim();
    public RenameRecordWindow(string title, bool personalVoice = false) { InitializeComponent(); if (personalVoice) { Title = Heading.Text = "Đổi tên giọng"; TitleInput.MaxLength = 100; } TitleInput.Text = title; Loaded += (_, _) => { TitleInput.Focus(); TitleInput.SelectAll(); }; }
    private void Save_Click(object sender, RoutedEventArgs e) { if (string.IsNullOrWhiteSpace(RecordTitle)) { ErrorLabel.Text = "Nhập tên trước khi lưu."; return; } DialogResult = true; }
    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();
}
