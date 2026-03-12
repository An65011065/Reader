import SwiftUI

struct ReadingSettingsView: View {
    @EnvironmentObject var settings: ReadingSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Font size
                Section("Text Size") {
                    HStack(spacing: 16) {
                        Button(action: { settings.fontSize = max(12, settings.fontSize - 1) }) {
                            Image(systemName: "textformat.size.smaller")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        Slider(value: $settings.fontSize, in: 12...32, step: 1)
                            .tint(.primary)

                        Button(action: { settings.fontSize = min(32, settings.fontSize + 1) }) {
                            Image(systemName: "textformat.size.larger")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        Text("\(Int(settings.fontSize))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                    }
                    .padding(.vertical, 4)
                }

                // Theme
                Section("Theme") {
                    HStack(spacing: 12) {
                        ForEach(ReadingSettings.Theme.allCases, id: \.rawValue) { theme in
                            ThemeButton(theme: theme, isSelected: settings.theme == theme) {
                                settings.theme = theme
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                // Font
                Section("Font") {
                    ForEach(ReadingSettings.FontFamily.allCases, id: \.rawValue) { font in
                        Button(action: { settings.font = font }) {
                            HStack {
                                Text(font.displayName)
                                    .font(.custom(font.rawValue, size: 17))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if settings.font == font {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                // Line spacing
                Section("Line Spacing") {
                    HStack(spacing: 12) {
                        ForEach([(1.2, "Compact"), (1.6, "Normal"), (2.0, "Relaxed")], id: \.0) { value, label in
                            Button(action: { settings.lineHeight = value }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "text.alignleft")
                                        .font(value == 1.2 ? .caption : value == 1.6 ? .body : .title3)
                                    Text(label)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(settings.lineHeight == value ? Color.accentColor.opacity(0.15) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(settings.lineHeight == value ? .blue : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Two-page layout (iPad)
                Section("Layout") {
                    Toggle("Two-Page Layout", isOn: $settings.twoPageMode)
                }

                // Margins
                Section("Margins") {
                    HStack(spacing: 12) {
                        ForEach([(24.0, "Narrow"), (48.0, "Normal"), (72.0, "Wide")], id: \.0) { value, label in
                            Button(action: { settings.marginSize = value }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "rectangle.portrait")
                                        .font(.body)
                                    Text(label)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(settings.marginSize == value ? Color.accentColor.opacity(0.15) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(settings.marginSize == value ? .blue : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Reading Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ThemeButton: View {
    let theme: ReadingSettings.Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.background)
                        .frame(width: 60, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(isSelected ? Color.blue : Color(.separator), lineWidth: isSelected ? 2 : 1)
                        )
                    Text("Aa")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.foreground)
                }
                Text(theme.label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
