/// Модель сессии диагностики + JSON-репозиторий (Application Support/sessions.json).
///
/// Канонический JSON совпадает с Android: длинные ключи, `timestamp` в **миллисекундах** Unix.
/// Поддерживается чтение legacy iOS (timestamp в секундах) и legacy Android (короткие ключи `ts`, `vn`, `md`…).
import Foundation

// MARK: - SessionRecord

struct SessionRecord: Codable, Identifiable {
    let id: String
    /// Unix-время начала сессии (**секунды** с 1970-01-01), внутри приложения.
    let timestamp: TimeInterval
    let vehicleName: String
    let vin: String?
    let mainDtcs: [String]
    let pendingDtcs: [String]
    let permanentDtcs: [String]
    let hasFreezeFrame: Bool
    let otherEcuErrors: [String: [String]]

    init(
        id: String = UUID().uuidString,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        vehicleName: String,
        vin: String? = nil,
        mainDtcs: [String] = [],
        pendingDtcs: [String] = [],
        permanentDtcs: [String] = [],
        hasFreezeFrame: Bool = false,
        otherEcuErrors: [String: [String]] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.vehicleName = vehicleName
        self.vin = vin
        self.mainDtcs = mainDtcs
        self.pendingDtcs = pendingDtcs
        self.permanentDtcs = permanentDtcs
        self.hasFreezeFrame = hasFreezeFrame
        self.otherEcuErrors = otherEcuErrors
    }

    private enum CK: String, CodingKey {
        case id, timestamp, ts, vehicleName, vn, vin
        case mainDtcs, md, pendingDtcs, pd, permanentDtcs, pm
        case hasFreezeFrame, ff, otherEcuErrors, ecu
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString

        if let ms = try? c.decode(Int64.self, forKey: .timestamp) {
            timestamp = TimeInterval(ms) / 1000.0
        } else if let d = try? c.decode(Double.self, forKey: .timestamp) {
            if d > BrandConfig.timestampUnixSecondsCeiling {
                timestamp = d / 1000.0
            } else {
                timestamp = d
            }
        } else if let tsMs = try? c.decode(Int64.self, forKey: .ts) {
            timestamp = TimeInterval(tsMs) / 1000.0
        } else if let tsD = try? c.decode(Double.self, forKey: .ts) {
            timestamp = TimeInterval(tsD) / 1000.0
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Missing timestamp"))
        }

        vehicleName = try c.decodeIfPresent(String.self, forKey: .vehicleName)
            ?? c.decodeIfPresent(String.self, forKey: .vn) ?? "Автомобиль"
        vin = try c.decodeIfPresent(String.self, forKey: .vin)

        mainDtcs = try c.decodeIfPresent([String].self, forKey: .mainDtcs)
            ?? c.decodeIfPresent([String].self, forKey: .md) ?? []
        pendingDtcs = try c.decodeIfPresent([String].self, forKey: .pendingDtcs)
            ?? c.decodeIfPresent([String].self, forKey: .pd) ?? []
        permanentDtcs = try c.decodeIfPresent([String].self, forKey: .permanentDtcs)
            ?? c.decodeIfPresent([String].self, forKey: .pm) ?? []

        if c.contains(.hasFreezeFrame) {
            hasFreezeFrame = try c.decode(Bool.self, forKey: .hasFreezeFrame)
        } else {
            hasFreezeFrame = try c.decodeIfPresent(Bool.self, forKey: .ff) ?? false
        }

        if let o = try c.decodeIfPresent([String: [String]].self, forKey: .otherEcuErrors) {
            otherEcuErrors = o
        } else if let legacy = try c.decodeIfPresent([String: [String]].self, forKey: .ecu) {
            otherEcuErrors = legacy
        } else {
            otherEcuErrors = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        try c.encode(id, forKey: .id)
        try c.encode(Int64(round(timestamp * 1000.0)), forKey: .timestamp)
        try c.encode(vehicleName, forKey: .vehicleName)
        try c.encodeIfPresent(vin, forKey: .vin)
        try c.encode(mainDtcs, forKey: .mainDtcs)
        try c.encode(pendingDtcs, forKey: .pendingDtcs)
        try c.encode(permanentDtcs, forKey: .permanentDtcs)
        try c.encode(hasFreezeFrame, forKey: .hasFreezeFrame)
        try c.encode(otherEcuErrors, forKey: .otherEcuErrors)
    }

    var totalErrors: Int {
        let ecuTotal = otherEcuErrors.values.reduce(0) { $0 + $1.count }
        return mainDtcs.count + pendingDtcs.count + permanentDtcs.count + ecuTotal
    }

    var formattedDate: String {
        let date = Date(timeIntervalSince1970: timestamp)
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM yyyy, HH:mm"
        fmt.locale = Locale(identifier: "ru_RU")
        return fmt
    }()
}

// MARK: - SessionRepository

final class SessionRepository {

    static let shared = SessionRepository()

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    private init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory unavailable")
        }

        let dir = appSupport.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "com.uremont.whoop",
            isDirectory: true
        )

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(BrandConfig.sessionsFileName)
    }

    func save(record: SessionRecord) {
        lock.lock()
        defer { lock.unlock() }

        var records = loadAllUnsafe()
        records.insert(record, at: 0)
        if records.count > BrandConfig.maxSessionRecords {
            records = Array(records.prefix(BrandConfig.maxSessionRecords))
        }
        persist(records)
    }

    func loadAll() -> [SessionRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadAllUnsafe()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        persist([])
    }

    private func loadAllUnsafe() -> [SessionRecord] {
        let rawData: Data
        do {
            rawData = try Data(contentsOf: fileURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        } catch {
            DebugLogger.shared.e("SessionRepo", "loadAll read failed: \(error.localizedDescription)")
            return []
        }

        guard let array = try? JSONSerialization.jsonObject(with: rawData) as? [[String: Any]] else {
            DebugLogger.shared.w("SessionRepo", "loadAll: JSON is not an array of objects")
            return []
        }

        var out: [SessionRecord] = []
        var bad = 0
        for obj in array {
            guard let data = try? JSONSerialization.data(withJSONObject: obj),
                  let rec = try? decoder.decode(SessionRecord.self, from: data) else {
                bad += 1
                continue
            }
            out.append(rec)
        }
        if bad > 0 {
            DebugLogger.shared.w("SessionRepo", "loadAll: skipped \(bad) corrupt or unknown entries")
        }
        return out
    }

    private func persist(_ records: [SessionRecord]) {
        do {
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DebugLogger.shared.e("SessionRepo", "persist failed: \(error.localizedDescription)")
        }
    }
}
