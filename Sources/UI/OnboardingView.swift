import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var playgroundTabNamespace

    @State private var page: Int = 0
    @State private var forward: Bool = true
    @State private var pageAnimationTrigger: Bool = false

    @State private var headlineRevealedLine1: Bool = false
    @State private var headlineRevealedLine2: Bool = false
    @State private var revealedPointIndices: Set<Int> = []

    @State private var hoveredManifestoIndex: Int? = nil

    @State private var interactiveTab: Int = 0
    @State private var animatedDisplayCount: Int = 0
    @State private var isBlockTrackersOn: Bool = true
    @State private var isBlockAdsOn: Bool = true
    @State private var isStripParamsOn: Bool = true
    @State private var isZenActiveInDemo: Bool = true
    @State private var omnibarSearchEngine: String = "DuckDuckGo"

    @State private var selectedSource: WebKitSourceType = .safari
    @State private var importBookmarks: Bool = true
    @State private var importHistory: Bool = true
    @State private var customSelectedFileURL: URL? = nil
    @State private var isImporting: Bool = false
    @State private var importResult: WebKitImportResult? = nil

    @State private var isDefaultBrowser: Bool = {
        guard let probe = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }()
    @State private var askedDefault: Bool = false
    @State private var isCustomizingInStep3: Bool = false

    private let totalPages = 3

    private let babyRed = Color(red: 0.94, green: 0.36, blue: 0.42)

    private let manifestoItems: [(title: String, subtitle: String, icon: String)] = [
        ("ads", "145,000+ native WebKit network and cosmetic rules defuse ads before arrival.", "shield.slash.fill"),
        ("tracking scripts", "Full protection from fingerprinting, covert trackers, and YouTube scriptlets.", "eye.slash.fill"),
        ("invasive telemetry", "Zero phone-home packets. Your browsing is strictly between you and the web.", "antenna.radiowaves.left.and.right.slash"),
        ("distractions", "Zen mode, floating omnibar, clean typography, and zero sponsored junk.", "sparkles"),
        ("resource bloat", "Lightweight native memory footprint keeps your Mac cool and fast.", "bolt.batteryblock.fill"),
        ("lock-in", "No accounts, no sync trap, and no subscriptions. Pure native speed.", "lock.open.fill")
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ambientAtmosphereBackground(size: size)

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 32)
                        .padding(.top, 24)

                    ZStack {
                        switch page {
                        case 0:
                            step1SilenceView(size: size)
                        case 1:
                            step2ImagineView(size: size)
                        default:
                            step3ReadyView(size: size)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(
                        insertion: .opacity
                            .combined(with: .offset(x: forward ? 36 : -36))
                            .combined(with: .scale(scale: forward ? 0.96 : 1.04)),
                        removal: .opacity
                            .combined(with: .offset(x: forward ? -36 : 36))
                            .combined(with: .scale(scale: forward ? 1.04 : 0.96))
                    ))
                    .id(page)

                    bottomBar
                        .padding(.horizontal, 36)
                        .padding(.bottom, 28)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color(red: 0.10, green: 0.10, blue: 0.12) : Color(red: 0.97, green: 0.97, blue: 0.98))
        .ignoresSafeArea()
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: page)
        .onAppear {
            if page == 0 {
                startTextRevealAnimation()
            }
            triggerPageEntranceAnimation()
        }
        .onChange(of: page) { newPage in
            if newPage == 0 {
                startTextRevealAnimation()
            } else if newPage == 1 && interactiveTab == 0 {
                startCountUpAnimation()
            }
            triggerPageEntranceAnimation()
        }
    }

    private func startTextRevealAnimation() {
        headlineRevealedLine1 = false
        headlineRevealedLine2 = false
        revealedPointIndices.removeAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.55)) {
                headlineRevealedLine1 = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeOut(duration: 0.55)) {
                headlineRevealedLine2 = true
            }
        }

        for (index, _) in manifestoItems.enumerated() {
            let delay = 0.48 + Double(index) * 0.16
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.55)) {
                    _ = revealedPointIndices.insert(index)
                }
            }
        }
    }

    private func startCountUpAnimation() {
        animatedDisplayCount = 0
        let target = 99
        let steps = 36
        let totalDuration: Double = 0.95
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let eased = 1.0 - pow(1.0 - progress, 3)
            let val = Int(round(Double(target) * eased))
            let delay = progress * totalDuration * (0.6 + 0.4 * progress)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                animatedDisplayCount = val
            }
        }
    }

    private func triggerPageEntranceAnimation() {
        pageAnimationTrigger = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                pageAnimationTrigger = true
            }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: {
                viewModel.completeOnboarding()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Onboarding")
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            HStack {
                if page > 0 {
                    Button(action: {
                        forward = false
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            page -= 1
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(minWidth: 120, alignment: .leading)

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { idx in
                    Capsule()
                        .fill(idx == page ? babyRed : Color.primary.opacity(0.18))
                        .frame(width: idx == page ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: page)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            forward = idx > page
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                page = idx
                            }
                        }
                }
            }

            Spacer()

            HStack {
                Button(action: {
                    if page < totalPages - 1 {
                        forward = true
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            page += 1
                        }
                    } else {
                        viewModel.completeOnboarding()
                    }
                }) {
                    HStack(spacing: 6) {
                        Text(page == 0 ? "Start" : (page == 1 ? "Continue" : "Start Browsing"))
                            .font(.system(size: 12, weight: .bold))
                            .tracking(0.6)
                        Image(systemName: page == totalPages - 1 ? "checkmark" : "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                babyRed,
                                Color(red: 0.88, green: 0.30, blue: 0.36)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .frame(minWidth: 120, alignment: .trailing)
        }
    }

    private func ambientAtmosphereBackground(size: CGSize) -> some View {
        ZStack {
            (colorScheme == .dark ? Color(red: 0.10, green: 0.10, blue: 0.12) : Color(red: 0.97, green: 0.97, blue: 0.98))
                .ignoresSafeArea()

            LinearGradient(
                colors: colorScheme == .dark ? [
                    Color(red: 0.12, green: 0.12, blue: 0.14),
                    Color(red: 0.09, green: 0.09, blue: 0.11)
                ] : [
                    Color(red: 0.99, green: 0.99, blue: 1.0),
                    Color(red: 0.95, green: 0.95, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Canvas { ctx, cSize in
                let step: CGFloat = 32
                for x in stride(from: 0, to: cSize.width, by: step) {
                    for y in stride(from: 0, to: cSize.height, by: step) {
                        let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                        ctx.fill(dot, with: .color(Color.primary.opacity(0.025)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func step1SilenceView(size: CGSize) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 16)

            VStack(spacing: 16) {
                browserLogoView(size: 80)
                    .opacity(headlineRevealedLine1 ? 1 : 0)
                    .blur(radius: headlineRevealedLine1 ? 0 : 5)
                    .offset(y: headlineRevealedLine1 ? 0 : 8)

                VStack(spacing: 4) {
                    Text("A quiet, private browser")
                        .font(.system(size: 38, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.primary)
                        .opacity(headlineRevealedLine1 ? 1 : 0)
                        .blur(radius: headlineRevealedLine1 ? 0 : 6)
                        .offset(y: headlineRevealedLine1 ? 0 : 12)

                    Text("built for macOS.")
                        .font(.system(size: 38, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.primary)
                        .opacity(headlineRevealedLine2 ? 1 : 0)
                        .blur(radius: headlineRevealedLine2 ? 0 : 6)
                        .offset(y: headlineRevealedLine2 ? 0 : 12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<manifestoItems.count, id: \.self) { idx in
                    let item = manifestoItems[idx]
                    let isHovered = hoveredManifestoIndex == idx
                    let isRevealed = revealedPointIndices.contains(idx)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("No")
                                .font(.system(size: 26, weight: .medium, design: .serif))
                                .foregroundStyle(babyRed)

                            Text(item.title)
                                .font(.system(size: 26, weight: .regular, design: .serif))
                                .foregroundStyle(Color.primary.opacity(0.88))

                            Spacer(minLength: 0)

                            Image(systemName: item.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.secondary.opacity(isHovered ? 0.9 : 0.35))
                        }

                        if isHovered {
                            Text(item.subtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.secondary)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .padding(.leading, 4)
                                .padding(.top, 1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isHovered ? Color.primary.opacity(0.045) : Color.clear)
                    )
                    .onHover { h in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            hoveredManifestoIndex = h ? idx : nil
                        }
                    }
                    .opacity(isRevealed ? 1 : 0)
                    .blur(radius: isRevealed ? 0 : 6)
                    .offset(y: isRevealed ? 0 : 12)
                }
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step2ImagineView(size: CGSize) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("designed for quiet focus.")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(Color.primary.opacity(0.9))

                Text("Experience the native difference. Touch and test.")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Color.secondary)
            }
            .multilineTextAlignment(.center)
            .opacity(pageAnimationTrigger ? 1 : 0)
            .offset(y: pageAnimationTrigger ? 0 : 8)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: pageAnimationTrigger)

            interactiveBrowserPlayground(size: size)
                .opacity(pageAnimationTrigger ? 1 : 0)
                .scaleEffect(pageAnimationTrigger ? 1 : 0.96)
                .animation(.spring(response: 0.48, dampingFraction: 0.82).delay(0.08), value: pageAnimationTrigger)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func interactiveBrowserPlayground(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 1.0, green: 0.38, blue: 0.35)).frame(width: 10, height: 10)
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.22)).frame(width: 10, height: 10)
                    Circle().fill(Color(red: 0.18, green: 0.78, blue: 0.35)).frame(width: 10, height: 10)
                }
                .padding(.leading, 14)

                Spacer()

                HStack(spacing: 4) {
                    interactiveTabPill(index: 0, title: "Shield Engine", icon: "shield.checkered")
                    interactiveTabPill(index: 1, title: "Zen Mode", icon: "leaf.fill")
                    interactiveTabPill(index: 2, title: "Omnibar", icon: "magnifyingglass")
                }
                .padding(3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                )

                Spacer()

                Color.clear
                    .frame(width: 48, height: 10)
                    .padding(.trailing, 14)
            }
            .frame(height: 42)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider().opacity(0.4)

            ZStack {
                switch interactiveTab {
                case 0:
                    shieldDemoView
                case 1:
                    zenDemoView
                default:
                    omnibarDemoView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color(red: 0.98, green: 0.98, blue: 0.99))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: interactiveTab)
        }
        .frame(width: min(680, size.width - 80), height: min(390, size.height - 180))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 24, x: 0, y: 10)
    }

    private func interactiveTabPill(index: Int, title: String, icon: String) -> some View {
        let isSelected = interactiveTab == index
        return Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
                interactiveTab = index
            }
            if index == 0 {
                startCountUpAnimation()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .background {
                if isSelected {
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                        .matchedGeometryEffect(id: "activePlaygroundTabPill", in: playgroundTabNamespace)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var shieldDemoView: some View {
        HStack(spacing: 28) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(babyRed.opacity(colorScheme == .dark ? 0.16 : 0.08))
                        .frame(width: 80, height: 80)

                    Image(systemName: "shield.checkered")
                        .font(.system(size: 38))
                        .foregroundStyle(babyRed)
                }

                VStack(spacing: 3) {
                    Text("\(animatedDisplayCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(babyRed)

                    Text("trackers & ads defused")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 190)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Native WebKit Content Blocker")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)

                VStack(spacing: 8) {
                    interactiveToggleRow(
                        title: "145,000+ Defusal Rules",
                        subtitle: "Blocks ads before network payload arrives",
                        icon: "shield.slash.fill",
                        isOn: $isBlockAdsOn
                    )
                    interactiveToggleRow(
                        title: "Zero Fingerprinting",
                        subtitle: "Neutralizes covert tracking scripts",
                        icon: "eye.slash.fill",
                        isOn: $isBlockTrackersOn
                    )
                    interactiveToggleRow(
                        title: "Strip URL Telemetry",
                        subtitle: "Strips UTM, fbclid, and referral trackers",
                        icon: "link.badge.plus",
                        isOn: $isStripParamsOn
                    )
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 11))
                    Text("Strictly private • Zero phone-home packets")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 20)
        }
        .padding(24)
        .onAppear {
            startCountUpAnimation()
        }
    }

    private func interactiveToggleRow(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isOn.wrappedValue ? babyRed : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var zenDemoView: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(Color.green)
                    Text("Zen Reading Environment")
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isZenActiveInDemo.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isZenActiveInDemo ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isZenActiveInDemo ? Color.green : Color.secondary)
                        Text(isZenActiveInDemo ? "Zen Mode: Active" : "Zen Mode: Off")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                if isZenActiveInDemo {
                    VStack(spacing: 12) {
                        Text("Simplicity is about subtracting the obvious and adding the meaningful.")
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 32)
                            .lineSpacing(4)

                        Text("Toolbars vanish automatically. Full focus on reading.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            Text("⌘L")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            Text("summons the floating omnibar instantly")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    VStack(spacing: 10) {
                        HStack {
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 80, height: 12)
                            Spacer()
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 140, height: 12)
                            Spacer()
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 60, height: 12)
                        }
                        .padding(.horizontal, 20)

                        HStack {
                            Rectangle().fill(Color.red.opacity(0.12)).frame(width: 90, height: 40)
                                .overlay(Text("AD").font(.system(size: 9, weight: .bold)).foregroundStyle(.red))
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(maxWidth: .infinity, maxHeight: 40)
                            Rectangle().fill(Color.red.opacity(0.12)).frame(width: 90, height: 40)
                                .overlay(Text("AD").font(.system(size: 9, weight: .bold)).foregroundStyle(.red))
                        }
                        .padding(.horizontal, 20)

                        Text("Cluttered web: sidebars, banners, and toolbars stealing attention.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var omnibarDemoView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Floating Minimal Omnibar")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Instant keyboard-first search, calculations, and tab jumping")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(babyRed)
                    .font(.system(size: 12, weight: .semibold))

                Text("search with \(omnibarSearchEngine)...")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Text("ESC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.20) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(babyRed.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
            .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text("Switch Search Engine:")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(["DuckDuckGo", "Google", "Ecosia", "Kagi", "Brave"], id: \.self) { engine in
                        let isSel = omnibarSearchEngine == engine
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                omnibarSearchEngine = engine
                            }
                        }) {
                            Text(engine)
                                .font(.system(size: 11, weight: isSel ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4.5)
                                .background(isSel ? babyRed.opacity(0.15) : Color.primary.opacity(0.04))
                                .foregroundStyle(isSel ? babyRed : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                quickCommandChip(keys: "⌘T", label: "New Tab")
                quickCommandChip(keys: "⌘L", label: "Focus Omnibar")
                quickCommandChip(keys: "⌘⇧B", label: "Ad Shields")
            }
            .padding(.bottom, 16)
        }
    }

    private func quickCommandChip(keys: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private func step3ReadyView(size: CGSize) -> some View {
        HStack(spacing: 48) {
            ZStack {
                ForEach(0..<3, id: \.self) { cardIdx in
                    let angle: Double = cardIdx == 0 ? -10 : (cardIdx == 1 ? 8 : -3)
                    let scale: CGFloat = cardIdx == 0 ? 0.88 : (cardIdx == 1 ? 0.92 : 0.96)
                    let xOff: CGFloat = cardIdx == 0 ? -28 : (cardIdx == 1 ? 24 : -8)
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .frame(width: 230, height: 230)
                        .rotationEffect(.degrees(angle))
                        .scaleEffect(scale)
                        .offset(x: xOff, y: CGFloat(cardIdx * 4))
                        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
                }

                browserLogoView(size: 200)
            }
            .frame(width: 280)
            .opacity(pageAnimationTrigger ? 1 : 0)
            .scaleEffect(pageAnimationTrigger ? 1 : 0.88)
            .animation(.spring(response: 0.48, dampingFraction: 0.8), value: pageAnimationTrigger)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One click and\nthe web is yours.")
                        .font(.system(size: 38, weight: .regular, design: .serif))
                        .foregroundStyle(Color.primary)
                        .lineSpacing(3)

                    Text("Zero telemetry, instant WebKit memory management, and built-in ad defusal. Tailor it to your workflow in seconds.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .frame(maxWidth: 440)
                }
                .opacity(pageAnimationTrigger ? 1 : 0)
                .offset(y: pageAnimationTrigger ? 0 : 10)
                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.08), value: pageAnimationTrigger)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button(action: {
                            askedDefault = true
                            let app = Bundle.main.bundleURL
                            for scheme in ["http", "https"] {
                                NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { _ in
                                    DispatchQueue.main.async {
                                        if let probe = URL(string: "https://example.com"),
                                           let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) {
                                            isDefaultBrowser = handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
                                        }
                                    }
                                }
                            }
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: isDefaultBrowser ? "checkmark.circle.fill" : "globe")
                                    .foregroundStyle(isDefaultBrowser ? Color.green : Color.primary)
                                Text(isDefaultBrowser ? "Default Browser" : "Make Default Browser")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isDefaultBrowser ? Color.green.opacity(0.12) : Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isDefaultBrowser ? Color.green.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isCustomizingInStep3.toggle()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                Text(isCustomizingInStep3 ? "Hide Importer & Settings" : "Import & Search Settings")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isCustomizingInStep3 ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isCustomizingInStep3 ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if isCustomizingInStep3 {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("Search:")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(SearchEngine.allCases) { engine in
                                    let sel = viewModel.searchEngine == engine
                                    Button(action: {
                                        viewModel.searchEngine = engine
                                    }) {
                                        Text(engine.displayName)
                                            .font(.system(size: 11, weight: sel ? .semibold : .regular))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(sel ? babyRed.opacity(0.16) : Color.primary.opacity(0.04))
                                            .foregroundStyle(sel ? babyRed : .secondary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            HStack(spacing: 8) {
                                Text("Layout:")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Button(action: {
                                    viewModel.tabPlacement = .top
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "macwindow")
                                        Text("Top Bar")
                                    }
                                    .font(.system(size: 11, weight: viewModel.tabPlacement == .top ? .semibold : .regular))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(viewModel.tabPlacement == .top ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    viewModel.tabPlacement = .left
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sidebar.left")
                                        Text("Left Sidebar")
                                    }
                                    .font(.system(size: 11, weight: viewModel.tabPlacement == .left ? .semibold : .regular))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(viewModel.tabPlacement == .left ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 10) {
                                ForEach(WebKitSourceType.allCases.filter { $0.isDetected }) { src in
                                    let isSel = selectedSource == src
                                    Button(action: {
                                        selectedSource = src
                                    }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: src.iconName)
                                            Text(src.displayName)
                                        }
                                        .font(.system(size: 11, weight: isSel ? .semibold : .regular))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(isSel ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button(action: executeImport) {
                                    HStack(spacing: 5) {
                                        if isImporting {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.down.doc")
                                        }
                                        Text(isImporting ? "Importing…" : "Import Now")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isImporting)
                            }

                            if let res = importResult {
                                HStack(spacing: 5) {
                                    Image(systemName: res.bookmarksCount > 0 ? "checkmark.circle.fill" : "info.circle.fill")
                                        .foregroundStyle(res.bookmarksCount > 0 ? Color.green : Color.orange)
                                    Text(res.message)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .opacity(pageAnimationTrigger ? 1 : 0)
                .offset(y: pageAnimationTrigger ? 0 : 12)
                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.14), value: pageAnimationTrigger)
            }
            .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func executeImport() {
        isImporting = true
        WebKitImporter.shared.performImport(
            source: selectedSource,
            selectedFileURL: customSelectedFileURL,
            importBookmarks: importBookmarks,
            importHistory: importHistory
        ) { result in
            self.isImporting = false
            self.importResult = result
        }
    }

    private func loadBrowserLogo() -> NSImage? {
        if let img = NSImage(named: "AppIcon") {
            return img
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        if let img = NSImage(contentsOfFile: "Assets/AppIcon.icns") {
            return img
        }
        if let img = NSImage(contentsOfFile: "Assets/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png") {
            return img
        }
        if let img = NSImage(contentsOfFile: "Assets/isa_browser.png") {
            return img
        }
        return nil
    }

    @ViewBuilder
    private func browserLogoView(size: CGFloat) -> some View {
        if let logo = loadBrowserLogo() {
            Image(nsImage: logo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: size * 0.08, x: 0, y: size * 0.04)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                babyRed,
                                Color(red: 0.88, green: 0.30, blue: 0.36)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "safari.fill")
                    .font(.system(size: size * 0.48))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: Color.black.opacity(0.15), radius: size * 0.08, x: 0, y: size * 0.04)
        }
    }
}
