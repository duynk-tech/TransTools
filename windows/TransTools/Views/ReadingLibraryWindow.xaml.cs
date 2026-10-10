using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using TransTools.ViewModels;
using TransTools.Services.Reading;
namespace TransTools.Views;
public partial class ReadingLibraryWindow : Window
{
    public ReadingLibraryViewModel Model { get; }
    public ReadingLibraryWindow(ReadingLibraryViewModel? model = null)
    {
        Model = model ?? new(); InitializeComponent(); DataContext = Model; Closed += (_, _) => Model.Dispose();
    }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
    private void UsePart_Click(object sender, RoutedEventArgs e) { if (Model.CanUsePart) DialogResult = true; }
    private void Source_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: ReadingStory story }) return;
        try { Process.Start(new ProcessStartInfo(story.Page.AbsoluteUri) { UseShellExecute = true }); }
        catch (Exception) { Model.Status = "Chưa mở được trình duyệt để xem nguồn."; }
    }
    private async void Query_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { e.Handled = true; await Model.SearchAsync(); }
    }
}
