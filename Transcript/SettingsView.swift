import SwiftUI

struct SettingsView: View {
    var stats: StatsStore
    var replacements: ReplacementStore

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            StatsTab(stats: stats)
                .tabItem { Label("Statistics", systemImage: "chart.bar.fill") }
                .tag(0)

            OutputTab(store: replacements)
                .tabItem { Label("Output", systemImage: "text.badge.checkmark") }
                .tag(1)
        }
        .frame(width: 480, height: 420)
    }
}

// MARK: - Statistics

private struct StatsTab: View {
    var stats: StatsStore

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    value: "\(stats.totalWords)",
                    label: "Total Words",
                    icon: "text.word.spacing",
                    tint: .blue
                )
                StatCard(
                    value: "\(stats.wordsToday)",
                    label: "Words Today",
                    icon: "sun.max.fill",
                    tint: .orange
                )
                StatCard(
                    value: stats.averageWPM > 0 ? String(format: "%.0f", stats.averageWPM) : "—",
                    label: "Avg WPM",
                    icon: "gauge.with.needle",
                    tint: .purple
                )
                StatCard(
                    value: "\(stats.totalSessions)",
                    label: "Sessions",
                    icon: "mic.fill",
                    tint: .pink
                )
            }
            .padding(20)

            Divider().padding(.horizontal, 20)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(stats.formattedRecordingTime)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("total recording time")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 14)

            Spacer()
        }
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Output

private struct OutputTab: View {
    @Bindable var store: ReplacementStore

    @AppStorage("removeStuttering") private var removeStuttering = true
    @AppStorage("detectQuotations") private var detectQuotations = false
    @AppStorage("outputStyle") private var outputStyleRaw = "Formal"

    private var outputStyle: OutputStyle {
        OutputStyle(rawValue: outputStyleRaw) ?? .formal
    }

    var body: some View {
        VStack(spacing: 0) {
            outputSettings
            Divider()
            replacementsHeader
            if store.rules.isEmpty {
                emptyState
            } else {
                rulesList
            }
            Divider()
            bottomBar
        }
        .onChange(of: store.rules) { store.save() }
    }

    // MARK: Style & stutter controls

    private var outputSettings: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Style")
                        .font(.system(size: 12, weight: .medium))
                    Text(styleDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Picker("", selection: $outputStyleRaw) {
                    ForEach(OutputStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            Toggle(isOn: $removeStuttering) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Remove stuttering")
                        .font(.system(size: 12, weight: .medium))
                    Text("Drops duplicate adjacent words (\"the the\" → \"the\")")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $detectQuotations) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Detect quotations")
                        .font(.system(size: 12, weight: .medium))
                    Text("Best-effort quoting after speech verbs (e.g. said / was like)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var styleDescription: String {
        switch outputStyle {
        case .formal: "Default transcription output"
        case .noCapitals: "Removes all capital letters"
        case .casual: "No capitals, no periods"
        }
    }

    // MARK: Replacement rules

    private var replacementsHeader: some View {
        HStack {
            Text("Auto-Replacements")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("No replacement rules")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Auto-correct or expand words after transcription")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var rulesList: some View {
        List {
            ForEach($store.rules) { $rule in
                HStack(spacing: 10) {
                    Toggle("", isOn: $rule.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                    TextField("Word or phrase", text: $rule.pattern)
                        .textFieldStyle(.roundedBorder)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)

                    TextField("Replacement", text: $rule.replacement)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        withAnimation { store.rules.removeAll { $0.id == rule.id } }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                withAnimation { store.addRule() }
            } label: {
                Label("Add Rule", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)

            Spacer()

            if !store.rules.isEmpty {
                Text("\(store.rules.count) rule\(store.rules.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
