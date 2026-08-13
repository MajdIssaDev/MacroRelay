using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using MacroRelay.Core.Catalog;
using MacroRelay.Core.Models;

namespace MacroRelay.App.ViewModels;

public sealed partial class StepItemViewModel : ObservableObject
{
    public StepItemViewModel(MacroStep step) => Step = step;

    public MacroStep Step { get; }

    public bool Enabled
    {
        get => Step.Enabled;
        set
        {
            if (Step.Enabled == value) return;
            Step.Enabled = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(Display));
        }
    }

    public string Display => StepCatalog.Describe(Step);

    public void Refresh() => OnPropertyChanged(nameof(Display));
}

public sealed partial class MacroItemViewModel : ObservableObject
{
    public MacroItemViewModel(MacroDefinition model)
    {
        Model = model;
        foreach (var step in model.Steps)
            Steps.Add(new StepItemViewModel(step));
    }

    public MacroDefinition Model { get; }

    public Guid Id => Model.Id;

    public ObservableCollection<StepItemViewModel> Steps { get; } = [];

    [ObservableProperty] private PlaybackState _state = PlaybackState.Stopped;

    public string StateLabel => State switch
    {
        PlaybackState.Running => "Running",
        PlaybackState.Paused => "Paused",
        _ => "Stopped"
    };

    public string Name
    {
        get => Model.Name;
        set { if (Model.Name != value) { Model.Name = value; OnPropertyChanged(); } }
    }

    public bool Enabled
    {
        get => Model.Enabled;
        set { if (Model.Enabled != value) { Model.Enabled = value; OnPropertyChanged(); } }
    }

    public string? Hotkey
    {
        get => Model.Hotkey;
        set { if (Model.Hotkey != value) { Model.Hotkey = value; OnPropertyChanged(); } }
    }

    public LoopMode LoopMode
    {
        get => Model.LoopMode;
        set { if (Model.LoopMode != value) { Model.LoopMode = value; OnPropertyChanged(); OnPropertyChanged(nameof(ShowCount)); OnPropertyChanged(nameof(ShowDuration)); } }
    }

    public bool ShowCount => LoopMode == LoopMode.Count;
    public bool ShowDuration => LoopMode == LoopMode.Duration || TimeLimitEnabled;

    public int RepeatCount
    {
        get => Model.RepeatCount;
        set { if (Model.RepeatCount != value) { Model.RepeatCount = value; OnPropertyChanged(); } }
    }

    public int DurationMs
    {
        get => Model.DurationMs;
        set { if (Model.DurationMs != value) { Model.DurationMs = value; OnPropertyChanged(); } }
    }

    public bool TimeLimitEnabled
    {
        get => Model.TimeLimitEnabled;
        set { if (Model.TimeLimitEnabled != value) { Model.TimeLimitEnabled = value; OnPropertyChanged(); OnPropertyChanged(nameof(ShowDuration)); } }
    }

    public int IntervalMs
    {
        get => Model.IntervalMs;
        set { if (Model.IntervalMs != value) { Model.IntervalMs = Math.Max(0, value); OnPropertyChanged(); } }
    }

    public double Speed
    {
        get => Model.Speed;
        set { if (Math.Abs(Model.Speed - value) > 0.001) { Model.Speed = Math.Clamp(value, 0.1, 10); OnPropertyChanged(); } }
    }

    public int JitterPercent
    {
        get => Model.JitterPercent;
        set { if (Model.JitterPercent != value) { Model.JitterPercent = Math.Clamp(value, 0, 100); OnPropertyChanged(); } }
    }

    public PlaybackMode PlaybackMode
    {
        get => Model.Target.Mode;
        set { if (Model.Target.Mode != value) { Model.Target.Mode = value; OnPropertyChanged(); } }
    }

    public string? ProcessName
    {
        get => Model.Target.ProcessName;
        set { if (Model.Target.ProcessName != value) { Model.Target.ProcessName = value; OnPropertyChanged(); OnPropertyChanged(nameof(TargetSummary)); } }
    }

    public string? TitleContains
    {
        get => Model.Target.TitleContains;
        set { if (Model.Target.TitleContains != value) { Model.Target.TitleContains = value; OnPropertyChanged(); OnPropertyChanged(nameof(TargetSummary)); } }
    }

    public string? ClassName
    {
        get => Model.Target.ClassName;
        set { if (Model.Target.ClassName != value) { Model.Target.ClassName = value; OnPropertyChanged(); } }
    }

    public int ProcessId
    {
        get => Model.Target.ProcessId ?? 0;
        set { Model.Target.ProcessId = value <= 0 ? null : value; OnPropertyChanged(); OnPropertyChanged(nameof(TargetSummary)); }
    }

    public string TargetSummary
    {
        get
        {
            if (PlaybackMode == PlaybackMode.Foreground)
                return "Foreground";
            var bits = new List<string>();
            if (!string.IsNullOrWhiteSpace(ProcessName)) bits.Add(ProcessName);
            if (!string.IsNullOrWhiteSpace(TitleContains)) bits.Add("\"" + TitleContains + "\"");
            if (ProcessId > 0) bits.Add("PID " + ProcessId);
            return bits.Count == 0 ? "No window selected" : string.Join(" · ", bits);
        }
    }

    public void SyncStepsToModel()
    {
        Model.Steps = Steps.Select(s => s.Step).ToList();
    }

    public void NotifyTarget()
    {
        OnPropertyChanged(nameof(ProcessName));
        OnPropertyChanged(nameof(TitleContains));
        OnPropertyChanged(nameof(ClassName));
        OnPropertyChanged(nameof(ProcessId));
        OnPropertyChanged(nameof(TargetSummary));
        OnPropertyChanged(nameof(PlaybackMode));
    }

    partial void OnStateChanged(PlaybackState value) => OnPropertyChanged(nameof(StateLabel));
}
