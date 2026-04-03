import Foundation

/// Разбор ответов Mode 09 / Mode 01 для расширенного `VehicleInfo`.
enum ObdVehicleInfoParse {

    static func mode09SupportMask(_ clean: String) -> [UInt8]? {
        guard let r = clean.range(of: "4900") else { return nil }
        var p = r.upperBound
        var out: [UInt8] = []
        for _ in 0..<4 {
            guard let end = clean.index(p, offsetBy: 2, limitedBy: clean.endIndex) else { return nil }
            let pair = String(clean[p..<end])
            guard let v = UInt8(pair, radix: 16) else { return nil }
            out.append(v)
            p = end
        }
        return out
    }

    static func isMode09PidSupported(_ mask: [UInt8]?, pid: Int) -> Bool {
        guard pid >= 1, pid <= 32 else { return false }
        guard let mask, mask.count >= 4 else { return pid == 3 || pid == 4 }
        let bitIndex = pid - 1
        let byteIx = bitIndex / 8
        let bitInByte = 7 - (bitIndex % 8)
        let b = Int(mask[byteIx])
        return (b >> bitInByte) & 1 != 0
    }

    static func bestAsciiAfterMarker(_ clean: String, marker: String, maxChars: Int) -> String? {
        var best: String?
        var searchFrom = clean.startIndex
        while searchFrom < clean.endIndex,
              let r = clean.range(of: marker, range: searchFrom..<clean.endIndex) {
            let start = r.upperBound
            if let s = asciiFromMode09Index(clean, start: start, maxChars: maxChars) {
                if best == nil || s.count > best!.count { best = s }
            }
            searchFrom = r.upperBound
        }
        return best
    }

    private static func asciiFromMode09Index(_ clean: String, start: String.Index, maxChars: Int) -> String? {
        var p = start
        if clean.distance(from: p, to: clean.endIndex) >= 2,
           String(clean[p..<clean.index(p, offsetBy: 2)]) == "01" {
            p = clean.index(p, offsetBy: 2)
        }
        var chars: [Character] = []
        while chars.count < maxChars, clean.distance(from: p, to: clean.endIndex) >= 2 {
            let pair = String(clean[p..<clean.index(p, offsetBy: 2)])
            guard let byte = UInt8(pair, radix: 16) else { break }
            if byte == 0 { break }
            guard let u = UnicodeScalar(UInt32(byte)), (32...126).contains(Int(u.value)) else { break }
            chars.append(Character(u))
            p = clean.index(p, offsetBy: 2)
        }
        let s = String(chars).trimmingCharacters(in: .whitespaces)
        return s.count >= 2 ? s : nil
    }

    static func cvnHexLine(_ clean: String) -> String? {
        guard let r = clean.range(of: "4904") else { return nil }
        var p = r.upperBound
        if clean.distance(from: p, to: clean.endIndex) >= 2,
           String(clean[p..<clean.index(p, offsetBy: 2)]) == "01" {
            p = clean.index(p, offsetBy: 2)
        }
        var groups: [String] = []
        while groups.count < 16, clean.distance(from: p, to: clean.endIndex) >= 8 {
            let end = clean.index(p, offsetBy: 8)
            let chunk = String(clean[p..<end]).uppercased()
            guard chunk.count == 8, chunk.allSatisfy(\.isHexDigit) else { break }
            groups.append(chunk)
            p = end
        }
        let joined = groups.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    static func hexPayloadAfterMarker(_ clean: String, marker: String, maxDataBytes: Int) -> String? {
        guard let r = clean.range(of: marker) else { return nil }
        var p = r.upperBound
        if clean.distance(from: p, to: clean.endIndex) >= 2,
           String(clean[p..<clean.index(p, offsetBy: 2)]) == "01" {
            p = clean.index(p, offsetBy: 2)
        }
        var out = ""
        var bytes = 0
        while bytes < maxDataBytes, clean.distance(from: p, to: clean.endIndex) >= 2 {
            let end = clean.index(p, offsetBy: 2)
            let pair = String(clean[p..<end])
            guard pair.count == 2, UInt8(pair, radix: 16) != nil else { break }
            out.append(pair)
            bytes += 1
            p = end
        }
        return out.count >= 4 ? out : nil
    }

    static func singleByteMode01(_ clean: String, pidHex2: String) -> Int? {
        let marker = "41\(pidHex2.uppercased())"
        guard let r = clean.range(of: marker) else { return nil }
        let p = r.upperBound
        guard clean.distance(from: p, to: clean.endIndex) >= 2 else { return nil }
        let end = clean.index(p, offsetBy: 2)
        return Int(String(clean[p..<end]), radix: 16)
    }
}
