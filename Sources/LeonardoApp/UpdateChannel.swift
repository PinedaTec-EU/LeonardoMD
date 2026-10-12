import Foundation

/// Subscription choice is independent of the installed package's maturity.
enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: Self { self }
    var allowedChannels: Set<String> { self == .beta ? ["beta"] : [] }
    @MainActor var title: String { L10n.text(self == .stable ? "Stable" : "Beta") }
}

struct UpdateConfiguration {
    let version: ApplicationVersion
    let installedChannel: UpdateChannel?
    let stableFeed: URL?
    let betaFeed: URL?
    let isConfigured: Bool

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        version = ApplicationVersion(info: info)
        installedChannel = (info["LeonardoUpdateChannel"] as? String).flatMap(UpdateChannel.init(rawValue:))
        stableFeed = Self.feed(info["LeonardoStableFeedURL"])
        betaFeed = Self.feed(info["LeonardoBetaFeedURL"])
        let key = info["SUPublicEDKey"] as? String
        isConfigured = key != nil && key == info["LeonardoUpdatePublicKey"] as? String
            && Data(base64Encoded: key ?? "")?.count == 32
            && stableFeed != nil && betaFeed != nil && stableFeed != betaFeed
    }

    func feed(for channel: UpdateChannel) -> URL? { channel == .stable ? stableFeed : betaFeed }

    private static func feed(_ value: Any?) -> URL? {
        guard let text = value as? String, let url = URL(string: text),
              url.scheme == "https", url.host != nil, url.user == nil,
              url.password == nil, url.fragment == nil else { return nil }
        return url
    }
}
