using System.Windows;
using MacroRelay.App.Services;
using MacroRelay.App.ViewModels;
using MacroRelay.Core.Storage;
using Wpf.Ui.Appearance;

namespace MacroRelay.App;

public partial class App : System.Windows.Application
{
    public static MainViewModel ViewModel { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var settings = JsonStore.LoadSettings();
        ApplyTheme(settings.Theme);

        ViewModel = new MainViewModel(settings);
        var window = new MainWindow(ViewModel);
        MainWindow = window;

        if (settings.StartMinimized)
            ViewModel.EnsureTray();
        else
            window.Show();

        if (settings.CheckUpdatesOnLaunch)
            _ = ViewModel.CheckUpdatesAsync(silent: true);
    }

    public static void ApplyTheme(string theme)
    {
        ApplicationTheme t;
        if (theme.Equals("Light", StringComparison.OrdinalIgnoreCase))
            t = ApplicationTheme.Light;
        else if (theme.Equals("System", StringComparison.OrdinalIgnoreCase))
        {
            SystemThemeManager.UpdateSystemThemeCache();
            t = SystemThemeManager.GetCachedSystemTheme() == SystemTheme.Light
                ? ApplicationTheme.Light
                : ApplicationTheme.Dark;
        }
        else
            t = ApplicationTheme.Dark;
        ApplicationThemeManager.Apply(t);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        ViewModel.Dispose();
        base.OnExit(e);
    }
}
