import SwiftUI

struct IssueCard: View {
    @ObservedObject var model: WidgetModel
    let issue: Issue
    let showClosed: Bool
    let orange = Color.orange

    var body: some View {
                            VStack(alignment: .leading, spacing: 8) {
                                if !issue.blockers.isEmpty {
                                    Label(tr("Заблокирована"), systemImage: "lock.fill")
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(orange)
                                        .padding(.horizontal, 8).padding(.vertical, 4).background(orange.opacity(0.12), in: Capsule())
                                } else if issue.links == nil {
                                    Label(tr("Блокировки не проверены"), systemImage: "questionmark.circle")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Button { model.open(issue.url) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                    HStack(alignment: .top, spacing: 9) {
                                        Text(issue.number).font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.secondary).padding(.top, 1)
                                        Text(issue.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.tertiary)
                                    }
                                    HStack(spacing: 5) {
                                        Text(issue.project).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 0)
                                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).help(tr("Открыть %@ в браузере", issue.number))
                                HStack(spacing: 6) {
                                    HStack(spacing: 5) {
                                        Image(systemName: issue.state == "closed" ? "checkmark.circle.fill" : "circle.inset.filled")
                                            .symbolRenderingMode(.hierarchical)
                                            .foregroundStyle(Color.gitLabHex(issue.details?.status?.color ?? (issue.state == "closed" ? "#2da160" : "#888888")))
                                        Text(issue.details?.status?.name ?? (issue.state == "closed" ? tr("Закрыта") : tr("Открыта")))
                                            .lineLimit(1)
                                    }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(.white.opacity(0.06), in: Capsule())
                                    Spacer(minLength: 0)
                                    WidgetIconButton(title: tr("Изменить %@", issue.number), symbol: "square.and.pencil", tint: .blue) { model.onEdit?(issue) }
                                        .disabled(!model.editingEnabled || model.loginRequired || model.connecting)
                                        .help(tr("Изменить статус и метки %@", issue.number))
                                    WidgetIconButton(title: tr("Удалить %@", issue.number), symbol: "trash", tint: .red) { model.onDelete?(issue) }
                                        .disabled(!model.editingEnabled || model.loginRequired || model.loading || model.saving || issue.details?.canDelete != true)
                                        .help(issue.details?.canDelete == true ? tr("Удалить %@", issue.number) : tr("Нет права удаления этой задачи"))
                                }
                                if !issue.labels.isEmpty {
                                    ScrollView(.horizontal) {
                                        HStack(spacing: 4) {
                                            ForEach(issue.labels, id: \.self) { label in
                                                Text(label).font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4)
                                                    .background(Color.gitLabHex(issue.details?.labels.first { $0.title == label }?.color ?? "#65717e").opacity(0.3),
                                                                in: Capsule())
                                            }
                                        }
                                    }.scrollIndicators(.hidden)
                                }
                                if let closed = issue.closedAt.flatMap(IssueDay.parse), showClosed {
                                    Text(tr("Закрыта %@", IssueDay.time(closed)))
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                ForEach(issue.blockers) { link in
                                    relationshipButton(link, prefix: tr("Ждёт"), color: orange)
                                }
                                ForEach(issue.blockedIssues) { link in
                                    relationshipButton(link, prefix: tr("Блокирует"), color: .blue)
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func relationshipButton(_ link: IssueLink, prefix: String, color: Color) -> some View {
        Button { model.open(link.url) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label("\(prefix) \(link.number) · \(link.project)", systemImage: "link")
                    .font(.system(size: 10, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(color)
                Text(link.title).font(.system(size: 11)).lineLimit(2)
                    .multilineTextAlignment(.leading).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help("\(prefix) \(link.project)\(link.number): \(link.title)")
    }
}
