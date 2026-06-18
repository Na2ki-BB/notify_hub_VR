namespace NotifyHubVr;

public sealed record NotificationRequest
{
    public string? Title { get; init; }
    public string? Body { get; init; }
    public string? Level { get; init; }
    public int? DurationMs { get; init; }
    public bool? Sound { get; init; }

    public NotificationMessage Normalize(int defaultDurationMs)
    {
        return new NotificationMessage(
            TrimToNull(Title),
            NormalizeBody(Body),
            TrimToNull(Level) ?? "info",
            DurationMs is > 0 ? DurationMs.Value : defaultDurationMs,
            Sound ?? false);
    }

    private static string? TrimToNull(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrEmpty(trimmed) ? null : trimmed;
    }

    private static string NormalizeBody(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var lines = value
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Take(2);

        return string.Join('\n', lines);
    }
}

public sealed record NotificationMessage(
    string? Title,
    string Body,
    string Level,
    int DurationMs,
    bool Sound);
