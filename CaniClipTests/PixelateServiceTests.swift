import XCTest
@testable import CaniClip

final class PixelateServiceTests: XCTestCase {
    private func makeService() -> PixelateService {
        PixelateService(base: TestImages.solid(width: 16, height: 16, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
    }

    func testEvictDropsEntriesForAnnotationsNoLongerPresent() {
        let service = makeService()
        let a = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 8, height: 8), blockSize: 4))
        let b = Annotation(kind: .pixelate(CGRect(x: 8, y: 8, width: 8, height: 8), blockSize: 4))
        XCTAssertNotNil(service.image(for: a))
        XCTAssertNotNil(service.image(for: b))
        XCTAssertEqual(service.cachedCount, 2)

        service.evict(keeping: [b.id])
        XCTAssertEqual(service.cachedCount, 1)
        service.evict(keeping: [])
        XCTAssertEqual(service.cachedCount, 0)
    }
}
