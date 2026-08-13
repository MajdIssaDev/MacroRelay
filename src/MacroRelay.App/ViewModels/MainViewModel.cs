using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MacroRelay.App.Services;
using MacroRelay.App.Views;
using MacroRelay.Core.Catalog;
using MacroRelay.Core.Input;
using MacroRelay.Core.Models;
using MacroRelay.Core.Playback;
using MacroRelay.Core.Recording;
using MacroRelay.Core.Storage;
using MacroRelay.Core.Windows;
using Forms = System.Windows.Forms;

namespace MacroRelay.App.ViewModels;

public sealed partial class MainViewModel : ObservableObject, IDisposable
{
    public ObservableCollection<MacroItemViewModel> Macros { get; } = [];
    public LoopMode[] LoopModes { get; } = Enum.GetValues<LoopMode>();
    public PlaybackMode[] PlaybackModes { get; } = Enum.GetValues<PlaybackMode>();

    private readonly PlaybackEngine _engine = new();
    private readonly InputRecorder _recorder = new();
    private readonly DispatcherTimer _saveTimer;
    private Forms.NotifyIcon? _tray;
    private bool _exitRequested;

    public HotkeyService Hotkeys { get; } = new();
    public UpdateService Updates { get; } = new();
    public AppSettings Settings { get; }

    [ObservableProperty] private MacroItemViewModel? _selected;
    [ObservableProperty] private StepItemViewModel? _selectedStep;
    [ObservableProperty] private bool _isRecording;
    [ObservableProperty] private bool _keepDelays = true;
    [ObservableProperty] private string _statusText = "Ready";
    [ObservableProperty] private string _updateStatus = "";
    [ObservableProperty] private int _runningCount;
    [ObservableProperty] private bool _advancedTarget;

    public string Version => "1.0.0";
    public bool IsAdministrator => ElevationService.IsAdministrator();
    public string ElevationLabel => IsAdministrator ? "Running as Administrator" : "Run as Administrator";

    public MainViewModel(AppSettings settings)
    {
        Settings = settings;
        _engine.StateChanged += OnEngineState;
        _engine.PasteText = PasteOnUiThread;
        _recorder.StepCaptured += OnRecordedStep;
        foreach (var macro in JsonStore.LoadMacros().Macros)
            Macros.Add(new MacroItemViewModel(macro));
        if (Macros.Count > 0)
            Selected = Macros[0];
        _saveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _saveTimer.Tick += (_, _) => { _saveTimer.Stop(); Persist(); };
        StatusText = Macros.Count == 0 ? "Add a macro to get started." : "Ready";
    }

    public void AttachWindow(Window window)
    {
        Hotkeys.Attach(window);
        BindHotkeys();
        window.Closing += OnMainClosing;
    }

    public void BindHotkeys()
    {
        Hotkeys.Clear();
        Hotkeys.TryRegister(Settings.HotkeyStartAll, () => Dispatch(StartAll));
        Hotkeys.TryRegister(Settings.HotkeyPauseAll, () => Dispatch(PauseAll));
        Hotkeys.TryRegister(Settings.HotkeyStopAll, () => Dispatch(StopAll));
        Hotkeys.TryRegister(Settings.HotkeyPanic, () => Dispatch(Panic));
        Hotkeys.TryRegister(Settings.HotkeyRecord, () => Dispatch(ToggleRecord));
        foreach (var macro in Macros)
        {
            var item = macro;
            Hotkeys.TryRegister(item.Hotkey, () => Dispatch(() => ToggleMacro(item)));
        }
        _recorder.IgnoreKeys.Clear();
        foreach (var key in Hotkeys.RegisteredKeys)
            _recorder.IgnoreKeys.Add(key);
    }

    private static void Dispatch(Action action) =>
        System.Windows.Application.Current.Dispatcher.BeginInvoke(action);

    [RelayCommand]
    private void AddMacro()
    {
        var item = new MacroItemViewModel(new MacroDefinition
        {
            Name = $"Macro {Macros.Count + 1}",
            IntervalMs = Settings.DefaultIntervalMs,
            Speed = Settings.DefaultSpeed,
            JitterPercent = Settings.DefaultJitterPercent
        });
        Macros.Add(item);
        Selected = item;
        QueueSave();
        BindHotkeys();
    }

