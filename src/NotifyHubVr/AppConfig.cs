using System.Text.Json;
using System.Text.Json.Serialization;

namespace NotifyHubVr;

public sealed record AppConfig
{
    public string BindAddress { get; init; } = "0.0.0.0";
    public int Port { get; init; } = 17890;
    public int DefaultDurationMs { get; init; } = 5000;
    public string OverlayPosition { get; init; } = "upper-right";
    public int FontSize { get; init; } = 32;
    public bool SoundEnabled { get; init; } = false;
    public string Renderer { get; init; } = "console";

    public static AppConfig Load(string path)
    {
        if (!File.Exists(path))
        {
            return new AppConfig();
        }

        var json = File.ReadAllText(path);
        var config = JsonSerializer.Deserialize<AppConfig>(json, JsonOptions.Default);
        return config?.Validate() ?? new AppConfig();
    }

    private AppConfig Validate()
    {
        return this with
        {
            BindAddress = string.IsNullOrWhiteSpace(BindAddress) ? "0.0.0.0" : BindAddress,
            Port = Port is > 0 and <= 65535 ? Port : 17890,
            DefaultDurationMs = DefaultDurationMs > 0 ? DefaultDurationMs : 5000,
            OverlayPosition = string.IsNullOrWhiteSpace(OverlayPosition) ? "upper-right" : OverlayPosition,
            FontSize = FontSize > 0 ? FontSize : 32,
            Renderer = string.IsNullOrWhiteSpace(Renderer) ? "console" : Renderer,
        };
    }
}

internal static class JsonOptions
{
    public static readonly JsonSerializerOptions Default = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };
}
