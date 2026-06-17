import SwiftUI

struct PopoverView: View {
    @Environment(UsageStore.self) private var store
    @State private var showSettings = false

    var body: some View {
        // NOTE: 설정을 .sheet 로 띄우면 transient 팝오버가 닫힐 때 시트가 고아로 남아
        // 이후 팝오버의 모든 버튼 클릭을 차단할 수 있음 — 팝오버 내부 화면 전환으로 처리
        Group {
            if showSettings {
                SettingsView(onClose: { showSettings = false })
                    .environment(store)
            } else {
                mainContent
            }
        }
        .frame(width: 360)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if store.hasAnyLimits {
                limitsSection
                Divider()
            }
            footer
        }
        .padding(14)
    }

    // MARK: 헤더 — 오늘 합계 + provider/토큰타입 분해

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("오늘 사용한 토큰")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(TokenFormatter.compact(store.todayTotalTokens))
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                Text(TokenFormatter.grouped(store.todayTotalTokens))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(TokenFormatter.cost(todayCost))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(store.snapshots) { snapshot in
                if let today = snapshot.today {
                    providerRow(snapshot: snapshot, today: today)
                }
            }

            // 주간/월간 누적
            if store.weekTotalTokens > 0 || store.monthTotalTokens > 0 {
                HStack(spacing: 14) {
                    periodLabel("이번 주", tokens: store.weekTotalTokens, cost: store.weekCostTotal)
                    periodLabel("이번 달", tokens: store.monthTotalTokens, cost: store.monthCostTotal)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    private func periodLabel(_ name: String, tokens: Int, cost: Double) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(tokens))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(TokenFormatter.cost(cost))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var todayCost: Double {
        store.snapshots.reduce(0) { $0 + ($1.today?.totalCost ?? 0) }
    }

    private func providerRow(snapshot: ProviderSnapshot, today: DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(snapshot.displayName)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(TokenFormatter.compact(today.totalTokens))
                    .font(.callout)
                    .monospacedDigit()
                Text(TokenFormatter.cost(today.totalCost))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                tokenTypeLabel("in", today.inputTokens)
                tokenTypeLabel("out", today.outputTokens)
                tokenTypeLabel("cache w", today.cacheCreationTokens)
                tokenTypeLabel("cache r", today.cacheReadTokens)
            }
        }
        .padding(.top, 2)
    }

    private func tokenTypeLabel(_ name: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(value))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: 한도 섹션 — 공식 5h/주간 % + 리셋 카운트다운

    @ViewBuilder
    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("한도 (공식)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let limits = store.limits {
                limitProviderTitle("Claude Code")
                limitRow(name: "5시간 세션", window: limits.fiveHour)
                forecastRow
                limitRow(name: "주간", window: limits.sevenDay)
                limitRow(name: "주간 Opus", window: limits.sevenDayOpus)
                limitRow(name: "주간 Sonnet", window: limits.sevenDaySonnet)
                if let block = store.snapshots.first(where: { $0.activeBlock != nil })?.activeBlock,
                   let end = block.endDate {
                    HStack {
                        Text("Claude 현재 5h 블록")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(TokenFormatter.compact(block.totalTokens))
                            .font(.caption)
                            .monospacedDigit()
                        Spacer()
                        Text("리셋 \(end, style: .relative) 후")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if let codex = store.codexLimits?.codex, codex.hasVisibleLimit {
                limitProviderTitle("Codex")
                codexMetaRow(codex)
                codexLimitRow(name: codex.primary?.displayName ?? "5시간 세션", window: codex.primary)
                codexLimitRow(name: codex.secondary?.displayName ?? "주간", window: codex.secondary)
                codexSpendLimitRow(codex.individualLimit)
            }
        }
    }

    private func limitProviderTitle(_ name: String) -> some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    @ViewBuilder
    private func limitRow(name: String, window: LimitWindow?) -> some View {
        if let window, let utilization = window.utilization {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.callout)
                    Spacer()
                    Text(TokenFormatter.percent(utilization))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(limitColor(utilization))
                    if let reset = window.resetDate {
                        Text("· \(reset, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                ProgressView(value: min(utilization, 100), total: 100)
                    .tint(limitColor(utilization))
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func codexMetaRow(_ snapshot: CodexRateLimitSnapshot) -> some View {
        if snapshot.planType != nil || snapshot.rateLimitReachedType != nil {
            HStack(spacing: 8) {
                if let plan = snapshot.planType {
                    Text("플랜 \(plan)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if snapshot.rateLimitReachedType != nil {
                    Text("한도 도달")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func codexLimitRow(name: String, window: CodexRateLimitWindow?) -> some View {
        if let window {
            let utilization = Double(window.usedPercent)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.callout)
                    Spacer()
                    Text(TokenFormatter.percent(utilization))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(limitColor(utilization))
                    if let reset = window.resetDate {
                        Text("· \(reset, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                ProgressView(value: min(utilization, 100), total: 100)
                    .tint(limitColor(utilization))
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func codexSpendLimitRow(_ limit: CodexSpendControlLimit?) -> some View {
        if let limit {
            let utilization = Double(limit.usedPercent)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("개인 사용 한도")
                        .font(.callout)
                    Spacer()
                    Text("\(limit.used) / \(limit.limit)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(TokenFormatter.percent(utilization))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(limitColor(utilization))
                    Text("· \(limit.resetDate, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ProgressView(value: min(utilization, 100), total: 100)
                    .tint(limitColor(utilization))
                    .controlSize(.small)
            }
        }
    }

    /// 한도 소진 예측 — 현재 burn rate 로 5h 한도 100% 도달 시각 외삽
    @ViewBuilder
    private var forecastRow: some View {
        if let forecast = store.fiveHourForecast {
            HStack(spacing: 4) {
                Image(systemName: forecast.beforeReset
                    ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.caption2)
                Text(forecast.beforeReset
                    ? "현재 속도면 \(Self.timeFormatter.string(from: forecast.depletionDate)) 한도 도달"
                    : "현재 속도로는 리셋 전 한도 도달 없음")
                    .font(.caption)
            }
            .foregroundStyle(forecast.beforeReset ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            .padding(.leading, 2)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func limitColor(_ utilization: Double) -> Color {
        if utilization >= store.critThreshold { return .red }
        if utilization >= store.warnThreshold { return .orange }
        return .green
    }

    // MARK: 푸터

    private var footer: some View {
        HStack(spacing: 10) {
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("지금 새로고침")
            }
            if let updated = store.lastUpdated {
                Text("갱신 \(updated, style: .relative) 전")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if store.lastErrorDescription != nil {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(store.lastErrorDescription ?? "")
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("설정")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("종료")
        }
    }
}
