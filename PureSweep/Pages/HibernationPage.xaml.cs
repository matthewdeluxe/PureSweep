using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class HibernationPage : UserControl
    {
        bool _enabled;

        public HibernationPage()
        {
            InitializeComponent();
            Refresh();
        }

        void Refresh()
        {
            long size = Util.HibernationFileSize();

            try
            {
                using (RegistryKey k = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Power"))
                    _enabled = Convert.ToInt32(k?.GetValue("HibernateEnabled", 0)) == 1;
            }
            catch { _enabled = size > 0; }

            StateText.Text = _enabled ? "Hibernation is on" : "Hibernation is off";
            SizeText.Text = size > 0 ? $"hiberfil.sys is using {Util.Size(size)}."
                          : _enabled ? "The size of hiberfil.sys couldn't be read."
                          : "No disk space is reserved.";
            ToggleBtn.Content = _enabled ? "Turn off hibernation" : "Turn on hibernation";
        }

        async void Toggle_Click(object sender, RoutedEventArgs e)
        {
            if (_enabled && !await Util.Confirm("Turn off hibernation?",
                "The Hibernate option and Fast Startup will no longer be available until you turn it back on.", "Turn off"))
                return;
            try
            {
                ToggleBtn.IsEnabled = false;
                Process p = Process.Start(new ProcessStartInfo("powercfg.exe", "/hibernate " + (_enabled ? "off" : "on"))
                {
                    Verb = "runas",
                    UseShellExecute = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                });
                await Task.Run(() => p.WaitForExit());
            }
            catch (Win32Exception) { /* UAC prompt declined */ }
            finally
            {
                ToggleBtn.IsEnabled = true;
                Refresh();
            }
        }
    }
}
