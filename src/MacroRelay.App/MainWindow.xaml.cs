using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using MacroRelay.App.ViewModels;
using MacroRelay.Core.Catalog;

namespace MacroRelay.App;

public partial class MainWindow
{
    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
        viewModel.AttachWindow(this);
        BuildStepMenu();
        Loaded += (_, _) => viewModel.QueueSave();
    }

    private void StepList_OnMouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (DataContext is MainViewModel vm)
            vm.EditStepCommand.Execute(null);
    }

    private void BuildStepMenu()
    {
        StepContextMenu.Items.Clear();
        var add = new MenuItem { Header = "Add step…" };
        add.Click += (_, _) => (DataContext as MainViewModel)?.AddStepFromPaletteCommand.Execute(null);
        StepContextMenu.Items.Add(add);
        StepContextMenu.Items.Add(new Separator());

        foreach (var group in StepCatalog.All.GroupBy(t => t.Category))
        {
            var category = new MenuItem { Header = group.Key };
            if (group.Key == "Keyboard")
            {
                AddSearchableKeys(category, group);
            }
            else
            {
                foreach (var template in group)
                {
                    var item = new MenuItem { Header = template.Name, Tag = template };
                    item.Click += OnTemplateClick;
                    category.Items.Add(item);
                }
            }
            StepContextMenu.Items.Add(category);
        }

        StepContextMenu.Items.Add(new Separator());
        var edit = new MenuItem { Header = "Edit" };
        edit.Click += (_, _) => (DataContext as MainViewModel)?.EditStepCommand.Execute(null);
        var del = new MenuItem { Header = "Delete" };
        del.Click += (_, _) => (DataContext as MainViewModel)?.DeleteStepCommand.Execute(null);
        StepContextMenu.Items.Add(edit);
        StepContextMenu.Items.Add(del);
    }

    private static void AddSearchableKeys(MenuItem category, IGrouping<string, StepTemplate> group)
    {
        var searchItem = new MenuItem { StaysOpenOnClick = true };
        var box = new System.Windows.Controls.TextBox { MinWidth = 180, Margin = new Thickness(4) };
        searchItem.Header = box;
        category.Items.Add(searchItem);
        category.Items.Add(new Separator());

        var templates = group.ToList();
        void Refresh()
        {
            while (category.Items.Count > 2)
                category.Items.RemoveAt(2);
            foreach (var template in StepCatalog.Search(box.Text).Where(t => t.Category == "Keyboard").Take(40))
            {
                var item = new MenuItem { Header = template.Name, Tag = template };
                item.Click += OnTemplateClick;
                category.Items.Add(item);
            }
        }
        box.TextChanged += (_, _) => Refresh();
        foreach (var template in templates.Take(40))
        {
            var item = new MenuItem { Header = template.Name, Tag = template };
            item.Click += OnTemplateClick;
            category.Items.Add(item);
        }
    }

    private static void OnTemplateClick(object sender, RoutedEventArgs e)
    {
        if (sender is MenuItem { Tag: StepTemplate template }
            && System.Windows.Application.Current.MainWindow?.DataContext is MainViewModel vm)
        {
            vm.AddStepFromTemplate(template);
        }
    }
}
