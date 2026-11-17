using System;
using System.IO;
using System.Security.Cryptography;

namespace PureSweep.Core
{
    public static class Shredder
    {
        /// <summary>Overwrites and deletes a file or a whole folder. Returns the number of files destroyed.</summary>
        public static int Shred(string path, int passes)
        {
            if (IsProtected(path))
                throw new InvalidOperationException("Refusing to shred a drive root, a Windows or Program Files folder, or a user profile folder.");
            return ShredCore(path, passes);
        }

        /// <summary>
        /// True for a drive or share root, anything inside the Windows folder, and any folder that is (or contains)
        /// Program Files, ProgramData or a user profile. Shredding one of these by mistake would wreck the PC.
        /// </summary>
        static bool IsProtected(string path)
        {
            string full;
            try { full = Path.GetFullPath(path).TrimEnd('\\'); }
            catch { return true; }

            string root = Path.GetPathRoot(full) ?? "";
            if (full.Length == 0 || string.Equals(root.TrimEnd('\\'), full, StringComparison.OrdinalIgnoreCase)) return true;

            string candidate = full + "\\";
            string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows).TrimEnd('\\') + "\\";
            if (candidate.StartsWith(windows, StringComparison.OrdinalIgnoreCase)) return true;

            string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            foreach (string p in new[]
            {
                windows,
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                profile,
                string.IsNullOrEmpty(profile) ? null : Path.GetDirectoryName(profile)   // C:\Users
            })
            {
                if (string.IsNullOrEmpty(p)) continue;
                // protected if the chosen path is this folder or one of its parents
                if ((p.TrimEnd('\\') + "\\").StartsWith(candidate, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        static int ShredCore(string path, int passes)
        {
            if (File.Exists(path)) { ShredFile(path, passes); return 1; }
            if (!Directory.Exists(path)) return 0;

            var dir = new DirectoryInfo(path);
            if ((dir.Attributes & FileAttributes.ReparsePoint) != 0) { dir.Delete(); return 0; }  // remove the link, never follow it

            int count = 0;
            foreach (FileInfo f in dir.GetFiles()) { ShredFile(f.FullName, passes); count++; }
            foreach (DirectoryInfo d in dir.GetDirectories()) count += ShredCore(d.FullName, passes);
            dir.Attributes = FileAttributes.Directory;
            dir.Delete();
            return count;
        }

        static void ShredFile(string path, int passes)
        {
            var fi = new FileInfo(path);
            if ((fi.Attributes & FileAttributes.ReparsePoint) != 0) { fi.Delete(); return; }
            fi.Attributes = FileAttributes.Normal;
            long length = fi.Length;

            var buffer = new byte[1 << 20];
            using (var rng = RandomNumberGenerator.Create())
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.None))
            {
                for (int p = 0; p < passes; p++)
                {
                    fs.Position = 0;
                    long left = length;
                    while (left > 0)
                    {
                        rng.GetBytes(buffer);
                        int n = (int)Math.Min(left, buffer.Length);
                        fs.Write(buffer, 0, n);
                        left -= n;
                    }
                    fs.Flush(true);
                }
            }

            // Rename so the original file name does not linger in the directory entry.
            string anon = Path.Combine(fi.DirectoryName, Guid.NewGuid().ToString("N"));
            File.Move(path, anon);
            File.Delete(anon);
        }
    }
}
