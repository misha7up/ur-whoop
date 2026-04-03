package com.uremont.bluetooth

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit-тесты парсинга OBD2: DTC (Mode 03/07/0A), VIN (Mode 09), PID-данных,
 * декодирования года/марки из VIN, классификации BrandEcuHints.
 *
 * Зеркалит iOS `ObdParserTests.swift` + расширенное покрытие DTC/K-Line.
 */
class ObdParserTest {

    private lateinit var mgr: ObdConnectionManager

    @Before
    fun setUp() {
        mgr = ObdConnectionManager()
    }

    // ─────────────────────────── decodeDtc ───────────────────────────

    @Test
    fun decodeDtc_powertrain() {
        assertEquals("P0420", mgr.decodeDtc("0420"))
        assertEquals("P0171", mgr.decodeDtc("0171"))
        assertEquals("P0300", mgr.decodeDtc("0300"))
        assertEquals("P1523", mgr.decodeDtc("1523"))
    }

    @Test
    fun decodeDtc_chassis() {
        assertEquals("C0031", mgr.decodeDtc("4031"))
        assertEquals("C1110", mgr.decodeDtc("5110"))
    }

    @Test
    fun decodeDtc_body() {
        assertEquals("B1000", mgr.decodeDtc("9000"))
        assertEquals("B0051", mgr.decodeDtc("8051"))
    }

    @Test
    fun decodeDtc_network() {
        assertEquals("U0100", mgr.decodeDtc("C100"))
        assertEquals("U0001", mgr.decodeDtc("C001"))
    }

    @Test
    fun decodeDtc_shortHex() {
        assertEquals("AB", mgr.decodeDtc("AB"))
    }

    // ─────────────────────────── parseDtcFrameData ───────────────────

    @Test
    fun parseDtcFrameData_canWithCountByte() {
        mgr.isCanProtocol = true
        val dtcs = mutableSetOf<String>()
        // count=02, then P0420 (0420) and P0171 (0171)
        mgr.parseDtcFrameData("0204200171", dtcs)
        assertEquals(setOf("P0420", "P0171"), dtcs)
    }

    @Test
    fun parseDtcFrameData_kLineNoCountByte() {
        mgr.isCanProtocol = false
        val dtcs = mutableSetOf<String>()
        // K-Line: no count byte, first bytes are DTC directly: 0135 0000 0000
        mgr.parseDtcFrameData("013500000000", dtcs)
        assertEquals(setOf("P0135"), dtcs)
    }

    @Test
    fun parseDtcFrameData_kLineHondaBug() {
        // Регрессионный тест: Honda 2004 K-Line отвечала 43 01 35 00 00 00 00
        // Раньше парсер считал 01 за count byte и получал P3500 вместо P0135
        mgr.isCanProtocol = false
        val dtcs = mutableSetOf<String>()
        mgr.parseDtcFrameData("013500000000", dtcs)
        assertTrue("Должен содержать P0135", dtcs.contains("P0135"))
        assertFalse("Не должен содержать P3500", dtcs.contains("P3500"))
    }

    @Test
    fun parseDtcFrameData_canSingleDtc() {
        mgr.isCanProtocol = true
        val dtcs = mutableSetOf<String>()
        mgr.parseDtcFrameData("01042000000000", dtcs)
        assertEquals(setOf("P0420"), dtcs)
    }

    @Test
    fun parseDtcFrameData_skipsZeroPairs() {
        mgr.isCanProtocol = true
        val dtcs = mutableSetOf<String>()
        mgr.parseDtcFrameData("030420017103000000", dtcs)
        assertTrue(dtcs.contains("P0420"))
        assertTrue(dtcs.contains("P0171"))
        assertTrue(dtcs.contains("P0300"))
    }

    // ─────────────────────────── parseDtcResponse ────────────────────

    @Test
    fun parseDtcResponse_mode03_singleEcu() {
        mgr.isCanProtocol = true
        val result = mgr.parseDtcResponse("43", "43 01 04 20 00 00 00 00\r\n>")
        assertTrue(result is DtcResult.DtcList)
        val list = (result as DtcResult.DtcList).codes
        assertTrue("P0420 in result", list.contains("P0420"))
    }

    @Test
    fun parseDtcResponse_noData() {
        val result = mgr.parseDtcResponse("43", "NO DATA\r\n>")
        assertTrue(result is DtcResult.RawResponse)
    }

    @Test
    fun parseDtcResponse_mode07_noDtcs() {
        val result = mgr.parseDtcResponse(
            "47", "NO DATA\r\n>",
            missingMarkerResult = DtcResult.NoDtcs,
        )
        assertTrue(result is DtcResult.NoDtcs)
    }

