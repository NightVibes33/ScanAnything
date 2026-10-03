import Testing
@testable import ScanAnything

@MainActor
struct ScanAnythingCoreTests {
    @Test("Dex numbering is zero padded")
    func dexNumberFormatting() {
        let entry = DexEntry(number: 7, name: "Test")
        #expect(entry.dexNumber == "#0007")
    }

    @Test("Generated entries start in generating state")
    func newEntryState() {
        let entry = DexEntry(number: 1, name: "Specimen 1")
        #expect(entry.status == .generating)
        #expect(entry.glbFileName == nil)
    }
}
