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
import AVFoundation
import UIKit

@available(iOS 13.0, *)
final class PhotoSelectorController: ComponentController<ContentBase> {
    let didPick = Signal<ImageSource>()

    @injected private var config: Aiuta.Configuration
    @injected private var history: HistoryModel
    @injected private var tracker: AnalyticTracker
    @injected private var session: SessionModel

    private let selectPhotoBulletin = PhotoSelectorBulletin()
    private let photoHistoryBulletin = PhotoHistoryBulletin()

    private var lock: LoadingBulletin?
    private var photoPicker: PhotoPicker?
    private let imagePickerDelegate = ImagePickerControllerDelegate()

    @bundle(key: "NSCameraUsageDescription")
    private var cameraUsageDescription: String?

    func choosePhoto(withHistoryPrefered: Bool = true) {
        let minHistoryItemsToPreferHistory = withHistoryPrefered ? 1 : 2
        if history.uploaded.items.count >= minHistoryItemsToPreferHistory {
            showBulletin(photoHistoryBulletin)
            session.track(.picker(event: .uploadsHistoryOpened, page: page, product: session.activeSku))
        } else {
            showSelectorIfCameraAvailableOrPicker()
        }
    }

    override func setup() {
        photoPicker = PhotoPicker(vc: vc)
        photoPicker?.shouldTryLoadExifData = false

        selectPhotoBulletin.takeNewPhoto.onTouchUpInside.subscribe(with: self) { [unowned self] in
            takeNewPhoto()
        }

        selectPhotoBulletin.chooseFromLibrary.onTouchUpInside.subscribe(with: self) { [unowned self] in
            pickOrChooseFromLibrary()
        }

        photoHistoryBulletin.onSelect.subscribe(with: self) { [unowned self] image in
            session.track(.picker(event: .uploadedPhotoSelected, page: page, product: session.activeSku))
            photoHistoryBulletin.dismiss()
            didPick.fire(image)
        }

        photoHistoryBulletin.onDelete.subscribe(with: self) { [unowned self] image in
            Task { await deleteHistory(image) }
        }

        photoHistoryBulletin.newPhotosButton.onTouchUpInside.subscribe(with: self) { [unowned self] in
            showSelectorIfCameraAvailableOrPicker()
        }

        photoPicker?.willPick.subscribe(with: self) { [unowned self] in
            lock = showBulletin(LoadingBulletin(empty: false, isDismissable: false))
        }

        imagePickerDelegate.willPick.subscribe(with: self) { [unowned self] in
            lock = showBulletin(LoadingBulletin(empty: false, isDismissable: false))
        }

        photoPicker?.didPick.subscribe(with: self) { [unowned self] photos in
            lock?.dismiss()
            if photos.isEmpty { return }
            session.track(.picker(event: .galleryPhotoSelected, page: page, product: session.activeSku))
            pickPhotos(photos)
        }

        imagePickerDelegate.didPick.subscribe(with: self) { [unowned self] photo, source in
            switch source {
                case .camera:
                    session.track(.picker(event: .newPhotoTaken, page: page, product: session.activeSku))
                case .photoLibrary:
                    session.track(.picker(event: .galleryPhotoSelected, page: page, product: session.activeSku))
                default: break
            }
            lock?.dismiss()
            pickPhotos([photo])
        }

        photoHistoryBulletin.errorSnackbar.onTouchDown.subscribe(with: self) { [unowned self] in
            photoHistoryBulletin.errorSnackbar.hide()
        }

        photoHistoryBulletin.history = history.uploaded
        photoHistoryBulletin.deleting = history.deletingUploaded
    }

    private func showSelectorIfCameraAvailableOrPicker() {
        if cameraUsageDescription.isSomeAndNotEmpty,
           ds.config.behavior.isCameraAvailable {
            showBulletin(selectPhotoBulletin)
        } else {
            pickOrChooseFromLibrary()
        }
    }

