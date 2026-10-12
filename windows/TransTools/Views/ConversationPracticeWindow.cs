using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using TransTools.ViewModels;
namespace TransTools.Views;
public sealed class ConversationPracticeWindow : Window
{
    public ConversationPracticeWindow(ConversationViewModel conversation)
    {
        Title = "Luyện hội thoại"; Width = 900; Height = 720; MinWidth = 800; MinHeight = 650;
        WindowStartupLocation = WindowStartupLocation.CenterOwner; ShowInTaskbar = false;
        var background = new Grid(); Content = background;
        background.Children.Add(new GardenBackground());
        var root = new DockPanel { Margin = new Thickness(20) }; background.Children.Add(root);
        var heading = new DockPanel { Margin = new Thickness(0, 0, 0, 16) };
        var close = new Button { Content = "Đóng", Style = (Style)FindResource("SecondaryButton"), HorizontalAlignment = HorizontalAlignment.Right };
        close.Click += (_, _) => Close(); DockPanel.SetDock(close, Dock.Right); heading.Children.Add(close);
        heading.Children.Add(new TextBlock { Text = "Luyện hội thoại", FontSize = 20, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
        DockPanel.SetDock(heading, Dock.Top); root.Children.Add(heading);
        root.Children.Add(new ConversationView(conversation));
        Closed += (_, _) => conversation.EndConversationCommand.Execute(null);
    }
}
