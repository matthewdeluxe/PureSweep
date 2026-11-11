using System;
using System.IO;
using System.Reflection;
using System.Windows;
using PureSweep.Core;

[assembly: AssemblyTitle("PureSweep")]
[assembly: AssemblyProduct("PureSweep")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: ThemeInfo(ResourceDictionaryLocation.None, ResourceDictionaryLocation.SourceAssembly)]

namespace PureSweep
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            DispatcherUnhandledException += (s, a) =>
            {
                try { File.WriteAllText(Path.Combine(AppSettings.Folder, "crash.log"), a.Exception.ToString()); } catch { }
                MessageBox.Show(a.Exception.Message, "PureSweep", MessageBoxButton.OK, MessageBoxImage.Error);
                a.Handled = true;
            };
            AppSettings.Load();
            AppSettings.Apply();
            base.OnStartup(e);
        }
    }
}
