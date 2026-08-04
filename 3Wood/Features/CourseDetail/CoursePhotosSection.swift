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
            PhotoViewer(
                photos: photos,
                current: photo,
                onDelete: { await delete($0) },
                onReport: { reported = $0 }
            )
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.sand, lineWidth: 1)
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

/// Full-screen photo browser. Swipes between every photo on the course, and
/// carries delete/report as visible buttons — they previously existed only in
/// a long-press context menu on the thumbnail, which is why they read as
/// missing.
private struct PhotoViewer: View {
    let photos: [CoursePhoto]
    @State var current: CoursePhoto
    let onDelete: (CoursePhoto) async -> Void
    let onReport: (CoursePhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(photos) { photo in
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
                    .tag(photo)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { controls }
        .overlay(alignment: .bottom) {
            Text("Photo by @" + current.username)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 30)
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let doomed = current
                Task {
                    await onDelete(doomed)
                    dismiss()
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Close")

            Spacer()

            if photos.count > 1, let index = photos.firstIndex(of: current) {
                Text("\(index + 1) of \(photos.count)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            if current.isMine {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash").font(.title3)
                }
                .accessibilityLabel("Delete photo")
            } else {
                Button {
                    onReport(current)
                } label: {
                    Image(systemName: "flag").font(.title3)
                }
                .accessibilityLabel("Report photo")
            }
        }
        .foregroundStyle(.white)
        .padding()
    }
}
