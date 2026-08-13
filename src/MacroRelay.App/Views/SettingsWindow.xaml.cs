using System.Windows;
using MacroRelay.App.ViewModels;

namespace MacroRelay.App.Views;

public partial class SettingsWindow
{
    private readonly MainViewModel _vm;

    public SettingsWindow(MainViewModel vm)
    {
        _vm = vm;
        InitializeComponent();
        Loaded += (_, _) => Load();
    }

    private void Load()
    {
        var s = _vm.Settings;
        StartAllBox.Text = s.HotkeyStartAll;
        PauseAllBox.Text = s.HotkeyPauseAll;
        StopAllBox.Text = s.HotkeyStopAll;
        PanicBox.Text = s.HotkeyPanic;
        RecordBox.Text = s.HotkeyRecord;
        ThemeBox.ItemsSource = new[] { "Dark", "Light", "System" };
        ThemeBox.SelectedItem = s.Theme;
        CloseTrayBox.IsChecked = s.CloseToTray;
        StartMinBox.IsChecked = s.StartMinimized;
        StartWinBox.IsChecked = s.StartWithWindows;
        UpdateLaunchBox.IsChecked = s.CheckUpdatesOnLaunch;
        IntervalBox.Text = s.DefaultIntervalMs.ToString();
        SpeedBox.Text = s.DefaultSpeed.ToString("0.##");
        JitterBox.Text = s.DefaultJitterPercent.ToString();
        OwnerBox.Text = s.GitHubOwner;
        UpdateLabel.Text = _vm.UpdateStatus;
        AdminLabel.Text = _vm.IsAdministrator
            ? "This session is elevated. You can send input to administrator windows."
            : "Not elevated. Use this if a target app is running as Administrator.";
        AdminButton.IsEnabled = !_vm.IsAdministrator;
    }

    private void Save_OnClick(object sender, RoutedEventArgs e)
    {
        var s = _vm.Settings;
        s.HotkeyStartAll = StartAllBox.Text.Trim();
        s.HotkeyPauseAll = PauseAllBox.Text.Trim();
        s.HotkeyStopAll = StopAllBox.Text.Trim();
        s.HotkeyPanic = PanicBox.Text.Trim();
        s.HotkeyRecord = RecordBox.Text.Trim();
        s.Theme = ThemeBox.SelectedItem as string ?? "Dark";
        s.CloseToTray = CloseTrayBox.IsChecked == true;
        s.StartMinimized = StartMinBox.IsChecked == true;
        s.StartWithWindows = StartWinBox.IsChecked == true;
        s.CheckUpdatesOnLaunch = UpdateLaunchBox.IsChecked == true;
        if (int.TryParse(IntervalBox.Text, out var interval)) s.DefaultIntervalMs = interval;
        if (double.TryParse(SpeedBox.Text, out var speed)) s.DefaultSpeed = speed;
        if (int.TryParse(JitterBox.Text, out var jitter)) s.DefaultJitterPercent = jitter;
        s.GitHubOwner = OwnerBox.Text.Trim();
        _vm.PersistSettings();
        _vm.BindHotkeys();
        DialogResult = true;
        Close();
    }

    private async void CheckUpdates_OnClick(object sender, RoutedEventArgs e)
    {
        _vm.Settings.GitHubOwner = OwnerBox.Text.Trim();
        UpdateLabel.Text = "Checking…";
        await _vm.CheckUpdatesAsync(silent: false);
        UpdateLabel.Text = _vm.UpdateStatus;
    }

    private void Admin_OnClick(object sender, RoutedEventArgs e) => _vm.ToggleElevationCommand.Execute(null);
}
