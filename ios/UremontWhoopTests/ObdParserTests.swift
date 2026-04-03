import XCTest
@testable import UremontWhoop

final class ObdParserTests: XCTestCase {

    private var mgr: ObdConnectionManager!

    override func setUp() {
        super.setUp()
        mgr = ObdConnectionManager()
    }

    // MARK: - decodeDtc

    func testDecodeDtcPowertrain() {
        XCTAssertEqual(mgr.decodeDtc("0420"), "P0420")
        XCTAssertEqual(mgr.decodeDtc("0171"), "P0171")
        XCTAssertEqual(mgr.decodeDtc("0300"), "P0300")
        XCTAssertEqual(mgr.decodeDtc("1523"), "P1523")
    }

    func testDecodeDtcChassis() {
        XCTAssertEqual(mgr.decodeDtc("4031"), "C0031")
        XCTAssertEqual(mgr.decodeDtc("5110"), "C1110")
    }

    func testDecodeDtcBody() {
        XCTAssertEqual(mgr.decodeDtc("9000"), "B1000")
        XCTAssertEqual(mgr.decodeDtc("8051"), "B0051")
    }

    func testDecodeDtcNetwork() {
        XCTAssertEqual(mgr.decodeDtc("C100"), "U0100")
        XCTAssertEqual(mgr.decodeDtc("C001"), "U0001")
    }

    func testDecodeDtcShortHex() {
        XCTAssertEqual(mgr.decodeDtc("AB"), "AB")
    }

    // MARK: - parseHexBytes

    func testParseHexBytesSimple() {
        let bytes = mgr.parseHexBytes(from: "4105FF", marker: "41")
        XCTAssertEqual(bytes, [0x41, 0x05, 0xFF])
    }

    func testParseHexBytesMarkerNotFound() {
        XCTAssertNil(mgr.parseHexBytes(from: "4205FF", marker: "43"))
    }

    func testParseHexBytesRpmResponse() {
        let bytes = mgr.parseHexBytes(from: "410C0FA0", marker: "41")
        XCTAssertNotNil(bytes)
        guard let b = bytes, b.count >= 4 else { return XCTFail() }
        let rpm = (b[2] * 256 + b[3]) / 4
        XCTAssertEqual(rpm, 1000)
    }

    // MARK: - parseVin

    func testParseVinValid() {
        let raw = "49 02 01 57 42 41 50 48 35 43 35 30 42 41 31 32 33 34 35 36"
        let vin = mgr.parseVin(raw)
        XCTAssertNotNil(vin)
        XCTAssertEqual(vin?.count, 17)
    }

    func testParseVinNoData() {
        XCTAssertNil(mgr.parseVin("NO DATA\r\n>"))
    }

    func testParseVinTooShort() {
        XCTAssertNil(mgr.parseVin("4902014142"))
    }

    /// Реальный формат ELM327 ISO-TP (`014 0:… 1:… 2:…`) — раньше ломался regex `[0-9]+:` после склейки пробелов.
    func testParseVinElmMultiframeVw() {
        let raw = """
        014 0:490201585738 1:5A5A5A37505A46 2:47303030323036
        """
        let vin = mgr.parseVin(raw)
        XCTAssertEqual(vin, "XW8ZZZ7PZFG000206")
    }

    func testParseVinElmMultiframeToyota() {
        let raw = """
        014 0:490201345433 1:42413342425830 2:55303535313730
        """
        let vin = mgr.parseVin(raw)
        XCTAssertEqual(vin, "4T3BA3BBX0U055170")
    }

    // MARK: - decodeVinMake

    func testDecodeVinMakeBMW() {
        XCTAssertEqual(mgr.decodeVinMake("WBAPH5C50BA123456"), "BMW car")
    }

    func testDecodeVinMakeMercedes() {
        XCTAssertEqual(mgr.decodeVinMake("WDBRF61J21F123456"), "Mercedes-Benz & Maybach")
    }

    func testDecodeVinMakeVW() {
        XCTAssertEqual(mgr.decodeVinMake("WVWZZZ3CZWE123456"), "Volkswagen passenger car, Sharan, Golf Plus, Golf Sportsvan")
    }

    func testDecodeVinMakeVwSpainXW8() {
        XCTAssertEqual(mgr.decodeVinMake("XW8ZZZ7PZFG000206"), "Volkswagen Group Russia")
    }

