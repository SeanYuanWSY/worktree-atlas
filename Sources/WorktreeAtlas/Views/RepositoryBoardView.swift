import SwiftUI
import AtlasCore

/// Only the board scrolls horizontally. Each full-height repository owns its vertical commit scroll.
struct RepositoryBoardView: View {
    let records: [RepositoryRecord]
    let snapshots: [UUID: RepositorySnapshot]
    let presentations: [UUID: RepositoryGraphPresentation]
    let failures: [UUID: String]
    let focused: Bool
    let selectedRepositoryID: UUID?
    let selectedPath: String?
    let canMutate: (UUID) -> Bool
    let onSelect: (UUID, GitWorktree) -> Void
    let onFocus: (UUID) -> Void
    let onCreate: (RepositorySnapshot) -> Void
    let onPrune: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var leadingRepository: UUID?
    private var singlePanel: Bool { focused || records.count == 1 }
    private var currentIndex: Int { records.firstIndex { $0.id == leadingRepository } ?? 0 }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                let minimumWidth = max(560, CGFloat(records.map { presentations[$0.id]?.laneCount ?? 1 }.max() ?? 1) * 17 + 460)
                let count = max(1, min(3, records.count, Int((geometry.size.width - 12) / (minimumWidth + 12))))
                let panelWidth = max(minimumWidth, (geometry.size.width - 24 - CGFloat(count - 1) * 12) / CGFloat(count))
                let firstIndex = min(currentIndex, max(0, records.count - count))
                VStack(spacing: 0) {
                    if !singlePanel {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.split.2x1").foregroundStyle(AtlasStyle.accent)
                            Text("并排总览").fontWeight(.medium)
                            Text("横向浏览仓库 · 纵向浏览提交").foregroundStyle(.secondary)
                            Spacer()
                            Text(count == 1 ? "\(firstIndex + 1) / \(records.count)" : "\(firstIndex + 1)–\(firstIndex + count) / \(records.count)")
                                .monospacedDigit().foregroundStyle(.secondary)
                            Button { move(-1, visibleCount: count, proxy: proxy) } label: { Image(systemName: "chevron.left") }
                                .disabled(firstIndex == 0).help("前一个仓库")
                            Button { move(1, visibleCount: count, proxy: proxy) } label: { Image(systemName: "chevron.right") }
                                .disabled(firstIndex >= records.count - count).help("下一个仓库")
                        }
                        .font(.system(size: 10)).buttonStyle(AtlasToolbarButtonStyle())
                        .padding(.horizontal, 16).frame(height: 36)
                    }
                    if singlePanel, let record = records.first {
                        panel(record).padding(12)
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) {
                                ForEach(records) { record in
                                    panel(record)
                                        .frame(width: panelWidth, height: max(250, geometry.size.height - 64))
                                        .id(record.id)
                                }
                            }
                            .scrollTargetLayout().padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 20)
                        }
                        .scrollIndicators(.visible)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $leadingRepository, anchor: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func panel(_ record: RepositoryRecord) -> some View {
        if let snapshot = snapshots[record.id], let presentation = presentations[record.id] {
            RepositoryCardView(snapshot: snapshot, presentation: presentation, error: failures[record.id], focused: singlePanel,
                selectedPath: selectedRepositoryID == record.id ? selectedPath : nil, canMutate: canMutate(record.id),
                onSelect: { onSelect(record.id, $0) }, onFocus: { onFocus(record.id) },
                onCreate: { onCreate(snapshot) }, onPrune: { onPrune(record.id) })
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label(record.displayName, systemImage: "square.stack.3d.up").font(.headline)
                if let error = failures[record.id] {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                } else { ProgressView("正在读取工作树…").controlSize(.small) }
                Spacer()
            }
            .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AtlasStyle.card(colorScheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AtlasStyle.panelBorder(colorScheme)))
        }
    }

    private func move(_ offset: Int, visibleCount: Int, proxy: ScrollViewProxy) {
        guard !records.isEmpty else { return }
        let lastStart = max(0, records.count - visibleCount)
        let next = min(max(0, min(currentIndex, lastStart) + offset), lastStart)
        let id = records[next].id
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .leading) }
        leadingRepository = id
    }
}
