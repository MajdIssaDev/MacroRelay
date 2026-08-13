using System.Threading;
using System.Windows;
using Velopack;

namespace MacroRelay.App;

internal static class Program
{
    private const string MutexName = "MacroRelay.SingleInstance.v1";

    [STAThread]
    public static void Main(string[] args)
    {
        VelopackApp.Build().Run();

        using var mutex = new Mutex(true, MutexName, out bool created);
        if (!created)
        {
            NativeBroadcast.ShowExisting();
            return;
        }

        var app = new App();
        app.InitializeComponent();
        app.Run();
    }
}

internal static class NativeBroadcast
{
    public const int WmShowMacroRelay = 0x8000 + 77;

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern IntPtr FindWindow(string? lpClassName, string lpWindowName);

    public static void ShowExisting()
    {
        var hwnd = FindWindow(null, "MacroRelay");
        if (hwnd != IntPtr.Zero)
            PostMessage(hwnd, WmShowMacroRelay, IntPtr.Zero, IntPtr.Zero);
    }
}
