using System.Windows;
namespace TransTools.Views;
public partial class ConfirmDeleteWindow : Window
{
    public ConfirmDeleteWindow(string title) { InitializeComponent(); RecordName.Text = title; }
    private void Confirm_Click(object sender, RoutedEventArgs e) => DialogResult = true;
    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();
}