    [RelayCommand]
    private void DuplicateMacro()
    {
        if (Selected is null) return;
        Selected.SyncStepsToModel();
        var json = System.Text.Json.JsonSerializer.Serialize(Selected.Model, JsonStore.Options);
        var copy = System.Text.Json.JsonSerializer.Deserialize<MacroDefinition>(json, JsonStore.Options)!;
        copy.Id = Guid.NewGuid();
        copy.Name += " copy";
        foreach (var step in copy.Steps)
            step.Id = Guid.NewGuid();
        var item = new MacroItemViewModel(copy);
        Macros.Add(item);
        Selected = item;
        QueueSave();
    }

    [RelayCommand]
    private void DeleteMacro()
    {
        if (Selected is null) return;
        _engine.Stop(Selected.Id);
        var index = Macros.IndexOf(Selected);
        Macros.Remove(Selected);
        Selected = Macros.Count == 0 ? null : Macros[Math.Clamp(index, 0, Macros.Count - 1)];
        QueueSave();
        BindHotkeys();
    }

    [RelayCommand]
    private void StartSelected()
    {
        if (Selected is { Enabled: true })
            Play(Selected);
    }

    [RelayCommand]
    private void PauseSelected()
    {
        if (Selected is not null)
            _engine.Pause(Selected.Id);
    }

    [RelayCommand]
    private void StopSelected()
    {
        if (Selected is not null)
            _engine.Stop(Selected.Id);
    }

    [RelayCommand]
    private void StartAll()
    {
        foreach (var macro in Macros.Where(m => m.Enabled))
            Play(macro);
        StatusText = "Started enabled macros.";
    }

    [RelayCommand]
    private void PauseAll()
    {
        _engine.PauseAll();
        StatusText = "Paused.";
    }

    [RelayCommand]
    private void StopAll()
    {
        _engine.StopAll();
        StatusText = "Stopped.";
    }

    [RelayCommand]
    private void Panic()
    {
        _engine.StopAll();
        if (IsRecording)
            ToggleRecord();
        StatusText = "Panic — all input stopped.";
    }

    [RelayCommand]
    private void ToggleRecord()
    {
        if (Selected is null)
        {
            StatusText = "Select a macro before recording.";
            return;
        }
        if (IsRecording)
        {
            _recorder.Stop();
            IsRecording = false;
            StatusText = "Recording stopped.";
            QueueSave();
            return;
        }
        _recorder.KeepDelays = KeepDelays;
        _recorder.IgnoreKeys.Clear();
        foreach (var key in Hotkeys.RegisteredKeys)
            _recorder.IgnoreKeys.Add(key);
        _recorder.Start();
        IsRecording = true;
        StatusText = KeepDelays ? "Recording (with delays)…" : "Recording (no delays)…";
    }

    [RelayCommand]
    private void AddStepFromPalette()
    {
        if (Selected is null) return;
        var win = new AddStepWindow { Owner = System.Windows.Application.Current.MainWindow };
        if (win.ShowDialog() == true && win.CreatedStep is not null)
            InsertStep(win.CreatedStep);
    }

    public void AddStepFromTemplate(StepTemplate template)
    {
        if (Selected is null) return;
        var step = template.Create();
        if (NeedsEdit(step))
        {
            var editor = new EditStepWindow(step) { Owner = System.Windows.Application.Current.MainWindow };
            if (editor.ShowDialog() != true)
                return;
        }
        InsertStep(step);
    }

    [RelayCommand]
    private void EditStep()
    {
        if (SelectedStep is null) return;
        var editor = new EditStepWindow(SelectedStep.Step) { Owner = System.Windows.Application.Current.MainWindow };
        if (editor.ShowDialog() == true)
        {
            SelectedStep.Refresh();
            QueueSave();
        }
    }

    [RelayCommand]
    private void DeleteStep()
    {
        if (Selected is null || SelectedStep is null) return;
        var index = Selected.Steps.IndexOf(SelectedStep);
        Selected.Steps.Remove(SelectedStep);
        Selected.SyncStepsToModel();
        SelectedStep = Selected.Steps.Count == 0 ? null : Selected.Steps[Math.Clamp(index, 0, Selected.Steps.Count - 1)];
        QueueSave();
    }

    [RelayCommand]
    private void MoveStepUp() => MoveStep(-1);

    [RelayCommand]
    private void MoveStepDown() => MoveStep(1);

