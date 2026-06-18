namespace NotifyHubVr;

public sealed class ConsoleNotificationRenderer : INotificationRenderer
{
    public Task ShowAsync(NotificationMessage message, CancellationToken cancellationToken)
    {
        Console.WriteLine();
        Console.WriteLine("=== VR Notification Preview ===");
        if (!string.IsNullOrWhiteSpace(message.Title))
        {
            Console.WriteLine(message.Title);
        }

        Console.WriteLine(message.Body);
        Console.WriteLine($"duration_ms={message.DurationMs} sound={message.Sound}");
        Console.WriteLine("===============================");
        Console.WriteLine();

        return Task.CompletedTask;
    }

    public Task HideAsync(CancellationToken cancellationToken)
    {
        Console.WriteLine("[notification hidden]");
        return Task.CompletedTask;
    }
}
