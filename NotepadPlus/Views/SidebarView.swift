import SwiftUI

struct SidebarView: View {
    @ObservedObject var workspace: WorkspaceStore
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    @State private var newGroupParentID: UUID?
    @State private var documentToRename: EditorDocument?
    @State private var groupToRename: DocumentGroup?
    @State private var renameValue = ""
    @State private var expandedGroupIDs = Set<UUID>()
    @State private var isUngroupedExpanded = true
    @State private var dropTargetID: UUID?
    @State private var hoveredRecentPath: String?

    private var preferences: EditorPreferences { workspace.preferences }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let folder = workspace.workspaceFolder {
                        workspaceSection(folder)
                    }

                    sectionTitle(preferences.tr("我的分组", "My groups"), systemImage: "folder.fill")
                    VStack(spacing: 8) {
                        ForEach(visibleGroupEntries) { entry in
                            if let group = workspace.documentGroups.first(where: { $0.id == entry.id }) {
                                groupCard(group)
                                    .padding(.leading, CGFloat(min(entry.depth, 5)) * 12)
                                    .help(workspace.groupHierarchy.path(for: group.id))
                            }
                        }
                        ungroupedCard
                    }

                    if !workspace.recentFiles.isEmpty {
                        recentSection
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .background(EditorChrome.background)
        }
        .background(EditorChrome.background)
        .navigationTitle("NotepadPlus")
        .toolbarBackground(EditorChrome.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            if expandedGroupIDs.isEmpty {
                expandedGroupIDs = Set(workspace.documentGroups.map(\.id))
            }
        }
        .onChange(of: workspace.selectedGroupID) { _, id in
            if let id { expandedGroupIDs.formUnion(workspace.groupHierarchy.ancestors(of: id)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestNewDocumentGroup)) { _ in
            presentNewGroup()
        }
        .alert(preferences.tr("新建分组", "New group"), isPresented: $isAddingGroup) {
            TextField(preferences.tr("分组名称", "Group name"), text: $newGroupName)
            Button(preferences.tr("取消", "Cancel"), role: .cancel) {}
            Button(preferences.tr("创建", "Create")) {
                if let group = workspace.addDocumentGroup(named: newGroupName, parentID: newGroupParentID) {
                    expandedGroupIDs.insert(group.id)
                    expandedGroupIDs.formUnion(workspace.groupHierarchy.ancestors(of: group.id))
                }
            }
        } message: {
            Text(newGroupParentID.map { "上级分组：" + workspace.groupHierarchy.path(for: $0) } ?? "上级分组：无（顶级分组）")
        }
        .alert(preferences.tr("重命名文档", "Rename document"), isPresented: Binding(
            get: { documentToRename != nil },
            set: { if !$0 { documentToRename = nil } }
        )) {
            TextField(preferences.tr("文档名称", "Document name"), text: $renameValue)
            Button(preferences.tr("取消", "Cancel"), role: .cancel) { documentToRename = nil }
            Button(preferences.tr("重命名", "Rename")) {
                if let documentToRename { workspace.rename(documentToRename, to: renameValue) }
                documentToRename = nil
            }
        }
        .alert(preferences.tr("重命名分组", "Rename group"), isPresented: Binding(
            get: { groupToRename != nil },
            set: { if !$0 { groupToRename = nil } }
        )) {
            TextField(preferences.tr("分组名称", "Group name"), text: $renameValue)
            Button(preferences.tr("取消", "Cancel"), role: .cancel) { groupToRename = nil }
            Button(preferences.tr("保存", "Save")) {
                if let groupToRename { workspace.renameDocumentGroup(groupToRename, to: renameValue) }
                groupToRename = nil
            }
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.14))
                Image(systemName: "sidebar.left")
                    .foregroundStyle(.green)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(preferences.tr("文档导航", "Document navigator"))
                    .font(.headline)
                Text(selectedDestinationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { presentNewGroup() } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help(preferences.tr("新建文档分组", "New document group"))
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(EditorChrome.background)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var selectedDestinationText: String {
        guard let id = workspace.selectedGroupID,
              let group = workspace.documentGroups.first(where: { $0.id == id })
        else { return preferences.tr("新文档将放入：未分组", "New documents: Ungrouped") }
        return preferences.tr("新文档将放入：\(group.name)", "New documents: \(group.name)")
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 3)
    }

