using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class TextReaderView : UserControl
{
    public TextReaderView(TextReaderViewModel model) { InitializeComponent(); DataContext = model; }
    private void ShowReadingOptions_Click(object sender, RoutedEventArgs e) => ReadingOptionsPopup.IsOpen = !ReadingOptionsPopup.IsOpen;
    private void ShowLibrary_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not TextReaderViewModel { CanConfigureReader: true } model) return;
        var library = new ReadingLibraryWindow { Owner = Window.GetWindow(this) };
        if (library.ShowDialog() == true && library.Model.SelectedStory is { } story && library.Model.SelectedPart is { } part) model.UseStory(story, part.Text);
    }
    private void ShowSource_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not TextReaderViewModel { Story: { } story } model) return;
        try { Process.Start(new ProcessStartInfo(story.Page.AbsoluteUri) { UseShellExecute = true }); }
        catch (Exception) { model.Status = "Chưa mở được trình duyệt để xem nguồn."; }
    }
}
