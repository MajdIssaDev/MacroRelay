using System.Windows;
using MacroRelay.Core.Input;
using MacroRelay.Core.Models;

namespace MacroRelay.App.Views;

public partial class EditStepWindow
{
    private readonly MacroStep _step;

    public EditStepWindow(MacroStep step)
    {
        _step = step;
        InitializeComponent();
        Loaded += (_, _) => Load();
    }

    private void Load()
    {
        TypeLabel.Text = _step.Type.ToString();
        EnabledBox.IsChecked = _step.Enabled;
        switch (_step.Type)
        {
            case StepType.Key:
                KeyPanel.Visibility = Visibility.Visible;
                foreach (var key in KeyCatalog.CommonKeys)
                    KeyBox.Items.Add(key);
                KeyBox.Text = _step.Key ?? "A";
                KeyStrokeBox.ItemsSource = Enum.GetValues<KeyStroke>();
                KeyStrokeBox.SelectedItem = _step.KeyStroke;
                ModsBox.Text = string.Join("+", _step.Modifiers);
                break;
            case StepType.Mouse:
                MousePanel.Visibility = Visibility.Visible;
                MouseButtonBox.ItemsSource = Enum.GetValues<MouseButtonKind>();
                MouseButtonBox.SelectedItem = _step.MouseButton;
                MouseStrokeBox.ItemsSource = Enum.GetValues<MouseStroke>();
                MouseStrokeBox.SelectedItem = _step.MouseStroke;
                CoordBox.ItemsSource = Enum.GetValues<CoordinateMode>();
                CoordBox.SelectedItem = _step.CoordinateMode;
                XBox.Text = _step.X?.ToString() ?? "0";
                YBox.Text = _step.Y?.ToString() ?? "0";
                WheelBox.Text = _step.WheelDelta.ToString();
                break;
            case StepType.Delay:
                DelayPanel.Visibility = Visibility.Visible;
                DelayBox.Text = _step.DelayMs.ToString();
                break;
            case StepType.Text:
                TextPanel.Visibility = Visibility.Visible;
                TextMethodBox.ItemsSource = Enum.GetValues<TextMethod>();
                TextMethodBox.SelectedItem = _step.TextMethod;
                BodyTextBox.Text = _step.Text ?? "";
                break;
        }
    }

    private void Save_OnClick(object sender, RoutedEventArgs e)
    {
        _step.Enabled = EnabledBox.IsChecked == true;
        switch (_step.Type)
        {
            case StepType.Key:
                _step.Key = KeyBox.Text.Trim();
                if (KeyStrokeBox.SelectedItem is KeyStroke ks) _step.KeyStroke = ks;
                _step.Modifiers = ModsBox.Text
                    .Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
                    .ToList();
                break;
            case StepType.Mouse:
                if (MouseButtonBox.SelectedItem is MouseButtonKind mb) _step.MouseButton = mb;
                if (MouseStrokeBox.SelectedItem is MouseStroke ms) _step.MouseStroke = ms;
                if (CoordBox.SelectedItem is CoordinateMode cm) _step.CoordinateMode = cm;
                _step.X = int.TryParse(XBox.Text, out var x) ? x : 0;
                _step.Y = int.TryParse(YBox.Text, out var y) ? y : 0;
                _step.WheelDelta = int.TryParse(WheelBox.Text, out var w) ? w : 0;
                break;
            case StepType.Delay:
                _step.DelayMs = int.TryParse(DelayBox.Text, out var d) ? Math.Max(0, d) : 0;
                break;
            case StepType.Text:
                if (TextMethodBox.SelectedItem is TextMethod tm) _step.TextMethod = tm;
                _step.Text = BodyTextBox.Text;
                break;
        }
        DialogResult = true;
        Close();
    }
}
