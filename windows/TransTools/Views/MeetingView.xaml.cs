using System.Windows.Controls;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class MeetingView : UserControl
{
    public MeetingView(MeetingViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
    }
}
