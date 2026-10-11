using System.Windows;
using System.Windows.Controls;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class PersonalVoiceLibraryView : UserControl
{
    public PersonalVoiceLibraryView(VoiceSettingsViewModel model) { InitializeComponent(); DataContext = model; Unloaded += (_, _) => model.StopPreviewCommand.Execute(null); }
    private void RecordVoice_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not VoiceSettingsViewModel model || !model.CanConfigure) return;
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
}
