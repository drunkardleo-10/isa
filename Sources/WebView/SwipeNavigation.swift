import Foundation
import WebKit
import SwiftUI
import AppKit

struct Pull: Equatable {
    var back: Bool
    var travel: CGFloat
    var armed: Bool
    var going: Bool
}

enum Swipe {
    static func calm(_ web: WKWebView) {
        let set = NSSelectorFromString("_setRubberBandingEnabled:")
        guard web.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        let left: UInt = 1 << 0
        let right: UInt = 1 << 2
        unsafeBitCast(web.method(for: set), to: Setter.self)(web, set, left | right)
    }

    static let watch = """
    (function () {
      if (window.__isaSwipe) return;
      window.__isaSwipe = true;

      var was = null, said = 0;

      function rootCanScroll() {
        var html = getComputedStyle(document.documentElement).overflowX;
        var body = document.body ? getComputedStyle(document.body).overflowX : 'visible';
        var effective = html === 'visible' ? body : html;
        return effective !== 'hidden' && effective !== 'clip';
      }

      function taken(e) {
        var el = e.target;
        if (el && el.nodeType !== 1) el = el.parentElement;
        while (el) {
          var root = el === document.documentElement || el === document.body;
          var can, left, max;
          if (root) {
            can = rootCanScroll();
            left = window.scrollX || 0;
            max = document.documentElement.scrollWidth - window.innerWidth;
          } else {
            var ox = getComputedStyle(el).overflowX;
            can = ox === 'auto' || ox === 'scroll';
            left = el.scrollLeft;
            max = el.scrollWidth - el.clientWidth;
          }
          if (can && max > 1) {
            if (e.deltaX > 0 ? left < max - 1 : left > 1) return true;
          }
          el = el.parentElement;
        }
        return false;
      }

      window.addEventListener('wheel', function (e) {
        if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;
        var t = taken(e), now = Date.now();
        if (t === was && now - said < 100) return;
        was = t; said = now;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.swipeNavigation) {
          window.webkit.messageHandlers.swipeNavigation.postMessage({ side: t ? 'taken' : 'free' });
        }
      }, { passive: true, capture: true });
    })();
    """
}

struct SwipeOverlayView: View {
    let pull: Pull?

    var body: some View {
        ZStack {
            if let pull = pull {
                Disc(pull: pull)
                    .id(pull.back ? "swipe_back" : "swipe_forward")
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.7))
                                .combined(with: .offset(x: pull.back ? -30 : 30)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.8))
                                .combined(with: .offset(x: pull.back ? (pull.going ? 40 : -30) : (pull.going ? -40 : 30)))
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: pull != nil)
    }
}

struct Disc: View {
    let pull: Pull

    var body: some View {
        let reach = 150.0 * (1.0 - exp(-Double(pull.travel) / 110.0))
        let grown = min(1.0, Double(pull.travel) / 110.0)
        let scale: CGFloat = pull.going ? 1.08 : CGFloat(0.86 + 0.14 * grown)

        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
            Circle()
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            Circle()
                .trim(from: 0, to: CGFloat(grown))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(0.75)
            Image(systemName: pull.back ? "arrow.left" : "arrow.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(width: 52, height: 52)
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
        .scaleEffect(scale)
        .opacity(pull.going ? 0 : 1)
        .offset(x: (pull.back ? 1.0 : -1.0) * (14.0 + reach * 0.2 + (pull.going ? 12.0 : 0.0)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pull.back ? .leading : .trailing)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.22), value: pull.going)
    }
}
