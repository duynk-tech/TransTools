using System.Windows;
using System.Windows.Controls;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class VoiceSettingsView : UserControl
{
    public event Action? ManageModelsRequested;
    public VoiceSettingsView(VoiceSettingsViewModel model) { InitializeComponent(); DataContext = model; Unloaded += (_, _) => model.StopPreviewCommand.Execute(null); }
    private void Default_Checked(object sender, RoutedEventArgs e) { if (DefaultPanel == null) return; DefaultPanel.Visibility = Visibility.Visible; AdvancedPanel.Visibility = Visibility.Collapsed; }
    private void Advanced_Checked(object sender, RoutedEventArgs e) { if (AdvancedPanel == null) return; DefaultPanel.Visibility = Visibility.Collapsed; AdvancedPanel.Visibility = Visibility.Visible; }
    private void RenameVoice_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not VoiceSettingsViewModel model || !model.CanManagePersonalVoice || model.SelectedPersonalVoice is not { } voice) return;
        var dialog = new RenameRecordWindow(voice.Name, personalVoice: true) { Owner = Window.GetWindow(this) };
        if (dialog.ShowDialog() == true) model.RenamePersonalVoice(dialog.RecordTitle);
    }
    private void DeleteVoice_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not VoiceSettingsViewModel model || !model.CanManagePersonalVoice || model.SelectedPersonalVoice?.Id is not Guid id) return;
        var dialog = ConfirmDeleteWindow.ForPersonalVoice(model.SelectedPersonalVoice.Name); dialog.Owner = Window.GetWindow(this);
        if (dialog.ShowDialog() == true) model.DeletePersonalVoice(id);
    }
    private void RecordVoice_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not VoiceSettingsViewModel model || !model.CanConfigure || !model.SupportsPersonalVoice) return;
        new PersonalVoiceRecorderWindow(model.CreateRecorder()) { Owner = Window.GetWindow(this) }.ShowDialog();
        model.RefreshPersonalVoicesCommand.Execute(null);
    }
    private void RenameRecording_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not VoiceSettingsViewModel model || !model.CanManageRecording || model.SelectedRecording == null) return;
        var dialog = new RenameRecordWindow(model.SelectedRecording.Name, personalVoice: true) { Owner = Window.GetWindow(this) };
        if (dialog.ShowDialog() == true) model.RenameRecording(dialog.RecordTitle);
    }
    private void DeleteRecording_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not VoiceSettingsViewModel model || !model.CanManageRecording || model.SelectedRecording == null) return;
        var id = model.SelectedRecording.Id;
        var dialog = ConfirmDeleteWindow.ForPersonalVoice(model.SelectedRecording.Name); dialog.Owner = Window.GetWindow(this);
        if (dialog.ShowDialog() == true) model.DeleteRecording(id);
    }
    private void RemoveRecordingModel_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not VoiceSettingsViewModel model || !model.CanManageRecording || model.SelectedRecording == null) return;
        var id = model.SelectedRecording.Id;
        var dialog = ConfirmDeleteWindow.ForVoiceModel(model.SelectedRecording.Name); dialog.Owner = Window.GetWindow(this);
        if (dialog.ShowDialog() == true) model.RemoveRecordingModel(id);
    }
    private void ManageModels_Click(object sender, RoutedEventArgs e) => ManageModelsRequested?.Invoke();
}
