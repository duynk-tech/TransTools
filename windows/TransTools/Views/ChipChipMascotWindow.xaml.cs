using System.Windows;
using System.Windows.Input;

namespace TransTools.Views;

public partial class ChipChipMascotWindow : Window
{
    public ChipChipMascotWindow()
    {
        InitializeComponent();
        Left = SystemParameters.PrimaryScreenWidth - Width - 30;
        Top = SystemParameters.PrimaryScreenHeight - Height - 120;
    }

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }
}
