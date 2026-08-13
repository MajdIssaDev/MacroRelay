using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using Microsoft.Win32;

namespace MacroRelay.App.Services;

public static class ElevationService
{
    public static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    public static void RelaunchElevated()
    {
        var exe = Environment.ProcessPath ?? Assembly.GetEntryAssembly()?.Location;
        if (string.IsNullOrWhiteSpace(exe))
            return;
        var start = new ProcessStartInfo(exe)
        {
            UseShellExecute = true,
            Verb = "runas"
        };
        Process.Start(start);
        System.Windows.Application.Current.Shutdown();
    }
}

public static class StartupService
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "MacroRelay";

    public static void SetStartWithWindows(bool enabled)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
                        ?? Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled)
        {
            var exe = Environment.ProcessPath;
            if (!string.IsNullOrWhiteSpace(exe))
                key.SetValue(ValueName, $"\"{exe}\"");
        }
        else if (key.GetValue(ValueName) is not null)
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }
}
