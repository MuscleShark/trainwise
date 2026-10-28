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

/// The photo at the top of the profile, with buttons to change or remove it.
struct ProfilePhotoSection: View {
    let email: String?
    @Environment(Clerk.self) private var clerk
    @State private var item: PhotosPickerItem?
    /// Set after a change here, until clerk.user catches up.
    @State private var changedURL: URL??
    @State private var isWorking = false
    @State private var failed = false

    private var url: URL? { changedURL ?? ProfilePhoto.url(of: clerk.user) }

    var body: some View {
        Section {
            VStack(spacing: 12) {
                AvatarView(url: url, email: email, size: 96)
                    .overlay {
                        if isWorking {
                            ProgressView()
                                .frame(width: 96, height: 96)
                                .background(.regularMaterial, in: .circle)
                        }
                    }
                if clerk.user != nil {
                    HStack(spacing: 20) {
                        PhotosPicker(url == nil ? "Add photo" : "Change photo", selection: $item, matching: .images)
                        if url != nil {
                            Button("Remove", role: .destructive) {
                                Task { await remove() }
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isWorking)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
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
        guard let user = clerk.user else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
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
