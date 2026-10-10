using System.Diagnostics;
using TransTools.ViewModels;
using TransTools.Models;
using TransTools.Views;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

internal static class Program
{
    [STAThread] private static int Main(string[] args)
    {
        var output = Path.GetFullPath(args.FirstOrDefault() ?? "windows/test-results/ui");
        Directory.CreateDirectory(output);
        var errors = new BindingErrors();
        PresentationTraceSources.DataBindingSource.Listeners.Add(errors);
        PresentationTraceSources.DataBindingSource.Switch.Level = SourceLevels.Error;
        try {
            if (CaptionDisplayTextConverter.Select("source", "translated", "translation", false) != "translated" || CaptionDisplayTextConverter.Select("source", "", "translation", false) != "source" || CaptionDisplayTextConverter.Select("source", "translated", "original", true) != "") throw new Exception("Caption display fallback is incorrect");
            CheckMeetingSpeechQueue();
            var app = new TransTools.App(); app.InitializeComponent();
            var connected = true;
            using (var deviceFixture = new MeetingViewModel(() => connected ? [new("fixture-device", "USB tai nghe")] : [])) {
                deviceFixture.RefreshPlaybackDevices(); deviceFixture.SelectedPlaybackDevice = deviceFixture.PlaybackDevices[0]; deviceFixture.AutomaticReading = true;
                deviceFixture.RefreshPlaybackDevices();
                if (!deviceFixture.AutomaticReading || deviceFixture.SelectedPlaybackDevice?.Id != "fixture-device") throw new Exception("Refreshing a connected device disabled automatic reading");
                connected = false; deviceFixture.RefreshPlaybackDevices();
                if (deviceFixture.AutomaticReading || deviceFixture.SelectedPlaybackDevice != null) throw new Exception("Disconnected earphone remained enabled");
            }
            var window = new TransTools.MainWindow(); app.MainWindow = window; window.Show();
            System.Threading.SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(app.Dispatcher));
            var background = (Button)window.FindName("BackgroundButton");
            foreach (var mode in new[] { "morning", "noon", "afternoon", "night", "mint" }) {
                var item = background.ContextMenu.Items.OfType<MenuItem>().First(value => Equals(value.Tag, mode));
                item.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
                if (!item.IsChecked) throw new Exception("Background selection did not update: " + mode);
                Capture(window, output, "background-" + mode + ".png");
            }
            background.ContextMenu.Items.OfType<MenuItem>().First(value => Equals(value.Tag, "noon")).RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
            foreach (var (width, height) in new[] { (1280, 820), (1200, 740), (1440, 900) }) {
                SetViewportSize(window, width, height);
                foreach (var route in new[] { "Cuộc họp", "Sổ tay", "Dịch nhanh", "Đọc văn bản", "Học ngôn ngữ", "Trò chuyện", "Cài đặt" }) {
                    var button = Descendants(window).OfType<RadioButton>().First(b => Equals(b.Content, route));
                    button.IsChecked = true; Pump(); window.UpdateLayout();
                    if (width == 1280) Capture(window, output, $"{width}-idle-{route}.png");
                    var quickView = Descendants(window).OfType<QuickTranslateView>().FirstOrDefault();
                    if (quickView != null) {
                        var quickModel = (QuickTranslateViewModel)quickView.DataContext;
                        var originalDomain = quickModel.SelectedDomain; var originalText = quickModel.SourceText;
                        quickModel.SelectedDomain = "Công nghệ thông tin";
                        if (quickModel.QuickPhrases.Length != 5) throw new Exception("Mac developer phrases missing");
                        quickModel.SelectQuickPhrase(quickModel.QuickPhrases[0]);
                        if (quickModel.SourceText != "Nhờ bạn review PR này giúp mình nhé") throw new Exception("Phrase selection lost text");
                        quickModel.IsTranslating = true; quickModel.SelectQuickPhrase(quickModel.QuickPhrases[1]);
                        if (quickModel.SourceText != "Nhờ bạn review PR này giúp mình nhé") throw new Exception("Busy phrase selection replaced request");
                        quickModel.IsTranslating = false; quickModel.ShowContext = true; Pump(); window.UpdateLayout();
                        ValidateControlLayout(window, "Quick context expanded");
                        Capture(window, output, $"{width}-quick-context.png");
                        quickModel.ShowContext = false; quickModel.SelectedDomain = originalDomain; quickModel.SourceText = originalText; Pump();
                    }
                    var reader = Descendants(window).OfType<TextReaderView>().FirstOrDefault();
                    if (reader != null) {
                        var options = (Button)reader.FindName("ReadingOptionsButton");
                        var popup = (System.Windows.Controls.Primitives.Popup)reader.FindName("ReadingOptionsPopup");
                        if (popup.IsOpen) throw new InvalidOperationException("Reading options must be collapsed initially");
                        options.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                        if (!popup.IsOpen || popup.Child == null) throw new InvalidOperationException("Reading options did not open");
                        var readingModel = (TextReaderViewModel)reader.DataContext;
                        var sentenceSlider = (Slider)reader.FindName("SentencePauseSlider");
                        var paragraphSlider = (Slider)reader.FindName("ParagraphPauseSlider");
                        if (sentenceSlider.Maximum != 2 || paragraphSlider.Maximum != 4) throw new Exception("Reader pause ranges differ from macOS");
                        var oldText = readingModel.Text;
                        readingModel.Text = string.Concat(Enumerable.Repeat("a\u0301", 5000)); Pump();
                        if (readingModel.CharacterCount != 5000 || !readingModel.CanRead) throw new Exception("Reader 5000-character limit incorrectly counts combining marks");
                        readingModel.Text += "x"; Pump();
                        if (!readingModel.IsTooLong || readingModel.CanRead || readingModel.CanExport || readingModel.Text.Length != 10001) throw new Exception("Oversized reader text was silently truncated or remained playable");
                        readingModel.Text = oldText; Pump();
                        var oldSentence = readingModel.SentencePause; var oldParagraph = readingModel.ParagraphPause;
                        sentenceSlider.Value = .7; paragraphSlider.Value = 1.6; Pump();
                        if (readingModel.SentencePause != .7 || readingModel.ParagraphPause != 1.6) throw new Exception("Reader pause controls did not reach their playback model");
                        readingModel.IsBusy = true; Pump();
                        if (sentenceSlider.IsEnabled || paragraphSlider.IsEnabled) throw new Exception("Reader pause controls changed during an active reading");
                        readingModel.IsBusy = false; readingModel.SentencePause = oldSentence; readingModel.ParagraphPause = oldParagraph; Pump();
                        ValidateControlLayout((FrameworkElement)popup.Child, "Reading options");
                        CaptureElement((FrameworkElement)popup.Child, output, $"{width}-reader-options-popup.png");
                        Capture(window, output, $"{width}-reader-options.png");
                        popup.IsOpen = false;
                    }
                    var meeting = Descendants(window).OfType<MeetingView>().FirstOrDefault()?.DataContext as MeetingViewModel;
                    if (meeting != null && meeting.Captions.Count == 0) {
                        for (var n = 0; n < 12; n++) meeting.Captions.Add(new Caption { Start = n * 8, End = n * 8 + 7, Original = "We should preserve the full conversation, including longer sentences and the context needed to understand the discussion.", Vietnamese = "Cần giữ đầy đủ cuộc hội thoại, bao gồm những câu dài và ngữ cảnh để hiểu đúng nội dung đang thảo luận." });
                    }
                    if (meeting != null) {
                        var meetingView = Descendants(window).OfType<MeetingView>().First();
                        var snapshot = meeting.Captions.Select(c => (c.Id, c.Original, c.Vietnamese)).ToArray();
                        foreach (var mode in meeting.DisplayModes) {
                            meeting.SelectedDisplayMode = mode; Pump();
                            ValidateControlLayout(meetingView, "Meeting display " + mode);
                            var visibleText = Descendants(meetingView).OfType<TextBlock>().Where(t => t.IsVisible).Select(t => t.Text).ToArray();
                            var hasOriginal = visibleText.Contains(snapshot[0].Original);
                            var hasTranslation = visibleText.Contains(snapshot[0].Vietnamese);
                            if (hasOriginal != (mode != "Bản dịch") || hasTranslation != (mode != "Tiếng gốc")) throw new Exception("Meeting display mode did not update existing captions: " + mode);
                            if (!snapshot.SequenceEqual(meeting.Captions.Select(c => (c.Id, c.Original, c.Vietnamese)))) throw new Exception("Display mode modified stored captions");
                            if (width == 1280) Capture(window, output, "meeting-display-" + meeting.DisplayModeKey + ".png");
                        }
                        meeting.SelectedDisplayMode = "Song ngữ"; Pump();
                        var settings = (Button)meetingView.FindName("TranslationSettingsButton");
                        settings.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                        var translationPopup = (System.Windows.Controls.Primitives.Popup)meetingView.FindName("TranslationSettingsPopup");
                        if (!translationPopup.IsOpen) throw new Exception("Meeting translation settings did not open");
                        ValidateControlLayout((FrameworkElement)translationPopup.Child, "Meeting translation settings");
                        if (width == 1280) CaptureElement((FrameworkElement)translationPopup.Child, output, "meeting-translation-settings.png");
                        translationPopup.IsOpen = false;
                        var earphones = (Button)meetingView.FindName("EarphoneButton"); earphones.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                        var earphonePopup = (System.Windows.Controls.Primitives.Popup)meetingView.FindName("EarphonePopup");
                        if (!earphonePopup.IsOpen) throw new Exception("Earphone popup did not open");
                        ValidateControlLayout((FrameworkElement)earphonePopup.Child, "Meeting earphones");
                        if (width == 1280) CaptureElement((FrameworkElement)earphonePopup.Child, output, "meeting-earphones.png");
                        meeting.StopEarphoneReadingCommand.Execute(null); if (meeting.AutomaticReading) throw new Exception("Earphone stop did not disable auto reading");
                        earphonePopup.IsOpen = false;
                    }
                    var conversation = Descendants(window).OfType<ConversationView>().FirstOrDefault()?.DataContext as ConversationViewModel;
                    if (conversation != null && conversation.Messages.Count == 0) {
                        for (var n = 0; n < 8; n++) conversation.Messages.Add(new ChatMessageItem { IsUser = n % 2 == 0, Text = "Let us practice a longer conversation about your work and the next project. What would you like to discuss today?", Translation = n % 2 == 0 ? "" : "Cùng luyện một cuộc trò chuyện dài về công việc và dự án sắp tới. Hôm nay bạn muốn thảo luận điều gì?" });
                    }
                    if (conversation != null) {
                        var chatView = Descendants(window).OfType<ConversationView>().First();
                        var topicButton = (Button)chatView.FindName("TopicButton"); topicButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                        var topicPopup = (System.Windows.Controls.Primitives.Popup)chatView.FindName("TopicPopup");
                        if (!topicPopup.IsOpen || topicPopup.Child == null) throw new Exception("Conversation name/options popup did not open");
                        ValidateControlLayout((FrameworkElement)topicPopup.Child, "Conversation name and options");
                        CaptureElement((FrameworkElement)topicPopup.Child, output, $"{width}-conversation-options.png");
                        var wasActive = conversation.IsConversationActive;
                        conversation.IsConversationActive = true; Pump();
                        if (((TextBox)chatView.FindName("LearnerNameInput")).IsEnabled) throw new Exception("Learner name can change during active conversation");
                        conversation.IsConversationActive = wasActive; topicPopup.IsOpen = false; Pump();
                        var delay = (TextBox)chatView.FindName("SendDelayInput");
                        var oldDelay = conversation.SendDelaySeconds;
                        delay.Text = "30"; delay.GetBindingExpression(TextBox.TextProperty)!.UpdateSource(); Pump();
                        if (conversation.SendDelaySeconds != 30) throw new Exception("Conversation numeric delay did not accept 30 seconds");
                        delay.UpdateLayout();
                        var numberHost = Descendants(delay).OfType<ScrollViewer>().First();
                        if (numberHost.ViewportWidth < 24 || numberHost.ViewportHeight < 20) throw new Exception("Conversation numeric input padding clips its value");
                        conversation.IncreaseSendDelayCommand.Execute(null); if (conversation.SendDelaySeconds != 30) throw new Exception("Conversation stepper exceeded upper limit");
                        conversation.SendDelaySeconds = 1; conversation.DecreaseSendDelayCommand.Execute(null); if (conversation.SendDelaySeconds != 1) throw new Exception("Conversation stepper exceeded lower limit");
                        conversation.SendDelaySeconds = oldDelay;
                        conversation.IsListening = true; Pump();
                        if (!delay.IsEnabled) throw new Exception("Conversation delay cannot be adjusted while listening");
                        conversation.IsListening = false; conversation.IsThinking = true; Pump();
                        if (delay.IsEnabled) throw new Exception("Conversation delay remains editable during AI processing");
                        conversation.IsThinking = false; Pump();
                        var list = (ListBox)chatView.FindName("MessageList"); Pump(); list.UpdateLayout();
                        var bubbles = Descendants(list).OfType<Border>().Where(b => Equals(b.Tag, "ChatBubble") && b.IsVisible).Select(b => (Bubble: b, Bounds: new Rect(b.TransformToAncestor(list).Transform(new Point()), b.RenderSize))).Where(b => b.Bounds.IntersectsWith(new Rect(0, 0, list.ActualWidth, list.ActualHeight))).OrderBy(b => b.Bounds.Top).ToArray();
                        if (bubbles.Length < 2) { Capture(window, output, $"{width}-conversation-spacing-failure.png"); throw new Exception("Conversation fixture did not render adjacent bubbles"); }
                        for (var i = 1; i < bubbles.Length; i++) {
                            var gap = bubbles[i].Bounds.Top - bubbles[i - 1].Bounds.Bottom;
                            if (gap < -1 || gap > 20) { Capture(window, output, $"{width}-conversation-spacing-failure.png"); throw new Exception($"Conversation bubble spacing is not content driven: {gap}; bounds={string.Join(";", bubbles.Select(b => b.Bounds.ToString()))}"); }
                        }
                        var originalToggle = conversation.ShowVietnameseTranslation;
                        conversation.ShowVietnameseTranslation = false; Pump();
                        if (Descendants(list).OfType<TextBlock>().Any(t => t.IsVisible && conversation.Messages.Any(m => m.Translation.Length > 0 && m.Translation == t.Text))) throw new Exception("Conversation translation toggle left translations visible");
                        conversation.ShowVietnameseTranslation = originalToggle; Pump();
                        list.UpdateLayout(); var chatScroll = Descendants(list).OfType<ScrollViewer>().First();
                        if (chatScroll.ScrollableHeight > .5 && chatScroll.VerticalOffset < chatScroll.ScrollableHeight - .5) throw new Exception("Conversation did not reveal the final line after translation height changed");
                        ValidateControlLayout(chatView, "Conversation bubbles");
                    }
                    var notebook = Descendants(window).OfType<NotebookView>().FirstOrDefault()?.DataContext as NotebookViewModel;
                    if (notebook != null && notebook.Sessions.Count == 0) {
                        var view = Descendants(window).OfType<NotebookView>().First(); Pump();
                        if (notebook.HasSelectedSession || ((Border)view.FindName("RecordDetailPanel")).IsVisible || !((StackPanel)view.FindName("EmptyRecordPanel")).IsVisible) throw new Exception("Empty notebook exposed orphan detail controls");
                        var sample = new MeetingSession { Title = "Cuộc họp dự án • Nội dung dài để kiểm tra bố cục", DurationSeconds = 96, Notes = "# Ghi chú cuộc họp\n- Giữ nguyên toàn bộ nội dung đã ghi nhận.", Summary = string.Join("\n", Enumerable.Range(0, 30).Select(n => "Quyết định cần được giữ đầy đủ trong phần tóm tắt, kể cả khi nội dung dài. " + n)), Captions = Enumerable.Range(0, 12).Select(n => new Caption { Start = n * 8, End = n * 8 + 7, Original = "The recording should remain readable when the window is resized and when a longer sentence arrives.", Vietnamese = "Bản ghi phải dễ đọc khi thay đổi kích thước cửa sổ và khi xuất hiện câu dài hơn." }).ToList() };
                        notebook.Sessions.Add(sample); notebook.SelectedSession = sample; Pump();
                        if (!notebook.HasSelectedSession || !((Border)view.FindName("RecordDetailPanel")).IsVisible || ((StackPanel)view.FindName("EmptyRecordPanel")).IsVisible) throw new Exception("Selecting a notebook record did not replace its empty state");
                        if (((ScrollViewer)view.FindName("SummaryScroll")).ScrollableHeight <= 0) throw new Exception("Long notebook summary is clipped instead of scrollable");
                        notebook.CaptionSearch = "no-matching-caption-fixture"; Pump();
                        if (notebook.FilteredCaptionCount != 0 || sample.Captions.Count != 12) throw new Exception("Transcript filtering changed stored captions or its visible count");
                        notebook.ClearCaptionSearchCommand.Execute(null); Pump();
                        if (notebook.FilteredCaptionCount != 12) throw new Exception("Clearing transcript search did not restore the visible count");
                        for (var n = 0; n < 20; n++) notebook.IncreaseCaptionFontCommand.Execute(null);
                        if (notebook.CaptionFontSize != 22 || notebook.IncreaseCaptionFontCommand.CanExecute(null)) throw new Exception("Notebook font upper limit differs from macOS");
                        for (var n = 0; n < 20; n++) notebook.DecreaseCaptionFontCommand.Execute(null);
                        if (notebook.CaptionFontSize != 12 || notebook.DecreaseCaptionFontCommand.CanExecute(null)) throw new Exception("Notebook font lower limit differs from macOS");
                        notebook.CaptionFontSize = 14;
                        var before = sample.Captions.Select(c => (c.Id, c.Original, c.Vietnamese)).ToArray();
                        sample.Captions[0].Vietnamese = "";
                        foreach (var mode in notebook.CaptionModes) {
                            notebook.CaptionMode = mode; Pump();
                            if (!Descendants(view).OfType<TextBlock>().Any(t => t.IsVisible && t.Text == sample.Captions[0].Original)) throw new Exception("Notebook display mode erased a caption without translation: " + mode);
                        }
                        sample.Captions[0].Vietnamese = before[0].Vietnamese;
                        notebook.SelectedSession = null; notebook.SelectedSession = sample; notebook.CaptionMode = "Song ngữ"; Pump();
                        if (!before.SequenceEqual(sample.Captions.Select(c => (c.Id, c.Original, c.Vietnamese)))) throw new Exception("Notebook display controls altered stored captions");
                    }
                    Pump(); window.UpdateLayout();
                    if (button.ActualHeight < 30 || button.ActualWidth < 60) throw new Exception("Navigation collapsed: " + route);
                    var filename = $"{width}-{Array.IndexOf(new[] { "Cuộc họp", "Sổ tay", "Dịch nhanh", "Đọc văn bản", "Học ngôn ngữ", "Trò chuyện", "Cài đặt" }, route)}.png";
                    ValidateControlLayout(window, route);
                    Capture(window, output, filename);
                    Console.WriteLine($"PASS: rendered {route} at {width}x{height}");
                    if (route == "Sổ tay" && width == 1280) {
                        var copyMenu = Descendants(window).OfType<MenuItem>().First(item => Equals(item.Header, "Sao chép"));
                        copyMenu.IsSubmenuOpen = true; Pump();
                        var copy = (MenuItem)copyMenu.Items[2];
                        if (copy.DataContext is not Caption caption) throw new Exception("Caption copy menu lost its row context");
                        copy.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
                        if (!Clipboard.ContainsText() || !Clipboard.GetText().Contains(caption.Original) || !Clipboard.GetText().Contains(caption.Vietnamese)) throw new Exception("Bilingual copy did not preserve both texts");
                        copyMenu.IsSubmenuOpen = false;
                    }
                    if (route == "Sổ tay") {
                        var notebookView = Descendants(window).OfType<NotebookView>().First();
                        ((RadioButton)notebookView.FindName("WordsTab")).IsChecked = true; Pump();
                        var vocabularyView = Descendants(window).OfType<NotebookVocabularyView>().First();
                        var model = (LearningViewModel)vocabularyView.DataContext;
                        if (model.VisibleVocabulary.Count == 0) {
                            model.VisibleVocabulary.Add(new TransTools.Models.VocabularyItem { Word = "follow up", Phonetic = "/ˈfɒləʊ ʌp/", Meaning = "Theo dõi và tiếp tục xử lý", ExampleSentence = "I will follow up with the team after the meeting.", ExampleTranslation = "Tôi sẽ trao đổi tiếp với nhóm sau cuộc họp." });
                            model.VisibleVocabulary.Add(new TransTools.Models.VocabularyItem { Word = "deadline", MasteryScore = 5, Meaning = "Hạn hoàn thành", ExampleSentence = "We need to agree on the deadline." });
                        }
                        Pump(); ValidateControlLayout(window, "Notebook vocabulary");
                        Capture(window, output, $"{width}-notebook-vocabulary.png");
                        var search = (TextBox)vocabularyView.FindName("SearchBox");
                        var words = (ListBox)vocabularyView.FindName("WordsList");
                        var count = model.VisibleVocabulary.Count;
                        ((RadioButton)vocabularyView.FindName("MasteredWords")).IsChecked = true; Pump();
                        if (words.Items.Cast<TransTools.Models.VocabularyItem>().Any(word => word.MasteryScore < 4)) throw new Exception("Mastered filter contains learning words");
                        ((RadioButton)vocabularyView.FindName("LearningWords")).IsChecked = true; Pump();
                        if (words.Items.Cast<TransTools.Models.VocabularyItem>().Any(word => word.MasteryScore >= 4)) throw new Exception("Learning filter contains mastered words");
                        ((RadioButton)vocabularyView.FindName("AllWords")).IsChecked = true; Pump();
                        search.Text = "follow up"; Pump();
                        if (words.Items.Count != 1 || model.VisibleVocabulary.Count != count) throw new Exception("Notebook search changed the learning vocabulary collection");
                        search.Text = "not-a-word"; Pump();
                        if (((FrameworkElement)vocabularyView.FindName("EmptyState")).Visibility != Visibility.Visible) throw new Exception("Vocabulary missing empty-search state");
                        search.Text = ""; Pump();
                        ((Button)vocabularyView.FindName("AddWordButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                        var add = (System.Windows.Controls.Primitives.Popup)vocabularyView.FindName("AddWordPopup");
                        if (!add.IsOpen || add.Child == null) throw new Exception("Notebook add-word popup did not open");
                        ValidateControlLayout((FrameworkElement)add.Child, "Notebook add word");
                        CaptureElement((FrameworkElement)add.Child, output, $"{width}-notebook-add-word.png");
                        add.IsOpen = false;
                        ((RadioButton)notebookView.FindName("RecordsTab")).IsChecked = true; Pump();
                    }

                    if (route == "Học ngôn ngữ") {
                        var learning = Descendants(window).OfType<LearningView>().First();
                        foreach (var label in new[] { "Hôm nay", "Chữ & Viết", "Từ vựng của tôi", "Luyện giao tiếp" }) {
                            var section = Descendants(learning).OfType<RadioButton>().First(item => Equals(item.Content, label));
                            section.IsChecked = true; Pump(); window.UpdateLayout();
                            ValidateControlLayout(window, "Learning: " + label);
                            Capture(window, output, $"{width}-learning-{Array.IndexOf(new[] { "Hôm nay", "Chữ & Viết", "Từ vựng của tôi", "Luyện giao tiếp" }, label)}.png");
                        }
                        var goal = (Button)learning.FindName("LearningGoalButton");
                        goal.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                        var popup = (System.Windows.Controls.Primitives.Popup)learning.FindName("LearningGoalPopup");
                        if (!popup.IsOpen || popup.Child == null) throw new Exception("Learning goal popup did not open");
                        ValidateControlLayout((FrameworkElement)popup.Child, "Learning goal");
                        CaptureElement((FrameworkElement)popup.Child, output, $"{width}-learning-goal.png");
                        popup.IsOpen = false;
                        Descendants(learning).OfType<RadioButton>().First(item => Equals(item.Content, "Hôm nay")).IsChecked = true;
                    }
                    if (route == "Cài đặt") {
                        var sections = Descendants(window).OfType<TabControl>().First();
                        for (var i = 0; i < sections.Items.Count; i++) {
                            sections.SelectedIndex = i; Pump(); window.UpdateLayout();
                            if (sections.SelectedItem is TabItem { Header: "AI & Kết nối" } && width == 1280) {
                                var provider = Descendants(window).OfType<ComboBox>().First(control => control.ItemsSource is string[] values && values.Contains("openai"));
                                foreach (var name in new[] { "openai", "gemini", "claude", "deepseek" }) {
                                    provider.SelectedItem = name; Pump(); window.UpdateLayout();
                                    ValidateControlLayout(window, "AI settings: " + name);
                                    Capture(window, output, "settings-provider-" + name + ".png");
                                }
                                provider.SelectedItem = "openai"; Pump();
                            }
                            if (sections.SelectedItem is TabItem { Header: "Mô hình AI" }) {
                                var modelSettings = (SettingsViewModel)Descendants(window).OfType<SettingsView>().First().DataContext;
                                modelSettings.ModelVoiceLanguage = "en";
                                if (modelSettings.CanUseVieNeu) throw new Exception("VieNeu can be selected for English");
                                modelSettings.ModelVoiceLanguage = "vi";
                                if (modelSettings.CanUseVieNeu != (modelSettings.CanManageModels && modelSettings.VieNeuInstalled)) throw new Exception("VieNeu default availability differs from installation");
                                modelSettings.ModelFilter = "tts";
                                if (!modelSettings.ShowSupertonicCard || !modelSettings.ShowVieNeuCard || modelSettings.ModelFilterEmpty) throw new Exception("TTS filter hides supported models");
                                foreach (var filter in new[] { "stt", "translation", "languageModel" }) {
                                    modelSettings.ModelFilter = filter;
                                    if (!modelSettings.ModelFilterEmpty || modelSettings.ShowSupertonicCard || modelSettings.ShowVieNeuCard) throw new Exception("Unsupported category displays TTS models");
                                }
                                modelSettings.ModelFilter = "installed";
                                if (modelSettings.ShowSupertonicCard != modelSettings.SupertonicInstalled || modelSettings.ShowVieNeuCard != modelSettings.VieNeuInstalled) throw new Exception("Installed model filter differs from inventory");
                                Pump(); Capture(window, output, $"{width}-models-installed.png");
                                modelSettings.ModelFilter = "recommended";
                                modelSettings.DownloadingModel = "supertonic";
                                if (!modelSettings.DownloadingSupertonic || modelSettings.DownloadingVieNeu || modelSettings.ShowSupertonicInstall) throw new Exception("Supertonic download exposes wrong actions");
                                modelSettings.DownloadingModel = "vieneu";
                                if (!modelSettings.DownloadingVieNeu || modelSettings.DownloadingSupertonic || modelSettings.ShowVieNeuInstall) throw new Exception("VieNeu download exposes wrong actions");
                                modelSettings.DownloadingModel = "";
                                if (modelSettings.DownloadingSupertonic || modelSettings.DownloadingVieNeu) throw new Exception("Idle model exposes cancellation");
                                modelSettings.UpdatingCatalog = true; Pump();
                                if (modelSettings.CanManageModels || modelSettings.CatalogUpdateLabel != "Đang cập nhật…") throw new Exception("Catalog busy state is not visible or permits mutation");
                                modelSettings.UpdatingCatalog = false; Pump();
                                var busySettings = new SettingsViewModel(() => true);
                                if (busySettings.CanManageModels) throw new Exception("Active session permits model management");
                                Await(busySettings.UpdateCatalogCommand.ExecuteAsync(null));
                                if (busySettings.UpdatingCatalog) throw new Exception("Busy session started catalog network request");
                            }
                            ValidateControlLayout(window, "Settings section " + i);
                            if (sections.SelectedItem is TabItem { Header: "Dịch & Phụ đề" } && width == 1280) {
                                var settings = (SettingsViewModel)Descendants(window).OfType<SettingsView>().First().DataContext;
                                var quick = new QuickTranslateViewModel();
                                if (quick.TranslateCommand.CanExecute(null) || quick.CheckGrammarCommand.CanExecute(null)) throw new Exception("Empty quick text enables AI actions");
                                var originalQuickFont = quick.EditorFontSize;
                                quick.SourceText = "a\u0301";
                                if (!quick.TranslateCommand.CanExecute(null) || !quick.CheckGrammarCommand.CanExecute(null)) throw new Exception("Quick AI actions did not enable for text");
                                quick.IsTranslating = true;
                                if (quick.CanConfigure || quick.TranslateCommand.CanExecute(null) || quick.CheckGrammarCommand.CanExecute(null)) throw new Exception("Quick processing permits overlapping actions");
                                quick.IsTranslating = false;
                                if (quick.CharacterCountLabel != "1 ký tự") throw new Exception("Quick editor Unicode count is incorrect");
                                for (var n = 0; n < 30; n++) quick.IncreaseEditorFontCommand.Execute(null);
                                if (quick.EditorFontSize != 22 || quick.IncreaseEditorFontCommand.CanExecute(null)) throw new Exception("Quick editor upper font bound failed");
                                for (var n = 0; n < 30; n++) quick.DecreaseEditorFontCommand.Execute(null);
                                if (quick.EditorFontSize != 12 || quick.DecreaseEditorFontCommand.CanExecute(null) || quick.SourceText != "a\u0301") throw new Exception("Quick editor lower font bound or source preservation failed");
                                quick.EditorFontSize = originalQuickFont;
                                var domain = settings.TranslationDomain; var pace = settings.SubtitlePacing; var size = settings.SubtitleFontSize; var light = settings.SubtitleLight;
                                settings.TranslationDomain = "Công nghệ thông tin"; settings.SubtitlePacing = "Nhanh"; settings.SubtitleFontSize = 21; settings.SubtitleLight = true;
                                settings.SaveSubtitlePreferencesCommand.Execute(null);
                                var preferences = TransTools.Services.Experience.SubtitlePreferences.Shared;
                                if (quick.SelectedDomain != "Công nghệ thông tin" || preferences.Pacing != "fast" || preferences.FontSize != 21 || !preferences.Light) throw new Exception("Translation/subtitle settings did not update shared consumers");
                                settings.TranslationDomain = domain; settings.SubtitlePacing = pace; settings.SubtitleFontSize = size; settings.SubtitleLight = light;
                                settings.SaveSubtitlePreferencesCommand.Execute(null); Pump();
                            }
                            if (sections.SelectedItem is TabItem { Header: "Giọng đọc & Phát âm" }) {
                                var voice = Descendants(window).OfType<VoiceSettingsView>().First();
                                Capture(window, output, $"{width}-voice-default.png");
                                ((RadioButton)voice.FindName("AdvancedTab")).IsChecked = true; Pump(); ValidateControlLayout(window, "Voice advanced");
                                Capture(window, output, $"{width}-voice-advanced.png");
                                ((RadioButton)voice.FindName("DefaultTab")).IsChecked = true; Pump();
                                if (width == 1280) {
                                    var management = (SettingsViewModel)Descendants(window).OfType<SettingsView>().First().DataContext;
                                    var blocked = new VoiceSettingsViewModel(management, () => true);
                                    Await(blocked.PreviewCommand.ExecuteAsync(null));
                                    if (blocked.IsPreviewing || !blocked.Status.Contains("Dừng phiên")) throw new Exception("Voice preview did not respect active audio session");
                                    var voicePreviewReader = new TextReaderViewModel { Text = "Keep this original text unchanged." };
                                    var old = TransTools.Services.Speech.VoicePreferences.Get("vi");
                                    TransTools.Services.Speech.VoicePreferences.Save("vi", "Giọng cơ bản", 1.2);
                                    if (voicePreviewReader.Engine != "Giọng cơ bản" || Math.Abs(voicePreviewReader.Rate - 1.2) > 0.000001 || voicePreviewReader.Text != "Keep this original text unchanged.") throw new Exception("Voice preference update failed or overwrote reader text");
                                    TransTools.Services.Speech.VoicePreferences.Save("vi", old.Engine, old.Rate);
                                }
                            }
                            Capture(window, output, $"{width}-settings-{i}.png");
                            Console.WriteLine($"PASS: settings section {i} at {width}x{height}");
                        }
                    }
                }
            }
            Descendants(window).OfType<RadioButton>().First(b => Equals(b.Content, "Cuộc họp")).IsChecked = true; Pump();
            var routedMeeting = Descendants(window).OfType<MeetingView>().First();
            ((Button)routedMeeting.FindName("EarphoneButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
            var routedPopup = (System.Windows.Controls.Primitives.Popup)routedMeeting.FindName("EarphonePopup");
            Descendants(routedPopup.Child).OfType<Button>().First(b => Equals(b.Content, "Giọng & Tốc độ")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
            var routedSettings = Descendants(window).OfType<SettingsView>().First();
            if (((TabControl)routedSettings.FindName("SettingsSections")).SelectedIndex != 4 || Descendants(routedSettings).OfType<VoiceSettingsView>().First().DataContext is not VoiceSettingsViewModel routedVoice || routedVoice.Language != ((MeetingViewModel)routedMeeting.DataContext).TargetLanguage) throw new Exception("Earphone voice settings route lost the target language");
            var about = new AboutWindow { Owner = window }; about.Show(); Pump(); ValidateControlLayout(about, "About"); Capture(about, output, "about.png"); about.Close();
            var rename = new RenameRecordWindow("Cuộc họp dự án"){ Owner = window }; rename.Show(); Pump(); ValidateControlLayout(rename, "Rename record"); Capture(rename, output, "rename-record.png"); rename.Close();
            var deleteConfirm = new ConfirmDeleteWindow("Cuộc họp dự án") { Owner = window }; deleteConfirm.Show(); Pump(); ValidateControlLayout(deleteConfirm, "Delete confirmation"); Capture(deleteConfirm, output, "delete-record.png"); deleteConfirm.Close();
            var clearMeeting = new ConfirmDeleteWindow("Nội dung cuộc họp hiện tại", currentMeeting: true) { Owner = window }; clearMeeting.Show(); Pump(); ValidateControlLayout(clearMeeting, "Clear current meeting"); Capture(clearMeeting, output, "clear-current-meeting.png"); clearMeeting.Close();
            var deleteAll = new ConfirmDeleteWindow("12 bản ghi đã lưu", true) { Owner = window }; deleteAll.Show(); Pump(); ValidateControlLayout(deleteAll, "Delete all confirmation"); Capture(deleteAll, output, "delete-all-records.png"); deleteAll.Close();
            var generatedJson = "{\"lessons\":[{\"original\":\"Hello.\",\"meaning\":\"Xin chào.\",\"context\":\"Chào hỏi\"},{\"original\":\"Thank you.\",\"meaning\":\"Cảm ơn.\",\"context\":\"Cảm ơn\"},{\"original\":\"Goodbye.\",\"meaning\":\"Tạm biệt.\",\"context\":\"Tạm biệt\"}]}";
            var generated = TransTools.Services.Learning.AdaptiveLessons.ParseGenerated(generatedJson, "en", "Giao tiếp đời sống");
            if (generated.Count != 3 || generated.Any(l => l.Goal != "Giao tiếp đời sống")) throw new Exception("Generated lessons lost goal context");
            var rejected = false; try { TransTools.Services.Learning.AdaptiveLessons.ParseGenerated("{\"lessons\":[]}", "en", "test"); } catch { rejected = true; }
            if (!rejected) throw new Exception("Invalid AI lesson response accepted");
            var lessonRoot = Path.Combine(output, "adaptive-fixture"); var lessonStore = new TransTools.Services.Learning.AdaptiveLessons(lessonRoot);
            lessonStore.AddGenerated(generated);
            var restoredLessons = new TransTools.Services.Learning.AdaptiveLessons(lessonRoot);
            if (restoredLessons.Lessons.Count != 3 || restoredLessons.Lessons[0].Goal != "Giao tiếp đời sống") throw new Exception("Generated lesson persistence lost goal");
            var progress = new TransTools.Services.Learning.LessonProgress(); var day = new DateTime(2026,10,10);
            for (var i=0;i<10;i++) progress = progress.Record(true,day);
            if (progress.Difficulty != 1) throw new Exception("Repeated same-day answers increased difficulty");
            progress = progress.Record(true,day.AddDays(1)).Record(true,day.AddDays(2));
            if (progress.Difficulty != 2 || progress.Record(false,day.AddDays(3)).Difficulty != 1) throw new Exception("Adaptive multi-day difficulty progression failed");
            var exportFixture = new MeetingSession { Title = "Tiếng Việt", Captions = [new Caption { Start = 1.25, End = 3.5, Original = "Hello", Vietnamese = "Xin chào" }] };
            var exportSrt = MeetingViewModel.FormatExport(exportFixture, "srt");
            if (!exportSrt.Contains("00:00:01,250 --> 00:00:03,500") || !exportSrt.Contains("Hello\nXin chào")) throw new Exception("Meeting SRT export lost timing or bilingual text");
            if (!MeetingViewModel.FormatExport(exportFixture, "txt").Contains("Tiếng Việt")) throw new Exception("Meeting TXT export lost Unicode title");
            CheckNotebookRecords(window, output);
            CheckReadingLibrary(window, output);
            var chatModel = Descendants(window).OfType<ConversationView>().FirstOrDefault()?.DataContext as ConversationViewModel;
            // The cached conversation view may be hidden; create an isolated fixture instead.
            chatModel = new ConversationViewModel(() => false);
            chatModel.Messages.Add(new ChatMessageItem { Text = "A long reply should wrap and remain readable in the mini chat window. The user should be able to follow the conversation while the main window is closed.", Translation = "Câu trả lời dài cần xuống dòng và vẫn dễ đọc trong cửa sổ trò chuyện nhỏ." });
            var mini = new ConversationMiniWindow(chatModel); mini.Show(); Pump(); ValidateControlLayout(mini, "Mini chat"); Capture(mini, output, "mini-chat.png"); mini.CloseForExit(); chatModel.Dispose();
            CheckSubtitleHud(output);
            File.WriteAllLines(Path.Combine(output, "bindings.txt"), errors.Lines);
            if (errors.Lines.Count != 0) throw new Exception("WPF binding errors detected; see bindings.txt.");
            File.WriteAllText(Path.Combine(output, "result.txt"), "PASS: seven routes, three window sizes, no WPF binding errors. Audio, model inference and Windows 10/11 interactive tests remain separate.");
            app.Shutdown(); return 0;
        } catch (Exception ex) { File.WriteAllText(Path.Combine(output, "failure.txt"), ex.ToString()); Console.Error.WriteLine(ex); return 1; }
    }
    private static void Await(Task task)
    {
        var deadline = DateTime.UtcNow.AddSeconds(20);
        while (!task.IsCompleted) { if (DateTime.UtcNow > deadline) throw new TimeoutException("Fixture did not complete"); Pump(); }
        task.GetAwaiter().GetResult();
    }
    private static void CheckNotebookRecords(Window window, string output)
    {
        var conversationTab = Descendants(window).OfType<RadioButton>().First(b => Equals(b.Content, "Trò chuyện"));
        conversationTab.IsChecked = true; Pump();
        var conversation = (ConversationViewModel)Descendants(window).OfType<ConversationView>().First().DataContext;
        var saved = new TransTools.Services.Storage.ConversationSession {
            Title = "Trò chuyện · Cuộc họp dự án", Language = "Tiếng Nhật", Topic = "Công việc", UpdatedAt = DateTime.Now.AddHours(1),
            Messages = [new ChatMessageItem { IsUser = true, Text = "プロジェクトについて話しましょう。", Translation = "Cùng nói về dự án.", TimeString = "10:30" }, new ChatMessageItem { Text = "もちろんです。", Translation = "Chắc chắn rồi.", TimeString = "10:32" }]
        };
        conversation.Sessions.Add(saved);
        var notebookTab = Descendants(window).OfType<RadioButton>().First(b => Equals(b.Content, "Sổ tay"));
        notebookTab.IsChecked = true; Pump();
        var notebook = (NotebookViewModel)Descendants(window).OfType<NotebookView>().First().DataContext;
        notebook.SetConversations(conversation.Sessions);
        var projection = notebook.Sessions.Single(s => s.Id == saved.Id);
        if (!projection.IsConversation || projection.SourceLanguage != "ja" || projection.Captions[0].FormattedTimestamp != "10:30" || !projection.Captions[0].Original.Contains(saved.Messages[0].Text)) throw new Exception("Saved conversation projection lost source language, text or original time");
        if (System.Text.Json.JsonSerializer.Serialize(projection).Contains("IsConversation")) throw new Exception("Conversation projection metadata leaked into meeting persistence");
        notebook.RecordKind = "Trò chuyện";
        if (notebook.SessionsView.Cast<MeetingSession>().Any(s => !s.IsConversation)) throw new Exception("Conversation filter contains meetings");
        notebook.SelectedSession = projection;
        foreach (var width in new[] {1200, 1280, 1440}) {
            SetViewportSize(window, width, (int)window.Height); Pump(); ValidateControlLayout(window, "Notebook conversation"); Capture(window, output, $"{width}-notebook-conversation.png");
        }
        notebook.RecordKind = "Cuộc họp";
        if (notebook.SessionsView.Cast<MeetingSession>().Any(s => s.IsConversation)) throw new Exception("Meeting filter contains conversations");
        notebook.RecordKind = "Tất cả"; notebook.SearchKeyword = "プロジェクト"; Pump();
        if (!notebook.SessionsView.Contains(projection)) throw new Exception("Conversation text search lost saved messages");
        notebook.SearchKeyword = ""; notebook.SelectedSession = projection;
        notebook.ResumeConversationCommand.Execute(null); Pump();
        if (conversation.SelectedSession?.Id != saved.Id || conversation.Messages.Count != 2 || conversation.Messages[0].Text != saved.Messages[0].Text) throw new Exception("Resume conversation did not restore exact saved messages");
        if (conversation.IsThinking || conversation.IsListening) throw new Exception("Resuming saved conversation triggered AI or microphone automatically");
        notebook.SetConversations(conversation.Sessions);
        if (notebook.Sessions.Count(s => s.Id == saved.Id) != 1) throw new Exception("Conversation refresh duplicated a saved session");
        var beforeRenameText = conversation.Messages[0].Text;
        Await(notebook.RenameRecordTitleAsync(notebook.Sessions.Single(s => s.Id == saved.Id), "Tên riêng của tôi"));
        if (saved.Title != "Tên riêng của tôi" || !saved.HasCustomTitle) throw new Exception("Conversation rename did not update shared source: " + notebook.Status);
        Await(conversation.SaveConversationCommand.ExecuteAsync(null));
        var storedTitle = new TransTools.Services.Storage.ConversationStore().Load().Single(s => s.Id == saved.Id);
        if (storedTitle.Title != "Tên riêng của tôi" || !storedTitle.HasCustomTitle || storedTitle.Messages[0].Text != beforeRenameText) throw new Exception("Saving conversation overwrote custom title or messages");
        var invalidRename = notebook.RenameRecordTitleAsync(notebook.Sessions.Single(s => s.Id == saved.Id), "   "); Await(invalidRename);
        if (invalidRename.Result || saved.Title != "Tên riêng của tôi") throw new Exception("Empty rename changed source title");
        var beforeDeleteCount = conversation.Sessions.Count;
        Await(notebook.DeleteRecordByIdAsync(notebook.Sessions.Single(s => s.Id == saved.Id)));
        if (conversation.Sessions.Count != beforeDeleteCount - 1 || conversation.Sessions.Any(s => s.Id == saved.Id) || new TransTools.Services.Storage.ConversationStore().Load().Any(s => s.Id == saved.Id) || notebook.Sessions.Any(s => s.Id == saved.Id)) throw new Exception("Deleting conversation did not remove only the selected shared record");
        conversation.Sessions.Add(saved); notebook.SetConversations(conversation.Sessions);
        notebook.RecordManagementBusy = () => true;
        var busyDelete = notebook.DeleteAllRecordsAsync(); Await(busyDelete);
        if (busyDelete.Result || !notebook.Sessions.Any(s => s.Id == saved.Id)) throw new Exception("Bulk deletion ignored busy guard");
        notebook.RecordManagementBusy = () => false;
        notebook.RecordKind = "Cuộc họp"; notebook.SearchKeyword = "does not match any record";
        var allDelete = notebook.DeleteAllRecordsAsync(); Await(allDelete);
        if (!allDelete.Result || notebook.Sessions.Count != 0 || conversation.Sessions.Count != 0 || new TransTools.Services.Storage.ConversationStore().Load().Count != 0) throw new Exception("Bulk delete left hidden records behind");
        Console.WriteLine("PASS: combined notebook filters, search, source timestamps and resume routing");
    }

    private static void CheckReadingLibrary(Window owner, string output)
    {
        var unicode = new string('a', 4499) + "😊 " + ReadingFixtureHandler.Sample;
        var parts = TransTools.Services.Reading.ReadingLibrary.SplitParts(unicode);
        if (string.Concat(parts.Select(part => part.Text)) != unicode.Trim() || parts.Any(part => part.Text.Length > 4500 || char.IsHighSurrogate(part.Text[^1]))) throw new Exception("Story splitting lost text or broke Unicode");
        var html = TransTools.Services.Reading.ReadingLibrary.ExtractParagraphs("<p>Tiếng <b>Việt</b> &amp; tên riêng.<script>ignore me</script></p>");
        if (html != "Tiếng Việt & tên riêng.") throw new Exception("Story HTML extraction lost readable text");
        var handler = new ReadingFixtureHandler(); using var client = new System.Net.Http.HttpClient(handler);
        using var model = new ReadingLibraryViewModel(new TransTools.Services.Reading.ReadingLibrary(client));
        var library = new ReadingLibraryWindow(model) { Owner = owner }; library.Show(); Pump();
        ValidateControlLayout(library, "Story catalog"); Capture(library, output, "reading-library-catalog.png");
        var reader = new TextReaderViewModel { Text = "Keep the original text until the user confirms." };
        Await(model.LoadStoryAsync(TransTools.Services.Reading.ReadingLibrary.Catalog[0])); Pump();
        if (!model.CanUsePart || reader.Text != "Keep the original text until the user confirms." || string.Concat(model.Parts.Select(part => part.Text)) != ReadingFixtureHandler.Sample) throw new Exception("Story preview changed the editor or lost content");
        ValidateControlLayout(library, "Story preview"); Capture(library, output, "reading-library-preview.png");
        reader.UseStory(model.SelectedStory!, model.SelectedPart!.Text);
        if (reader.Language != "vi" || !reader.HasStory || reader.Text != model.PreviewText) throw new Exception("Story import lost its text, language or source");
        Await(model.LoadStoryAsync(TransTools.Services.Reading.ReadingLibrary.Catalog[1]));
        if (string.Concat(model.Parts.Select(part => part.Text)) != ReadingFixtureHandler.Sample) throw new Exception("Gutenberg import retained boilerplate or lost story text");
        model.Query = "truyện cổ tích"; Await(model.SearchAsync());
        if (model.Stories.Count != 2 || !model.Stories.All(story => story.Page.Scheme == "https" && story.Id.Contains("123"))) throw new Exception("Online story search did not retain source links");
        Capture(library, output, "reading-library-search.png");
        model.SuggestionsCommand.Execute(null);
        handler.Fail = true; var preserved = reader.Text; Await(model.LoadStoryAsync(TransTools.Services.Reading.ReadingLibrary.Catalog[0]));
        if (model.CanUsePart || reader.Text != preserved || !model.Status.StartsWith("Chưa tải")) throw new Exception("Failed story download changed the reader");
        handler.Fail = false; handler.Oversized = true; Await(model.LoadStoryAsync(TransTools.Services.Reading.ReadingLibrary.Catalog[0]));
        if (model.CanUsePart) throw new Exception("Oversized story download was accepted");
        handler.Oversized = false; handler.Pending = new(TaskCreationOptions.RunContinuationsAsynchronously); model.Query = "old search";
        var pending = model.SearchAsync(); model.SuggestionsCommand.Execute(null); handler.Pending.SetResult(ReadingFixtureHandler.SearchResponse()); Await(pending);
        if (model.Stories.Count != 4 || model.IsBusy || model.Stories[0].Id != "tam-cam") throw new Exception("Canceled search overwrote the suggested catalog");
        library.Close(); Console.WriteLine("PASS: story catalog, search, preview, import, Unicode, cancellation and download limits");
    }
    private static void CheckMeetingSpeechQueue()
    {
        if (TransTools.Services.Audio.PlaybackDevices.CanRead(true, "device-a", "device-a") || TransTools.Services.Audio.PlaybackDevices.CanRead(true, null, "device-b") || !TransTools.Services.Audio.PlaybackDevices.CanRead(true, "device-a", "device-b") || !TransTools.Services.Audio.PlaybackDevices.CanRead(false, null, "device-a")) throw new Exception("Earphone feedback policy is incorrect");
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var done = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var spoken = new System.Collections.Concurrent.ConcurrentQueue<string>();
        using var queue = new TransTools.Services.Speech.MeetingSpeechQueue(async (request, token) => {
            spoken.Enqueue(request.Text);
            if (request.Text == "first") { entered.TrySetResult(); await release.Task.WaitAsync(token); }
            if (request.Text == "fourth") done.TrySetResult();
        }, error => done.TrySetException(error));
        queue.Enqueue(new("first", "en", "device-b")); entered.Task.WaitAsync(TimeSpan.FromSeconds(5)).GetAwaiter().GetResult();
        foreach (var text in new[] { "second", "third", "fourth" }) queue.Enqueue(new(text, "en", "device-b"));
        release.TrySetResult(); done.Task.WaitAsync(TimeSpan.FromSeconds(5)).GetAwaiter().GetResult();
        if (!spoken.SequenceEqual(new[] { "first", "third", "fourth" })) throw new Exception("Auto reading retained an unbounded stale backlog");
        queue.Dispose(); queue.Completion.WaitAsync(TimeSpan.FromSeconds(5)).GetAwaiter().GetResult();
        if (queue.Enqueue(new("later", "en", "device-b"))) throw new Exception("Stopped auto reader accepted new speech");
        var canceled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var active = new TransTools.Services.Speech.MeetingSpeechQueue(async (_, token) => { canceled.TrySetResult(); await Task.Delay(Timeout.Infinite, token); }, _ => throw new Exception("Cancellation was reported as a playback failure"));
        active.Enqueue(new("active", "en", "device-b")); canceled.Task.WaitAsync(TimeSpan.FromSeconds(5)).GetAwaiter().GetResult(); active.Dispose(); active.Completion.WaitAsync(TimeSpan.FromSeconds(5)).GetAwaiter().GetResult();
        Console.WriteLine("PASS: auto reading bounded backlog, owned cancellation and endpoint feedback policy");
    }
    private static void CheckSubtitleHud(string output)
    {
        var prefs = TransTools.Services.Experience.SubtitlePreferences.Shared;
        prefs.DisplayMode = "bilingual"; prefs.Light = false; prefs.Side = false; prefs.ShowMascot = false; prefs.ShowContext = true; prefs.ShowNext = true; prefs.ShowOriginal = true;
        var hud = new FloatingSubtitleWindow(); hud.Show(); hud.SetMeetingState(true); Pump();
        var paused = false; var started = false; hud.StopRequested += () => paused = true; hud.StartRequested += () => started = true;
        ((Button)hud.FindName("StopButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        if (!paused) throw new Exception("HUD pause action did not reach the meeting");
        hud.SetMeetingState(false); ((Button)hud.FindName("StopButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        if (!started) throw new Exception("HUD start action did not reach the meeting");
        hud.SetMeetingState(true);
        for (var i = 0; i < 33; i++) hud.UpdateCaption(new Caption { Start = i, Original = "Original sentence " + i, Vietnamese = "Câu hoàn chỉnh cần được giữ lại để người dùng có thể đọc đủ nội dung. " + i });
        hud.UpdateIncoming(new Caption { Start = 34, Original = "A new sentence is arriving and should not replace the completed translation." });
        Pump(); ValidateControlLayout(hud, "HUD live"); Capture(hud, output, "subtitles.png");
        foreach (var mode in new[] { "original", "translation", "bilingual" }) {
            prefs.DisplayMode = mode; prefs.Save(); Pump();
            var shown = ((TextBlock)hud.FindName("TranslatedText")).Text;
            if (mode == "original" ? shown != "Original sentence 32" : !shown.EndsWith("32")) throw new Exception("HUD display mode lost the latest caption");
            var sourceVisible = ((TextBlock)hud.FindName("OriginalText")).Visibility == Visibility.Visible;
            if (sourceVisible != (mode == "bilingual")) throw new Exception("HUD source visibility differs from selected mode");
            if (hud.HistoryCount != 30) throw new Exception("HUD display mode modified history");
            Capture(hud, output, "subtitles-mode-" + mode + ".png");
        }
        var last = ((TextBlock)hud.FindName("TranslatedText")).Text; hud.UpdateSubtitle("", ""); Pump();
        if (hud.HistoryCount != 30 || ((TextBlock)hud.FindName("TranslatedText")).Text != last) throw new Exception("HUD lost a completed caption or retained unbounded history");
        var original = (MenuItem)hud.FindName("ShowOriginal"); original.IsChecked = false; original.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
        hud.UpdateCaption(new Caption { Original = "Translation failed; the original must remain readable." }); Pump();
        if (((TextBlock)hud.FindName("TranslatedText")).Text != "Translation failed; the original must remain readable.") throw new Exception("HUD translation failure erased its source text");
        var light = (MenuItem)hud.FindName("LightBackground"); light.IsChecked = true; light.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
        ((Button)hud.FindName("ReviewButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
        Capture(hud, output, "subtitles-review-light.png");
        var review = (ListBox)hud.FindName("ReviewList");
        if (review.Visibility != Visibility.Visible || ((ScrollViewer)hud.FindName("CaptionScroll")).Visibility != Visibility.Collapsed) throw new Exception("HUD review did not isolate manual scrolling");
        ((Button)hud.FindName("ReviewButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        ((MenuItem)hud.FindName("LayoutItem")).RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump(); ValidateControlLayout(hud, "HUD side"); Capture(hud, output, "subtitles-side.png");
        ((MenuItem)hud.FindName("LayoutItem")).RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); hud.Width = 820;
        var mascot = (MenuItem)hud.FindName("ShowMascot"); mascot.IsChecked = true; mascot.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
        if (!hud.IsMascotDisplayed) throw new Exception("HUD mascot was not displayed in its own column");
        ValidateControlLayout(hud, "HUD mascot"); Capture(hud, output, "subtitles-mascot.png");
        var longCaption = new Caption { Original = string.Join("\n", Enumerable.Repeat("Long source line for checking scroll after content layout.", 25)), Vietnamese = string.Join("\n", Enumerable.Repeat("Nội dung dài cần tự cuộn đến dòng cuối sau khi bố cục hoàn tất.", 25)) };
        hud.UpdateCaption(longCaption); Pump();
        var scroll = (ScrollViewer)hud.FindName("CaptionScroll");
        if (scroll.ScrollableHeight > .5 && scroll.VerticalOffset < scroll.ScrollableHeight - .5) throw new Exception("HUD did not scroll to its final line");
        hud.ResetSession(); Pump(); if (hud.HistoryCount != 0) throw new Exception("HUD new session retained previous history");
        hud.Hide(); Console.WriteLine("PASS: HUD controls, retained captions, review history, layouts, mascot and final-line scrolling");
    }
    private static void ValidateControlLayout(Window window, string route)
        => ValidateControlLayout((FrameworkElement)window.Content, route);
    private static void ValidateControlLayout(FrameworkElement root, string route)
    {
        var viewport = new Rect(0, 0, root.ActualWidth, root.ActualHeight);
        var controls = Descendants(root).OfType<FrameworkElement>().Where(e => e.IsVisible && (e is Button || e is ComboBox || e is RadioButton)).Select(e => (Element: e, Bounds: VisibleBounds(e, root))).Where(e => e.Bounds.Width > 1 && e.Bounds.Height > 1 && viewport.IntersectsWith(e.Bounds)).ToArray();
        for (var i = 0; i < controls.Length; i++) for (var j = i + 1; j < controls.Length; j++) {
            var overlap = Rect.Intersect(controls[i].Bounds, controls[j].Bounds);
            if (!overlap.IsEmpty && overlap.Width > 2 && overlap.Height > 2)
                throw new Exception($"Overlapping controls in {route}: {controls[i].Element.Name} ({controls[i].Element.GetType().Name}) and {controls[j].Element.Name} ({controls[j].Element.GetType().Name}), {overlap}");
        }
        Console.WriteLine($"PASS: no button/dropdown overlap in {route}");
    }
    private static Rect VisibleBounds(FrameworkElement element, FrameworkElement root)
    {
        var bounds = element.TransformToAncestor(root).TransformBounds(new Rect(element.RenderSize));
        for (DependencyObject? ancestor = VisualTreeHelper.GetParent(element); ancestor != null && ancestor != root; ancestor = VisualTreeHelper.GetParent(ancestor))
            if (ancestor is FrameworkElement frame && (frame.ClipToBounds || frame is ScrollContentPresenter))
                bounds.Intersect(frame.TransformToAncestor(root).TransformBounds(new Rect(frame.RenderSize)));
        bounds.Intersect(new Rect(root.RenderSize));
        return bounds;
    }
    private static void SetViewportSize(Window window, int width, int height)
    {
        // Hosted runners may have a small desktop. Raise track minimums as well
        // as requested size so native window constraints cannot silently clamp it.
        window.MinWidth = width; window.MinHeight = height;
        window.Width = width; window.Height = height; Pump(); window.UpdateLayout();
        var root = (FrameworkElement)window.Content;
        if (Math.Abs(window.ActualWidth - width) > 2 || Math.Abs(window.ActualHeight - height) > 2 || root.ActualWidth < width - 40 || root.ActualHeight < height - 60)
            throw new Exception($"Requested {width}x{height}, actual window {window.ActualWidth}x{window.ActualHeight}, client {root.ActualWidth}x{root.ActualHeight}");
        Console.WriteLine($"PASS: requested {width}x{height}; actual window {window.ActualWidth}x{window.ActualHeight}; client {root.ActualWidth}x{root.ActualHeight}");
    }
    private static void Capture(Window window, string output, string name)
    {
        window.UpdateLayout(); var root = (FrameworkElement)window.Content;
        var margin = root.Margin;
        var width = root.ActualWidth + margin.Left + margin.Right;
        var height = root.ActualHeight + margin.Top + margin.Bottom;
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(width), (int)Math.Ceiling(height), 96, 96, PixelFormats.Pbgra32);
        // Capture the client area including the content's outer margin. An explicit
        // viewbox prevents VisualBrush from stretching descendant bounds into it.
        var drawing = new DrawingVisual();
        using (var context = drawing.RenderOpen()) {
            context.DrawRectangle(window.Background, null, new Rect(0, 0, width, height));
            var offset = VisualTreeHelper.GetOffset(root);
            var brush = new VisualBrush(root) { Stretch = Stretch.Fill, ViewboxUnits = BrushMappingMode.Absolute, Viewbox = new Rect(offset.X, offset.Y, root.ActualWidth, root.ActualHeight) };
            context.DrawRectangle(brush, null, new Rect(margin.Left, margin.Top, root.ActualWidth, root.ActualHeight));
        }
        bitmap.Render(drawing);
        var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(Path.Combine(output, name)); png.Save(file);
    }
    private static void CaptureElement(FrameworkElement element, string output, string name)
    {
        element.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(element.ActualWidth), (int)Math.Ceiling(element.ActualHeight), 96, 96, PixelFormats.Pbgra32);
        var drawing = new DrawingVisual();
        using (var context = drawing.RenderOpen()) context.DrawRectangle(new VisualBrush(element), null, new Rect(0, 0, element.ActualWidth, element.ActualHeight));
        bitmap.Render(drawing);
        var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(Path.Combine(output, name)); png.Save(file);
    }
    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) {
            var child = VisualTreeHelper.GetChild(root, i); yield return child;
            foreach (var descendant in Descendants(child)) yield return descendant;
        }
    }
    private static void Pump()
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(250) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; }; timer.Start(); Dispatcher.PushFrame(frame);
    }
    private sealed class BindingErrors : TraceListener
    {
        public List<string> Lines { get; } = new();
        public override void Write(string? message) { if (!string.IsNullOrWhiteSpace(message)) Lines.Add(message); }
        public override void WriteLine(string? message) => Write(message);
    }
}
