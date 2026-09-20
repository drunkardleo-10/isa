import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DownloadsPopoverView: View {
    @ObservedObject var downloadManager: DownloadManager = DownloadManager.shared

    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB, .useBytes, .useGB]
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloads")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if downloadManager.hasActiveDownloads {
                    let count = downloadManager.activeDownloads.count
                    Text("\(count) active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.bottom, 2)

            if downloadManager.items.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No recent downloads")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(downloadManager.items) { item in
                        DownloadRowView(item: item)
                        if item.id != downloadManager.items.last?.id {
                            Divider()
                                .opacity(0.3)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

private struct DownloadRowView: View {
    @ObservedObject var item: DownloadItem

    private var fileIcon: NSImage {
        let ext = (item.suggestedFilename as NSString).pathExtension
        let icon: NSImage
        if let utType = UTType(filenameExtension: ext) {
            icon = NSWorkspace.shared.icon(for: utType)
        } else {
            icon = NSWorkspace.shared.icon(for: .data)
        }
        icon.size = NSSize(width: 24, height: 24)
        return icon
    }

    private var progressSubtitle: String {
        switch item.status {
        case .downloading:
            if item.totalBytes > 0 {
                let current = DownloadsPopoverView.byteFormatter.string(fromByteCount: item.bytesDownloaded)
                let total = DownloadsPopoverView.byteFormatter.string(fromByteCount: item.totalBytes)
                let pct = Int(item.progress * 100)
                return "\(current) of \(total) (\(pct)%)"
            } else if item.bytesDownloaded > 0 {
                let current = DownloadsPopoverView.byteFormatter.string(fromByteCount: item.bytesDownloaded)
                return "\(current) downloaded"
            } else {
                return "Starting…"
            }
        case .completed:
            if item.totalBytes > 0 {
                return DownloadsPopoverView.byteFormatter.string(fromByteCount: item.totalBytes)
            } else if let url = item.destinationURL,
                      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let size = attrs[.size] as? Int64 {
                return DownloadsPopoverView.byteFormatter.string(fromByteCount: size)
            }
            return "Complete"
        case .failed(let err):
            return "Failed: \(err)"
        case .cancelled:
            return "Cancelled"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.suggestedFilename)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(progressSubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(item.status == .downloading ? .secondary : (item.status == .completed ? .secondary : .red))
                    .lineLimit(1)

                if item.status == .downloading {
                    ProgressView(value: item.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(height: 3)
                }
            }

            Spacer()

            switch item.status {
            case .downloading:
                Button(action: {
                    item.cancel()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Cancel Download")

            case .completed:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))

                    if let url = item.destinationURL {
                        Button(action: {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }) {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                    }
                }

            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 13))

            case .cancelled:
                EmptyView()
            }
        }
    }
}
