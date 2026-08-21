import SwiftUI
import UIKit

/// One custom list: its ranked courses (ordered by the owner's live score),
/// like/comment engagement, and — owner-only — rename/edit/add-remove-
/// courses/delete. Non-owners get "Report list" instead of manage.
struct ListDetailView: View {
    let list: CustomList

    @Environment(Router.self) private var router
    @State private var live: CustomList
    @State private var courses: [ListCourse] = []
    @State private var comments: [ActivityComment] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isSending = false
    @State private var actionError: String?
    @State private var isEditing = false
    @State private var isAddingCourses = false
    @State private var isConfirmingDelete = false
    @State private var isReportingList = false
    @State private var reportedComment: ActivityComment?
    @State private var shareImage: UIImage?
    @FocusState private var composerFocused: Bool

    init(list: CustomList) {
        self.list = list
        _live = State(initialValue: list)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Divider().overlay(Color.sand)
                    coursesSection
                    Divider().overlay(Color.sand)
                    commentsSection
                }
                .padding()
            }
            composer
        }
        .creamScreen()
        .navigationTitle(live.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menuButton }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Something went wrong", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .sheet(isPresented: $isEditing) {
            ListEditorSheet(editing: live) { updated in live = updated }
        }
        .sheet(isPresented: $isAddingCourses) {
            AddCoursesToListSheet(
                listID: live.id,
                currentCourseIDs: Set(courses.map(\.courseID))
            ) {
                Task { await reload() }
            }
        }
        .confirmationDialog(
            "Delete \"\(live.title)\"?",
            isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete list", role: .destructive) {
                Task { await deleteList() }
            }
        } message: {
            Text("This can't be undone. Courses stay in your ranking — only the list goes away.")
        }
        .confirmationDialog(
            "Report \"\(live.title)\"?",
            isPresented: $isReportingList, titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.rawValue) { Task { await reportList(reason) } }
            }
        } message: {
            Text("Reports are reviewed within 24 hours.")
        }
        .confirmationDialog(
            "Report @\(reportedComment?.username ?? "")'s comment?",
            isPresented: .init(
                get: { reportedComment != nil },
                set: { if !$0 { reportedComment = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.rawValue) {
                    if let comment = reportedComment {
                        Task { await report(comment, reason: reason) }
                    }
                }
            }
        } message: {
            Text("Reports are reviewed within 24 hours.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(live.title)
                    .font(.title2.bold())
                Image(systemName: live.visibility == .public ? "globe" : "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(live.visibility == .public ? "Public list" : "Private list")
            }
            if live.isMine != true, let ownerID = live.ownerID, let username = live.ownerUsername {
                Button {
                    router.push(.person(ProfileSummary(
                        id: ownerID, username: username, displayName: nil, isFollowing: false
                    )))
                } label: {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if let description = live.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
            }
            HStack(spacing: 20) {
                Button { Task { await toggleLike() } } label: {
                    Label("\(live.likeCount)", systemImage: (live.likedByMe ?? false) ? "heart.fill" : "heart")
                }
                .foregroundStyle((live.likedByMe ?? false) ? Color.clayRed : .secondary)
                .accessibilityIdentifier("listLikeButton")

                Label("\(live.commentCount)", systemImage: "text.bubble")
                    .foregroundStyle(.secondary)

                Spacer()

                if let shareImage {
                    ShareLink(
                        item: ShareableImage(image: shareImage),
                        preview: SharePreview(live.title, image: Image(uiImage: shareImage))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("listShareButton")
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private var coursesSection: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if loadFailed, courses.isEmpty {
            LoadFailedView { await reload() }
        } else if courses.isEmpty {
            Text(live.isMine == true
                 ? "No courses yet. Add some from your ranked list."
                 : "No courses in this list yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 24, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).lineLimit(2)
                            Text(course.locationText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ScoreBadge(score: course.score, compact: true)
                        if live.isMine == true {
                            Button {
                                Task { await removeCourse(course) }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Color.clayRed)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(course.name) from this list")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { router.push(.courseID(course.courseID)) }
                }
            }
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        if !isLoading {
            if comments.isEmpty {
                Text("No comments yet. Say something.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if comment.isMine {
                                    Text("@\(comment.username)")
                                        .font(.subheadline.weight(.semibold))
                                } else {
                                    Button {
                                        router.push(.person(ProfileSummary(
                                            id: comment.userID, username: comment.username,
                                            displayName: nil, isFollowing: false
                                        )))
                                    } label: {
                                        Text("@\(comment.username)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                                Text(comment.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Menu {
                                    if comment.isMine {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            Task { await delete(comment) }
                                        }
                                    } else {
                                        Button("Report comment", systemImage: "flag") {
                                            reportedComment = comment
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel(comment.isMine
                                                    ? "Comment actions"
                                                    : "Report @\(comment.username)'s comment")
                            }
                            Text(comment.body).font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.sand).frame(height: 1)
            HStack(spacing: 10) {
                TextField("Add a comment", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .accessibilityIdentifier("listCommentField")
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(trimmedDraft.isEmpty || isSending)
                .tint(Color.fairwayGreen)
                .accessibilityLabel("Send comment")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color.cream)
    }

    private var menuButton: some View {
        Menu {
            if live.isMine == true {
                Button {
                    isEditing = true
                } label: {
                    Label("Edit list", systemImage: "pencil")
                }
                Button {
                    isAddingCourses = true
                } label: {
                    Label("Add or remove courses", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("addCoursesButton")
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete list", systemImage: "trash")
                }
                .accessibilityIdentifier("deleteListButton")
            } else {
                Button(role: .destructive) {
                    isReportingList = true
                } label: {
                    Label("Report list", systemImage: "flag")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("List options")
        .accessibilityIdentifier("listManageMenu")
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func reload() async {
        async let detailTask = ListsRepo.detail(listID: live.id)
        async let coursesTask = ListsRepo.listCourses(listID: live.id)
        async let commentsTask = ListsRepo.comments(listID: live.id)
        do {
            if let fresh = try await detailTask { live = fresh }
            courses = try await coursesTask
            comments = try await commentsTask
            loadFailed = false
            shareImage = ListShareRenderer.render(list: live, courses: courses)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func toggleLike() async {
        // Move first — waiting on the network to light the heart feels broken,
        // same reasoning as FeedView.react.
        let wasLiked = live.likedByMe ?? false
        live.likedByMe = !wasLiked
        live.likeCount += wasLiked ? -1 : 1
        do {
            try await ListsRepo.toggleLike(listID: live.id)
        } catch {
            live.likedByMe = wasLiked
            live.likeCount += wasLiked ? 1 : -1
            actionError = "Couldn't save that. \(error.localizedDescription)"
        }
    }

    private func removeCourse(_ course: ListCourse) async {
        courses.removeAll { $0.id == course.id }
        // Derived from the array, not decremented — courseCount came from
        // list_detail's live-score inner join, which can drift from a naive
        // decrement if a course was un-/re-ranked elsewhere since the last load.
        live.courseCount = courses.count
        do {
            try await ListsRepo.removeCourse(listID: live.id, courseID: course.courseID)
        } catch {
            actionError = "Couldn't remove \(course.name). \(error.localizedDescription)"
            await reload()
        }
    }

    private func deleteList() async {
        do {
            try await ListsRepo.delete(listID: live.id)
            if !router.path.isEmpty { router.path.removeLast() }
        } catch {
            actionError = "Couldn't delete this list. \(error.localizedDescription)"
        }
    }

    private func reportList(_ reason: ReportReason) async {
        do {
            try await ModerationRepo.report(listID: live.id, reason: reason.rawValue)
            actionError = "Report received. We review reports within 24 hours."
        } catch {
            actionError = "Couldn't send the report. \(error.localizedDescription)"
        }
    }

    private func send() async {
        let body = trimmedDraft
        guard !body.isEmpty else { return }
        guard !ContentFilter.isObjectionable(body) else {
            actionError = "That comment contains language we don't allow. Please revise it."
            return
        }
        isSending = true
        do {
            try await ListsRepo.addComment(listID: live.id, body: body)
            draft = ""
            composerFocused = false
            await reload()
        } catch {
            actionError = "Couldn't post that comment. \(error.localizedDescription)"
        }
        isSending = false
    }

    private func delete(_ comment: ActivityComment) async {
        do {
            try await ListsRepo.deleteComment(id: comment.id)
            comments.removeAll { $0.id == comment.id }
            live.commentCount = comments.count
        } catch {
            actionError = "Couldn't delete that comment. \(error.localizedDescription)"
        }
    }

    private func report(_ comment: ActivityComment, reason: ReportReason) async {
        do {
            try await ModerationRepo.report(listCommentID: comment.id, reason: reason.rawValue)
            actionError = "Report received. We review reports within 24 hours."
        } catch {
            actionError = "Couldn't send the report. \(error.localizedDescription)"
        }
    }
}
