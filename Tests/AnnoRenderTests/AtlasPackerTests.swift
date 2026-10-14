import Testing

@testable import AnnoRender

@Suite("AtlasPacker")
struct AtlasPackerTests {
    func overlaps(_ a: AtlasPlacement, _ b: AtlasPlacement) -> Bool {
        a.page == b.page && a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
    }

    @Test func placementsDoNotOverlapAndStayInsidePage() throws {
        let sizes = (0..<500).map { i in (width: 8 + (i * 37) % 120, height: 4 + (i * 53) % 90) }
        let result = try AtlasPacker(pageSize: 512).pack(sizes: sizes)
        #expect(result.placements.count == sizes.count)
        for (p, size) in zip(result.placements, sizes) {
            #expect(p.width == size.width && p.height == size.height)
            #expect(p.x >= 0 && p.y >= 0 && p.x + p.width <= 512 && p.y + p.height <= result.pageHeights[p.page])
        }
        for i in result.placements.indices {
            for j in result.placements.indices where j > i {
                #expect(!overlaps(result.placements[i], result.placements[j]))
            }
        }
        #expect(result.pageCount > 1)
    }

    @Test func emptyImagesGetEmptyPlacement() throws {
        let result = try AtlasPacker(pageSize: 64).pack(sizes: [(0, 0), (10, 10)])
        #expect(result.placements[0].width == 0)
        #expect(result.placements[1].width == 10)
    }

    @Test func tooLargeImageThrows() {
        #expect(throws: AtlasPacker.TooLarge.self) {
            try AtlasPacker(pageSize: 64).pack(sizes: [(65, 10)])
        }
    }

    @Test func pageHeightIsTrimmed() throws {
        let result = try AtlasPacker(pageSize: 4096).pack(sizes: [(64, 31), (64, 31)])
        #expect(result.pageHeights == [31])
    }
}
