using System.Windows.Controls;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class SettingsView : UserControl
{
    public void ShowVoiceSettings(string language)
    {
        SettingsSections.SelectedIndex = 4;
        if (VoiceSettingsHost.Content is VoiceSettingsView voice && voice.DataContext is VoiceSettingsViewModel model && model.CanConfigure) model.Language = language;
    }
    private void About_Click(object sender, System.Windows.RoutedEventArgs e) { new AboutWindow(() => { SettingsSections.SelectedItem = SystemSection; if (DataContext is SettingsViewModel model) model.CheckUpdateCommand.Execute(null); }) { Owner = System.Windows.Window.GetWindow(this) }.ShowDialog(); }
    public SettingsView(SettingsViewModel viewModel, System.Func<bool>? audioBusy = null)
    {
        InitializeComponent();
        DataContext = viewModel;
        var voiceModel = new VoiceSettingsViewModel(viewModel, audioBusy);
        var voice = new VoiceSettingsView(voiceModel);
        PersonalVoiceHost.Content = new PersonalVoiceLibraryView(voiceModel);
        voice.PersonalVoiceLibraryRequested += () => SettingsSections.SelectedItem = PersonalVoiceSection;
        voice.ManageModelsRequested += () => SettingsSections.SelectedIndex = 2;
        VoiceSettingsHost.Content = voice;
    }
}
