import SwiftUI

struct AdBlockStatusPopover: View {
    @ObservedObject var viewModel: BrowserViewModel

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.secondaryGroupingSize = 3
        return formatter
    }()

    init(viewModel: BrowserViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let currentHost = viewModel.activeTab.currentURL?.host
        let cosmeticCount = currentHost.map { AdBlockController.cosmeticRuleCount(for: $0) } ?? 0
        let counts = AdBlockController.totalRuleCounts
        let sessionCount = AdBlockController.sessionSitesWithRulesCount
        let isProtected = AdBlockController.isProtectionActive(for: currentHost)

        let formattedNetwork = Self.numberFormatter.string(from: NSNumber(value: counts.network)) ?? "\(counts.network)"
        let formattedCosmetic = Self.numberFormatter.string(from: NSNumber(value: counts.cosmetic)) ?? "\(counts.cosmetic)"

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if isProtected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                    Text("Protection active")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Protection paused")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }

            if let host = currentHost, !host.isEmpty {
                if cosmeticCount > 0 {
                    Text("Cosmetic rules: \(cosmeticCount) selector\(cosmeticCount == 1 ? "" : "s") for this site")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("No cosmetic rules for this domain")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No site loaded")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text("\(formattedNetwork) network rules + \(formattedCosmetic) cosmetic selectors loaded")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text("\(sessionCount) site\(sessionCount == 1 ? "" : "s") with rules applied this session")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(minWidth: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}
