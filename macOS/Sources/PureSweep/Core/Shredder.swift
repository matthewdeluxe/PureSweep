import Darwin
import Foundation

enum ShredError: LocalizedError {
    case protected, io(String)
    var errorDescription: String? {
        switch self {
        case .protected: return "Refusing to shred a disk, a system folder, your home folder or one of its main folders."
        case .io(let m): return m
        }
    }
}

enum Shredder {
    /// Overwrites and deletes a file or a whole folder. Returns the number of files destroyed.
    static func shred(_ path: String, passes: Int) throws -> Int {
        if isProtected(path) { throw ShredError.protected }
        return try shredCore(path, passes)
    }

    /// True for volume roots, system locations, the home folder and its standard folders, and any folder containing them.
    static func isProtected(_ path: String) -> Bool {
        let full = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        if full == "/" || full.isEmpty { return true }
        if (try? URL(fileURLWithPath: full).resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true { return true }

        // Nothing inside these.
        for p in ["/System", "/usr", "/bin", "/sbin", "/Library", "/private/etc", "/private/var/db"] where full == p || full.hasPrefix(p + "/") {
            return true
        }
        // Not these folders themselves, nor any folder that contains one of them.
        let home = Util.home
        var keep = ["/Applications", "/Users", "/Volumes", "/private", "/private/var", "/private/tmp", "/opt", home]
        keep += ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "Applications"]
            .map { (home as NSString).appendingPathComponent($0) }
        return keep.contains { $0 == full || $0.hasPrefix(full + "/") }
    }

    private static func shredCore(_ path: String, _ passes: Int) throws -> Int {
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        switch st.st_mode & S_IFMT {
        case S_IFLNK:
            unlink(path)                         // remove the link, never follow it
            return 0
        case S_IFDIR:
            var count = 0
            for item in try FileManager.default.contentsOfDirectory(atPath: path) {
                count += try shredCore((path as NSString).appendingPathComponent(item), passes)
            }
            try FileManager.default.removeItem(atPath: path)
            return count
        case S_IFREG:
            try shredFile(path, passes, Int64(st.st_size))
            return 1
        default:
            return 0
        }
    }

    private static func shredFile(_ path: String, _ passes: Int, _ length: Int64) throws {
        chmod(path, 0o600)                       // in case it was read-only
        let fd = open(path, O_WRONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw ShredError.io("\((path as NSString).lastPathComponent): \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        for _ in 0..<passes {
            lseek(fd, 0, SEEK_SET)
            var left = length
            while left > 0 {
                let n = Int(min(left, Int64(buffer.count)))
                arc4random_buf(&buffer, n)
                guard write(fd, buffer, n) == n else { throw ShredError.io("Write failed: \(String(cString: strerror(errno)))") }
                left -= Int64(n)
            }
            _ = fcntl(fd, F_FULLFSYNC)               // push the pass to the disk itself, not just its cache
        }
        // Rename so the original file name does not linger in the directory entry.
        let anon = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(UUID().uuidString)
        if rename(path, anon) != 0 { throw ShredError.io(String(cString: strerror(errno))) }
        unlink(anon)
    }

    /// Whether FileVault encrypts the startup disk (nil if unknown).
    static func fileVaultOn() -> Bool? {
        let out = Util.run("/usr/bin/fdesetup", ["isactive"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return out == "true" ? true : out == "false" ? false : nil
    }
}
