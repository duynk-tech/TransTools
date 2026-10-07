using System.Windows.Controls;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class TextReaderView : UserControl { public TextReaderView(TextReaderViewModel model) { InitializeComponent(); DataContext = model; } }
