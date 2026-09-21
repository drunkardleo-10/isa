import SwiftUI
import WebKit

struct PageErrorInfo: Equatable {
    enum ErrorType: Equatable {
        case dnsProbePossible
        case nameNotResolved
        case connectionRefused
        case timedOut
        case internetDisconnected
        case processCrashed
        case generic(String)
    }

    let type: ErrorType
    let failingURL: URL?
    let host: String
    let localizedDescription: String

    var title: String {
        "Sorry, this page isn’t feeling too well."
    }

    var shortErrorLabel: String {
        switch type {
        case .dnsProbePossible, .nameNotResolved:
            return "DNS"
        case .connectionRefused:
            return "connection"
        case .timedOut:
            return "timeout"
        case .internetDisconnected:
            return "network"
        case .processCrashed:
            return "crash"
        case .generic(let desc):
            if desc.contains("400") { return "400" }
            if desc.contains("404") { return "404" }
            if desc.contains("500") { return "500" }
            if desc.contains("502") { return "502" }
            if desc.contains("503") { return "503" }
            return "loading"
        }
    }

    var errorCode: String {
        switch type {
        case .dnsProbePossible:
            return "DNS_PROBE_POSSIBLE"
        case .nameNotResolved:
            return "ERR_NAME_NOT_RESOLVED"
        case .connectionRefused:
            return "ERR_CONNECTION_REFUSED"
        case .timedOut:
            return "ERR_TIMED_OUT"
        case .internetDisconnected:
            return "ERR_INTERNET_DISCONNECTED"
        case .processCrashed:
            return "RESULT_CODE_KILLED_BAD_MESSAGE"
        case .generic:
            return "ERR_CONNECTION_FAILED"
        }
    }

    static func from(error: Error, url: URL?, host: String) -> PageErrorInfo {
        let ns = error as NSError
        let failingURL = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? url
        let resolvedHost: String
        if !host.isEmpty {
            resolvedHost = host
        } else if let h = failingURL?.host, !h.isEmpty {
            resolvedHost = h
        } else if let str = ns.userInfo["NSErrorFailingURLStringKey"] as? String, let u = URL(string: str), let h = u.host {
            resolvedHost = h
        } else {
            resolvedHost = ""
        }

        let type: ErrorType
        switch ns.code {
        case NSURLErrorCannotFindHost:
            type = .dnsProbePossible
        case NSURLErrorDNSLookupFailed:
            type = .nameNotResolved
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            type = .connectionRefused
        case NSURLErrorTimedOut:
            type = .timedOut
        case NSURLErrorNotConnectedToInternet:
            type = .internetDisconnected
        default:
            type = .generic(ns.localizedDescription)
        }

        return PageErrorInfo(
            type: type,
            failingURL: failingURL,
            host: resolvedHost,
            localizedDescription: ns.localizedDescription
        )
    }
}

