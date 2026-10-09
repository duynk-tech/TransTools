using System.Windows.Controls;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class TextReaderView : UserControl { public TextReaderView(TextReaderViewModel model) { InitializeComponent(); DataContext = model; }
 private void ShowReadingOptions_Click(object sender, System.Windows.RoutedEventArgs e) => ReadingOptionsPopup.IsOpen = !ReadingOptionsPopup.IsOpen;
}
