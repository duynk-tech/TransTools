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
            var app = new TransTools.App(); app.InitializeComponent();
            var window = new TransTools.MainWindow(); app.MainWindow = window; window.Show();
            var background = (Button)window.FindName("BackgroundButton");
            foreach (var mode in new[] { "morning", "noon", "afternoon", "night", "mint" }) {
                var item = background.ContextMenu.Items.OfType<MenuItem>().First(value => Equals(value.Tag, mode));
                item.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
                if (!item.IsChecked) throw new Exception("Background selection did not update: " + mode);
                Capture(window, output, "background-" + mode + ".png");
            }
            background.ContextMenu.Items.OfType<MenuItem>().First(value => Equals(value.Tag, "noon")).RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
            foreach (var (width, height) in new[] { (1280, 820), (1200, 740), (1440, 900) }) {
                window.Width = width; window.Height = height;
                foreach (var route in new[] { "Cuộc họp", "Sổ tay", "Dịch nhanh", "Đọc văn bản", "Học ngôn ngữ", "Trò chuyện", "Cài đặt" }) {
                    var button = Descendants(window).OfType<RadioButton>().First(b => Equals(b.Content, route));
                    button.IsChecked = true; Pump(); window.UpdateLayout();
                    if (width == 1280) Capture(window, output, $"{width}-idle-{route}.png");
                    var reader = Descendants(window).OfType<TextReaderView>().FirstOrDefault();
                    if (reader != null) {
                        var options = (Button)reader.FindName("ReadingOptionsButton");
                        var popup = (System.Windows.Controls.Primitives.Popup)reader.FindName("ReadingOptionsPopup");
                        if (popup.IsOpen) throw new InvalidOperationException("Reading options must be collapsed initially");
                        options.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                        if (!popup.IsOpen || popup.Child == null) throw new InvalidOperationException("Reading options did not open");
                        ValidateControlLayout((FrameworkElement)popup.Child, "Reading options");
                        CaptureElement((FrameworkElement)popup.Child, output, $"{width}-reader-options-popup.png");
                        Capture(window, output, $"{width}-reader-options.png");
                        popup.IsOpen = false;
                    }
                    var meeting = Descendants(window).OfType<MeetingView>().FirstOrDefault()?.DataContext as MeetingViewModel;
                    if (meeting != null && meeting.Captions.Count == 0) {
                        for (var n = 0; n < 12; n++) meeting.Captions.Add(new Caption { Start = n * 8, End = n * 8 + 7, Original = "We should preserve the full conversation, including longer sentences and the context needed to understand the discussion.", Vietnamese = "Cần giữ đầy đủ cuộc hội thoại, bao gồm những câu dài và ngữ cảnh để hiểu đúng nội dung đang thảo luận." });
                    }
                    var conversation = Descendants(window).OfType<ConversationView>().FirstOrDefault()?.DataContext as ConversationViewModel;
                    if (conversation != null && conversation.Messages.Count == 0) {
                        for (var n = 0; n < 8; n++) conversation.Messages.Add(new ChatMessageItem { IsUser = n % 2 == 0, Text = "Let us practice a longer conversation about your work and the next project. What would you like to discuss today?", Translation = n % 2 == 0 ? "" : "Cùng luyện một cuộc trò chuyện dài về công việc và dự án sắp tới. Hôm nay bạn muốn thảo luận điều gì?" });
                    }
                    var notebook = Descendants(window).OfType<NotebookView>().FirstOrDefault()?.DataContext as NotebookViewModel;
                    if (notebook != null && notebook.Sessions.Count == 0) {
                        var sample = new MeetingSession { Title = "Cuộc họp dự án • Nội dung dài để kiểm tra bố cục", DurationSeconds = 96, Notes = "# Ghi chú cuộc họp\n- Giữ nguyên toàn bộ nội dung đã ghi nhận.", Captions = Enumerable.Range(0, 12).Select(n => new Caption { Start = n * 8, End = n * 8 + 7, Original = "The recording should remain readable when the window is resized and when a longer sentence arrives.", Vietnamese = "Bản ghi phải dễ đọc khi thay đổi kích thước cửa sổ và khi xuất hiện câu dài hơn." }).ToList() };
                        notebook.Sessions.Add(sample); notebook.SelectedSession = sample;
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
                            ValidateControlLayout(window, "Settings section " + i);
                            if (sections.SelectedItem is TabItem { Header: "Dịch & Phụ đề" } && width == 1280) {
                                var settings = (SettingsViewModel)Descendants(window).OfType<SettingsView>().First().DataContext;
                                var quick = new QuickTranslateViewModel();
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
            var about = new AboutWindow { Owner = window }; about.Show(); Pump(); ValidateControlLayout(about, "About"); Capture(about, output, "about.png"); about.Close();
            var rename = new RenameRecordWindow("Cuộc họp dự án"){ Owner = window }; rename.Show(); Pump(); ValidateControlLayout(rename, "Rename record"); Capture(rename, output, "rename-record.png"); rename.Close();
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
            window.Width = width; Pump(); ValidateControlLayout(window, "Notebook conversation"); Capture(window, output, $"{width}-notebook-conversation.png");
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
        if (saved.Title != "Tên riêng của tôi" || !saved.HasCustomTitle) throw new Exception("Conversation rename did not update shared source");
        Await(conversation.SaveConversationCommand.ExecuteAsync(null));
        var storedTitle = new TransTools.Services.Storage.ConversationStore().Load().Single(s => s.Id == saved.Id);
        if (storedTitle.Title != "Tên riêng của tôi" || !storedTitle.HasCustomTitle || storedTitle.Messages[0].Text != beforeRenameText) throw new Exception("Saving conversation overwrote custom title or messages");
        var invalidRename = notebook.RenameRecordTitleAsync(notebook.Sessions.Single(s => s.Id == saved.Id), "   "); Await(invalidRename);
        if (invalidRename.Result || saved.Title != "Tên riêng của tôi") throw new Exception("Empty rename changed source title");
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
    private static void CheckSubtitleHud(string output)
    {
        var prefs = TransTools.Services.Experience.SubtitlePreferences.Shared;
        prefs.Light = false; prefs.Side = false; prefs.ShowMascot = false; prefs.ShowContext = true; prefs.ShowNext = true; prefs.ShowOriginal = true;
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
    private static void Capture(Window window, string output, string name)
    {
        window.UpdateLayout(); var root = (FrameworkElement)window.Content;
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(root.ActualWidth), (int)Math.Ceiling(root.ActualHeight), 96, 96, PixelFormats.Pbgra32);
        // VisualBrush removes the content's layout offset; include the Window background.
        var drawing = new DrawingVisual();
        using (var context = drawing.RenderOpen()) {
            var bounds = new Rect(0, 0, root.ActualWidth, root.ActualHeight);
            context.DrawRectangle(window.Background, null, bounds);
            context.DrawRectangle(new VisualBrush(root) { Stretch = Stretch.Fill }, null, bounds);
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