struct SickBrowserIllustration: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var borderColor: Color {
        isDark ? Color(red: 0.60, green: 0.63, blue: 0.67) : Color(red: 0.38, green: 0.40, blue: 0.44)
    }

    private var windowFill: Color {
        isDark ? Color(red: 0.14, green: 0.15, blue: 0.16) : Color.white
    }

    private var featureColor: Color {
        isDark ? Color(red: 0.60, green: 0.63, blue: 0.67) : Color(red: 0.38, green: 0.40, blue: 0.44)
    }

    private var puffColor: Color {
        isDark ? Color(red: 0.22, green: 0.24, blue: 0.26) : Color(red: 0.88, green: 0.89, blue: 0.91)
    }

    private var addressBarFill: Color {
        isDark ? Color(red: 0.22, green: 0.24, blue: 0.26) : Color(red: 0.88, green: 0.89, blue: 0.91)
    }

    private var boxUpperFill: Color {
        isDark ? Color(red: 0.32, green: 0.34, blue: 0.38) : Color(red: 0.46, green: 0.48, blue: 0.52)
    }

    private var boxLowerFill: Color {
        isDark ? Color(red: 0.24, green: 0.26, blue: 0.29) : Color(red: 0.36, green: 0.38, blue: 0.42)
    }

    private var boxStroke: Color {
        isDark ? Color(red: 0.60, green: 0.63, blue: 0.67) : Color(red: 0.28, green: 0.30, blue: 0.34)
    }

    private var tissueFill: Color {
        isDark ? Color(red: 0.22, green: 0.24, blue: 0.26) : Color.white
    }

    private var tissueStroke: Color {
        isDark ? Color(red: 0.55, green: 0.58, blue: 0.62) : Color(red: 0.45, green: 0.48, blue: 0.52)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(windowFill)
                .frame(width: 230, height: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 3.0)
                )
                .overlay(
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(red: 0.94, green: 0.40, blue: 0.48))
                                .frame(width: 7, height: 7)
                            Circle()
                                .fill(Color(red: 0.96, green: 0.74, blue: 0.31))
                                .frame(width: 7, height: 7)
                            Circle()
                                .fill(Color(red: 0.48, green: 0.82, blue: 0.52))
                                .frame(width: 7, height: 7)
                        }
                        .padding(.leading, 12)
                        .padding(.top, 12)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(addressBarFill)
                            .frame(width: 135, height: 12)
                            .padding(.leading, 50)
                            .padding(.top, 10)

                        Canvas { context, size in
                            var leftEye = Path()
                            leftEye.move(to: CGPoint(x: 62, y: 76))
                            leftEye.addQuadCurve(to: CGPoint(x: 82, y: 76), control: CGPoint(x: 72, y: 71))
                            leftEye.addQuadCurve(to: CGPoint(x: 62, y: 76), control: CGPoint(x: 72, y: 83))
                            context.fill(leftEye, with: .color(featureColor))

                            var leftPuff = Path()
                            leftPuff.move(to: CGPoint(x: 62, y: 76))
                            leftPuff.addQuadCurve(to: CGPoint(x: 82, y: 76), control: CGPoint(x: 72, y: 83))
                            leftPuff.addQuadCurve(to: CGPoint(x: 62, y: 76), control: CGPoint(x: 72, y: 88))
                            context.fill(leftPuff, with: .color(puffColor))

                            var rightEye = Path()
                            rightEye.move(to: CGPoint(x: 148, y: 76))
                            rightEye.addQuadCurve(to: CGPoint(x: 168, y: 76), control: CGPoint(x: 158, y: 71))
                            rightEye.addQuadCurve(to: CGPoint(x: 148, y: 76), control: CGPoint(x: 158, y: 83))
                            context.fill(rightEye, with: .color(featureColor))

                            var rightPuff = Path()
                            rightPuff.move(to: CGPoint(x: 148, y: 76))
                            rightPuff.addQuadCurve(to: CGPoint(x: 168, y: 76), control: CGPoint(x: 158, y: 83))
                            rightPuff.addQuadCurve(to: CGPoint(x: 148, y: 76), control: CGPoint(x: 158, y: 88))
                            context.fill(rightPuff, with: .color(puffColor))

                            var mouth = Path()
                            mouth.move(to: CGPoint(x: 104, y: 114))
                            mouth.addQuadCurve(to: CGPoint(x: 128, y: 110), control: CGPoint(x: 116, y: 109))
                            mouth.addQuadCurve(to: CGPoint(x: 146, y: 115), control: CGPoint(x: 137, y: 111))
                            context.stroke(mouth, with: .color(featureColor), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

                            var stem = Path()
                            stem.move(to: CGPoint(x: 126, y: 110))
                            stem.addLine(to: CGPoint(x: 164, y: 132))
                            context.stroke(stem, with: .color(isDark ? Color(red: 0.35, green: 0.37, blue: 0.40) : Color(red: 0.82, green: 0.84, blue: 0.86)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

                            var mercury = Path()
                            mercury.move(to: CGPoint(x: 128, y: 111))
                            mercury.addLine(to: CGPoint(x: 163, y: 131))
                            context.stroke(mercury, with: .color(Color(red: 0.88, green: 0.12, blue: 0.22)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

                            let bulbRect = CGRect(x: 160, y: 127, width: 10, height: 10)
                            context.fill(Path(ellipseIn: bulbRect), with: .color(Color(red: 0.88, green: 0.12, blue: 0.22)))

                            let bulbGlowRect = CGRect(x: 162, y: 128, width: 3, height: 3)
                            context.fill(Path(ellipseIn: bulbGlowRect), with: .color(Color.white.opacity(0.7)))
                        }
                    }
                )

            ZStack(alignment: .top) {
                Canvas { context, size in
                    var t1 = Path()
                    t1.move(to: CGPoint(x: 14, y: 22))
                    t1.addCurve(to: CGPoint(x: 10, y: 8), control1: CGPoint(x: 12, y: 15), control2: CGPoint(x: 8, y: 10))
                    t1.addCurve(to: CGPoint(x: 24, y: 6), control1: CGPoint(x: 14, y: 4), control2: CGPoint(x: 20, y: 3))
                    t1.addCurve(to: CGPoint(x: 32, y: 22), control1: CGPoint(x: 28, y: 10), control2: CGPoint(x: 30, y: 16))
                    t1.closeSubpath()
                    context.fill(t1, with: .color(tissueFill))
                    context.stroke(t1, with: .color(tissueStroke), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                    var t2 = Path()
                    t2.move(to: CGPoint(x: 24, y: 22))
                    t2.addCurve(to: CGPoint(x: 26, y: 4), control1: CGPoint(x: 22, y: 12), control2: CGPoint(x: 22, y: 6))
                    t2.addCurve(to: CGPoint(x: 44, y: 4), control1: CGPoint(x: 30, y: 2), control2: CGPoint(x: 38, y: 2))
                    t2.addCurve(to: CGPoint(x: 42, y: 22), control1: CGPoint(x: 46, y: 8), control2: CGPoint(x: 44, y: 16))
                    t2.closeSubpath()
                    context.fill(t2, with: .color(tissueFill))
                    context.stroke(t2, with: .color(tissueStroke), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 54, height: 24)
                .offset(y: -14)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(boxUpperFill)
                        .frame(width: 52, height: 18)
                    Rectangle()
                        .fill(boxLowerFill)
                        .frame(width: 52, height: 10)
                }
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(boxStroke, lineWidth: 2)
                )
            }
            .offset(x: -20, y: 118)
        }
        .frame(width: 250, height: 180)
    }
}

struct PageCrashErrorView: View {
    let error: PageErrorInfo
    let onReload: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var backgroundColor: Color {
        isDark ? Color(red: 0.12, green: 0.13, blue: 0.14) : Color(red: 0.98, green: 0.98, blue: 0.99)
    }

    private var titleColor: Color {
        isDark ? Color(red: 0.91, green: 0.92, blue: 0.93) : Color(red: 0.13, green: 0.13, blue: 0.14)
    }

    private var messageColor: Color {
        isDark ? Color(red: 0.60, green: 0.63, blue: 0.67) : Color(red: 0.38, green: 0.40, blue: 0.44)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 22) {
                SickBrowserIllustration()
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    Text(error.title)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(titleColor)
                        .multilineTextAlignment(.center)

                    (Text(verbatim: "There was a ")
                    + Text(verbatim: "\(error.shortErrorLabel)").fontWeight(.bold)
                    + Text(verbatim: " error which caused this page to fail to load. Try refreshing this page or coming back later."))
                        .font(.system(size: 13.5))
                        .foregroundColor(messageColor)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 390)
                }
            }
            .padding(32)
        }
    }
}
