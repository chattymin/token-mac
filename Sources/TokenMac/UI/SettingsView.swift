import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    /// 팝오버 내부 화면 전환 방식 — sheet/dismiss 를 쓰지 않는다 (PopoverView 의 NOTE 참조)
    var onClose: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    private var l: L { companion.l }

    private var isBundledApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 14) {
            Text(l.settings)
                .font(.headline)

            Picker(l.language, selection: Binding(
                get: { companion.language },
                set: { companion.setLanguage($0); store.localizationLanguage = $0 })) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(lang.label).tag(lang)
                }
            }
            .pickerStyle(.menu)

            Picker(l.refreshInterval, selection: $store.refreshInterval) {
                ForEach(UsageStore.intervalPresets, id: \.value) { preset in
                    Text(l.intervalLabel(preset.value)).tag(preset.value)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 4) {
                Text(l.menuBarItems)
                    .font(.callout)
                Toggle(l.todayTokensShort, isOn: $store.showTokensInMenu)
                Toggle(l.todayCost, isOn: $store.showCostInMenu)
                Toggle(l.limitPercent, isOn: $store.showLimitInMenu)
                Text(l.allOffHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(l.disableKeychain, isOn: $store.disableKeychainAccess)
                Text(l.disableKeychainHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    Button {
                        Task { await store.refreshLimitTokenFromKeychain() }
                    } label: {
                        if store.isRefreshingLimitToken {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(l.refreshLimitToken)
                        }
                    }
                    .disabled(store.disableKeychainAccess || store.isRefreshingLimitToken)
                    Text(l.onlyOnPress)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let limitTokenRefreshError = store.limitTokenRefreshError {
                    Text(limitTokenRefreshError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(l.launchAtLogin, isOn: $launchAtLogin)
                    .disabled(!isBundledApp)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = "\(error.localizedDescription)"
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if !isBundledApp {
                    Text(l.bundledOnly)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(l.limitAlertThresholds)
                    .font(.callout)
                HStack {
                    Text(l.warning)
                    Slider(value: $store.warnThreshold, in: 50...95, step: 5)
                    Text(TokenFormatter.percent(store.warnThreshold))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.caption)
                HStack {
                    Text(l.critical)
                    Slider(value: $store.critThreshold, in: 80...100, step: 5)
                    Text(TokenFormatter.percent(store.critThreshold))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.caption)
            }

            Text(l.aggregationNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button(l.close) { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}
