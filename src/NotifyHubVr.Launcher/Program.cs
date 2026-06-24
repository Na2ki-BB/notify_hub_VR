using System.Diagnostics;

if (args.Length < 3)
{
    return 2;
}

var appPath = args[0];
var configPath = args[1];
var logDir = args[2];

Directory.CreateDirectory(logDir);
var launcherLogPath = Path.Combine(logDir, "startup-launch.log");
var appLogPath = Path.Combine(logDir, "notifyhub-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");

void AppendLauncherLog(string message)
{
    File.AppendAllText(
        launcherLogPath,
        $"[{DateTime.Now:O}] {message}{Environment.NewLine}");
}

try
{
    AppendLauncherLog("launcher invoked");
    AppendLauncherLog($"app_path={appPath}");
    AppendLauncherLog($"config_path={configPath}");

    if (!File.Exists(appPath))
    {
        AppendLauncherLog("app executable was not found");
        return 3;
    }

    if (!File.Exists(configPath))
    {
        AppendLauncherLog("config file was not found");
        return 4;
    }

    if (Process.GetProcessesByName("NotifyHubVr").Length > 0)
    {
        AppendLauncherLog("NotifyHubVr is already running; launch skipped");
        return 0;
    }

    using var appLog = new StreamWriter(new FileStream(appLogPath, FileMode.Append, FileAccess.Write, FileShare.Read))
    {
        AutoFlush = true
    };

    void WriteAppLog(string streamName, string? line)
    {
        if (line is null)
        {
            return;
        }

        lock (appLog)
        {
            appLog.WriteLine($"[{DateTime.Now:O}] [{streamName}] {line}");
        }
    }

    var startInfo = new ProcessStartInfo
    {
        FileName = appPath,
        WorkingDirectory = Path.GetDirectoryName(appPath) ?? AppContext.BaseDirectory,
        UseShellExecute = false,
        CreateNoWindow = true,
        RedirectStandardOutput = true,
        RedirectStandardError = true
    };
    startInfo.ArgumentList.Add(configPath);

    using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
    process.OutputDataReceived += (_, eventArgs) => WriteAppLog("out", eventArgs.Data);
    process.ErrorDataReceived += (_, eventArgs) => WriteAppLog("err", eventArgs.Data);

    if (!process.Start())
    {
        AppendLauncherLog("process start returned false");
        return 5;
    }

    AppendLauncherLog($"started NotifyHubVr pid={process.Id}");
    process.BeginOutputReadLine();
    process.BeginErrorReadLine();
    process.WaitForExit();
    AppendLauncherLog($"NotifyHubVr exited with code {process.ExitCode}");
    return process.ExitCode;
}
catch (Exception ex)
{
    AppendLauncherLog("launcher failed: " + ex);
    return 1;
}