    @Test
    fun parseDtcResponse_searching() {
        val result = mgr.parseDtcResponse("43", "SEARCHING...\r\n>")
        assertTrue(result is DtcResult.Error)
    }

    // ─────────────────────────── parseVin ─────────────────────────────

    @Test
    fun parseVin_valid() {
        val raw = "49 02 01 57 42 41 50 48 35 43 35 30 42 41 31 32 33 34 35 36"
        val vin = mgr.parseVin(raw)
        assertNotNull(vin)
        assertEquals(17, vin!!.length)
    }

    @Test
    fun parseVin_noData() {
        assertNull(mgr.parseVin("NO DATA\r\n>"))
    }

    @Test
    fun parseVin_tooShort() {
        assertNull(mgr.parseVin("4902014142"))
    }

    @Test
    fun parseVin_elmMultiframeVw() {
        val raw = "014 0:490201585738 1:5A5A5A37505A46 2:47303030323036"
        val vin = mgr.parseVin(raw)
        assertEquals("XW8ZZZ7PZFG000206", vin)
    }

    @Test
    fun parseVin_elmMultiframeToyota() {
        val raw = "014 0:490201345433 1:42413342425830 2:55303535313730"
        val vin = mgr.parseVin(raw)
        assertEquals("4T3BA3BBX0U055170", vin)
    }

    // ─────────────────────────── decodeVinMake ───────────────────────

    @Test
    fun decodeVinMake_bmw() {
        assertEquals("BMW car", mgr.decodeVinMake("WBAPH5C50BA123456"))
    }

    @Test
    fun decodeVinMake_mercedes() {
        assertEquals("Mercedes-Benz & Maybach", mgr.decodeVinMake("WDBRF61J21F123456"))
    }

    @Test
    fun decodeVinMake_vw() {
        assertEquals(
            "Volkswagen passenger car, Sharan, Golf Plus, Golf Sportsvan",
            mgr.decodeVinMake("WVWZZZ3CZWE123456"),
        )
    }

    @Test
    fun decodeVinMake_vwRussiaXw8() {
        assertEquals("Volkswagen Group Russia", mgr.decodeVinMake("XW8ZZZ7PZFG000206"))
    }

    @Test
    fun decodeVinMake_lada() {
        assertEquals("Lada / AvtoVAZ", mgr.decodeVinMake("XTA21703080123456"))
    }

    @Test
    fun decodeVinMake_tesla() {
        assertEquals("Tesla, Inc. passenger car", mgr.decodeVinMake("5YJSA1E26HF123456"))
    }

    @Test
    fun decodeVinMake_unknown() {
        assertNull(mgr.decodeVinMake("ZZZ123456789ABCDE"))
    }

    @Test
    fun decodeVinMake_short() {
        assertNull(mgr.decodeVinMake("WB"))
    }

    // ─────────────────────────── decodeVinYear ───────────────────────

    @Test
    fun decodeVinYear_oldCycle() {
        assertEquals("1996", mgr.decodeVinYear("1BAPH5B00T1234567"))
        assertEquals("2000", mgr.decodeVinYear("1BAPH5B00Y1234567"))
        assertEquals("2009", mgr.decodeVinYear("1BAPH5B0091234567"))
    }

    @Test
    fun decodeVinYear_newCycle() {
        assertEquals("2010", mgr.decodeVinYear("1BAPH550BA1234567"))
        assertEquals("2025", mgr.decodeVinYear("1BAPH550BS1234567"))
        assertEquals("2026", mgr.decodeVinYear("1BAPH550BT1234567"))
        assertEquals("2021", mgr.decodeVinYear("X9FMXXEEBMCR70295"))
        assertEquals("2011", mgr.decodeVinYear("WBAPH5C50BA123456"))
    }

    @Test
    fun decodeVinYear_invalid() {
        assertNull(mgr.decodeVinYear("SHORT"))
        assertNull(mgr.decodeVinYear("WBAPH550BZ123456X"))
    }

    // ─────────────────────────── BrandEcuHints ───────────────────────

    @Test
    fun classify_vagFromVin() {
        assertEquals(
            BrandEcuHints.VehicleBrandGroup.VAG,
            BrandEcuHints.classify(null, "WVWZZZ3CZWE123456"),
        )
    }

    @Test
    fun classify_toyotaFromMake() {
        assertEquals(
            BrandEcuHints.VehicleBrandGroup.TOYOTA,
            BrandEcuHints.classify("Toyota", null),
        )
    }

    @Test
    fun classify_mitsubishiJmb_notMazda() {
        // JMB — Mitsubishi Japan export, не должен попасть в Mazda
        val group = BrandEcuHints.classify(null, "JMBLYV78A0U000001")
        assertEquals(BrandEcuHints.VehicleBrandGroup.MITSUBISHI, group)
    }