    private func pickOrChooseFromLibrary() {
        if #available(iOS 14.0, *) {
            photoPicker?.pick(max: 1)
            session.track(.picker(event: .photoGalleryOpened, page: page, product: session.activeSku))
        } else {
            chooseFromLibrary()
        }
    }

    private func pickPhotos(_ photos: [UIImage]) {
        Task {
            if selectPhotoBulletin.isPresenting {
                await selectPhotoBulletin.dismiss()
            }
            guard let photo = photos.first else { return }
            didPick.fire(photo)
        }
    }

    private func deleteHistory(_ image: Aiuta.Image) async {
        photoHistoryBulletin.errorSnackbar.hide()
        do {
            try await history.removeUploaded(image)
            session.track(.picker(event: .uploadedPhotoDeleted, page: page, product: session.activeSku))
        } catch {
            photoHistoryBulletin.errorSnackbar.bar.tryAgain.onTouchUpInside.cancelSubscription(for: self)
            photoHistoryBulletin.errorSnackbar.bar.tryAgain.onTouchUpInside.subscribe(with: self) { [unowned self] in
                photoHistoryBulletin.onDelete.fire(image)
            }
            photoHistoryBulletin.errorSnackbar.show()
        }
    }
}

@available(iOS 13.0, *)
private extension PhotoSelectorController {
    func checkCameraPermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .denied:
                showPermissionAlert()
                return false
            case .restricted:
                return false
            default: return true
        }
    }

    func showPermissionAlert() {
        vc?.showAlert(title: L.dialogCameraPermissionTitle, message: L.dialogCameraPermissionDescription) { alert in
            alert.addAction(title: L.dialogCameraPermissionConfirmButton, style: .default).subscribe(with: self) {
                UIApplication.shared.openSettings()
            }
            alert.addAction(title: L.cancel, style: .cancel)
        }
    }

    func takeNewPhoto() {
        guard checkCameraPermission() else { return }
        let picker = UIImagePickerController()
        imagePickerDelegate.source = .camera
        picker.modalPresentationStyle = .overFullScreen
        picker.modalTransitionStyle = .coverVertical
        picker.delegate = imagePickerDelegate
        picker.sourceType = .camera
        picker.overrideUserInterfaceStyle = config.appearance.colors.style.userInterface
        vc?.present(picker, animated: true)
        session.track(.picker(event: .cameraOpened, page: page, product: session.activeSku))
    }

    func chooseFromLibrary() {
        let picker = UIImagePickerController()
        imagePickerDelegate.source = .photoLibrary
        picker.modalPresentationStyle = .pageSheet
        picker.delegate = imagePickerDelegate
        picker.sourceType = .photoLibrary
        picker.overrideUserInterfaceStyle = config.appearance.colors.style.userInterface
        vc?.popover(picker)
        session.track(.picker(event: .photoGalleryOpened, page: page, product: session.activeSku))
    }
}

@available(iOS 13.0, *)
private extension PhotoSelectorController {
    var page: Aiuta.Event.Page { (vc as? PageRepresentable)?.page ?? .imagePicker }
}

@available(iOS 13.0, *)
private final class ImagePickerControllerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let willPick = Signal<Void>()
    let didPick = Signal<(UIImage, UIImagePickerController.SourceType)>()
    var source: UIImagePickerController.SourceType = .photoLibrary
    let breadcrumbs = Breadcrumbs()

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = info[.originalImage] as? UIImage else { return }
        willPick.fire()
        picker.dismiss()
        Task { await pick(image, from: source) }
    }

    @MainActor func pick(_ image: UIImage, from source: UIImagePickerController.SourceType) async {
        var loaders = [try? await image.prefetch(.hiResImage, breadcrumbs: breadcrumbs)]
        didPick.fire((image, source))
        await asleep(.halfOfSecond)
        loaders.removeAll()
    }
}