    func testDecodeVinMakeLada() {
        XCTAssertEqual(mgr.decodeVinMake("XTA21703080123456"), "Lada / AvtoVAZ")
    }

    func testDecodeVinMakeTesla() {
        XCTAssertEqual(mgr.decodeVinMake("5YJSA1E26HF123456"), "Tesla, Inc. passenger car")
    }

    func testDecodeVinMakeUnknown() {
        XCTAssertNil(mgr.decodeVinMake("ZZZ123456789ABCDE"))
    }

    func testDecodeVinMakeShort() {
        XCTAssertNil(mgr.decodeVinMake("WB"))
    }

    // MARK: - decodeVinYear

    func testDecodeVinYearOldCycle() {
        // Только WMI `1`…`5` (Северная Америка): буква на 7-й позиции → старый 30-летний цикл.
        XCTAssertEqual(mgr.decodeVinYear("1BAPH5B00T1234567"), "1996")
        XCTAssertEqual(mgr.decodeVinYear("1BAPH5B00Y1234567"), "2000")
        XCTAssertEqual(mgr.decodeVinYear("1BAPH5B0091234567"), "2009")
    }

    func testDecodeVinYearNewCycle() {
        // NA: 7-я — цифра → новый цикл
        XCTAssertEqual(mgr.decodeVinYear("1BAPH550BA1234567"), "2010")
        XCTAssertEqual(mgr.decodeVinYear("1BAPH550BS1234567"), "2025")
        XCTAssertEqual(mgr.decodeVinYear("1BAPH550BT1234567"), "2026")
        // EU/RU и пр.: ближе к текущему году (не «1991» для `M` при букве на 7-й позиции)
        XCTAssertEqual(mgr.decodeVinYear("X9FMXXEEBMCR70295"), "2021")
        // Европейский WMI, 10-я `B` → ближе к 2011, чем к 1981
        XCTAssertEqual(mgr.decodeVinYear("WBAPH5C50BA123456"), "2011")
    }

    func testDecodeVinYearInvalid() {
        XCTAssertNil(mgr.decodeVinYear("SHORT"))
        XCTAssertNil(mgr.decodeVinYear("WBAPH550BZ123456X"))
    }

    // MARK: - UDS 0x19

    func testParseUdsDtcRecordsSingle() {
        var s = Set<String>()
        mgr.parseUdsDtcRecords("00681709", into: &s)
        XCTAssertEqual(s, ["P0068-17"])
    }

    func testParseUdsDtcRecordsMultiple() {
        var s = Set<String>()
        mgr.parseUdsDtcRecords("042000084031110900000000", into: &s)
        XCTAssertTrue(s.contains("P0420"))
        XCTAssertTrue(s.contains("C0031-11"))
        XCTAssertEqual(s.count, 2)
    }

    func testParseUdsDtcRecordsSkipZero() {
        var s = Set<String>()
        mgr.parseUdsDtcRecords("0000000000000000FFFF0000", into: &s)
        XCTAssertTrue(s.isEmpty)
    }

    func testParseUdsDtcResponseValid() {
        let raw = "59 02 FF 04 20 00 08\r\n>"
        let r = mgr.parseUdsDtcResponse(raw)
        guard case .dtcList(let codes) = r else { return XCTFail() }
        XCTAssertTrue(codes.contains("P0420"))
    }

    func testParseUdsDtcResponseNoData() {
        let r = mgr.parseUdsDtcResponse("NO DATA\r\n>")
        guard case .error = r else { return XCTFail() }
    }

    func testParseUdsDtcResponse7F19() {
        let r = mgr.parseUdsDtcResponse("7F 19 11\r\n>")
        guard case .error = r else { return XCTFail() }
    }

    func testParseUdsDtcResponseEmpty5902() {
        let r = mgr.parseUdsDtcResponse("5902FF\r\n>")
        guard case .noDtcs = r else { return XCTFail() }
    }

    func testParseUdsDtcResponseBody() {
        let r = mgr.parseUdsDtcResponse("59 02 FF 90 00 54 09\r\n>")
        guard case .dtcList(let codes) = r else { return XCTFail() }
        XCTAssertTrue(codes.contains("B1000-54"))
    }

    func testParseUdsDtcResponseNetwork() {
        let r = mgr.parseUdsDtcResponse("5902FF C1000008\r\n>")
        guard case .dtcList(let codes) = r else { return XCTFail() }
        XCTAssertTrue(codes.contains("U0100"))
    }
}
