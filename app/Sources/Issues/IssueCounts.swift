struct IssueCounts {
    var toDo = 0
    var inProgress = 0
    var blocked = 0
    var unchecked = 0

    init(issues: [Issue]) {
        for issue in issues where issue.state != "closed" {
            if !issue.blockers.isEmpty { blocked += 1 }
            switch issue.details?.status?.normalizedCategory {
            case "TO_DO": toDo += 1
            case "IN_PROGRESS": inProgress += 1
            default: break
            }
            if issue.links == nil || issue.details == nil { unchecked += 1 }
        }
    }

    var help: String {
        tr("Открытые задачи: To Do %lld | In progress %lld | заблокированные %lld. Блокировки считаются отдельно от статуса.", toDo, inProgress, blocked) +
            (unchecked == 0 ? "" : tr(" Неполные данные: %lld.", unchecked))
    }
}
