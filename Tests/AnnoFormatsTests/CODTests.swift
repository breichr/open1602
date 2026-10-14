import Testing

@testable import AnnoFormats

@Suite("COD")
struct CODTests {
    @Test func decryptNegatesBytes() {
        let plain = Array("Nummer: 1".utf8)
        #expect(COD.decrypt(plain.map { 0 &- $0 }) == "Nummer: 1")
    }

    @Test func constantsExpressionsAndRelativeValues() {
        let doc = COD.parse(text: """
            GFXBASE = 10
            GFXNEXT = GFXBASE+4   ; Kommentar
            Objekt: HAUS
              @Nummer: 0
              Id:   20000+1
              Gfx:  GFXNEXT
              Size: 2, 3
              @Nummer: +1
              @Id:  +1
              @Gfx: -4
            EndObj;
            """)
        #expect(doc.unparsedLines.isEmpty)
        #expect(doc.variables["GFXNEXT"] == .int(14))
        let items = doc.items("HAUS")
        #expect(items.count == 2)
        #expect(items[0].int("Gfx") == 14)
        #expect(items[0]["Size"] == [.int(2), .int(3)])
        #expect(items[1].int("Id") == 20002)
        #expect(items[1].int("Gfx") == 10)
    }

    @Test func templateFillAndCopy() {
        let doc = COD.parse(text: """
            Objekt: HAUS
              @Nummer: 0
              Kind: UNUSED
              Rotate: 1
              ObjFill: 0, MAXHAUS
              @Nummer: 0
              Kind: BODEN
              @Nummer: +1
              VORLAGE = Nummer
              Kind: WALD
              Rotate: 0
              @Nummer: +1
              ObjFill: VORLAGE
              @Nummer: +1
            EndObj;
            """)
        let items = doc.items("HAUS")
        #expect(items.map { $0.symbol("Kind") } == ["BODEN", "WALD", "WALD", "UNUSED"])
        #expect(items[2].int("Rotate") == 0)
        #expect(items[3].int("Rotate") == 1)
        #expect(items[2].int("Nummer") == 2)
    }

    @Test func nestedObjectsAndRepeatedFields() {
        let doc = COD.parse(text: """
            Objekt: BGRUPPE
              Nummer: 1
              Objekt: BGRUPPE_WARE
                Ware: STOFFE, 0.6
                Ware: ALKOHOL, 0.5
              EndObj;
            EndObj;
            """)
        let ware = doc.items("BGRUPPE")[0].child("BGRUPPE_WARE")
        #expect(ware?.entries.map(\.values) == [[.symbol("STOFFE"), .float(0.6)], [.symbol("ALKOHOL"), .float(0.5)]])
    }

    @Test func symbolicNumbersAndRelativeVariables() {
        let doc = COD.parse(text: """
            X = 5
            @X = +3
            Objekt: INFRA
              Nummer: INFRA_A
              Nummer: INFRA_B
            EndObj;
            """)
        #expect(doc.variables["X"] == .int(8))
        #expect(doc.variables["INFRA_B"] == .int(1))
        #expect(doc.items("INFRA").count == 2)
    }

    @Test func spriteIndexHonoursRotationAndParts() {
        let rock = BuildingType(
            id: 1, number: 0, gfx: 100, kind: "FELS", width: 3, height: 3, rotateStride: 9,
            animationCount: 0, animationStride: 0, randomCount: 1, randomStride: 0, elevation: 20)
        #expect(rock.spriteIndex(rotation: 0, animation: 0, dx: 1, dy: 2) == 107)
        #expect(rock.spriteIndex(rotation: 1, animation: 0, dx: 0, dy: 0) == 109 + 6)
        #expect(rock.spriteIndex(rotation: 2, animation: 0, dx: 0, dy: 0) == 118 + 8)
        #expect(rock.spriteIndex(rotation: 3, animation: 0, dx: 0, dy: 0) == 127 + 2)
        let wide = BuildingType(
            id: 2, number: 0, gfx: 0, kind: "X", width: 2, height: 1, rotateStride: 2,
            animationCount: 0, animationStride: 0, randomCount: 1, randomStride: 0, elevation: 0)
        #expect(wide.footprint(rotation: 1) == (1, 2))
    }
}
