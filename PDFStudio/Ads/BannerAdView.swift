import GoogleMobileAds
import SwiftUI

/// A standard 320×50 banner, shown only once consent allows ads.
struct BannerAdView: View {
    private let ads = AdsManager.shared

    var body: some View {
        if ads.canShowAds {
            BannerRepresentable(unitID: ads.bannerUnitID)
                .frame(width: 320, height: 50)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.bar)
        }
    }
}

private struct BannerRepresentable: UIViewRepresentable {
    let unitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = unitID
        banner.rootViewController = AdsManager.topViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        if banner.rootViewController == nil { banner.rootViewController = AdsManager.topViewController }
    }
}
