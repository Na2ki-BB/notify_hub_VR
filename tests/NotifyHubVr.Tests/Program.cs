using NotifyHubVr;

var tests = new (string Name, Func<Task> Run)[]
{
    ("NotificationRequest.Normalize trims to two body lines", TestNormalizeBodyLines),
    ("NotificationRequest.Normalize applies defaults", TestNormalizeDefaults),
    ("NotificationDisplayService replaces visible notification", TestReplaceVisibleNotification),
    ("NotificationDisplayService hides after duration", TestHideAfterDuration),
    ("AppConfig.Load reads snake_case config", TestLoadConfig),
};

var failures = 0;

foreach (var test in tests)
{
    try
    {
        await test.Run();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception ex)
    {
        failures++;
        Console.WriteLine($"FAIL {test.Name}");
        Console.WriteLine(ex.Message);
    }
}

if (failures > 0)
{
    Console.WriteLine($"{failures} test(s) failed.");
    return 1;
}

Console.WriteLine($"{tests.Length} test(s) passed.");
return 0;

static Task TestNormalizeBodyLines()
{
    var request = new NotificationRequest
    {
        Title = "  title  ",
        Body = " line 1 \n\n line 2 \n line 3 ",
        DurationMs = 1234,
        Sound = true,
    };

    var message = request.Normalize(defaultDurationMs: 5000);

    AssertEqual("title", message.Title, "title should be trimmed");
    AssertEqual("line 1\nline 2", message.Body, "body should keep first two non-empty lines");
    AssertEqual(1234, message.DurationMs, "duration should use request value");
    AssertEqual(true, message.Sound, "sound should use request value");

    return Task.CompletedTask;
}

static Task TestNormalizeDefaults()
{
    var request = new NotificationRequest
    {
        Body = "hello",
        DurationMs = -1,
    };

    var message = request.Normalize(defaultDurationMs: 5000);

    AssertEqual("hello", message.Body, "body should be preserved");
    AssertEqual("info", message.Level, "level should default to info");
    AssertEqual(5000, message.DurationMs, "invalid duration should use default");
    AssertEqual(false, message.Sound, "sound should default to false");

    return Task.CompletedTask;
}

static async Task TestReplaceVisibleNotification()
{
    var renderer = new RecordingRenderer();
    var state = new NotificationState();
    var display = new NotificationDisplayService(renderer, state);

    var first = new NotificationMessage(null, "first", "info", 10_000, false);
    var second = new NotificationMessage(null, "second", "info", 10_000, false);

    await display.ReplaceAsync(first, CancellationToken.None);
    await display.ReplaceAsync(second, CancellationToken.None);

    AssertEqual("second", state.Current?.Body, "current notification should be replaced");
    AssertSequenceEqual(new[] { "show:first", "show:second" }, renderer.Events, "renderer should show both notifications");
}

static async Task TestHideAfterDuration()
{
    var renderer = new RecordingRenderer();
    var state = new NotificationState();
    var display = new NotificationDisplayService(renderer, state);

    await display.ReplaceAsync(new NotificationMessage(null, "short", "info", 50, false), CancellationToken.None);
    await Task.Delay(250);

    AssertEqual(null, state.Current, "current notification should be cleared after duration");
    AssertSequenceEqual(new[] { "show:short", "hide" }, renderer.Events, "renderer should hide after duration");
}

static Task TestLoadConfig()
{
    var path = Path.Combine(Path.GetTempPath(), $"notify-hub-vr-{Guid.NewGuid():N}.json");

    try
    {
        File.WriteAllText(path, """
        {
          "bind_address": "127.0.0.1",
          "port": 18000,
          "default_duration_ms": 7000,
          "overlay_position": "lower-left",
          "font_size": 44,
          "sound_enabled": true,
          "renderer": "console"
        }
        """);

        var config = AppConfig.Load(path);

        AssertEqual("127.0.0.1", config.BindAddress, "bind address should load");
        AssertEqual(18000, config.Port, "port should load");
        AssertEqual(7000, config.DefaultDurationMs, "default duration should load");
        AssertEqual("lower-left", config.OverlayPosition, "overlay position should load");
        AssertEqual(44, config.FontSize, "font size should load");
        AssertEqual(true, config.SoundEnabled, "sound setting should load");
    }
    finally
    {
        File.Delete(path);
    }

    return Task.CompletedTask;
}

static void AssertEqual<T>(T expected, T actual, string message)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"{message}. Expected: {expected}; Actual: {actual}");
    }
}

static void AssertSequenceEqual<T>(IReadOnlyList<T> expected, IReadOnlyList<T> actual, string message)
{
    if (expected.Count != actual.Count || expected.Where((item, index) => !EqualityComparer<T>.Default.Equals(item, actual[index])).Any())
    {
        throw new InvalidOperationException($"{message}. Expected: [{string.Join(", ", expected)}]; Actual: [{string.Join(", ", actual)}]");
    }
}

sealed class RecordingRenderer : INotificationRenderer
{
    public List<string> Events { get; } = [];

    public Task ShowAsync(NotificationMessage message, CancellationToken cancellationToken)
    {
        Events.Add($"show:{message.Body}");
        return Task.CompletedTask;
    }

    public Task HideAsync(CancellationToken cancellationToken)
    {
        Events.Add("hide");
        return Task.CompletedTask;
    }
}
