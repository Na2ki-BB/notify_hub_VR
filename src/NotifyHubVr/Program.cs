using NotifyHubVr;

var configPath = args.Length > 0 ? args[0] : "config.json";
var config = AppConfig.Load(configPath);

var builder = NotifyHubWebApplication.CreateBuilder(args, config);
var app = NotifyHubWebApplication.Build(builder);

var url = $"http://{config.BindAddress}:{config.Port}";
Console.WriteLine("Notify Hub VR");
Console.WriteLine($"Config: {Path.GetFullPath(configPath)}");
Console.WriteLine($"Listening: {url}");
Console.WriteLine("POST JSON to /notify, for example:");
Console.WriteLine("""{"body":"hello VR"}""");

app.Run(url);
