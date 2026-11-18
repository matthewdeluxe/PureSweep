using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Threading.Tasks;

namespace PureSweep.Core
{
    /// <summary>
    /// One-click fixes that reset a system cache with a command instead of deleting files. They rarely free much
    /// space; they fix glitches. Deliberately absent: "RAM cleaning", Prefetch cleaning and registry cleaning.
    /// </summary>
    public sealed class MaintenanceTask
    {
        public string Id, Title, Detail, Glyph;
        public bool NeedsAdmin;
        /// <summary>Shown in a confirmation dialog first, for tasks with a side effect worth knowing about.</summary>
        public string Confirm;
        /// <summary>Shown after it succeeds.</summary>
        public string DoneNote;
        public string File, Args;
        /// <summary>Exit codes that count as success besides 0 (DISM returns 3010 when a restart is needed).</summary>
        public int[] AlsoOk = new int[0];

        public static readonly MaintenanceTask[] All =
        {
            new MaintenanceTask
            {
                Id = "dns", Title = "Flush DNS cache", Glyph = "",
                Detail = "Forgets remembered website addresses. Helps when sites won't load after a network or DNS change.",
                File = "ipconfig.exe", Args = "/flushdns"
            },
            new MaintenanceTask
            {
                Id = "store", Title = "Reset Microsoft Store cache", Glyph = "",
                Detail = "Clears the Store's cache. Helps when apps won't download or update. The Store opens when it's done.",
                File = "wsreset.exe", Args = ""
            },
            new MaintenanceTask
            {
                Id = "fonts", Title = "Rebuild font cache", Glyph = "", NeedsAdmin = true,
                Detail = "Stops the Windows Font Cache service, deletes its cache and starts it again. Helps with garbled text or fonts that won't show up.",
                DoneNote = "Restart your PC to finish rebuilding the font cache.",
                File = "cmd.exe",
                Args = "/c net stop FontCache /y & del /f /q \"%WinDir%\\ServiceProfiles\\LocalService\\AppData\\Local\\FontCache\\*FontCache*\" & " +
                       "del /f /q \"%WinDir%\\System32\\FNTCACHE.DAT\" & net start FontCache"
            },
            new MaintenanceTask
            {
                Id = "components", Title = "Clean up Windows Update leftovers", Glyph = "", NeedsAdmin = true,
                Detail = "Removes old copies of system files that updates have replaced. Can free several GB.",
                Confirm = "This can take 10 minutes or more and keeps running in the background. Updates you've installed stay installed and can still be removed.",
                File = "Dism.exe", Args = "/Online /Cleanup-Image /StartComponentCleanup", AlsoOk = new[] { 3010 }
            },
        };

        /// <summary>Runs the task. Returns null on success, "" if the UAC prompt was declined, otherwise an error message.</summary>
        public Task<string> Run() => Task.Run(() =>
        {
            try
            {
                var psi = new ProcessStartInfo(File, Environment.ExpandEnvironmentVariables(Args))
                {
                    WindowStyle = ProcessWindowStyle.Hidden,
                    CreateNoWindow = true
                };
                if (NeedsAdmin && !Util.IsAdmin) { psi.Verb = "runas"; psi.UseShellExecute = true; }
                else { psi.UseShellExecute = false; psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; }

                using (Process p = Process.Start(psi))
                {
                    string output = psi.UseShellExecute ? "" : p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
                    p.WaitForExit();
                    if (p.ExitCode == 0 || Array.IndexOf(AlsoOk, p.ExitCode) >= 0) return null;
                    output = output.Trim();
                    return output.Length > 0 && output.Length < 300 ? output : $"It stopped with error code {p.ExitCode}.";
                }
            }
            catch (Win32Exception ex) when (ex.NativeErrorCode == 1223) { return ""; }   // UAC prompt declined
            catch (Exception ex) { return ex.Message; }
        });
    }
}
