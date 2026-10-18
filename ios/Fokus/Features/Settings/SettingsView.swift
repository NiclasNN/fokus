import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var notifyStatus: UNAuthorizationStatus = .notDetermined
    @State private var alarmStatus: (ok: Bool, text: String) = (false, "")
    @State private var importing = false
    @State private var exporting = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Larm") {
                    if !alarmStatus.ok {
                        Button {
                            Task { await requestNotifications() }
                        } label: {
                            Label("Slå på larm", systemImage: "alarm")
                        }
                    }
                    Toggle("Larm när passet är slut", isOn: $store.s.settings.notify)
                        .onChange(of: store.s.settings.notify) { _, on in
                            if !on { store.disarmAlarm() }
                            store.save()
                        }
                    Button {
                        Haptics.tap(); Sound.shared.finish()
                    } label: {
                        Label("Lyssna på slutklockan", systemImage: "speaker.wave.2")
                    }
                    Text(alarmStatus.text)
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

                Section {
                    HStack {
                        Text("Namn")
                        TextField("Malin", text: $store.s.settings.partnerName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Palette.second)
                    }
                    HStack {
                        Text("Emoji")
                        TextField("💖", text: $store.s.settings.partnerEmoji)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: store.s.settings.partnerEmoji) { _, v in
                                // en enda emoji — tangentbordet kan klistra in fler
                                if v.count > 1 { store.s.settings.partnerEmoji = String(v.suffix(1)) }
                            }
                    }
                } header: {
                    Text(store.s.settings.partnerName.isEmpty ? "Malin" : store.s.settings.partnerName)
                } footer: {
                    Text("Knappen dyker upp mitt bland plattorna i Fokus när du har gjort något i alla fyra livsområden under dagen — bockat av en uppgift eller kört ett pass i varje.")
                }
                .onChange(of: store.s.settings.partnerName) { _, _ in store.save() }

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
        alarmStatus = await PassAlarm.status()
    }
    private func requestNotifications() async {
        await PassAlarm.prepare()
        await refreshStatus()
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