    @Test
    fun classify_mazdaJm1() {
        // JM1 — Mazda Japan, должен остаться Mazda
        val group = BrandEcuHints.classify(null, "JM1BK323461000001")
        assertEquals(BrandEcuHints.VehicleBrandGroup.MAZDA, group)
    }

    @Test
    fun classify_renaultBeforePsa() {
        // VF1 — Renault, не PSA
        assertEquals(
            BrandEcuHints.VehicleBrandGroup.RENAULT,
            BrandEcuHints.classify(null, "VF1RFA00053000001"),
        )
    }

    @Test
    fun classify_psaVf3() {
        // VF3 — Peugeot/PSA
        assertEquals(
            BrandEcuHints.VehicleBrandGroup.PSA,
            BrandEcuHints.classify(null, "VF3ABCDEF12345678"),
        )
    }

    @Test
    fun classify_ladaFromVin() {
        assertEquals(
            BrandEcuHints.VehicleBrandGroup.LADA,
            BrandEcuHints.classify(null, "XTA21703080123456"),
        )
    }

    @Test
    fun classify_unknownBrand() {
        assertEquals(
            BrandEcuHints.VehicleBrandGroup.OTHER,
            BrandEcuHints.classify(null, "ZZZ123456789ABCDE"),
        )
    }

    @Test
    fun classify_subaruFromVinJf1() {
        assertEquals(
            BrandEcuHints.VehicleBrandGroup.SUBARU,
            BrandEcuHints.classify(null, "JF1SJ9LC5KG000001"),
        )
    }

    @Test
    fun classify_subaruFromMake() {
        assertEquals(
            BrandEcuHints.VehicleBrandGroup.SUBARU,
            BrandEcuHints.classify("Subaru", null),
        )
    }

    @Test
    fun classify_porscheFromMake_isVag() {
        assertEquals(
            BrandEcuHints.VehicleBrandGroup.VAG,
            BrandEcuHints.classify("Porsche", null),
        )
    }

    @Test
    fun ecuProbeList_universalBlocksPresent() {
        val specs = BrandEcuHints.ecuProbeList(null, null)
        val headers = specs.map { it.txHeader.uppercase() }
        assertTrue("7B0 in probes", headers.contains("7B0"))
        assertTrue("7D0 in probes", headers.contains("7D0"))
        assertTrue("7E1 in probes", headers.contains("7E1"))
        assertTrue("7E2 in probes", headers.contains("7E2"))
        assertTrue("7E3 in probes", headers.contains("7E3"))
        assertTrue("7E4 in probes", headers.contains("7E4"))
    }

    @Test
    fun ecuProbeList_noDuplicateHeaders() {
        val specs = BrandEcuHints.ecuProbeList("Volkswagen", "WVWZZZ3CZWE123456")
        val headers = specs.map { it.txHeader.uppercase() }
        assertEquals("No duplicates", headers.size, headers.toSet().size)
    }

    @Test
    fun ecuProbeList_manualToyotaWithoutVin_hasEps7A0() {
        val specs = BrandEcuHints.ecuProbeList(null, null, manualMakeHint = "Toyota")
        val headers = specs.map { it.txHeader.uppercase() }
        assertTrue("Toyota EPS 7A0 from manual make", headers.contains("7A0"))
    }

    @Test
    fun ecuProbeList_manualSubaruWithoutVin_hasBiu744() {
        val specs = BrandEcuHints.ecuProbeList(null, null, manualMakeHint = "Subaru")
        val headers = specs.map { it.txHeader.uppercase() }
        assertTrue("Subaru BIU 744", headers.contains("744"))
        assertTrue("Subaru EPS 746", headers.contains("746"))
    }

    @Test
    fun ecuProbeList_hondaHasAdditionalBlocks() {
        val specs = BrandEcuHints.ecuProbeList("Honda", "JHMGD18508S200001")
        val headers = specs.map { it.txHeader.uppercase() }
        assertTrue("Honda EPS 7A0", headers.contains("7A0"))
        assertTrue("Honda MICU 7C0", headers.contains("7C0"))
        assertTrue("Honda HVAC 770", headers.contains("770"))
        assertTrue("Honda VSA 730", headers.contains("730"))
        assertTrue("Honda ADAS 750", headers.contains("750"))
        assertTrue("Honda TPMS 780", headers.contains("780"))
    }

    // ─────────────────────────── UDS 0x19 DTC parsing ────────────────────────

    @Test
    fun parseUdsDtcRecords_singleDtc() {
        val dtcs = mutableSetOf<String>()
        // DTC P0068 (0068), FTB=17 (signal rate of change), status=09 (confirmed+testFailed)
        mgr.parseUdsDtcRecords("00681709", dtcs)
        assertEquals(setOf("P0068-17"), dtcs)
    }

