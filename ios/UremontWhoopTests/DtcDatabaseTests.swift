import XCTest
@testable import UremontWhoop

final class DtcDatabaseTests: XCTestCase {

    // MARK: - dtcInfo

    func testDtcInfoUniversal() {
        let info = DtcLookup.dtcInfo(code: "P0420", profile: .auto)
        XCTAssertFalse(info.title.isEmpty)
        XCTAssertTrue(info.title.contains("катализатор") || info.title.contains("КПД"))
    }

    func testDtcInfoBmwSpecific() {
        let profile = CarProfile.manual(make: "BMW", model: "3 Series", year: "2020")
        let info = DtcLookup.dtcInfo(code: "P0011", profile: profile)
        XCTAssertTrue(info.title.contains("VANOS") || info.title.contains("фаз"))
    }

    func testDtcInfoVagSpecific() {
        let profile = CarProfile.manual(make: "Volkswagen")
        let info = DtcLookup.dtcInfo(code: "P0299", profile: profile)
        XCTAssertFalse(info.title.isEmpty)
    }

    func testDtcInfoMercedesSpecific() {
        let profile = CarProfile.manual(make: "Mercedes-Benz")
        let info = DtcLookup.dtcInfo(code: "P0016", profile: profile)
        XCTAssertTrue(info.title.contains("коленвал") || info.title.contains("рассогласование") || info.title.contains("Рассогласование"))
    }

    /// JDM/экспорт Toyota: марка из WMI (`Toyota car` …) включает Toyota-специфичные P1xxx.
    func testDtcInfoToyotaFromDetectedMake() {
        let info = DtcLookup.dtcInfo(code: "P1349", profile: .auto, detectedMake: "Toyota car")
        XCTAssertTrue(info.title.localizedCaseInsensitiveContains("VVT"))
        let generic = DtcLookup.dtcInfo(code: "P1349", profile: .auto, detectedMake: nil)
        XCTAssertTrue(generic.title.contains("P1349"))
    }

    func testDtcInfoToyotaManualProfile() {
        let profile = CarProfile.manual(make: "Toyota", model: "Caldina", year: "2005")
        let info = DtcLookup.dtcInfo(code: "P1349", profile: profile)
        XCTAssertTrue(info.title.localizedCaseInsensitiveContains("VVT"))
    }

    func testDtcInfoUnknownCode() {
        let info = DtcLookup.dtcInfo(code: "P9999", profile: .auto)
        XCTAssertTrue(info.title.contains("P9999"))
    }

    /// Суффикс FTB из UDS (`P0420-17`) не должен ломать поиск в универсальной таблице.
    func testDtcInfoUdsFtbSuffixUsesBaseCode() {
        let a = DtcLookup.dtcInfo(code: "P0420-17", profile: .auto)
        let b = DtcLookup.dtcInfo(code: "P0420", profile: .auto)
        XCTAssertEqual(a.title, b.title)
    }

    // MARK: - buildProblemDescription

    func testBuildProblemDescriptionKnownCode() {
        let info = DtcLookup.dtcInfo(code: "P0420", profile: .auto)
        let desc = DtcLookup.buildProblemDescription(code: "P0420", info: info)
        XCTAssertTrue(desc.contains("катализатор"))
    }

    func testBuildProblemDescriptionWithFtbSuffix() {
        let info = DtcLookup.dtcInfo(code: "P0420-17", profile: .auto)
        let desc = DtcLookup.buildProblemDescription(code: "P0420-17", info: info)
        XCTAssertTrue(desc.contains("катализатор"))
    }

    func testBuildProblemDescriptionMisfire() {
        let info = DtcLookup.dtcInfo(code: "P0302", profile: .auto)
        let desc = DtcLookup.buildProblemDescription(code: "P0302", info: info)
        XCTAssertTrue(desc.contains("цилиндр"))
        XCTAssertTrue(desc.contains("2"))
    }

    func testBuildProblemDescriptionUnknownFallback() {
        let info = DtcInfo(title: "Test Error", repair: "Fix it")
        let desc = DtcLookup.buildProblemDescription(code: "P9999", info: info)
        XCTAssertTrue(desc.contains("test error"))
        XCTAssertTrue(desc.contains("fix it"))
    }

    // MARK: - buildUremontUrl

    func testBuildUremontUrlWithProfile() {
        let profile = CarProfile.manual(make: "BMW", model: "X5", year: "2020")
        let info = DtcLookup.dtcInfo(code: "P0420", profile: profile)
        let url = DtcLookup.buildUremontUrl(profile: profile, vehicleInfo: nil, code: "P0420", info: info)
        XCTAssertTrue(url.hasPrefix("https://map.uremont.com/?ai="))
        XCTAssertTrue(url.contains("BMW"))
    }

    func testBuildUremontUrlAutoProfile() {
        let info = DtcLookup.dtcInfo(code: "P0171", profile: .auto)
        let url = DtcLookup.buildUremontUrl(profile: .auto, vehicleInfo: nil, code: "P0171", info: info)
        XCTAssertTrue(url.contains("map.uremont.com"))
    }

    func testBuildUremontUrlWithVehicleInfo() {
        let vi = VehicleInfo(vin: "WBAPH5C50BA123456", detectedMake: "BMW", detectedYear: "2011")
        let info = DtcLookup.dtcInfo(code: "P0300", profile: .auto)
        let url = DtcLookup.buildUremontUrl(profile: .auto, vehicleInfo: vi, code: "P0300", info: info)
        XCTAssertTrue(url.contains("BMW"))
        XCTAssertTrue(url.contains("2011"))
    }
}
