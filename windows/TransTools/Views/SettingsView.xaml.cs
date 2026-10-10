using System.Windows.Controls;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class SettingsView : UserControl
{
    private void About_Click(object sender, System.Windows.RoutedEventArgs e) { new AboutWindow { Owner = System.Windows.Window.GetWindow(this) }.ShowDialog(); }
    public SettingsView(SettingsViewModel viewModel, System.Func<bool>? audioBusy = null)
    {
        InitializeComponent();
        DataContext = viewModel;
        var voice = new VoiceSettingsView(new VoiceSettingsViewModel(viewModel, audioBusy));
        voice.ManageModelsRequested += () => SettingsSections.SelectedIndex = 2;
        VoiceSettingsHost.Content = voice;
    }
}
