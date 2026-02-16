import SwiftUI
#if canImport(UIKit)
import UIKit

struct SelectableCollectionView: UIViewRepresentable {
    let scores: [Score]
    @Binding var selectedIds: Set<UUID>
    @Binding var isSelecting: Bool
    var isScrollEnabled: Bool = true
    var onScoreTapped: (Score) -> Void
    var contextMenuProvider: ((Score) -> UIMenu)?

    func makeUIView(context: Context) -> UICollectionView {
        let collectionView = SelfSizingCollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.isScrollEnabled = isScrollEnabled
        collectionView.isEditing = isSelecting
        collectionView.delegate = context.coordinator
        collectionView.contentInset = .zero
        collectionView.contentInsetAdjustmentBehavior = .never

        context.coordinator.configureDataSource(for: collectionView)
        context.coordinator.apply(scores: scores, selectedIds: selectedIds)

        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(scores: scores, selectedIds: selectedIds)

        if collectionView.isEditing != isSelecting {
            collectionView.isEditing = isSelecting
        }

        if collectionView.isScrollEnabled != isScrollEnabled {
            collectionView.isScrollEnabled = isScrollEnabled
            collectionView.invalidateIntrinsicContentSize()
        }

        context.coordinator.syncSelection(in: collectionView, selectedIds: selectedIds)
    }

    final class SelfSizingCollectionView: UICollectionView {
        override var contentSize: CGSize {
            didSet {
                if !isScrollEnabled {
                    invalidateIntrinsicContentSize()
                }
            }
        }

        override var intrinsicContentSize: CGSize {
            if isScrollEnabled {
                return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
            }
            layoutIfNeeded()
            return CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let spacing: CGFloat = 16
            let minimumWidth: CGFloat = 160
            let maximumWidth: CGFloat = 220

            let totalWidth = environment.container.effectiveContentSize.width
            let availableWidth = max(minimumWidth, totalWidth - (spacing * 2))

            var columns = max(1, Int((availableWidth + spacing) / (minimumWidth + spacing)))
            while columns > 1 {
                let candidateWidth = (availableWidth - (CGFloat(columns - 1) * spacing)) / CGFloat(columns)
                if candidateWidth <= maximumWidth {
                    break
                }
                columns += 1
            }

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(340)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(340)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columns
            )
            group.interItemSpacing = .fixed(spacing)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

            return section
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate {
        enum Section {
            case main
        }

        var parent: SelectableCollectionView
        private var scoresById: [UUID: Score] = [:]
        private var orderedIds: [UUID] = []
        private weak var collectionView: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Section, UUID>?

        init(parent: SelectableCollectionView) {
            self.parent = parent
            super.init()
        }

        func configureDataSource(for collectionView: UICollectionView) {
            self.collectionView = collectionView

            let registration = UICollectionView.CellRegistration<UICollectionViewCell, UUID> { [weak self] cell, _, scoreId in
                guard let self, let score = self.scoresById[scoreId] else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    ScoreCardView(
                        score: score,
                        isSelecting: self.parent.isSelecting,
                        isSelected: self.parent.selectedIds.contains(score.id)
                    )
                }
                .margins(.all, 0)
                cell.backgroundConfiguration = .clear()
            }

            dataSource = UICollectionViewDiffableDataSource<Section, UUID>(collectionView: collectionView) {
                collectionView, indexPath, itemIdentifier in
                collectionView.dequeueConfiguredReusableCell(
                    using: registration,
                    for: indexPath,
                    item: itemIdentifier
                )
            }
        }

        func apply(scores: [Score], selectedIds: Set<UUID>) {
            guard let dataSource else { return }

            scoresById = Dictionary(uniqueKeysWithValues: scores.map { ($0.id, $0) })
            orderedIds = scores.map(\.id)

            var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
            snapshot.appendSections([.main])
            snapshot.appendItems(orderedIds, toSection: .main)
            snapshot.reconfigureItems(orderedIds)
            dataSource.apply(snapshot, animatingDifferences: false)

            if let collectionView {
                syncSelection(in: collectionView, selectedIds: selectedIds)
            }
        }

        func syncSelection(in collectionView: UICollectionView, selectedIds: Set<UUID>) {
            for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
                guard let scoreId = dataSource?.itemIdentifier(for: indexPath) else { continue }
                if !selectedIds.contains(scoreId) {
                    collectionView.deselectItem(at: indexPath, animated: false)
                }
            }

            guard let dataSource else { return }
            for scoreId in selectedIds {
                guard let indexPath = dataSource.indexPath(for: scoreId) else { continue }
                if !(collectionView.indexPathsForSelectedItems ?? []).contains(indexPath) {
                    collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                }
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath
        ) -> Bool {
            true
        }

        func collectionView(
            _ collectionView: UICollectionView,
            didBeginMultipleSelectionInteractionAt indexPath: IndexPath
        ) {
            collectionView.isEditing = true
            if !parent.isSelecting {
                parent.isSelecting = true
            }
        }

        func collectionViewDidEndMultipleSelectionInteraction(_ collectionView: UICollectionView) {
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard let scoreId = dataSource?.itemIdentifier(for: indexPath),
                  let score = scoresById[scoreId]
            else { return }

            if parent.isSelecting {
                parent.selectedIds.insert(scoreId)
            } else {
                collectionView.deselectItem(at: indexPath, animated: false)
                parent.onScoreTapped(score)
            }
        }

        func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
            guard parent.isSelecting,
                  let scoreId = dataSource?.itemIdentifier(for: indexPath)
            else { return }

            parent.selectedIds.remove(scoreId)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            contextMenuConfigurationForItemAt indexPath: IndexPath,
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard !parent.isSelecting,
                  let scoreId = dataSource?.itemIdentifier(for: indexPath),
                  let score = scoresById[scoreId],
                  let menu = parent.contextMenuProvider?(score)
            else { return nil }

            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
        }
    }
}
#endif
