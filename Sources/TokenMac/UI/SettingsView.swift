import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    /// 팝오버 내부 화면 전환 방식 — sheet/dismiss 를 쓰지 않는다 (PopoverView 의 NOTE 참조)
    var onClose: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    private var isBundledApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 14) {
            Text("설정")
                .font(.headline)

            Picker("새로고침 간격", selection: $store.refreshInterval) {
                ForEach(UsageStore.intervalPresets, id: \.value) { preset in
                    Text(preset.label).tag(preset.value)
                }
            }
            .pickerStyle(.menu)

            Toggle("메뉴바 코인 회전", isOn: $store.spinEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Text("메뉴바 표시 항목 (복수 선택)")
                    .font(.callout)
                Toggle("오늘 토큰", isOn: $store.showTokensInMenu)
                Toggle("오늘 비용 ($)", isOn: $store.showCostInMenu)
                Toggle("5시간 한도 %", isOn: $store.showLimitInMenu)
                Text("전부 끄면 코인 아이콘만 표시됩니다")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Keychain 접근 끄기", isOn: $store.disableKeychainAccess)
                Text("켜면 공식 한도 % 조회를 건너뜁니다")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("로그인 시 자동 시작", isOn: $launchAtLogin)
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
                    Text(".app 번들로 설치된 경우에만 사용 가능 (scripts/build-app.sh)")
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
                Text("한도 알림 임계값")
                    .font(.callout)
                HStack {
                    Text("경고")
                    Slider(value: $store.warnThreshold, in: 50...95, step: 5)
                    Text(TokenFormatter.percent(store.warnThreshold))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.caption)
                HStack {
                    Text("임박")
                    Slider(value: $store.critThreshold, in: 80...100, step: 5)
                    Text(TokenFormatter.percent(store.critThreshold))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.caption)
            }

            Text("토큰 집계 기준: ccusage totalTokens (input + output + cache, 로컬 날짜)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("닫기") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}