    [RelayCommand]
    private void PickWindow()
    {
        if (Selected is null) return;
        var picker = new WindowPickerWindow { Owner = System.Windows.Application.Current.MainWindow };
        if (picker.ShowDialog() == true && picker.Picked is { } info)
        {
            Selected.Model.Target.ProcessName = info.ProcessName;
            Selected.Model.Target.TitleContains = info.Title;
            Selected.Model.Target.ClassName = info.ClassName;
            Selected.Model.Target.ProcessId = info.ProcessId;
            if (Selected.PlaybackMode == PlaybackMode.Foreground)
                Selected.PlaybackMode = PlaybackMode.FocusTarget;
            Selected.NotifyTarget();
            StatusText = "Target: " + info;
            QueueSave();
        }
    }

    [RelayCommand]
    private void ClearWindow()
    {
        if (Selected is null) return;
        Selected.Model.Target.ProcessName = null;
        Selected.Model.Target.TitleContains = null;
        Selected.Model.Target.ClassName = null;
        Selected.Model.Target.ProcessId = null;
        Selected.PlaybackMode = PlaybackMode.Foreground;
        Selected.NotifyTarget();
        QueueSave();
    }

    [RelayCommand]
    private void OpenSettings()
    {
        var win = new SettingsWindow(this) { Owner = System.Windows.Application.Current.MainWindow };
        win.ShowDialog();
        BindHotkeys();
        PersistSettings();
    }

    [RelayCommand]
    private void ImportMacros()
    {
        var dlg = new Microsoft.Win32.OpenFileDialog
        {
            Filter = "MacroRelay JSON|*.json",
            Title = "Import macros"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var lib = JsonStore.Import(dlg.FileName);
            foreach (var macro in lib.Macros)
            {
                macro.Id = Guid.NewGuid();
                Macros.Add(new MacroItemViewModel(macro));
            }
            QueueSave();
            StatusText = $"Imported {lib.Macros.Count} macro(s).";
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show(ex.Message, "Import failed");
        }
    }

    [RelayCommand]
    private void ExportMacros()
    {
        var dlg = new Microsoft.Win32.SaveFileDialog
        {
            Filter = "MacroRelay JSON|*.json",
            FileName = "macros.json"
        };
        if (dlg.ShowDialog() != true) return;
        Persist();
        JsonStore.Export(new MacroLibrary { Macros = Macros.Select(m => m.Model).ToList() }, dlg.FileName);
        StatusText = "Exported macros.";
    }

    [RelayCommand]
    private async Task CheckUpdates()
    {
        UpdateStatus = "Checking for updates…";
        var result = await Updates.CheckAsync(Settings, applyIfFound: false);
        UpdateStatus = result;
        StatusText = result;
        if (Updates.UpdateReady)
            UpdateService.ConfirmAndApply(Updates);
    }

    public async Task CheckUpdatesAsync(bool silent)
    {
        var result = await Updates.CheckAsync(Settings, applyIfFound: false);
        UpdateStatus = result;
        if (!silent)
            StatusText = result;
        if (Updates.UpdateReady)
            Dispatch(() => UpdateService.ConfirmAndApply(Updates));
    }

    [RelayCommand]
    private void ToggleElevation()
    {
        if (IsAdministrator) return;
        ElevationService.RelaunchElevated();
    }

    [RelayCommand]
    private void HideToTray()
    {
        EnsureTray();
        System.Windows.Application.Current.MainWindow?.Hide();
    }

    [RelayCommand]
    private void Exit()
    {
        _exitRequested = true;
        System.Windows.Application.Current.Shutdown();
    }

    public void EnsureTray()
    {
        if (_tray is not null) return;
        _tray = new Forms.NotifyIcon
        {
            Visible = true,
            Text = "MacroRelay",
            Icon = System.Drawing.SystemIcons.Application,
            ContextMenuStrip = new Forms.ContextMenuStrip()
        };
        _tray.ContextMenuStrip.Items.Add("Open", null, (_, _) => ShowMain());
        _tray.ContextMenuStrip.Items.Add("Start all", null, (_, _) => Dispatch(StartAll));
        _tray.ContextMenuStrip.Items.Add("Stop all", null, (_, _) => Dispatch(StopAll));
        _tray.ContextMenuStrip.Items.Add("Exit", null, (_, _) => Dispatch(Exit));
        _tray.DoubleClick += (_, _) => ShowMain();
    }

    public void PersistSettings()
    {
        StartupService.SetStartWithWindows(Settings.StartWithWindows);
        JsonStore.SaveSettings(Settings);
        App.ApplyTheme(Settings.Theme);
        OnPropertyChanged(nameof(IsAdministrator));
        OnPropertyChanged(nameof(ElevationLabel));
    }

