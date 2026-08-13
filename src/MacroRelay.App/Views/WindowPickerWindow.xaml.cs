using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using MacroRelay.Core.Windows;

namespace MacroRelay.App.Views;

public partial class WindowPickerWindow
{
    public WindowInfo? Picked { get; private set; }
    private readonly DispatcherTimer _hover = new() { Interval = TimeSpan.FromMilliseconds(80) };

    public WindowPickerWindow()
    {
        InitializeComponent();
        _hover.Tick += (_, _) => UpdateHover();
        Loaded += (_, _) =>
        {
            _hover.Start();
            MouseLeftButtonDown += OnClick;
            KeyDown += OnKey;
        };
        Closed += (_, _) => _hover.Stop();
    }

    private void UpdateHover()
    {
        var (x, y) = WindowResolver.CurrentCursor();
        var self = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        var info = WindowResolver.FromPointExcluding(x, y, self);
        HoverLabel.Text = info?.ToString() ?? "";
    }

    private void OnClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        var (x, y) = WindowResolver.CurrentCursor();
        var self = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        var info = WindowResolver.FromPointExcluding(x, y, self);
        if (info is null)
            return;
        Picked = info;
        DialogResult = true;
        Close();
    }

    private void OnKey(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            DialogResult = false;
            Close();
        }
    }
}
