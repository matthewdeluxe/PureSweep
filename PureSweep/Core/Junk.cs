using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;

namespace PureSweep.Core
{
    public class JunkRoot
    {
        public string Path;             // may contain %ENV% variables and * directory segments
        public string Pattern;
        public bool Recurse;
        public string Label;            // drill-down group name; null = group by top-level subfolder
        public JunkRoot(string path, string pattern = "*", bool recurse = true, string label = null)
        { Path = path; Pattern = pattern; Recurse = recurse; Label = label; }
    }

    /// <summary>One line in a category's drill-down list: a set of files that can be kept or cleaned together.</summary>
    public class JunkGroup : INotifyPropertyChanged
    {
        public string Name { get; set; }
        public string Location { get; set; }
        public long Bytes;
        public int Files;
        internal readonly List<string> Found = new List<string>();
        internal JunkCategory Owner;
        bool _checked = true;

        public event PropertyChangedEventHandler PropertyChanged;

        public bool IsChecked
        {
            get => _checked;
            set
            {
                if (_checked == value) return;
                _checked = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsChecked)));
                Owner?.GroupChanged();
            }
        }
        public string SizeText => Util.Size(Bytes);
        public string DetailText => Files == 1 ? "1 item" : $"{Files:N0} items";
    }

    public class JunkCategory : INotifyPropertyChanged
    {
        const int MaxGroups = 40;

        public string Name { get; set; }
        public string Description { get; set; }
        public string Glyph { get; set; }
        public string Color { get; set; } = "#0078D4";
        public Brush Tint => (Brush)new BrushConverter().ConvertFromString(Color);
        public bool NeedsAdmin;
        public bool AgeGuard;           // skip files modified in the last 24 hours (they may be in use)
        public bool IsRecycleBin;
        public List<JunkRoot> Roots = new List<JunkRoot>();

        bool _checked = true, _scanned, _expanded, _bulk;
        long _bytes;
        int _files;
        List<JunkGroup> _groups = new List<JunkGroup>();
        List<string> _pruneDirs = new List<string>();

        public event PropertyChangedEventHandler PropertyChanged;
        void Raise(params string[] names) { foreach (string n in names) PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n)); }

        public IReadOnlyList<JunkGroup> Groups => _groups;

        /// <summary>true = everything, false = nothing, null = some of the drill-down groups.</summary>
        public bool? IsChecked
        {
            get
            {
                if (_groups.Count == 0) return _checked;
                int n = _groups.Count(g => g.IsChecked);
                return n == 0 ? false : n == _groups.Count ? true : (bool?)null;
            }
            set
            {
                _checked = value == true;
                _bulk = true;
                foreach (JunkGroup g in _groups) g.IsChecked = _checked;
                _bulk = false;
                Raise(nameof(IsChecked), nameof(SelectedBytes));
            }
        }

        internal void GroupChanged()
        {
            if (!_bulk) Raise(nameof(IsChecked), nameof(SelectedBytes));
        }

        public long Bytes => _bytes;
        public long SelectedBytes => _groups.Count == 0 ? (_checked ? _bytes : 0) : _groups.Where(g => g.IsChecked).Sum(g => g.Bytes);
        public string SizeText => _scanned ? Util.Size(_bytes) : "—";
        public string DetailText => !_scanned ? "Not scanned" : _files == 0 ? "Nothing to clean" : _files == 1 ? "1 item" : $"{_files:N0} items";
        public Visibility AdminBadge => NeedsAdmin && !Util.IsAdmin ? Visibility.Visible : Visibility.Collapsed;

        public bool IsExpanded
        {
            get => _expanded;
            set { _expanded = value; Raise(nameof(IsExpanded), nameof(ExpandGlyph), nameof(GroupsVisibility)); }
        }
        public string ExpandGlyph => _expanded ? "" : "";
        public Visibility ExpandVisibility => _groups.Count > 0 ? Visibility.Visible : Visibility.Hidden;
        public Visibility GroupsVisibility => _expanded && _groups.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

        public void Scan()
        {
            // Remember what was deselected so a rescan doesn't silently re-tick it.
            bool wasOff = IsChecked == false;
            var off = new HashSet<string>(_groups.Where(g => !g.IsChecked).Select(g => g.Name));

            long bytes = 0; int files = 0;
            var groups = new List<JunkGroup>();
            var prune = new List<string>();

            if (IsRecycleBin)
            {
                var info = new SHQUERYRBINFO { cbSize = Marshal.SizeOf(typeof(SHQUERYRBINFO)) };
                if (SHQueryRecycleBin(null, ref info) == 0) { bytes = info.i64Size; files = (int)info.i64NumItems; }
            }
            else
            {
                DateTime cutoff = Cutoff;
                var byName = new Dictionary<string, JunkGroup>(StringComparer.OrdinalIgnoreCase);
                JunkGroup Group(string name, string location)
                {
                    if (!byName.TryGetValue(name, out JunkGroup g))
                        byName[name] = g = new JunkGroup { Name = name, Location = location, Owner = this };
                    return g;
                }

                foreach (JunkRoot r in Roots)
                    foreach (string dir in Expand(r.Path))
                    {
                        var root = new DirectoryInfo(dir);
                        Collect(root, r, cutoff, Group(r.Label ?? "Loose files", dir), false);
                        if (!r.Recurse) continue;
                        prune.Add(dir);
                        try
                        {
                            foreach (DirectoryInfo sd in root.EnumerateDirectories())
                                if ((sd.Attributes & FileAttributes.ReparsePoint) == 0)
                                    Collect(sd, r, cutoff, Group(r.Label ?? sd.Name, r.Label != null ? dir : sd.FullName), true);
                        }
                        catch { }
                    }

                groups = byName.Values.Where(g => g.Files > 0).OrderByDescending(g => g.Bytes).ToList();
                if (groups.Count > MaxGroups)
                {
                    var rest = new JunkGroup { Name = $"Everything else ({groups.Count - MaxGroups + 1:N0} more folders)", Owner = this };
                    foreach (JunkGroup g in groups.Skip(MaxGroups - 1)) { rest.Bytes += g.Bytes; rest.Files += g.Files; rest.Found.AddRange(g.Found); }
                    groups = groups.Take(MaxGroups - 1).Concat(new[] { rest }).ToList();
                }
                foreach (JunkGroup g in groups)
                {
                    bytes += g.Bytes; files += g.Files;
                    if (wasOff || off.Contains(g.Name)) g.IsChecked = false;   // Owner notifications are harmless here
                }
            }

            _bytes = bytes; _files = files; _groups = groups; _pruneDirs = prune; _scanned = true;
            Raise(nameof(Groups), nameof(SizeText), nameof(DetailText), nameof(Bytes), nameof(IsChecked),
                  nameof(ExpandVisibility), nameof(GroupsVisibility));
        }

        /// <summary>Deletes the selected results of the last scan. Returns the bytes actually freed.</summary>
        public long Clean()
        {
            long freed = 0;
            if (IsRecycleBin)
            {
                if (_checked && _files > 0 && SHEmptyRecycleBin(IntPtr.Zero, null, 7) == 0) freed = _bytes;
                return freed;
            }
            // Re-apply the age guard now: a file may have been written to since the scan.
            DateTime cutoff = Cutoff;
            var emptied = new HashSet<string>(StringComparer.OrdinalIgnoreCase);   // folders this clean deleted from, and their parents
            foreach (JunkGroup g in _groups.Where(g => g.IsChecked))
                foreach (string f in g.Found)
                {
                    try
                    {
                        var fi = new FileInfo(f);
                        if (fi.LastWriteTimeUtc > cutoff) continue;
                        long len = fi.Length;
                        if ((fi.Attributes & FileAttributes.ReadOnly) != 0) fi.Attributes = FileAttributes.Normal;
                        fi.Delete();
                        freed += len;
                        for (string dir = fi.DirectoryName; !string.IsNullOrEmpty(dir) && emptied.Add(dir); dir = System.IO.Path.GetDirectoryName(dir)) { }
                    }
                    catch { /* in use or protected: leave it */ }
                }
            foreach (string d in _pruneDirs) PruneEmpty(d, cutoff, emptied);
            return freed;
        }

        DateTime Cutoff => AgeGuard && AppSettings.KeepRecentTemp ? DateTime.UtcNow.AddHours(-24) : DateTime.MaxValue;

        static void Collect(DirectoryInfo start, JunkRoot r, DateTime cutoff, JunkGroup g, bool recurse)
        {
            var stack = new Stack<DirectoryInfo>();
            stack.Push(start);
            while (stack.Count > 0)
            {
                DirectoryInfo dir = stack.Pop();
                try
                {
                    foreach (FileInfo f in dir.EnumerateFiles(r.Pattern))
                    {
                        try
                        {
                            if (f.LastWriteTimeUtc > cutoff) continue;
                            g.Bytes += f.Length; g.Files++; g.Found.Add(f.FullName);
                        }
                        catch { }
                    }
                }
                catch { }
                if (!recurse) continue;
                try
                {
                    foreach (DirectoryInfo sd in dir.EnumerateDirectories())
                        if ((sd.Attributes & FileAttributes.ReparsePoint) == 0) stack.Push(sd);
                }
                catch { }
            }
        }

        /// <summary>
        /// Removes empty folders below root (never root itself): those this clean emptied, or older than the cutoff.
        /// Deleting a file updates its folder's write time, so the date alone would keep every folder just emptied;
        /// an empty folder an app created recently is still left alone.
        /// </summary>
        static void PruneEmpty(string root, DateTime cutoff, HashSet<string> emptied)
        {
            try
            {
                foreach (DirectoryInfo d in new DirectoryInfo(root).GetDirectories())
                {
                    if ((d.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                    PruneEmpty(d.FullName, cutoff, emptied);
                    try { if ((emptied.Contains(d.FullName) || d.LastWriteTimeUtc <= cutoff) && !d.EnumerateFileSystemInfos().Any()) d.Delete(); } catch { }
                }
            }
            catch { }
        }

        static List<string> Expand(string pattern)
        {
            string full = Util.Env(pattern);
            var cur = new List<string>();
            if (full.Contains("%")) return cur;
            string[] parts = full.Split('\\');
            cur.Add(parts[0] + "\\");
            for (int i = 1; i < parts.Length; i++)
            {
                var next = new List<string>();
                foreach (string d in cur)
                {
                    if (parts[i].Contains("*"))
                    {
                        try { next.AddRange(Directory.GetDirectories(d, parts[i])); } catch { }
                    }
                    else
                    {
                        string p = System.IO.Path.Combine(d, parts[i]);
                        if (Directory.Exists(p)) next.Add(p);
                    }
                }
                cur = next;
            }
            return cur;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct SHQUERYRBINFO { public int cbSize; public long i64Size; public long i64NumItems; }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHQueryRecycleBin(string root, ref SHQUERYRBINFO info);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHEmptyRecycleBin(IntPtr hwnd, string root, uint flags);
    }

    public static class JunkCatalog
    {
        public static List<JunkCategory> Create()
        {
            var browsers = new JunkCategory
            {
                Name = "Browser caches",
                Description = "Cached pages, scripts and images from Chrome, Edge, Brave and Firefox. History, cookies and logins are not touched.",
                Glyph = "", Color = "#10893E"
            };
            var chromium = new[] { new[] { @"Google\Chrome", "Google Chrome" }, new[] { @"Microsoft\Edge", "Microsoft Edge" }, new[] { @"BraveSoftware\Brave-Browser", "Brave" } };
            foreach (string[] b in chromium)
                foreach (string c in new[] { @"Cache", @"Code Cache", @"GPUCache", @"Service Worker\CacheStorage" })
                    browsers.Roots.Add(new JunkRoot($@"%LocalAppData%\{b[0]}\User Data\*\{c}", label: b[1]));
            browsers.Roots.Add(new JunkRoot(@"%LocalAppData%\Mozilla\Firefox\Profiles\*\cache2", label: "Firefox"));

            return new List<JunkCategory>
            {
                new JunkCategory
                {
                    Name = "Temporary files", Glyph = "", Color = "#F7630C", AgeGuard = true,
                    Description = "Leftovers that apps and installers wrote to your user Temp folder.",
                    Roots = { new JunkRoot(@"%TEMP%") }
                },
                new JunkCategory
                {
                    Name = "Windows temporary files", Glyph = "", Color = "#0078D4", AgeGuard = true, NeedsAdmin = true,
                    Description = "Temporary files created by Windows and system services.",
                    Roots = { new JunkRoot(@"%SystemRoot%\Temp") }
                },
                browsers,
                new JunkCategory
                {
                    Name = "Windows Update cache", Glyph = "", Color = "#8764B8", NeedsAdmin = true,
                    Description = "Downloaded update packages. Windows downloads again anything it still needs.",
                    Roots = { new JunkRoot(@"%SystemRoot%\SoftwareDistribution\Download") }
                },
                new JunkCategory
                {
                    Name = "Thumbnail and icon cache", Glyph = "", Color = "#E3008C",
                    Description = "Explorer rebuilds these automatically the next time you browse a folder.",
                    Roots =
                    {
                        new JunkRoot(@"%LocalAppData%\Microsoft\Windows\Explorer", "thumbcache_*.db", false, "Thumbnails"),
                        new JunkRoot(@"%LocalAppData%\Microsoft\Windows\Explorer", "iconcache_*.db", false, "Icons")
                    }
                },
                new JunkCategory
                {
                    Name = "Crash dumps and error reports", Glyph = "", Color = "#E81123",
                    Description = "Memory dumps and Windows Error Reporting archives from past crashes.",
                    Roots =
                    {
                        new JunkRoot(@"%LocalAppData%\CrashDumps", label: "App crash dumps"),
                        new JunkRoot(@"%LocalAppData%\Microsoft\Windows\WER", label: "Error reports (your account)"),
                        new JunkRoot(@"%ProgramData%\Microsoft\Windows\WER", label: "Error reports (system)"),
                        new JunkRoot(@"%SystemRoot%\Minidump", label: "Windows minidumps")
                    }
                },
                new JunkCategory
                {
                    Name = "Shader cache", Glyph = "", Color = "#038387",
                    Description = "Compiled DirectX shaders. Games and apps regenerate them when needed.",
                    Roots = { new JunkRoot(@"%LocalAppData%\D3DSCache") }
                },
                new JunkCategory
                {
                    Name = "Windows log files", Glyph = "", Color = "#69797E", NeedsAdmin = true, AgeGuard = true,
                    Description = "Setup and servicing logs kept by Windows.",
                    Roots = { new JunkRoot(@"%SystemRoot%\Logs", "*.log"), new JunkRoot(@"%SystemRoot%\Logs", "*.cab") }
                },
                new JunkCategory
                {
                    Name = "Recycle Bin", Glyph = "", Color = "#CA5010", IsRecycleBin = true, IsChecked = false,   // off by default: it is the safety net for deleted files
                    Description = "Files you have already deleted, on all drives."
                }
            };
        }
    }
}
