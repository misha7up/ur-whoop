import Foundation

/// Экспериментальное UDS **0x22** на щиток; опционально prelude (**0x10 0x03** extended session).
/// **0x27** / **0x2E** в приложении не выполняются (см. `CONTEXT.md`).
enum ClusterOdometerProbes {
    struct Probe: Sendable {
        let groupLabel: String
        let txHeader: String
        let requestHex: String
        let positiveMarker: String
        var preludeHex: [String] = []
    }

    static func probes(for group: BrandEcuHints.VehicleBrandGroup) -> [Probe] {
        switch group {
        case .VAG:
            return [
                Probe(groupLabel: "VAG", txHeader: "714", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "VAG", txHeader: "714", requestHex: "22291A", positiveMarker: "62291A"),
                Probe(groupLabel: "VAG", txHeader: "714", requestHex: "222014", positiveMarker: "622014"),
                Probe(groupLabel: "VAG", txHeader: "714", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "VAG", txHeader: "710", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "VAG", txHeader: "710", requestHex: "22291A", positiveMarker: "62291A"),
                Probe(groupLabel: "VAG", txHeader: "710", requestHex: "222003", positiveMarker: "622003"),
            ]
        case .TOYOTA:
            return [
                Probe(groupLabel: "Toyota", txHeader: "750", requestHex: "222182", positiveMarker: "622182"),
                Probe(groupLabel: "Toyota", txHeader: "750", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Toyota", txHeader: "750", requestHex: "222100", positiveMarker: "622100"),
                Probe(groupLabel: "Toyota", txHeader: "7C0", requestHex: "222182", positiveMarker: "622182"),
                Probe(groupLabel: "Toyota", txHeader: "7C0", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Toyota", txHeader: "7C0", requestHex: "222100", positiveMarker: "622100"),
                Probe(groupLabel: "Toyota", txHeader: "7C0", requestHex: "222903", positiveMarker: "622903"),
                Probe(groupLabel: "Toyota", txHeader: "7B5", requestHex: "222182", positiveMarker: "622182"),
                Probe(groupLabel: "Toyota", txHeader: "710", requestHex: "222182", positiveMarker: "622182"),
                Probe(groupLabel: "Toyota", txHeader: "750", requestHex: "222903", positiveMarker: "622903"),
            ]
        case .HONDA:
            return [
                Probe(groupLabel: "Honda", txHeader: "760", requestHex: "223101", positiveMarker: "623101"),
                Probe(groupLabel: "Honda", txHeader: "760", requestHex: "223102", positiveMarker: "623102"),
                Probe(groupLabel: "Honda", txHeader: "760", requestHex: "2200B4", positiveMarker: "6200B4"),
                Probe(groupLabel: "Honda", txHeader: "760", requestHex: "222001", positiveMarker: "622001"),
                Probe(groupLabel: "Honda", txHeader: "7C0", requestHex: "223101", positiveMarker: "623101"),
                Probe(groupLabel: "Honda", txHeader: "7C0", requestHex: "2200B4", positiveMarker: "6200B4"),
                Probe(groupLabel: "Honda", txHeader: "714", requestHex: "223101", positiveMarker: "623101"),
                Probe(groupLabel: "Honda", txHeader: "714", requestHex: "223102", positiveMarker: "623102"),
                Probe(groupLabel: "Honda", txHeader: "718", requestHex: "223101", positiveMarker: "623101"),
                Probe(groupLabel: "Honda", txHeader: "771", requestHex: "223101", positiveMarker: "623101"),
                Probe(groupLabel: "Honda", txHeader: "714", requestHex: "22B002", positiveMarker: "62B002"),
            ]
        case .FORD:
            return [
                Probe(groupLabel: "Ford", txHeader: "720", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "Ford", txHeader: "720", requestHex: "22DD01", positiveMarker: "62DD01"),
                Probe(groupLabel: "Ford", txHeader: "720", requestHex: "22D028", positiveMarker: "62D028"),
                Probe(groupLabel: "Ford", txHeader: "720", requestHex: "224040", positiveMarker: "624040"),
                Probe(groupLabel: "Ford", txHeader: "720", requestHex: "22DE00", positiveMarker: "62DE00"),
                Probe(groupLabel: "Ford", txHeader: "720", requestHex: "22D108", positiveMarker: "62D108"),
                Probe(groupLabel: "Ford", txHeader: "720", requestHex: "221704", positiveMarker: "621704"),
                Probe(groupLabel: "Ford", txHeader: "726", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "Ford", txHeader: "726", requestHex: "22DD01", positiveMarker: "62DD01"),
                Probe(groupLabel: "Ford", txHeader: "732", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "Ford", txHeader: "732", requestHex: "22DD01", positiveMarker: "62DD01"),
                Probe(groupLabel: "Ford", txHeader: "736", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "Ford", txHeader: "764", requestHex: "22D111", positiveMarker: "62D111"),
            ]
        case .PSA:
            return [
                Probe(groupLabel: "PSA", txHeader: "752", requestHex: "222010", positiveMarker: "622010", preludeHex: ["1003"]),
                Probe(groupLabel: "PSA", txHeader: "752", requestHex: "222101", positiveMarker: "622101", preludeHex: ["1003"]),
                Probe(groupLabel: "PSA", txHeader: "752", requestHex: "222014", positiveMarker: "622014", preludeHex: ["1003"]),
                Probe(groupLabel: "PSA", txHeader: "753", requestHex: "222010", positiveMarker: "622010", preludeHex: ["1003"]),
                Probe(groupLabel: "PSA", txHeader: "740", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "PSA", txHeader: "742", requestHex: "222010", positiveMarker: "622010"),
            ]
        case .GM:
            return [
                Probe(groupLabel: "GM", txHeader: "724", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "GM", txHeader: "724", requestHex: "22D109", positiveMarker: "62D109"),
                Probe(groupLabel: "GM", txHeader: "724", requestHex: "22D028", positiveMarker: "62D028"),
                Probe(groupLabel: "GM", txHeader: "728", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "GM", txHeader: "244", requestHex: "22D111", positiveMarker: "62D111"),
            ]
        case .HYUNDAI_KIA:
            return [
                Probe(groupLabel: "HyundaiKia", txHeader: "7A0", requestHex: "22B002", positiveMarker: "62B002", preludeHex: ["1003"]),
                Probe(groupLabel: "HyundaiKia", txHeader: "770", requestHex: "22B958", positiveMarker: "62B958", preludeHex: ["1003"]),
                Probe(groupLabel: "HyundaiKia", txHeader: "770", requestHex: "22B002", positiveMarker: "62B002", preludeHex: ["1003"]),
                Probe(groupLabel: "HyundaiKia", txHeader: "771", requestHex: "22B958", positiveMarker: "62B958"),
                Probe(groupLabel: "HyundaiKia", txHeader: "7A2", requestHex: "22B002", positiveMarker: "62B002"),
                Probe(groupLabel: "HyundaiKia", txHeader: "7C6", requestHex: "22B002", positiveMarker: "62B002"),
            ]
        case .MAZDA:
            return [
                Probe(groupLabel: "Mazda", txHeader: "720", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Mazda", txHeader: "720", requestHex: "222100", positiveMarker: "622100"),
                Probe(groupLabel: "Mazda", txHeader: "730", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Mazda", txHeader: "731", requestHex: "222101", positiveMarker: "622101"),
            ]
        case .NISSAN:
            return [
                Probe(groupLabel: "Nissan", txHeader: "743", requestHex: "22D106", positiveMarker: "62D106"),
                Probe(groupLabel: "Nissan", txHeader: "743", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "Nissan", txHeader: "743", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Nissan", txHeader: "743", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Nissan", txHeader: "744", requestHex: "22D106", positiveMarker: "62D106"),
                Probe(groupLabel: "Nissan", txHeader: "744", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "Nissan", txHeader: "740", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "Nissan", txHeader: "740", requestHex: "22D106", positiveMarker: "62D106"),
                Probe(groupLabel: "Nissan", txHeader: "760", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "Nissan", txHeader: "793", requestHex: "22D111", positiveMarker: "62D111"),
            ]
        case .BMW_MINI:
            return [
                Probe(groupLabel: "BMW", txHeader: "600", requestHex: "22D010", positiveMarker: "62D010", preludeHex: ["1003"]),
                Probe(groupLabel: "BMW", txHeader: "600", requestHex: "222002", positiveMarker: "622002", preludeHex: ["1003"]),
                Probe(groupLabel: "BMW", txHeader: "600", requestHex: "222003", positiveMarker: "622003", preludeHex: ["1003"]),
                Probe(groupLabel: "BMW", txHeader: "601", requestHex: "22D010", positiveMarker: "62D010", preludeHex: ["1003"]),
                Probe(groupLabel: "Mini", txHeader: "600", requestHex: "22D010", positiveMarker: "62D010", preludeHex: ["1003"]),
            ]
        case .JAGUAR:
            return [
                Probe(groupLabel: "JLR", txHeader: "7C4", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "JLR", txHeader: "7C4", requestHex: "22DD01", positiveMarker: "62DD01"),
                Probe(groupLabel: "JLR", txHeader: "720", requestHex: "22D111", positiveMarker: "62D111"),
                Probe(groupLabel: "JLR", txHeader: "736", requestHex: "22D111", positiveMarker: "62D111"),
            ]
        case .LADA:
            return [
                Probe(groupLabel: "Lada", txHeader: "712", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Lada", txHeader: "712", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Lada", txHeader: "712", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Lada", txHeader: "714", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Lada", txHeader: "714", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Lada", txHeader: "714", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Lada", txHeader: "715", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Lada", txHeader: "715", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Lada", txHeader: "720", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Lada", txHeader: "720", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Lada", txHeader: "740", requestHex: "222010", positiveMarker: "622010"),
            ]
        case .MERCEDES:
            return [
                Probe(groupLabel: "Mercedes", txHeader: "720", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Mercedes", txHeader: "720", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Mercedes", txHeader: "720", requestHex: "222014", positiveMarker: "622014"),
                Probe(groupLabel: "Mercedes", txHeader: "720", requestHex: "22291A", positiveMarker: "62291A"),
                Probe(groupLabel: "Mercedes", txHeader: "743", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Mercedes", txHeader: "743", requestHex: "222010", positiveMarker: "622010"),
            ]
        case .CHANGAN:
            return [
                Probe(groupLabel: "Changan", txHeader: "720", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Changan", txHeader: "720", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Changan", txHeader: "714", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Changan", txHeader: "714", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Changan", txHeader: "740", requestHex: "222010", positiveMarker: "622010"),
            ]
        // Renault: щиток на 770, UCH на 742; DID 22F200 — Renault-специфичный
        case .RENAULT:
            return [
                Probe(groupLabel: "Renault", txHeader: "770", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Renault", txHeader: "770", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Renault", txHeader: "770", requestHex: "22F200", positiveMarker: "62F200"),
                Probe(groupLabel: "Renault", txHeader: "770", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Renault", txHeader: "742", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Renault", txHeader: "742", requestHex: "222010", positiveMarker: "622010"),
            ]
        // Mitsubishi: комбинация 7C0, gateway 750 — архитектура ближе к Toyota
        case .MITSUBISHI:
            return [
                Probe(groupLabel: "Mitsubishi", txHeader: "7C0", requestHex: "222182", positiveMarker: "622182"),
                Probe(groupLabel: "Mitsubishi", txHeader: "7C0", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Mitsubishi", txHeader: "7C0", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Mitsubishi", txHeader: "750", requestHex: "222182", positiveMarker: "622182"),
                Probe(groupLabel: "Mitsubishi", txHeader: "750", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Mitsubishi", txHeader: "750", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Mitsubishi", txHeader: "750", requestHex: "222010", positiveMarker: "622010"),
            ]
        // Haval/GWM: китайская платформа, типовые адреса 720/714/740
        case .HAVAL_GWM:
            return [
                Probe(groupLabel: "Haval", txHeader: "720", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Haval", txHeader: "720", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Haval", txHeader: "714", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Haval", txHeader: "714", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Haval", txHeader: "740", requestHex: "222010", positiveMarker: "622010"),
            ]
        // Geely: китайская платформа, аналогичные Haval/Changan адреса
        case .GEELY:
            return [
                Probe(groupLabel: "Geely", txHeader: "720", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Geely", txHeader: "720", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Geely", txHeader: "714", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Geely", txHeader: "714", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Geely", txHeader: "740", requestHex: "222010", positiveMarker: "622010"),
            ]
        case .CHERY:
            return [
                Probe(groupLabel: "Chery", txHeader: "720", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Chery", txHeader: "720", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Chery", txHeader: "714", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Chery", txHeader: "714", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Chery", txHeader: "740", requestHex: "222010", positiveMarker: "622010"),
            ]
        case .SUBARU:
            return [
                Probe(groupLabel: "Subaru", txHeader: "7C0", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Subaru", txHeader: "7C0", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Subaru", txHeader: "7C0", requestHex: "222101", positiveMarker: "622101"),
                Probe(groupLabel: "Subaru", txHeader: "744", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Subaru", txHeader: "744", requestHex: "222003", positiveMarker: "622003"),
                Probe(groupLabel: "Subaru", txHeader: "740", requestHex: "222010", positiveMarker: "622010"),
                Probe(groupLabel: "Subaru", txHeader: "750", requestHex: "222010", positiveMarker: "622010"),
            ]
        case .OTHER:
            return []
        }
    }

    static func extractPayloadAfterMarker(_ cleanUpper: String, marker: String) -> Data? {
        let m = marker.uppercased()
        guard let r = cleanUpper.range(of: m) else { return nil }
        var p = r.upperBound
        var out = [UInt8]()
        while out.count < 16 {
            guard let i1 = cleanUpper.index(p, offsetBy: 2, limitedBy: cleanUpper.endIndex) else { break }
            let pair = String(cleanUpper[p..<i1])
            if pair == "7F" { break }
            guard let b = UInt8(pair, radix: 16) else { break }
            out.append(b)
            p = i1
        }
        return out.isEmpty ? nil : Data(out)
    }

    static func parseOdometerKm(_ data: Data) -> Int? {
        guard !data.isEmpty else { return nil }
        func u8(_ i: Int) -> Int { Int(data[i]) }

        if data.count >= 3 {
            let be = (u8(0) << 16) | (u8(1) << 8) | u8(2)
            if (1...2_000_000).contains(be) { return be }
            let le = (u8(2) << 16) | (u8(1) << 8) | u8(0)
            if (1...2_000_000).contains(le) { return le }
        }
        if data.count >= 4 {
            let be32 = (UInt64(u8(0)) << 24) | (UInt64(u8(1)) << 16) | (UInt64(u8(2)) << 8) | UInt64(u8(3))
            if be32 >= 1, be32 <= 2_000_000 { return Int(be32) }
            if be32 >= 1, be32 <= 200_000_000 {
                let d = Int(be32 / 100)
                if (1...2_000_000).contains(d) { return d }
            }
        }
        if data.count >= 2 {
            let u16be = (u8(0) << 8) | u8(1)
            if (100...500_000).contains(u16be) { return u16be }
            let u16le = (u8(1) << 8) | u8(0)
            if (100...500_000).contains(u16le) { return u16le }
        }
        if data.count >= 3, let bcd = parseBcdSixDigits(u8(0), u8(1), u8(2)), (1...999_999).contains(bcd) {
            return bcd
        }
        return nil
    }

    private static func parseBcdSixDigits(_ b0: Int, _ b1: Int, _ b2: Int) -> Int? {
        func pair(_ byte: Int) -> Int? {
            let h = (byte >> 4) & 0xF
            let l = byte & 0xF
            guard h <= 9, l <= 9 else { return nil }
            return h * 10 + l
        }
        guard let p0 = pair(b0), let p1 = pair(b1), let p2 = pair(b2) else { return nil }
        return p0 * 10_000 + p1 * 100 + p2
    }
}
