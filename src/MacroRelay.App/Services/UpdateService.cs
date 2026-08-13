using System.Windows;
using MacroRelay.Core.Models;
using MacroRelay.Core.Storage;
using Velopack;
using Velopack.Sources;

namespace MacroRelay.App.Services;

public sealed class UpdateService
{
    public string Status { get; private set; } = "Idle";
    public bool UpdateReady { get; private set; }
    public UpdateInfo? Pending { get; private set; }
    private UpdateManager? _manager;

    public async Task<string> CheckAsync(AppSettings settings, bool applyIfFound)
    {
        try
        {
            var owner = settings.GitHubOwner;
            var repo = string.IsNullOrWhiteSpace(settings.GitHubRepo) ? "MacroRelay" : settings.GitHubRepo;
            if (string.IsNullOrWhiteSpace(owner))
            {
                Status = "Set GitHub owner in Settings to enable updates.";
                return Status;
            }

            var source = new GithubSource($"https://github.com/{owner}/{repo}", string.Empty, false);
            _manager = new UpdateManager(source);
            if (!_manager.IsInstalled)
            {
                Status = "Updates work after installing with Setup.exe from GitHub Releases.";
                return Status;
            }

            Status = "Checking…";
            Pending = await _manager.CheckForUpdatesAsync();
            if (Pending is null)
            {
                Status = $"Up to date ({_manager.CurrentVersion})";
                UpdateReady = false;
                return Status;
            }

            Status = $"Downloading {Pending.TargetFullRelease.Version}…";
            await _manager.DownloadUpdatesAsync(Pending);
            UpdateReady = true;
            Status = $"Update {Pending.TargetFullRelease.Version} ready.";
            if (applyIfFound)
                Apply();
            return Status;
        }
        catch (Exception ex)
        {
            Status = "Update check failed: " + ex.Message;
            return Status;
        }
    }

    public void Apply()
    {
        if (_manager is null || Pending is null)
            return;
        _manager.ApplyUpdatesAndRestart(Pending);
    }

    public static void ConfirmAndApply(UpdateService service)
    {
        if (!service.UpdateReady)
            return;
        var result = System.Windows.MessageBox.Show(
            service.Status + "\n\nRestart MacroRelay now?",
            "MacroRelay update",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);
        if (result == MessageBoxResult.Yes)
            service.Apply();
    }
}
