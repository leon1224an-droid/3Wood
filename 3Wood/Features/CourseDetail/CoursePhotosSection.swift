import SwiftUI
import PhotosUI

/// Course photos: a horizontal strip on the course page, tap to view full
/// screen, plus the add/delete/report actions.
struct CoursePhotosSection: View {
    let courseID: Int

    @State private var photos: [CoursePhoto] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var viewing: CoursePhoto?
    @State private var reported: CoursePhoto?
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(photos.isEmpty ? "Photos" : "^[\(photos.count) photo](inflect: true)")
                    .font(.headline)
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    if isUploading {
                        ProgressView()
                    } else {
                        Label("Add photo", systemImage: "camera")
                            .font(.subheadline)
                    }
                }
                .disabled(isUploading)
            }

            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if loadFailed, photos.isEmpty {
                LoadFailedView { await reload() }
            } else if photos.isEmpty {
                Text("No photos yet. Add the first one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            thumbnail(photo)
                        }
                    }
                }
                // The strip scrolls itself; the page must not scroll sideways.
                .scrollClipDisabled(false)
            }
        }
        .task { await reload() }
        .onChange(of: pickerItem) {
            guard let pickerItem else { return }
            Task { await upload(pickerItem) }
        }
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(photo: photo)
        }
        .confirmationDialog(
            "Report @\(reported?.username ?? "")'s photo?",
            isPresented: .init(
                get: { reported != nil },
                set: { if !$0 { reported = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.rawValue) {
                    if let photo = reported {
                        Task { await report(photo, reason: reason) }
                    }
                }
            }
        } message: {
            Text("Reports are reviewed within 24 hours.")
        }
        .alert("Something went wrong", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func thumbnail(_ photo: CoursePhoto) -> some View {
        Button {
            viewing = photo
        } label: {
            AsyncImage(url: PhotoRepo.publicURL(for: photo.storagePath)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 140, height: 105)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.sand, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo by @\(photo.username)")
        .contextMenu {
            if photo.isMine {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await delete(photo) }
                }
            } else {
                Button("Report photo", systemImage: "flag") {
                    reported = photo
                }
            }
        }
    }

    private func reload() async {
        do {
            photos = try await PhotoRepo.photos(courseID: courseID)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        defer { isUploading = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                actionError = "That photo couldn't be read."
                return
            }
            try await PhotoRepo.upload(image: image, courseID: courseID)
            await reload()
        } catch {
            actionError = "Couldn't add that photo. \(error.localizedDescription)"
        }
    }

    private func delete(_ photo: CoursePhoto) async {
        do {
            try await PhotoRepo.delete(photo)
            await reload()
        } catch {
            actionError = "Couldn't delete that photo. \(error.localizedDescription)"
        }
    }

    private func report(_ photo: CoursePhoto, reason: ReportReason) async {
        do {
            try await ModerationRepo.report(
                userID: photo.userID, photoID: photo.id, reason: reason.rawValue
            )
            actionError = "Report received. We review reports within 24 hours."
        } catch {
            actionError = "Couldn't send the report. \(error.localizedDescription)"
        }
    }
}

/// Full-screen photo with its attribution.
private struct PhotoViewer: View {
    let photo: CoursePhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: PhotoRepo.publicURL(for: photo.storagePath)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else if phase.error != nil {
                    Label("Couldn't load this photo", systemImage: "photo")
                        .foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding()
            }
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .bottom) {
            Text("Photo by @\(photo.username)")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 30)
        }
    }
}
