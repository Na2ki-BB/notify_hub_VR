using NotifyHubVr;
using System.Text.Json;

var configPath = args.Length > 0 ? args[0] : "config.json";
var config = AppConfig.Load(configPath);

var builder = WebApplication.CreateBuilder(args);
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower;
    options.SerializerOptions.PropertyNameCaseInsensitive = true;
});
builder.Services.AddSingleton(config);
builder.Services.AddSingleton<NotificationState>();
builder.Services.AddSingleton<INotificationRenderer, ConsoleNotificationRenderer>();
builder.Services.AddSingleton<NotificationDisplayService>();

var app = builder.Build();

app.MapGet("/", (AppConfig config) => Results.Ok(new
{
    service = "Notify Hub VR",
    endpoint = "/notify",
    config.BindAddress,
    config.Port,
    config.DefaultDurationMs,
    config.OverlayPosition,
    config.SoundEnabled,
}));

app.MapGet("/state", (NotificationState state) => Results.Ok(new
{
    current = state.Current,
}));

app.MapPost("/notify", async (
    HttpContext httpContext,
    NotificationDisplayService display,
    AppConfig config,
    CancellationToken cancellationToken) =>
{
    NotificationRequest? request;

    try
    {
        request = await httpContext.Request.ReadFromJsonAsync<NotificationRequest>(
            cancellationToken: cancellationToken);
    }
    catch
    {
        return Results.BadRequest(new { error = "Request body must be valid JSON." });
    }

    if (request is null)
    {
        return Results.BadRequest(new { error = "Request body is required." });
    }

    var normalized = request.Normalize(config.DefaultDurationMs);
    if (string.IsNullOrWhiteSpace(normalized.Body))
    {
        return Results.BadRequest(new { error = "`body` is required." });
    }

    await display.ReplaceAsync(normalized, cancellationToken);

    return Results.Accepted(value: new
    {
        accepted = true,
        normalized.Title,
        normalized.Body,
        normalized.DurationMs,
        normalized.Sound,
    });
});

var url = $"http://{config.BindAddress}:{config.Port}";
Console.WriteLine("Notify Hub VR");
Console.WriteLine($"Config: {Path.GetFullPath(configPath)}");
Console.WriteLine($"Listening: {url}");
Console.WriteLine("POST JSON to /notify, for example:");
Console.WriteLine("""{"body":"hello VR"}""");

app.Run(url);
