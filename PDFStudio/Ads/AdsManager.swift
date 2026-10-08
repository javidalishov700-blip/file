// Everything the app does with advertising: Apple's tracking prompt, Google's consent flow
// (UMP), one interstitial kept loaded, and the rule for when it may show. Same shape as the
// Slice & Blast AdsManager: ATT first, then consent, and no ad request until consent allows it.
import AppTrackingTransparency
import GoogleMobileAds
import Observation
import UIKit
import UserMessagingPlatform

@MainActor
@Observable
final class AdsManager {
    static let shared = AdsManager()

    /// Every 2nd finished tool run may end with an interstitial — never the first one, and
    /// never two within `minimumInterval`. The ad shows only after the result sheet is closed,
    /// so it never sits between the user and their file.
    private static let tasksBetweenInterstitials = 2
    private static let minimumInterval: TimeInterval = 90

    // ATT silently skips itself when requested before the window is key and visible.
    private static let attDelay: Duration = .seconds(1)

    /// True once consent allows ads and the SDK is started. Banners render only then.
    private(set) var canShowAds = false
    /// GDPR: withdrawing consent must stay as easy as giving it — Settings shows a button.
    private(set) var privacyOptionsRequired = false

    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var isLoadingInterstitial = false
    @ObservationIgnored private var loadFailures = 0
    @ObservationIgnored private var completedTasks = 0
    @ObservationIgnored private var lastInterstitial = Date.distantPast
    @ObservationIgnored private let delegate = InterstitialDelegate()

    var bannerUnitID: String { unitID("AdMobBannerUnitID", test: "ca-app-pub-3940256099942544/2435281174") }
    private var interstitialUnitID: String {
        unitID("AdMobInterstitialUnitID", test: "ca-app-pub-3940256099942544/4411468910")
    }

    private init() {
        delegate.onFinished = { [weak self] in
            self?.interstitial = nil
            self?.loadInterstitial()
        }
    }

    /// Debug builds always use Google's demo units; Release reads the ids from Info.plist.
    private func unitID(_ key: String, test: String) -> String {
        #if DEBUG
        return test
        #else
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return value.isEmpty ? test : value
        #endif
    }

    // MARK: Start-up

    func start() {
        guard !didStart else { return }
        didStart = true
        Task {
            try? await Task.sleep(for: Self.attDelay)
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined && !DemoMode.isActive {
                _ = await ATTrackingManager.requestTrackingAuthorization()
            }
            await gatherConsent()
        }
    }

    private func gatherConsent() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController)
        } catch {
            // Offline, most likely: whatever was consented to last time still stands and
            // canRequestAds already reflects it.
        }
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        startSDKIfAllowed()
    }

    private func startSDKIfAllowed() {
        guard !canShowAds, ConsentInformation.shared.canRequestAds else { return }
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor in
                self?.canShowAds = true
                self?.loadInterstitial()
            }
        }
    }

    func showPrivacyOptions() {
        Task {
            try? await ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController)
            // Consent refused at launch may have been granted just now.
            startSDKIfAllowed()
        }
    }

    // MARK: Interstitial

    private func loadInterstitial() {
        guard canShowAds, interstitial == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true
        Task {
            do {
                let ad = try await InterstitialAd.load(with: interstitialUnitID, request: Request())
                ad.fullScreenContentDelegate = delegate
                interstitial = ad
                loadFailures = 0
                isLoadingInterstitial = false
            } catch {
                isLoadingInterstitial = false
                // Retry after 2, 4, 8 … seconds, levelling off at 64.
                loadFailures += 1
                let delay = pow(2.0, Double(min(loadFailures, 6)))
                try? await Task.sleep(for: .seconds(delay))
                loadInterstitial()
            }
        }
    }

    /// Call when the user closes a tool's result sheet.
    func taskCompleted() {
        completedTasks += 1
        guard completedTasks % Self.tasksBetweenInterstitials == 0,
              Date().timeIntervalSince(lastInterstitial) > Self.minimumInterval,
              let ad = interstitial
        else { return }
        lastInterstitial = Date()
        ad.present(from: Self.topViewController)
    }

    static var topViewController: UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private final class InterstitialDelegate: NSObject, FullScreenContentDelegate {
    var onFinished: (@MainActor () -> Void)?

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        finish()
    }

    private func finish() {
        let callback = onFinished
        Task { @MainActor in callback?() }
    }
}
