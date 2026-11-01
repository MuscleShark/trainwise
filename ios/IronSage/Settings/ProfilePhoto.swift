import ClerkKit
import PhotosUI
import SwiftUI

/// Where the profile photo is kept: on the Clerk sign-in account for now, so it follows
/// the account to other devices and the website. Moving it to IronSage's own storage
/// changes only this type.
@MainActor
enum ProfilePhoto {
    /// The longest side of the uploaded photo, in pixels.
    static let maxSide: CGFloat = 512

    static func url(of user: User?) -> URL? {
        guard let user, user.hasImage else { return nil }
        return URL(string: user.imageUrl)
    }

    /// Shrinks the picked image to a small JPEG and uploads it. Returns its URL.
    static func upload(_ imageData: Data, for user: User) async throws -> URL? {
        guard let jpeg = resizedJPEG(imageData) else { throw UploadError.notAnImage }
        let image = try await user.setProfileImage(imageData: jpeg)
        // Refresh clerk.user, so every avatar shows the new photo.
        try? await user.reload()
        return image.publicUrl.flatMap(URL.init(string:))
    }

    static func remove(for user: User) async throws {
        try await user.deleteProfileImage()
        try? await user.reload()
    }

    enum UploadError: Error { case notAnImage }

    private static func resizedJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.8)
    }
}

/// The user's photo in a circle, or the first letter of their email without one.
struct AvatarView: View {
    var url: URL?
    var email: String?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
            if let initial = email?.first {
                Text(String(initial).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.tint)
            }
        }
    }
}

/// The top of the profile: the photo with a camera badge, the name and the email.
/// Tapping the photo offers the library, the camera and removing it.
struct ProfilePhotoSection: View {
    let account: MeView.AccountState
    @Environment(Clerk.self) private var clerk
    @State private var isChoosing = false
    @State private var isPickingPhoto = false
    @State private var isTakingPhoto = false
    @State private var item: PhotosPickerItem?
    /// Set after a change here, until clerk.user catches up.
    @State private var changedURL: URL??
    @State private var isWorking = false
    @State private var failed = false

    private static let size: CGFloat = 112

    private var url: URL? { changedURL ?? ProfilePhoto.url(of: clerk.user) }

    var body: some View {
        Section {
            VStack(spacing: 4) {
                Button {
                    isChoosing = true
                } label: {
                    AvatarView(url: url, email: account.email, size: Self.size)
                        .overlay {
                            if isWorking {
                                ProgressView()
                                    .frame(width: Self.size, height: Self.size)
                                    .background(.regularMaterial, in: .circle)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if clerk.user != nil {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.accentColor, in: .circle)
                                    .overlay { Circle().stroke(Color.appBackground, lineWidth: 3) }
                                    .offset(x: 2, y: -2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(clerk.user == nil || isWorking)
                .accessibilityLabel(url == nil ? "Add profile photo" : "Change profile photo")
                .accessibilityIdentifier("profilePhoto")

                if let name = clerk.user?.displayName {
                    Text(name)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                }
                switch account {
                case .loading:
                    ProgressView()
                        .padding(.top, 4)
                case .signedIn(let email):
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, clerk.user?.displayName == nil ? 10 : 0)
                case .unavailable:
                    Text("Couldn't load your account. Check your connection, then pull down on Me to try again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
        .confirmationDialog("Profile photo", isPresented: $isChoosing, titleVisibility: .visible) {
            Button("Choose from library") { isPickingPhoto = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take photo") { isTakingPhoto = true }
            }
            if url != nil {
                Button("Remove photo", role: .destructive) {
                    Task { await remove() }
                }
            }
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $item, matching: .images)
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { data in
                Task { await upload(data) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: item) {
            guard let item else { return }
            Task { await upload(item) }
        }
        .alert("Couldn't update your photo", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        defer { self.item = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await upload(data)
    }

    private func upload(_ data: Data) async {
        guard let user = clerk.user else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            changedURL = .some(try await ProfilePhoto.upload(data, for: user))
        } catch {
            failed = true
        }
    }

    private func remove() async {
        guard let user = clerk.user else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await ProfilePhoto.remove(for: user)
            changedURL = .some(nil)
        } catch {
            failed = true
        }
    }
}

extension User {
    /// First and last name, when the account has them.
    var displayName: String? {
        let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// The camera, for a new profile photo. Returns the photo as JPEG data.
private struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            if let data = image?.jpegData(compressionQuality: 0.9) {
                parent.onPhoto(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