    private func workspaceSection(_ folder: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(folder.lastPathComponent, systemImage: "folder")
            VStack(spacing: 2) {
                ForEach(workspace.workspaceFiles, id: \.path) { url in
                    Button { workspace.open(url: url) } label: {
                        Label(relativePath(for: url, in: folder), systemImage: fileIcon(for: url))
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .help(url.path)
                }
            }
            .padding(5)
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func groupCard(_ group: DocumentGroup) -> some View {
        let documents = workspace.documents.filter { $0.groupID == group.id }
        let isExpanded = expandedGroupIDs.contains(group.id)
        let isSelected = workspace.selectedGroupID == group.id
        let color = group.color.color

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    workspace.selectGroup(group)
                } label: {
                    HStack(spacing: 8) {
                        // Keep the selected group colour visible even when the
                        // folder icon is not in focus (for example while the
                        // menu is open). This mirrors the colour-coded groups
                        // used by Notepad++ and makes the colour choice obvious.
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(color.opacity(0.14))
                            Image(systemName: "folder.fill")
                                .foregroundStyle(color)
                        }
                        .frame(width: 30, height: 30)
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        countBadge(documents.count, color: color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .draggable(groupPayload(group.id)) {
                    Label(group.name, systemImage: "folder.fill")
                        .padding(9)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                }

                groupMenu(group)

                Button {
                    setExpanded(!isExpanded, for: group.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 26, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "收起分组" : "展开分组")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if isExpanded {
                Divider().padding(.leading, 48)
                if documents.isEmpty && !workspace.documentGroups.contains(where: { $0.parentID == group.id }) {
                    dropEmptyState(color: color)
                } else {
                    VStack(spacing: 2) {
                        ForEach(documents) { document in
                            documentRow(document, accent: color)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .padding(.vertical, 5)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(color.opacity(0.25))
                            .frame(width: 2)
                            .padding(.vertical, 7)
                            .padding(.leading, 22)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? color.opacity(0.08) : Color(uiColor: .systemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    dropTargetID == group.id ? color : (isSelected ? color.opacity(0.55) : Color.secondary.opacity(0.14)),
                    lineWidth: dropTargetID == group.id ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(0.035), radius: 4, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dropDestination(for: String.self) { payloads, _ in
            handleDrop(payloads, into: group)
        } isTargeted: { targeted in
            dropTargetID = targeted ? group.id : (dropTargetID == group.id ? nil : dropTargetID)
            if targeted {
                expandedGroupIDs.insert(group.id)
                workspace.selectGroup(group)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
        .animation(.easeOut(duration: 0.12), value: dropTargetID)
    }

    private var ungroupedCard: some View {
        let documents = workspace.documents.filter { $0.groupID == nil }
        let isSelected = workspace.selectedGroupID == nil

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    workspace.selectGroup(nil)
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.secondary.opacity(0.10))
                            Image(systemName: "tray.full")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 30, height: 30)
                        Text(preferences.tr("未分组文档", "Ungrouped documents"))
                            .font(.subheadline.weight(.semibold))
                        countBadge(documents.count, color: .gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { isUngroupedExpanded.toggle() } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isUngroupedExpanded ? 90 : 0))
                        .frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if isUngroupedExpanded {
                Divider().padding(.leading, 48)
                if documents.isEmpty {
                    dropEmptyState(color: .gray)
                } else {
                    VStack(spacing: 2) {
                        ForEach(documents) { document in
                            documentRow(document, accent: .gray)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.secondary.opacity(0.07) : Color(uiColor: .systemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    dropTargetID == ungroupedDropID ? Color.green : Color.secondary.opacity(isSelected ? 0.28 : 0.14),
                    lineWidth: dropTargetID == ungroupedDropID ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dropDestination(for: String.self) { payloads, _ in
            handleDrop(payloads, into: nil)
        } isTargeted: { targeted in
            dropTargetID = targeted ? ungroupedDropID : (dropTargetID == ungroupedDropID ? nil : dropTargetID)
            if targeted {
                isUngroupedExpanded = true
                workspace.selectGroup(nil)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                sectionTitle(preferences.tr("最近使用", "Recent files"), systemImage: "clock")
                Spacer()
                Button(preferences.tr("清空", "Clear")) {
                    workspace.clearRecentFiles()
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .help(preferences.tr("清空最近使用记录", "Clear recent files"))
            }
            VStack(spacing: 2) {
                ForEach(workspace.recentFiles, id: \.path) { url in
                    HStack(spacing: 4) {
                        Button { workspace.open(url: url) } label: {
                            Label(url.lastPathComponent, systemImage: "clock")
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 8)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .help(url.path)

                        Button {
                            workspace.removeRecentFile(url)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 26)
                        }
                        .buttonStyle(.plain)
                        .opacity(hoveredRecentPath == url.path ? 1 : 0.35)
                        .help(preferences.tr("从最近使用中移除", "Remove from recent files"))
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredRecentPath = hovering ? url.path : (hoveredRecentPath == url.path ? nil : hoveredRecentPath)
                    }
                    .contextMenu {
                        Button(preferences.tr("从最近使用中移除", "Remove from recent files"), role: .destructive) {
                            workspace.removeRecentFile(url)
                        }
                    }
                }
            }
            .padding(5)
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func documentRow(_ document: EditorDocument, accent: Color) -> some View {
        SidebarDocumentRow(
            document: document,
            isActive: workspace.activeDocumentID == document.id,
            accent: accent,
            fontSize: preferences.sidebarDocumentFontSize
        )
        .contentShape(Rectangle())
        .onTapGesture { workspace.activate(document) }
        .draggable(documentPayload(document.id)) {
            Label(document.title, systemImage: "doc.text")
                .padding(9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        }
        .contextMenu {
            if document.fileAccessError != nil {
                Button(preferences.tr("重新授权文件…", "Reauthorize File…")) {
                    workspace.requestFileAccess(for: document)
                }
                Divider()
            }
            Button(preferences.tr("重命名", "Rename")) {
                documentToRename = document
                renameValue = document.title
            }
            Menu(preferences.tr("移动到分组", "Move to group")) {
                Button(preferences.tr("未分组", "Ungrouped")) { workspace.assign(document, to: nil) }
                ForEach(workspace.documentGroups) { group in
                    Button(workspace.groupHierarchy.path(for: group.id)) { workspace.assign(document, to: group) }
                }
            }
            Divider()
            Button(preferences.tr("关闭", "Close")) {
                NotificationCenter.default.post(name: .requestCloseDocument, object: document)
            }
        }
        .help(document.fileURL?.path ?? document.title)
    }

    private func groupMenu(_ group: DocumentGroup) -> some View {
        Menu {
            Button(preferences.tr("新建分组…", "New Group…")) { presentNewGroup(parent: group) }
            Divider()
            Button(preferences.tr("重命名分组", "Rename group")) {
                groupToRename = group
                renameValue = group.name
            }
            Menu(preferences.tr("分组颜色", "Group color")) {
                ForEach(DocumentGroupColor.allCases) { color in
                    Button {
                        workspace.setColor(color, for: group)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color.color)
                                .frame(width: 10, height: 10)
                            Text(color.title)
                            if color == group.color {
                                Spacer(minLength: 8)
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            }
            Menu(preferences.tr("移动到上级分组", "Move to Parent Group")) {
                Button("无（顶级分组）") { workspace.moveDocumentGroup(group, to: nil) }
                ForEach(workspace.groupHierarchy.outline) { entry in
                    if workspace.groupHierarchy.canMove(group.id, to: entry.id) {
                        Button(workspace.groupHierarchy.path(for: entry.id)) {
                            workspace.moveDocumentGroup(group, to: entry.id)
                            expandedGroupIDs.formUnion(workspace.groupHierarchy.ancestors(of: group.id))
                        }
                    }
                }
            }
            Divider()
            Button(preferences.tr("删除分组（保留文档与子分组）", "Delete Group (Keep Contents)"), role: .destructive) {
                workspace.removeDocumentGroup(group)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 26, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(preferences.tr("分组设置", "Group settings"))
    }

    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.11), in: Capsule())
    }

    private func dropEmptyState(color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
            Text(preferences.tr("拖动文档到此分组", "Drag documents into this group"))
        }
        .font(.caption)
        .foregroundStyle(dropTargetID == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 50)
        .padding(.vertical, 10)
    }

    private func setExpanded(_ expanded: Bool, for id: UUID) {
        if expanded { expandedGroupIDs.insert(id) }
        else { expandedGroupIDs.remove(id) }
    }

    private var visibleGroupEntries: [GroupHierarchy.Entry] {
        let hierarchy = workspace.groupHierarchy
        return hierarchy.outline.filter { entry in
            hierarchy.ancestors(of: entry.id).allSatisfy { expandedGroupIDs.contains($0) }
        }
    }

    private func presentNewGroup(parent: DocumentGroup? = nil) {
        newGroupParentID = parent?.id
        newGroupName = ""
        isAddingGroup = true
    }

    private var ungroupedDropID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }

    private func documentPayload(_ id: UUID) -> String { "document:\(id.uuidString)" }
    private func groupPayload(_ id: UUID) -> String { "group:\(id.uuidString)" }

    private func handleDrop(_ payloads: [String], into group: DocumentGroup?) -> Bool {
        var handled = false
        for payload in payloads {
            if payload.hasPrefix("document:"),
               let id = UUID(uuidString: String(payload.dropFirst("document:".count))),
               let document = workspace.documents.first(where: { $0.id == id }) {
                workspace.assign(document, to: group)
                handled = true
            } else if let group,
                      payload.hasPrefix("group:"),
                      let id = UUID(uuidString: String(payload.dropFirst("group:".count))),
                      let moving = workspace.documentGroups.first(where: { $0.id == id }) {
                workspace.moveDocumentGroup(moving, before: group)
                handled = true
            }
        }
        dropTargetID = nil
        return handled
    }

    private func relativePath(for url: URL, in folder: URL) -> String {
        url.path.replacingOccurrences(of: folder.path + "/", with: "")
    }

    private func fileIcon(for url: URL) -> String {
        SyntaxLanguage.detect(filename: url.lastPathComponent) == .plainText
            ? "doc.plaintext"
            : "chevron.left.forwardslash.chevron.right"
    }
}

private struct SidebarDocumentRow: View {
    @ObservedObject var document: EditorDocument
    let isActive: Bool
    let accent: Color
    let fontSize: Double

    var body: some View {
        HStack(spacing: 7) {
            // A persistent colour marker lets every file inherit its group's
            // colour, rather than only colouring the active document icon.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accent)
                .frame(width: 3, height: 16)
                .opacity(isActive ? 1 : 0.62)
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("拖动文档")
            Image(systemName: document.fileURL == nil ? "doc.badge.plus" : "doc.text")
                .font(.system(size: max(11, fontSize)))
                .foregroundStyle(isActive ? accent : .secondary)
            Text(document.title)
                .font(.system(size: fontSize, weight: isActive ? .semibold : .regular))
                // Keep the inherited group colour on the filename itself so
                // colour-coded groups remain scannable even when a row is not
                // selected. The active row is additionally bold/highlighted.
                .foregroundStyle(accent)
                .lineLimit(1)
            Spacer(minLength: 4)
            if document.isDirty {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("已修改")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isActive ? accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
    }
}

extension Notification.Name {
    static let requestNewDocumentGroup = Notification.Name("NotepadPlus.requestNewDocumentGroup")
}
