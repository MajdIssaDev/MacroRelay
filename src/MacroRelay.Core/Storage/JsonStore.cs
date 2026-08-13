using System.Text.Json;
using System.Text.Json.Serialization;
using MacroRelay.Core.Models;

namespace MacroRelay.Core.Storage;

public static class JsonStore
{
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static string RootDirectory { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MacroRelay");

    public static string MacrosPath => Path.Combine(RootDirectory, "macros.json");
    public static string SettingsPath => Path.Combine(RootDirectory, "settings.json");

    public static void EnsureRoot() => Directory.CreateDirectory(RootDirectory);

    public static MacroLibrary LoadMacros()
    {
        EnsureRoot();
        if (!File.Exists(MacrosPath))
            return new MacroLibrary();
        try
        {
            return JsonSerializer.Deserialize<MacroLibrary>(File.ReadAllText(MacrosPath), Options)
                   ?? new MacroLibrary();
        }
        catch
        {
            return new MacroLibrary();
        }
    }

    public static void SaveMacros(MacroLibrary library)
    {
        EnsureRoot();
        File.WriteAllText(MacrosPath, JsonSerializer.Serialize(library, Options));
    }

    public static AppSettings LoadSettings()
    {
        EnsureRoot();
        if (!File.Exists(SettingsPath))
            return new AppSettings();
        try
        {
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath), Options)
                   ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    public static void SaveSettings(AppSettings settings)
    {
        EnsureRoot();
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings, Options));
    }

    public static MacroLibrary Import(string path)
    {
        var json = File.ReadAllText(path);
        return JsonSerializer.Deserialize<MacroLibrary>(json, Options)
               ?? throw new InvalidDataException("File is not a MacroRelay library.");
    }

    public static void Export(MacroLibrary library, string path) =>
        File.WriteAllText(path, JsonSerializer.Serialize(library, Options));
}
