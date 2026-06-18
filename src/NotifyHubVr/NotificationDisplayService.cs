namespace NotifyHubVr;

public sealed class NotificationDisplayService
{
    private readonly INotificationRenderer _renderer;
    private readonly NotificationState _state;
    private readonly object _gate = new();
    private CancellationTokenSource? _currentDisplay;

    public NotificationDisplayService(INotificationRenderer renderer, NotificationState state)
    {
        _renderer = renderer;
        _state = state;
    }

    public async Task ReplaceAsync(NotificationMessage message, CancellationToken cancellationToken)
    {
        CancellationTokenSource displayCts;

        lock (_gate)
        {
            _currentDisplay?.Cancel();
            _currentDisplay?.Dispose();
            _currentDisplay = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            displayCts = _currentDisplay;
            _state.Current = message;
        }

        await _renderer.ShowAsync(message, displayCts.Token);

        _ = HideLaterAsync(message, displayCts);
    }

    private async Task HideLaterAsync(NotificationMessage message, CancellationTokenSource displayCts)
    {
        try
        {
            await Task.Delay(message.DurationMs, displayCts.Token);

            lock (_gate)
            {
                if (!ReferenceEquals(_currentDisplay, displayCts))
                {
                    return;
                }

                _state.Current = null;
                _currentDisplay = null;
            }

            await _renderer.HideAsync(CancellationToken.None);
            displayCts.Dispose();
        }
        catch (OperationCanceledException)
        {
        }
    }
}

public sealed class NotificationState
{
    public NotificationMessage? Current { get; set; }
}
