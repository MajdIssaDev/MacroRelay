using System.Windows;
using System.Windows.Input;
using MacroRelay.Core.Catalog;
using MacroRelay.Core.Models;

namespace MacroRelay.App.Views;

public partial class AddStepWindow
{
    public MacroStep? CreatedStep { get; private set; }

    public AddStepWindow()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            Refresh("");
            SearchBox.Focus();
        };
    }

    private void SearchBox_OnTextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) =>
        Refresh(SearchBox.Text);

    private void Refresh(string query)
    {
        ResultList.Items.Clear();
        foreach (var template in StepCatalog.Search(query).Take(80))
            ResultList.Items.Add(template);
        ResultList.DisplayMemberPath = nameof(StepTemplate.Name);
        if (ResultList.Items.Count > 0)
            ResultList.SelectedIndex = 0;
    }

    private void ResultList_OnMouseDoubleClick(object sender, MouseButtonEventArgs e) => Accept();

    private void Add_OnClick(object sender, RoutedEventArgs e) => Accept();

    private void Accept()
    {
        if (ResultList.SelectedItem is not StepTemplate template)
            return;
        CreatedStep = template.Create();
        DialogResult = true;
        Close();
    }
}
