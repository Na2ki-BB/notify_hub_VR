namespace NotifyHubVr;

public interface INotificationRenderer
{
    Task ShowAsync(NotificationMessage message, CancellationToken cancellationToken);
    Task HideAsync(CancellationToken cancellationToken);
}
