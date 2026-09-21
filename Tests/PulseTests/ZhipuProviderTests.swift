import Testing
@testable import Pulse

/// The two GLM rows are one company's international and mainland storefronts,
/// and they share a mark rather than each wearing a product's own — see
/// [zai.md](../../Docs/providers/zai.md) for what that costs on the rail.
///
/// That the mark renders rather than merely loading is `ProviderMarkTests`.
struct ZhipuProviderTests {
    @Test
    func bothStorefrontsShareTheZaiMark() {
        #expect(Provider.glmCoding.iconResource == "zai")
        #expect(Provider.zai.iconResource == Provider.glmCoding.iconResource)
    }
}
