import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var notifyStatus: UNAuthorizationStatus = .notDetermined
    @State private var importing = false
    @State private var exporting = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Notiser & larm") {
                    if notifyStatus != .authorized {
                        Button {
                            Task { await requestNotifications() }
                        } label: {
                            Label("Aktivera notiser", systemImage: "bell")
                        }
                    }
                    Toggle("Larm när passet är slut", isOn: $store.s.settings.notify)
                        .onChange(of: store.s.settings.notify) { _, on in
                            on ? store.scheduleAlarm() : store.cancelAlarm()
                            store.save()
                        }
                    Text(notifyStatus == .authorized
                         ? "Larmet är schemalagt i systemet och väcker telefonen även med släckt skärm — appen behöver inte ligga igång."
                         : notifyStatus == .denied
                         ? "Notiser är avstängda för Fokus. Slå på dem i Inställningar → Fokus → Notiser."
                         : "Tillåt notiser så pinglar Fokus dig när passet är slut.")
                        .font(.system(size: 13)).foregroundStyle(Palette.second)
                }

                Section("Känsla") {
                    Toggle("Vibration", isOn: $store.s.settings.haptics)
                        .onChange(of: store.s.settings.haptics) { _, v in
                            Haptics.enabled = v; if v { Haptics.press() }; store.save()
                        }
                    Toggle("Ljud", isOn: $store.s.settings.sound)
                        .onChange(of: store.s.settings.sound) { _, v in
                            Sound.shared.enabled = v; if v { Sound.shared.check() }; store.save()
                        }
                    Text("Ratten klickar per minut, hårdare var femte och med en dov stöt vid hel timme.")
                        .font(.system(size: 13)).foregroundStyle(Palette.second)
                }

                Section("Utseende") {
                    Picker("Tema", selection: $store.s.settings.theme) {
                        Text("System").tag(Settings.Theme.system)
                        Text("Ljust").tag(Settings.Theme.light)
                        Text("Mörkt").tag(Settings.Theme.dark)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.s.settings.theme) { _, _ in store.save() }
                }

                Section {
                    Button { exporting = true } label: { Label("Exportera backup", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Importera", systemImage: "square.and.arrow.down") }
                } header: {
                    Text("Dina data")
                } footer: {
                    Text("Allt ligger på den här telefonen. Inget konto, ingen server. "
                         + "Importen läser både den här appens backup och en export från webbversionen.\n\n"
                         + "\(store.s.todos.filter { !$0.isHeading }.count) uppgifter · "
                         + "\(store.s.projects.count) projekt · \(store.s.sessions.count) pass")
                }

                if let n = note {
                    Section { Text(n).font(.system(size: 13.5)).foregroundStyle(Palette.second) }
                }

                Section {
                    HStack {
                        Text("Version").foregroundStyle(Palette.second)
                        Spacer()
                        Text(appVersion).foregroundStyle(Palette.third).monospacedDigit()
                    }
                    .font(.system(size: 14))
                }
            }
            .navigationTitle("Mer")
            .task { await refreshStatus() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): note = Importer.load(url, into: store)
                case .failure:          note = "Kunde inte läsa filen."
                }
            }
            .fileExporter(isPresented: $exporting,
                          document: BackupFile(data: Importer.export(store)),
                          contentType: .json,
                          defaultFilename: "fokus-backup-\(DayKey.today.raw)") { _ in }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
    private func refreshStatus() async {
        notifyStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
        await refreshStatus()
        store.scheduleAlarm()
    }
}

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
