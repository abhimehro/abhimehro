import Foundation

@main
struct SmokeTest {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DownloadsOrganizerSmoke-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

let eligible: [(String, String)] = [("report.pdf", "Documents"), ("photo.png", "Images"), ("archive.zip", "Archives")]
for (name, _) in eligible { fm.createFile(atPath: root.appendingPathComponent(name).path, contents: Data(name.utf8)) }
fm.createFile(atPath: root.appendingPathComponent("recent.txt").path, contents: Data("recent".utf8))
fm.createFile(atPath: root.appendingPathComponent("partial.crdownload").path, contents: Data("partial".utf8))

let oldDate = Date(timeIntervalSinceNow: -86400 * 30)
for (name, _) in eligible { try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: root.appendingPathComponent(name).path) }

func category(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "pdf": return "Documents"
    case "png": return "Images"
    case "zip": return "Archives"
    default: return "Other"
    }
}

let calendar = Calendar.current
let year = calendar.component(.year, from: oldDate)
let monthNumber = calendar.component(.month, from: oldDate)
let monthName = DateFormatter().monthSymbols[monthNumber - 1]
let monthFolder = String(format: "%02d-%@", monthNumber, monthName)
let organized = root.appendingPathComponent("Organized")

let files = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
var moved = 0
for file in files {
    let ext = file.pathExtension.lowercased()
    guard !["crdownload", "download", "part", "partial", "tmp"].contains(ext) else { continue }
    let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date()
    guard Date().timeIntervalSince(modified) > 120 else { continue }
    let destination = organized.appendingPathComponent(category(for: file)).appendingPathComponent(String(year)).appendingPathComponent(monthFolder).appendingPathComponent(file.lastPathComponent)
    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.moveItem(at: file, to: destination)
    moved += 1
}

precondition(moved == 3, "Expected three eligible files to move")
for (name, category) in eligible {
    let expected = organized.appendingPathComponent(category).appendingPathComponent(String(year)).appendingPathComponent(monthFolder).appendingPathComponent(name)
    precondition(fm.fileExists(atPath: expected.path), "Missing organized file: \(expected.path)")
}
precondition(fm.fileExists(atPath: root.appendingPathComponent("recent.txt").path), "Recent file was incorrectly moved")
precondition(fm.fileExists(atPath: root.appendingPathComponent("partial.crdownload").path), "Partial download was incorrectly moved")
        print("PASS: moved 3 eligible files by category and date; retained recent and partial files")
    }
}
