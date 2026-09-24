import SwiftUI
import AppKit

struct FindBarView: View {
    @ObservedObject var findState: TabFindState
    @FocusState private var isFieldFocused: Bool

    private var matchCountText: String {
        let trimmed = findState.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }
        if findState.totalMatches == 0 {
            return "No results"
        }
        return "\(findState.currentIndex) of \(findState.totalMatches)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            TextField("Find in page", text: $findState.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 160)
                .focused($isFieldFocused)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.shift) {
                        findState.findPrevious()
                    } else {
                        findState.findNext()
                    }
                }
                .onExitCommand {
                    findState.dismiss()
                }

            if !matchCountText.isEmpty {
                Text(matchCountText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(findState.totalMatches == 0 ? .secondary : .primary)
                    .lineLimit(1)
            }

            Divider()
                .frame(height: 14)
                .opacity(0.4)

            Button(action: {
                findState.findPrevious()
            }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(findState.totalMatches > 0 ? .primary : .secondary.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(findState.totalMatches == 0)
            .help("Previous Match (⇧⌘G or ⇧Return)")

            Button(action: {
                findState.findNext()
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(findState.totalMatches > 0 ? .primary : .secondary.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(findState.totalMatches == 0)
            .help("Next Match (⌘G or Return)")

            Button(action: {
                findState.dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Done (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor).opacity(0.92)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 6)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
    }
}
