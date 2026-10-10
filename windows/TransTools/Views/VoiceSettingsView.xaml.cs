using System.Windows;
using System.Windows.Controls;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class VoiceSettingsView : UserControl
{
    public event Action? ManageModelsRequested;
    public VoiceSettingsView(VoiceSettingsViewModel model) { InitializeComponent(); DataContext = model; }
    private void Default_Checked(object sender, RoutedEventArgs e) { if (DefaultPanel == null) return; DefaultPanel.Visibility = Visibility.Visible; AdvancedPanel.Visibility = Visibility.Collapsed; }
    private void Advanced_Checked(object sender, RoutedEventArgs e) { if (AdvancedPanel == null) return; DefaultPanel.Visibility = Visibility.Collapsed; AdvancedPanel.Visibility = Visibility.Visible; }
    private void ManageModels_Click(object sender, RoutedEventArgs e) => ManageModelsRequested?.Invoke();
}
