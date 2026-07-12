import Foundation
import AppKit
import CryptoKit

/// Extracts a Windows program's real icon (like CrossOver's launcher does) by
/// reading the RT_GROUP_ICON / RT_ICON resources straight out of the PE (.exe),
/// reconstructing a .ico, and letting AppKit rasterise it. Results are cached on
/// disk as PNG so the launcher grid stays snappy.
enum IconExtractor {
    private static let cacheDir: URL = {
        let dir = AppPaths.root.appendingPathComponent("IconCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The icon for a Windows .exe at `unixPath`, or nil if it has none we can read.
    /// Cached by path+mtime so a changed/reinstalled binary re-extracts.
    static func icon(forExe unixPath: String) -> NSImage? {
        let fm = FileManager.default
        let mtime = (try? fm.attributesOfItem(atPath: unixPath)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = sha("\(unixPath)|\(mtime)")
        let cached = cacheDir.appendingPathComponent("\(key).png")
        if let img = NSImage(contentsOf: cached) { return img }

        guard let data = fm.contents(atPath: unixPath),
              let ico = Self.buildICO(fromPE: [UInt8](data)),
              let img = NSImage(data: ico) else { return nil }

        // Persist a PNG so we don't re-parse the PE next time.
        if let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: cached)
        }
        return img
    }

    private static func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - PE resource parsing

    /// Reconstruct a full multi-size .ico from the PE's default icon group.
    private static func buildICO(fromPE b: [UInt8]) -> Data? {
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) | Int(b[o+1]) << 8 : 0 }
        func u32(_ o: Int) -> Int {
            o + 3 < b.count ? Int(b[o]) | Int(b[o+1]) << 8 | Int(b[o+2]) << 16 | Int(b[o+3]) << 24 : 0
        }
        guard b.count > 0x40, u16(0) == 0x5A4D else { return nil }        // "MZ"
        let pe = u32(0x3c)
        guard pe + 24 < b.count, u32(pe) == 0x0000_4550 else { return nil } // "PE\0\0"
        let coff = pe + 4
        let numSections = u16(coff + 2)
        let sizeOpt = u16(coff + 16)
        let opt = coff + 20
        guard opt < b.count else { return nil }
        let magic = u16(opt)
        let dirBase = opt + (magic == 0x20B ? 112 : 96)      // PE32+ vs PE32
        let resRVA = u32(dirBase + 2 * 8)                    // data dir index 2 = resources
        guard resRVA > 0 else { return nil }

        // Section table → RVA→file-offset mapping.
        let secTable = opt + sizeOpt
        struct Sec { let va: Int; let size: Int; let ptr: Int }
        var secs: [Sec] = []
        for i in 0..<numSections {
            let o = secTable + i * 40
            guard o + 24 < b.count else { break }
            secs.append(Sec(va: u32(o + 12), size: max(u32(o + 8), u32(o + 16)), ptr: u32(o + 20)))
        }
        func off(_ rva: Int) -> Int? {
            for s in secs where rva >= s.va && rva < s.va + s.size { return s.ptr + (rva - s.va) }
            return nil
        }
        guard let resBase = off(resRVA) else { return nil }

        // Walk one level of an IMAGE_RESOURCE_DIRECTORY, returning (id, entryOffset, isDir).
        func entries(_ dirOff: Int) -> [(id: Int, target: Int, isDir: Bool)] {
            guard dirOff + 16 < b.count else { return [] }
            let named = u16(dirOff + 12), ids = u16(dirOff + 14)
            var out: [(Int, Int, Bool)] = []
            for i in 0..<(named + ids) {
                let e = dirOff + 16 + i * 8
                guard e + 8 <= b.count else { break }
                let nameOrId = u32(e)
                let offToData = u32(e + 4)
                let isDir = (offToData & 0x8000_0000) != 0
                out.append((nameOrId & 0x7FFF_FFFF, resBase + (offToData & 0x7FFF_FFFF), isDir))
            }
            return out
        }
        // A leaf IMAGE_RESOURCE_DATA_ENTRY → (fileOffset, size) of the blob.
        func leaf(_ dataEntryOff: Int) -> (Int, Int)? {
            guard let o = off(u32(dataEntryOff)) else { return nil }
            return (o, u32(dataEntryOff + 4))
        }
        // Resolve type → (first) name → (first) language → blob.
        func firstBlob(type: Int, name: Int? = nil) -> (Int, Int)? {
            guard let typeEntry = entries(resBase).first(where: { $0.id == type && $0.isDir })
            else { return nil }
            let nameEntries = entries(typeEntry.target)
            let ne = name != nil ? nameEntries.first(where: { $0.id == name }) : nameEntries.first
            guard let nameDir = ne, nameDir.isDir,
                  let langEntry = entries(nameDir.target).first else { return nil }
            return leaf(langEntry.target)
        }

        // RT_GROUP_ICON = 14: pick the first group and read its directory of icon IDs.
        guard let (grpOff, _) = firstBlob(type: 14) else { return nil }
        let count = u16(grpOff + 4)
        guard count > 0, count < 64 else { return nil }

        struct Entry { let header: [UInt8]; let id: Int }
        var wanted: [Entry] = []
        for i in 0..<count {
            let e = grpOff + 6 + i * 14
            guard e + 14 <= b.count else { break }
            // GRPICONDIRENTRY: 12 bytes usable in an ICONDIRENTRY (w,h,cc,res,planes,bits,bytes) + iconId(u16)
            wanted.append(Entry(header: Array(b[e..<e+12]), id: u16(e + 12)))
        }
        guard !wanted.isEmpty else { return nil }

        // Collect the RT_ICON blob for each group entry (skip any we can't resolve),
        // so the ICONDIR count and image offsets are computed from what we'll actually
        // write.
        var imgs: [(header: [UInt8], data: [UInt8])] = []
        for w in wanted {
            guard let (io, size) = firstBlob(type: 3, name: w.id), io + size <= b.count, size > 0
            else { continue }
            imgs.append((w.header, Array(b[io..<io+size])))
        }
        guard !imgs.isEmpty else { return nil }

        // Assemble the .ico: ICONDIR + ICONDIRENTRY[] + concatenated RT_ICON blobs.
        var dir = Data([0, 0, 1, 0])                              // reserved, type=1 (icon)
        dir.append(contentsOf: le16(imgs.count))
        var blobs = Data()
        var imageOffset = 6 + imgs.count * 16
        for img in imgs {
            dir.append(contentsOf: img.header)                    // 12 bytes
            dir.append(contentsOf: le32(imageOffset))             // 4 bytes → 16-byte ICONDIRENTRY
            blobs.append(contentsOf: img.data)
            imageOffset += img.data.count
        }
        return dir + blobs
    }

    private static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
    private static func le32(_ v: Int) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }
}
