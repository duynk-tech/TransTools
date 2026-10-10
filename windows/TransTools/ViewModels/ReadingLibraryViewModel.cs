using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Services.Reading;
namespace TransTools.ViewModels;
public partial class ReadingLibraryViewModel : ObservableObject, IDisposable
{
    private readonly ReadingLibrary _library;
    private CancellationTokenSource? _request;
    private bool _online;
    public ObservableCollection<ReadingStory> Stories { get; } = new(ReadingLibrary.Catalog);
    public ObservableCollection<ReadingPart> Parts { get; } = new();
    public ICollectionView StoriesView { get; }
    [ObservableProperty] private string _query = "";
    [ObservableProperty] private string _languageFilter = "all";
    [ObservableProperty] private string _status = "Tải truyện cần Internet. Tên và link nguồn được giữ để bạn xem bản gốc.";
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanUsePart))] private bool _isBusy;
    [ObservableProperty] private ReadingStory? _selectedStory;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(PreviewText), nameof(CanUsePart))] private ReadingPart? _selectedPart;
    public string PreviewText => SelectedPart?.Text ?? "";
    public bool CanUsePart => !IsBusy && SelectedStory != null && SelectedPart != null;
    public ReadingLibraryViewModel(ReadingLibrary? library = null)
    {
        _library = library ?? new(); StoriesView = CollectionViewSource.GetDefaultView(Stories);
        StoriesView.Filter = item => item is ReadingStory story && (LanguageFilter == "all" || story.Language == LanguageFilter) && (_online || string.IsNullOrWhiteSpace(Query) || story.Title.Contains(Query, StringComparison.CurrentCultureIgnoreCase));
    }
    partial void OnQueryChanged(string value) => StoriesView.Refresh();
    partial void OnLanguageFilterChanged(string value)
    {
        _request?.Cancel(); IsBusy = false; StoriesView.Refresh();
    }
    [RelayCommand] private void Suggestions()
    {
        _request?.Cancel(); _online = false; IsBusy = false; Query = "";
        Stories.Clear(); foreach (var item in ReadingLibrary.Catalog) Stories.Add(item); StoriesView.Refresh(); Status = "Truyện gợi ý";
    }
    [RelayCommand] public async Task SearchAsync()
    {
        if (string.IsNullOrWhiteSpace(Query)) return;
        var request = BeginRequest(); Status = "Đang tìm trên Wikisource…";
        try {
            var stories = await _library.SearchAsync(Query.Trim(), LanguageFilter, request.Token);
            request.Token.ThrowIfCancellationRequested(); _online = true; Stories.Clear(); foreach (var item in stories) Stories.Add(item);
            StoriesView.Refresh(); Status = stories.Count == 0 ? "Không tìm thấy nội dung phù hợp." : $"{stories.Count} kết quả từ Wikisource";
        } catch (OperationCanceledException) { }
        catch (Exception) { if (!request.IsCancellationRequested) Status = "Chưa tìm được truyện. Bạn có thể thử lại hoặc chọn truyện gợi ý."; }
        finally { EndRequest(request); }
    }
    [RelayCommand] public async Task LoadStoryAsync(ReadingStory? story)
    {
        if (story == null) return;
        var request = BeginRequest(); SelectedStory = null; SelectedPart = null; Parts.Clear(); Status = "Đang tải nội dung…";
        try {
            var parts = await _library.LoadAsync(story, request.Token); request.Token.ThrowIfCancellationRequested();
            SelectedStory = story; foreach (var part in parts) Parts.Add(part); SelectedPart = Parts.FirstOrDefault();
            OnPropertyChanged(nameof(CanUsePart)); Status = "Chọn phần đọc rồi bấm Dùng phần này. Nội dung cũ chưa bị thay đổi.";
        } catch (OperationCanceledException) { }
        catch (Exception ex) { if (!request.IsCancellationRequested) Status = "Chưa tải được truyện. Bạn có thể mở nguồn hoặc thử lại. " + ex.Message; }
        finally { EndRequest(request); }
    }
    private CancellationTokenSource BeginRequest()
    {
        _request?.Cancel(); var request = new CancellationTokenSource(); _request = request; IsBusy = true; return request;
    }
    private void EndRequest(CancellationTokenSource request)
    {
        if (ReferenceEquals(_request, request)) { _request = null; IsBusy = false; }
        request.Dispose();
    }
    public void Dispose() { _request?.Cancel(); }
}
