// Copyright 2024 Aiuta USA, Inc
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@_spi(Aiuta) import AiutaKit
import UIKit

@available(iOS 13.0.0, *)
final class HistoryViewController: ViewController<HistoryView> {
    @injected private var history: HistoryModel
    @injected private var session: SessionModel
    @injected private var tracker: AnalyticTracker
    @injected private var watermarker: Watermarker
    private let breadcrumbs = Breadcrumbs()

    override func setup() {
        ui.navBar.onBack.subscribe(with: self) { [unowned self] in
            dismissAll()
        }

        ui.navBar.onClose.subscribe(with: self) { [unowned self] in
            dismissAll()
        }

        ui.navBar.onAction.subscribe(with: self) { [unowned self] in
            isEditMode.toggle()
            if !isEditMode { ui.errorSnackbar.hide() }
        }

        ui.selectionSnackbar.bar.cancelButton.onTouchUpInside.subscribe(with: self) { [unowned self] in
            isEditMode = false
        }

        ui.selectionSnackbar.bar.gestures.onSwipe(.down, with: self) { [unowned self] _ in
            isEditMode = false
        }

        ui.selectionSnackbar.bar.toggleSeletionButton.onTouchUpInside.subscribe(with: self) { [unowned self] in
            if isSelectedAll { selection.removeAll() }
            else { selection = Set(history.generated.items) }
            updateSelection()
        }

        ui.selectionSnackbar.bar.shareButton.onTouchUpInside.subscribe(with: self) { [unowned self] in
            guard !selection.isEmpty else { return }
            Task { await shareSelection() }
        }

        ui.selectionSnackbar.bar.deleteButton.onTouchUpInside.subscribe(with: self) { [unowned self] in
            Task { await deleteSelection() }
        }

        ui.history.onUpdateItem.subscribe(with: self) { [unowned self] cell in
            guard let image = cell.data else {
                cell.isSelectable = false
                return
            }
            cell.isDeleting = history.deletingGenerated.items.contains(image)
            cell.isSelectable = isEditMode && !cell.isDeleting
            cell.isSelected = isEditMode && !cell.isDeleting && selection.contains(image)
        }

        ui.history.onTapItem.subscribe(with: self) { [unowned self] cell in
            if isEditMode { toggleSelection(cell) }
            else { enterFullscreen(cell) }
        }

        history.deletingGenerated.onUpdate.subscribe(with: self) { [unowned self] in
            ui.history.updateItems()
        }

        ui.errorSnackbar.bar.tryAgain.onTouchUpInside.subscribe(with: self) { [unowned self] in
            Task { await deleteSelection() }
        }

        ui.errorSnackbar.onTouchDown.subscribe(with: self) { [unowned self] in
            if !isEditMode { selection.removeAll() }
            ui.errorSnackbar.isVisible = false
        }

        ui.history.data = history.generated
        ui.navBar.isActionAvailable = true

        session.track(.page(page: page, product: session.activeSku))
    }

    private var isEditMode = false {
        didSet {
            guard oldValue != isEditMode else { return }
            ui.selectionSnackbar.isVisible = isEditMode
            ui.navBar.actionStyle = .label(isEditMode ? L.cancel : L.appBarSelect)
            ui.history.updateItems()
            if !isEditMode { selection.removeAll() }
            updateSelection()
        }
    }

    private var selection = Set<Aiuta.Image>() {
        didSet {
            guard oldValue != selection else { return }
            ui.history.updateItems()
        }
    }

    var isSelectedAll: Bool {
        !selection.isEmpty && (selection.count == history.generated.items.count)
    }

    func toggleSelection(_ cell: HistoryView.HistoryCell) {
        guard let image = cell.data else { return }
        if selection.contains(image) {
            selection.remove(image)
        } else {
            selection.insert(image)
        }
        updateSelection()
    }

    func updateSelection() {
        ui.selectionSnackbar.bar.deleteButton.isEnabled = !selection.isEmpty
        ui.selectionSnackbar.bar.shareButton.isEnabled = !selection.isEmpty

        ui.selectionSnackbar.bar.toggleSeletionButton.text = isSelectedAll ? L.historySelectorEnableButtonUnselectAll : L.historySelectorEnableButtonSelectAll
        ui.selectionSnackbar.bar.view.layoutSubviews()
    }

    func deleteSelection() async {
        ui.errorSnackbar.hide()
        let candidates = selection
        isEditMode = false
        guard !candidates.isEmpty else { return }
        do {
            try await history.removeGenerated(Array(candidates))
            session.track(.history(event: .generatedImageDeleted, page: page, product: session.activeSku))

            if !history.hasGenerations {
                dispatch(.mainAsync) { [self] in
                    dismiss()
                }
            }
        } catch {
            ui.errorSnackbar.show()
            selection.formUnion(candidates)
        }
    }

    func shareSelection() async {
        let imagesToShare: [UIImage] = await selection.concurrentCompactMap { [watermarker, breadcrumbs] in
            guard let image = try? await $0.fetch(breadcrumbs: breadcrumbs.fork()) else { return nil }
            return watermarker.watermark(image)
        }
        guard !imagesToShare.isEmpty else { return }
        session.track(.history(event: .generatedImageShared, page: page, product: session.activeSku))
        let result = await share(images: imagesToShare)
        if result.isSucceeded {
            isEditMode = false
        }
        switch result {
            case let .succeeded(activity):
                tracker.track(.share(result: .succeeded, product: nil, page: page, target: activity))
            case let .canceled(activity):
                tracker.track(.share(result: .canceled, product: nil, page: page, target: activity))
            case let .failed(activity, error):
                tracker.track(.share(result: .failed(error: error), product: nil, page: page, target: activity))
        }
    }

    func enterFullscreen(_ cell: HistoryView.HistoryCell) {
        let gallery = GalleryViewController(TransformDataProvider(input: ui.history.data, transform: { $0 }), start: cell.index.item)
        gallery.willShare.subscribe(with: self) { [unowned self] generatedImage, _, gallery in
            Task {
                guard let image = try? await generatedImage.fetch(breadcrumbs: breadcrumbs.fork()) else { return }
                session.track(.history(event: .generatedImageShared, page: page, product: session.activeSku))
                let result = await gallery.share(image: watermarker.watermark(image))
                switch result {
                    case let .succeeded(activity):
                        tracker.track(.share(result: .succeeded, product: nil, page: page, target: activity))
                    case let .canceled(activity):
                        tracker.track(.share(result: .canceled, product: nil, page: page, target: activity))
                    case let .failed(activity, error):
                        tracker.track(.share(result: .failed(error: error), product: nil, page: page, target: activity))
                }
            }
        }
        cover(gallery)
    }
}

@available(iOS 13.0.0, *)
extension HistoryViewController: PageRepresentable {
    var page: Aiuta.Event.Page { .history }
    var isSafeToDismiss: Bool { true }
}
