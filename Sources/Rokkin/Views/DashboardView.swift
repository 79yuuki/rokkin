import Charts
import RokkinCore
import SwiftUI

/// How you focus, at a glance: totals, weekly trend, time of day, drift reasons, detours and
/// self-experiments. Everything is computed on this Mac from the saved history.
struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("dashboardPeriod") private var period: InsightPeriod = .last30
    @State private var copied = false

    var body: some View {
        let ins = InsightsBuilder.build(history: state.history, period: period)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(ins)
                if state.history.isEmpty {
                    emptyState
                } else {
                    if ins.isEmpty {
                        Text("この期間の記録はまだありません。期間を広げると前の分が見られます")
                            .foregroundStyle(.secondary)
                    } else {
                        kpiRow(ins)
                    }
                    weeklyCard(ins)
                    HStack(alignment: .top, spacing: 16) {
                        hourCard(ins)
                        dailyCard(ins)
                    }
                    if !ins.isEmpty {
                        HStack(alignment: .top, spacing: 16) {
                            triggerCard(ins)
                            detourCard(ins)
                        }
                        compareCard(ins)
                    }
                    sessionsCard
                }
                if !state.inbox.isEmpty { inboxCard }
            }
            .padding(24)
        }
        .frame(width: 900, height: 800)
    }

    // MARK: Header

    private func header(_ ins: Insights) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ダッシュボード")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(RokkinTheme.gradient)
                Text("集計はこの Mac の中だけで行っています")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("期間", selection: $period) {
                ForEach(InsightPeriod.allCases) { p in Text(p.label).tag(p) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 290)
            Button(copied ? "コピーしました ✓" : "Markdownでコピー") {
                Clipboard.copy(ins.markdown())
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    copied = false
                }
            }
            .help("この集計を Markdown でコピー。メモに貼ったり、Claude に渡して相談したりできます")
            .disabled(state.history.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("まだ記録がありません").font(.title3.weight(.bold))
            Text("1回 Lock in してリザルトを保存すると、集中率・時間帯・脱線のきっかけ・週ごとの推移がここに出ます。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Lock in ⚡") { state.openSetup() }
                .buttonStyle(.borderedProminent)
                .tint(RokkinTheme.pink)
                .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    // MARK: Totals

    private func kpiRow(_ ins: Insights) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StatTile(label: "集中率", value: Rates.percent(ins.onTaskRate),
                     detail: "自己チェックで「はい」\(ins.yes) / \(ins.answered)",
                     badge: weekBadge(ins))
            StatTile(label: "作業時間", value: TimeFormat.minutes(ins.workedSeconds),
                     detail: "\(ins.sessions)セッション ・ クリアしたブロック \(ins.blocksCleared)")
            StatTile(label: "気づけた回数", value: "\(ins.noticed)回",
                     detail: "「いいえ」\(ins.noticedOnCheck) ＋ 寄り道から復帰 \(ins.driftReturned)。気づけたら勝ち")
            StatTile(label: "最高コンボ", value: "🔥\(ins.bestCombo)",
                     detail: ins.judged > 0
                        ? "完了の定義を達成 \(ins.completed) / \(ins.judged)"
                        : "「はい」が続いた最高記録")
        }
    }

    private func weekBadge(_ ins: Insights) -> (String, Color)? {
        guard let d = ins.weekOverWeekPoints else { return nil }
        if d > 0 { return ("先週より +\(d)pt ↑", .green) }
        if d == 0 { return ("先週と同じ", .secondary) }
        return ("先週より \(d)pt", .secondary)
    }

    // MARK: Charts

    private var percentAxis: some AxisContent {
        AxisMarks(values: [0.0, 50.0, 100.0]) { v in
            AxisGridLine()
            AxisValueLabel {
                if let d = v.as(Double.self) { Text("\(Int(d))%") }
            }
        }
    }

    private func weeklyCard(_ ins: Insights) -> some View {
        let labels = ins.weekly.map { Self.weekLabel($0.start) }
        let rated = ins.weekly.filter { $0.answered > 0 }
        return Card("週ごとの推移", note: "直近8週・月曜はじまり") {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("集中率").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Chart {
                        ForEach(rated) { w in
                            LineMark(x: .value("週", Self.weekLabel(w.start)),
                                     y: .value("集中率", (w.rate ?? 0) * 100))
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .foregroundStyle(RokkinTheme.pink)
                            PointMark(x: .value("週", Self.weekLabel(w.start)),
                                      y: .value("集中率", (w.rate ?? 0) * 100))
                                .foregroundStyle(RokkinTheme.pink)
                                .annotation(position: .top, spacing: 4) {
                                    Text(Rates.percent(w.rate))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .chartXScale(domain: labels)
                    .chartYScale(domain: 0.0...115.0)
                    .chartYAxis { percentAxis }
                    .frame(height: 160)
                    .overlay {
                        if rated.isEmpty {
                            Text("自己チェックに答えると線が出ます").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("作業時間").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Chart(ins.weekly) { w in
                        BarMark(x: .value("週", Self.weekLabel(w.start)),
                                y: .value("時間", w.workedSeconds / 3600))
                            .foregroundStyle(Self.barGradient)
                            .cornerRadius(4)
                    }
                    .chartXScale(domain: labels)
                    .chartYAxis {
                        AxisMarks { v in
                            AxisGridLine()
                            AxisValueLabel {
                                if let h = v.as(Double.self) { Text(Self.hoursText(h)) }
                            }
                        }
                    }
                    .frame(height: 160)
                }
            }
        }
    }

    private func hourCard(_ ins: Insights) -> some View {
        let domain = (0..<24).map { String($0) }
        let active = ins.hours.filter { $0.answered > 0 }
        let best = ins.bestHour
        return Card("時間帯別の集中率", note: period.label) {
            Chart(active) { h in
                BarMark(x: .value("時", String(h.hour)), y: .value("集中率", (h.rate ?? 0) * 100))
                    .foregroundStyle(h.hour == best?.hour
                        ? AnyShapeStyle(RokkinTheme.pink)
                        : AnyShapeStyle(RokkinTheme.cyan.opacity(h.answered >= ins.minSamples ? 0.85 : 0.3)))
                    .cornerRadius(3)
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0.0...100.0)
            .chartXAxis {
                AxisMarks(values: stride(from: 0, to: 24, by: 3).map { String($0) }) { v in
                    AxisValueLabel {
                        if let s = v.as(String.self) { Text("\(s)時") }
                    }
                }
            }
            .chartYAxis { percentAxis }
            .frame(height: 150)
            .overlay {
                if active.isEmpty {
                    Text("この期間の回答はまだありません").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let best {
                Text("いちばん集中できているのは \(best.hour)時台（\(Rates.percent(best.rate))）")
                    .font(.callout.weight(.semibold))
            } else {
                Text("1つの時間帯で回答が\(ins.minSamples)回たまると、いちばん集中できる時間帯を出します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("薄いバーは回答\(ins.minSamples)回未満の参考値")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func dailyCard(_ ins: Insights) -> some View {
        let labels = ins.daily.map { Self.dayLabel($0.date) }
        let shown = labels.enumerated()
            .filter { $0.offset % 3 == 1 || $0.offset == labels.count - 1 }
            .map { $0.element }
        let activeDays = ins.daily.filter { $0.sessions > 0 }.count
        return Card("直近14日の作業時間", note: "Lock in した日 \(activeDays) / \(ins.daily.count)") {
            Chart(ins.daily) { d in
                BarMark(x: .value("日", Self.dayLabel(d.date)), y: .value("分", d.workedSeconds / 60))
                    .foregroundStyle(Self.barGradient)
                    .cornerRadius(3)
            }
            .chartXScale(domain: labels)
            .chartXAxis {
                AxisMarks(values: shown) { v in
                    AxisValueLabel {
                        if let s = v.as(String.self) { Text(s) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let m = v.as(Double.self) { Text("\(Int(m))分") }
                    }
                }
            }
            .frame(height: 150)
        }
    }

    // MARK: Rankings

    private func triggerCard(_ ins: Insights) -> some View {
        Card("脱線のきっかけ", note: "自己チェックで「いいえ」の理由") {
            if ins.triggers.isEmpty {
                Text("まだありません。「いいえ」と答えると、理由がここにたまります")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RankList(items: ins.triggers, color: RokkinTheme.pink)
                if let top = ins.triggers.first, let plan = DefaultContent.suggestedPlan(for: top.name) {
                    suggestion(top: top.name, plan: plan)
                }
            }
        }
    }

    private func suggestion(top: String, plan: String) -> some View {
        let added = state.settings.defaultIfThen.contains(plan)
        return VStack(alignment: .leading, spacing: 6) {
            Text("いちばん多いのは「\(top)」。こんな if-then プランが効きやすいです")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 6) {
                Text("⚡").foregroundStyle(RokkinTheme.bolt)
                Text(plan).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Button(added ? "開始画面に入っています ✓" : "開始画面のプランに追加") {
                state.settings.defaultIfThen.append(plan)
            }
            .disabled(added)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(RokkinTheme.pink.opacity(0.08)))
    }

    private func detourCard(_ ins: Insights) -> some View {
        Card("寄り道先", note: "ひと呼吸が出たアプリ・サイト") {
            if ins.detours.isEmpty {
                Text("まだありません。設定の「寄り道」で決めたアプリ・サイトを開くと、ここに回数がたまります")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                RankList(items: ins.detours, color: RokkinTheme.cyan)
                Text("ひと呼吸 \(ins.driftStops)回のうち、戻った・メモした \(ins.driftReturned)回")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Self-experiments

    private func compareCard(_ ins: Insights) -> some View {
        Card("自分で実験", note: "効き方は人それぞれ。自分のデータで確かめる") {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude の待ち時間").font(.callout.weight(.semibold))
                    CompareBar(label: "Claude 実行中", rate: ins.claudeRate, count: "\(ins.claudeAnswered)回答",
                               enough: ins.claudeAnswered >= ins.minSamples, color: RokkinTheme.violet)
                    CompareBar(label: "それ以外", rate: ins.otherRate, count: "\(ins.otherAnswered)回答",
                               enough: ins.otherAnswered >= ins.minSamples, color: RokkinTheme.cyan)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("背景ノイズ").font(.callout.weight(.semibold))
                    CompareBar(label: "ノイズあり", rate: ins.noise.withNoise, count: "\(ins.noise.sessionsWith)セッション",
                               enough: ins.noise.sessionsWith >= 3, color: RokkinTheme.pink)
                    CompareBar(label: "なし", rate: ins.noise.withoutNoise, count: "\(ins.noise.sessionsWithout)セッション",
                               enough: ins.noise.sessionsWithout >= 3, color: RokkinTheme.cyan)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("おすすめのブロック長").font(.callout.weight(.semibold))
                    if let rec = ins.recommendedBlockMinutes {
                        Text("\(rec)分")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(RokkinTheme.gradient)
                        Text("脱線するまでの時間の中央値から。開始画面に ★ 付きで出ます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("自己チェックの記録が3ブロック分たまると提案します")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 200, alignment: .leading)
            }
            Text("薄い表示は、回答\(ins.minSamples)回未満・3セッション未満の参考値です")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Sessions and loose notes

    private var sessionsCard: some View {
        let list = InsightsBuilder.sessions(history: state.history, period: period)
        let shown = Array(list.prefix(60))
        return Card("セッション", note: "\(period.label) ・ ダブルクリックでリザルト") {
            if list.isEmpty {
                Text("この期間のセッションはありません").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { s in
                        sessionRow(s)
                        Divider().opacity(0.5)
                    }
                }
                if list.count > shown.count {
                    Text("ほか \(list.count - shown.count)件。期間を絞ると見つけやすくなります")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sessionRow(_ s: SessionRecord) -> some View {
        let st = s.stats()
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.task).lineLimit(1)
                Text(Self.rowDate.string(from: s.start)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(TimeFormat.minutes(st.workedSeconds)).font(.callout.monospacedDigit())
            Text(Rates.percent(st.onTaskRate))
                .font(.callout.monospacedDigit())
                .frame(width: 48, alignment: .trailing)
            Image(systemName: s.completed == true ? "checkmark.seal.fill" : "circle.dotted")
                .foregroundStyle(s.completed == true ? Color.green : Color.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("リザルトを開く") { state.openReview(id: s.id) }
            Button("レポートをコピー") { Clipboard.copy(s.markdownReport()) }
        }
        .onTapGesture(count: 2) { state.openReview(id: s.id) }
    }

    private var inboxCard: some View {
        Card("セッション外のメモ") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(state.inbox) { n in
                    NoteRow(note: n) { state.toggleNote(n.id) }
                }
                Button("済みを削除") { state.clearResolvedInbox() }.controlSize(.small)
            }
        }
    }

    // MARK: Formatting

    private static let barGradient = LinearGradient(
        colors: [RokkinTheme.violet, RokkinTheme.cyan], startPoint: .bottom, endPoint: .top
    )

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d"
        return f
    }()

    private static let rowDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E) HH:mm"
        return f
    }()

    private static func weekLabel(_ d: Date) -> String { monthDay.string(from: d) + "〜" }

    private static func dayLabel(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "今日" : monthDay.string(from: d)
    }

    private static func hoursText(_ h: Double) -> String {
        if h <= 0 { return "0" }
        if h < 1 { return "\(Int((h * 60).rounded()))分" }
        if h.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(h))時間" }
        return String(format: "%.1f時間", h)
    }
}

// MARK: - Building blocks

private struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

private struct Card<Content: View>: View {
    let title: String
    let note: String?
    let content: Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(CardBackground())
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let detail: String
    var badge: (String, Color)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(RokkinTheme.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let badge {
                Text(badge.0).font(.caption.weight(.bold)).foregroundStyle(badge.1)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(CardBackground())
    }
}

private struct RankList: View {
    let items: [RankedItem]
    let color: Color
    var limit = 5

    var body: some View {
        let top = Array(items.prefix(limit))
        let maxCount = max(1, top.map(\.count).max() ?? 1)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(top.enumerated()), id: \.element.id) { i, item in
                HStack(spacing: 8) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(i == 0 ? color : Color.secondary)
                        .frame(width: 14)
                    Text(item.name)
                        .font(.callout)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                    GeometryReader { geo in
                        Capsule()
                            .fill(color.opacity(i == 0 ? 0.9 : 0.45))
                            .frame(width: max(6, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                    }
                    .frame(height: 10)
                    Text("\(item.count)回")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

private struct CompareBar: View {
    let label: String
    let rate: Double?
    let count: String
    let enough: Bool
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label).font(.caption)
                Spacer(minLength: 4)
                Text(Rates.percent(rate)).font(.callout.weight(.bold).monospacedDigit())
                Text(count).font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(rate ?? 0))
                }
            }
            .frame(height: 8)
        }
        .opacity(rate == nil ? 0.45 : (enough ? 1 : 0.55))
    }
}
