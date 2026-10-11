using System.Windows;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class PersonalVoiceRecorderWindow : Window
{
    public PersonalVoiceRecorderWindow(PersonalVoiceRecorderViewModel model)
    {
        InitializeComponent(); DataContext = model; Closed += (_, _) => model.Dispose();
    }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