    @Test
    fun parseUdsDtcRecords_multipleDtcs() {
        val dtcs = mutableSetOf<String>()
        // P0420 FTB=00 status=08 + C0031 FTB=11 status=09
        mgr.parseUdsDtcRecords("042000084031110900000000", dtcs)
        assertTrue("P0420 in result", dtcs.contains("P0420"))
        assertTrue("C0031-11 in result", dtcs.contains("C0031-11"))
        assertEquals(2, dtcs.size)
    }

    @Test
    fun parseUdsDtcRecords_skipZeroAndFfff() {
        val dtcs = mutableSetOf<String>()
        mgr.parseUdsDtcRecords("0000000000000000FFFF0000", dtcs)
        assertTrue("Should be empty", dtcs.isEmpty())
    }

    @Test
    fun parseUdsDtcRecords_ftbZeroNoSuffix() {
        val dtcs = mutableSetOf<String>()
        // P0171 FTB=00 status=09
        mgr.parseUdsDtcRecords("01710009", dtcs)
        assertEquals(setOf("P0171"), dtcs)
    }

    @Test
    fun parseUdsDtcResponse_validSingleFrame() {
        // 59 02 FF [DTC: P0420=0420, FTB=00, STATUS=08]
        val raw = "59 02 FF 04 20 00 08\r\n>"
        val result = mgr.parseUdsDtcResponse(raw)
        assertTrue(result is DtcResult.DtcList)
        val list = (result as DtcResult.DtcList).codes
        assertTrue("P0420 in result", list.contains("P0420"))
    }

    @Test
    fun parseUdsDtcResponse_noData() {
        val result = mgr.parseUdsDtcResponse("NO DATA\r\n>")
        assertTrue(result is DtcResult.Error)
    }

    @Test
    fun parseUdsDtcResponse_serviceNotSupported() {
        val result = mgr.parseUdsDtcResponse("7F 19 11\r\n>")
        assertTrue(result is DtcResult.Error)
    }

    @Test
    fun parseUdsDtcResponse_emptyResponse_noDtcs() {
        // 59 02 FF with no DTC records = no DTCs found
        val result = mgr.parseUdsDtcResponse("5902FF\r\n>")
        assertTrue(result is DtcResult.NoDtcs)
    }

    @Test
    fun parseUdsDtcResponse_bodyDtc() {
        // B1000 = hex 9000, FTB=54, STATUS=09
        val raw = "59 02 FF 90 00 54 09\r\n>"
        val result = mgr.parseUdsDtcResponse(raw)
        assertTrue(result is DtcResult.DtcList)
        val list = (result as DtcResult.DtcList).codes
        assertTrue("B1000-54 in result", list.contains("B1000-54"))
    }

    @Test
    fun parseUdsDtcResponse_networkDtc() {
        // U0100 = hex C100, FTB=00, STATUS=08
        val raw = "5902FF C1000008\r\n>"
        val result = mgr.parseUdsDtcResponse(raw)
        assertTrue(result is DtcResult.DtcList)
        val list = (result as DtcResult.DtcList).codes
        assertTrue("U0100 in result", list.contains("U0100"))
    }

    @Test
    fun dtcLookup_baseDtcCode_stripsFtbSuffix() {
        assertEquals("P0420", DtcLookup.baseDtcCode("P0420-17"))
        assertEquals("P0420", DtcLookup.baseDtcCode("p0420-17"))
        assertEquals("C0031", DtcLookup.baseDtcCode("C0031"))
    }

    @Test
    fun dtcLookup_dtcInfo_udsSuffixMatchesBase() {
        val a = DtcLookup.dtcInfo("P0420-17", CarProfile.Auto)
        val b = DtcLookup.dtcInfo("P0420", CarProfile.Auto)
        assertEquals(b.title, a.title)
    }

    @Test
    fun dtcLookup_toyotaP1349_whenDetectedMakeFromVin() {
        val toyota = DtcLookup.dtcInfo("P1349", CarProfile.Auto, detectedMake = "Toyota car")
        assertTrue(toyota.title.contains("VVT", ignoreCase = true))
        val notToyota = DtcLookup.dtcInfo("P1349", CarProfile.Auto, detectedMake = null)
        assertTrue(notToyota.title.contains("Код неисправности", ignoreCase = true))
    }

    @Test
    fun dtcLookup_toyotaManualProfile_withoutVin() {
        val manualToyota = CarProfile.Manual(make = "Toyota", model = "Caldina", year = "2005")
        val info = DtcLookup.dtcInfo("P1349", manualToyota, detectedMake = null)
        assertTrue(info.title.contains("VVT", ignoreCase = true))
    }
}