    public IEnumerable<IGrouping<string, StepTemplate>> StepMenu =>
        StepCatalog.All.GroupBy(t => t.Category);

    public void QueueSave()
    {
        _saveTimer.Stop();
        _saveTimer.Start();
    }

    public void Dispose()
    {
        _recorder.Dispose();
        _engine.Dispose();
        Hotkeys.Dispose();
        if (_tray is not null)
        {
            _tray.Visible = false;
            _tray.Dispose();
        }
        Persist();
        PersistSettings();
    }

    private void Play(MacroItemViewModel item)
    {
        item.SyncStepsToModel();
        if (item.Model.Steps.All(s => !s.Enabled))
        {
            StatusText = "Macro has no enabled steps.";
            return;
        }
        _engine.Start(item.Model);
    }

    private void ToggleMacro(MacroItemViewModel item)
    {
        if (item.State == PlaybackState.Running)
            _engine.Pause(item.Id);
        else
            Play(item);
    }

    private void InsertStep(MacroStep step)
    {
        if (Selected is null) return;
        int index = SelectedStep is null ? Selected.Steps.Count : Selected.Steps.IndexOf(SelectedStep) + 1;
        var vm = new StepItemViewModel(step);
        Selected.Steps.Insert(Math.Clamp(index, 0, Selected.Steps.Count), vm);
        Selected.SyncStepsToModel();
        SelectedStep = vm;
        QueueSave();
    }

    private void MoveStep(int delta)
    {
        if (Selected is null || SelectedStep is null) return;
        int index = Selected.Steps.IndexOf(SelectedStep);
        int next = index + delta;
        if (next < 0 || next >= Selected.Steps.Count) return;
        Selected.Steps.Move(index, next);
        Selected.SyncStepsToModel();
        QueueSave();
    }

    private void OnRecordedStep(MacroStep step)
    {
        Dispatch(() =>
        {
            if (Selected is null) return;
            ConvertRecordedCoordinates(step);
            Selected.Steps.Add(new StepItemViewModel(step));
            Selected.SyncStepsToModel();
        });
    }

    private void ConvertRecordedCoordinates(MacroStep step)
    {
        if (step.Type != StepType.Mouse || Selected is null)
            return;
        if (Selected.PlaybackMode == PlaybackMode.Foreground)
            return;
        var info = WindowResolver.Resolve(Selected.Model.Target);
        if (info is null || step.X is null || step.Y is null)
            return;
        var (cx, cy) = WindowResolver.ToClient(info.Handle, step.X.Value, step.Y.Value);
        step.X = cx;
        step.Y = cy;
        step.CoordinateMode = CoordinateMode.WindowClient;
    }

    private void OnEngineState(Guid id, PlaybackState state)
    {
        Dispatch(() =>
        {
            var item = Macros.FirstOrDefault(m => m.Id == id);
            if (item is not null)
                item.State = state;
            RunningCount = Macros.Count(m => m.State == PlaybackState.Running);
            StatusText = RunningCount == 0 ? "Ready" : $"{RunningCount} macro(s) running";
        });
    }

    private void OnMainClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (!_exitRequested && Settings.CloseToTray)
        {
            e.Cancel = true;
            HideToTray();
        }
    }

    private void ShowMain()
    {
        var w = System.Windows.Application.Current.MainWindow;
        if (w is null) return;
        w.Show();
        w.WindowState = WindowState.Normal;
        w.Activate();
    }

    private void Persist()
    {
        foreach (var macro in Macros)
            macro.SyncStepsToModel();
        JsonStore.SaveMacros(new MacroLibrary { Macros = Macros.Select(m => m.Model).ToList() });
        BindHotkeys();
    }

    private static void PasteOnUiThread(string text)
    {
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            string? previous = System.Windows.Clipboard.ContainsText() ? System.Windows.Clipboard.GetText() : null;
            System.Windows.Clipboard.SetText(text);
            InputSender.SendKey(0x11, false);
            InputSender.SendKey(0x56, false);
            InputSender.SendKey(0x56, true);
            InputSender.SendKey(0x11, true);
            if (previous is not null)
                System.Windows.Clipboard.SetText(previous);
            else
                System.Windows.Clipboard.Clear();
        });
    }

    private static bool NeedsEdit(MacroStep step) =>
        step.Type is StepType.Text or StepType.Delay
        || (step.Type == StepType.Key && step.KeyStroke != KeyStroke.Tap)
        || (step.Type == StepType.Mouse && step.MouseStroke is MouseStroke.Move or MouseStroke.Wheel);
}
