//
//  MigrateFromAnotherDevice.swift
//  SimpleX (iOS)
//
//  Created by Avently on 23.02.2024.
//  Copyright © 2024 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

private enum MigrationState: Equatable {
    case pasteOrScanLink(link: String)
    case linkDownloading(link: String)
    case downloadProgress(downloadedBytes: Int64, totalBytes: Int64, fileId: Int64, link: String, archivePath: URL, ctrl: chat_ctrl?)
    case downloadFailed(totalBytes: Int64, link: String, archivePath: URL)
    case archiveImport(archivePath: String)
    case archiveImportFailed(archivePath: String)
    case passphraseEntering(passphrase: String)
    case migration(passphrase: String)
}

private enum MigrateFromAnotherDeviceViewAlert: Identifiable {
    case chatImportedWithErrors(title: LocalizedStringKey = "Chat database imported",
                                text: LocalizedStringKey = "Some non-fatal errors occurred during import - you may see Chat console for more details.")

    case wrongPassphrase(title: LocalizedStringKey = "Wrong passphrase!", message: LocalizedStringKey = "Enter correct passphrase.")
    case invalidConfirmation(title: LocalizedStringKey = "Invalid migration confirmation")
    case keychainError(_ title: LocalizedStringKey = "Keychain error")
    case databaseError(_ title: LocalizedStringKey = "Database error", message: String)
    case unknownError(_ title: LocalizedStringKey = "Unknown error", message: String)

    case error(title: LocalizedStringKey, error: String = "")

    var id: String {
        switch self {
        case .chatImportedWithErrors: return "chatImportedWithErrors"

        case .wrongPassphrase: return "wrongPassphrase"
        case .invalidConfirmation: return "invalidConfirmation"
        case .keychainError: return "keychainError"
        case let .databaseError(title, message): return "\(title) \(message)"
        case let .unknownError(title, message): return "\(title) \(message)"

        case let .error(title, _): return "error \(title)"
        }
    }
}

struct MigrateFromAnotherDevice: View {
    @EnvironmentObject var m: ChatModel
    @Environment(\.dismiss) var dismiss: DismissAction
    @State private var migrationState: MigrationState = .pasteOrScanLink(link: "")
    @State private var useKeychain = storeDBPassphraseGroupDefault.get()
    @State private var alert: MigrateFromAnotherDeviceViewAlert?
    private let tempDatabaseUrl = urlForTemporaryDatabase()
    @State private var chatReceiver: MigrationChatReceiver? = nil
    @State private var backDisabled: Bool = false
    @State private var showQRCodeScanner: Bool = true

    var body: some View {
        VStack {
            switch migrationState {
            case let .pasteOrScanLink(link):
                pasteOrScanLinkView(link)
            case let .linkDownloading(link):
                linkDownloadingView(link)
            case let .downloadProgress(downloaded, total, _, link, archivePath, _):
                downloadProgressView(downloaded, totalBytes: total, link, archivePath)
            case let .downloadFailed(total, link, archivePath):
                downloadFailedView(totalBytes: total, link, archivePath)
            case let .archiveImport(archivePath):
                archiveImportView(archivePath)
            case let .archiveImportFailed(archivePath):
                archiveImportFailedView(archivePath)
            case let .passphraseEntering(passphrase):
                PassphraseEnteringView(migrationState: $migrationState, currentKey: passphrase, alert: $alert)
            case let .migration(passphrase):
                migrationView(passphrase)
            }
        }
        .modifier(BackButton(label: "Back") {
            if !backDisabled {
                dismiss()
            }
        })
        .onChange(of: migrationState) { state in
            backDisabled = switch migrationState {
            case .passphraseEntering: true
            case .migration: true
            default: false
            }
        }
        .onDisappear {
            Task {
                if case let .downloadProgress(_, _, fileId, _, _, ctrl) = migrationState, let ctrl {
                    await stopArchiveDownloading(fileId, ctrl)
                }
                chatReceiver?.stop()
                try? FileManager.default.removeItem(atPath: "\(tempDatabaseUrl.path)_chat.db")
                try? FileManager.default.removeItem(atPath: "\(tempDatabaseUrl.path)_agent.db")
                try? FileManager.default.removeItem(at: getMigrationTempFilesDirectory())
            }
        }
        .alert(item: $alert) { alert in
            switch alert {
            case let .chatImportedWithErrors(title, text): 
                return Alert(title: Text(title), message: Text(text))
            case let .wrongPassphrase(title, message):
                return Alert(title: Text(title), message: Text(message))
            case let .invalidConfirmation(title):
                return Alert(title: Text(title))
            case let .keychainError(title):
                return Alert(title: Text(title))
            case let .databaseError(title, message):
                return Alert(title: Text(title), message: Text(message))
            case let .unknownError(title, message):
                return Alert(title: Text(title), message: Text(message))
            case let .error(title, error):
                return Alert(title: Text(title), message: Text(error))
            }
        }
        .interactiveDismissDisabled(backDisabled)
    }

    private func pasteOrScanLinkView(_ link: String) -> some View {
        ZStack {
            List {
                Section("Paste link to an archive") {
                    pasteLinkView()
                }
                Section("Or scan QR code") {
                    ScannerInView(showQRCodeScanner: $showQRCodeScanner) { resp in
                        switch resp {
                        case let .success(r):
                            let link = r.string
                            if strHasSimplexFileLink(link.trimmingCharacters(in: .whitespaces)) {
                                migrationState = .linkDownloading(link: link.trimmingCharacters(in: .whitespaces))
                            } else {
                                alert = .error(title: "Invalid link", error: "The text you pasted is not a SimpleX link.")
                            }
                        case let .failure(e):
                            logger.error("processQRCode QR code error: \(e.localizedDescription)")
                            alert = .error(title: "Invalid link", error: "The text you pasted is not a SimpleX link.")
                        }
                    }
                }
            }
        }
    }

    private func pasteLinkView() -> some View {
        Button {
            if let str = UIPasteboard.general.string {
                if strHasSimplexFileLink(str.trimmingCharacters(in: .whitespaces)) {
                    migrationState = .linkDownloading(link: str.trimmingCharacters(in: .whitespaces))
                } else {
                    alert = .error(title: "Invalid link", error: "The text you pasted is not a SimpleX link.")
                }
            }
        } label: {
            Text("Tap to paste link")
        }
        .disabled(!ChatModel.shared.pasteboardHasStrings)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func linkDownloadingView(_ link: String) -> some View {
        ZStack {
            List {
                Section {} header: {
                    Text("Downloading link details…")
                }
            }
            progressView()
        }
        .onAppear {
            downloadLinkDetails(link)
        }
    }

    private func downloadProgressView(_ downloadedBytes: Int64, totalBytes: Int64, _ link: String, _ archivePath: URL) -> some View {
        ZStack {
            List {
                Section {} header: {
                    Text("Downloading archive…")
                }
            }
            let ratio = Float(downloadedBytes) / Float(totalBytes)
            largeProgressView(ratio, "\(Int(ratio * 100))%", "\(ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .binary)) downloaded")
        }
    }

    private func downloadFailedView(totalBytes: Int64, _ link: String, _ archivePath: URL) -> some View {
        List {
            Section {
                Button(action: {
                    migrationState = .downloadProgress(downloadedBytes: 0, totalBytes: totalBytes, fileId: 0, link: link, archivePath: archivePath, ctrl: nil)
                }) {
                    settingsRow("tray.and.arrow.down") {
                        Text("Repeat download").foregroundColor(.accentColor)
                    }
                }
            } header: {
                Text("Download failed")
            } footer: {
                Text("You can give another try")
                    .font(.callout)
            }
        }
        .onAppear {
            chatReceiver?.stop()
            try? FileManager.default.removeItem(atPath: "\(tempDatabaseUrl.path)_chat.db")
            try? FileManager.default.removeItem(atPath: "\(tempDatabaseUrl.path)_agent.db")
        }
    }

    private func archiveImportView(_ archivePath: String) -> some View {
        ZStack {
            List {
                Section {} header: {
                    Text("Importing archive…")
                }
            }
            progressView()
        }
        .onAppear {
            importArchive(archivePath)
        }
    }

    private func archiveImportFailedView(_ archivePath: String) -> some View {
        List {
            Section {
                Button(action: {
                    migrationState = .archiveImport(archivePath: archivePath)
                }) {
                    settingsRow("square.and.arrow.down") {
                        Text("Repeat import").foregroundColor(.accentColor)
                    }
                }
            } header: {
                Text("Import failed")
            } footer: {
                Text("You can give another try")
                    .font(.callout)
            }
        }
    }

    private func migrationView(_ passphrase: String) -> some View {
        ZStack {
            List {
                Section {} header: {
                    Text("Migrating…")
                }
            }
            progressView()
        }
        .onAppear {
            startChat(passphrase)
        }
    }

    private func largeProgressView(_ value: Float, _ title: String, _ description: LocalizedStringKey) -> some View {
        ZStack {
            VStack {
                Text(description)
                    .font(.title3)
                    .hidden()

                Text(title)
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text(description)
                    .font(.title3)
            }

            Circle()
                .trim(from: 0, to: CGFloat(value))
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 30)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear, value: value)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
    }

    private func downloadLinkDetails(_ link: String) {
        let archiveTime = Date.now
        let ts = archiveTime.ISO8601Format(Date.ISO8601FormatStyle(timeSeparator: .omitted))
        let archiveName = "simplex-chat.\(ts).zip"
        let archivePath = getMigrationTempFilesDirectory().appendingPathComponent(archiveName)

        startDownloading(0, link, archivePath)
    }

    private func initTemporaryDatabase() -> (chat_ctrl, User)? {
        let (status, ctrl) = chatInitTemporaryDatabase(url: tempDatabaseUrl)
        showErrorOnMigrationIfNeeded(status, $alert)
        do {
            if let ctrl, let user = try startChatWithTemporaryDatabase(ctrl: ctrl) {
                return (ctrl, user)
            }
        } catch let error {
            logger.error("Error while starting chat in temporary database: \(error.localizedDescription)")
        }
        return nil
    }

    private func startDownloading(_ totalBytes: Int64, _ link: String, _ archivePath: URL) {
        Task {
            guard let ctrlAndUser = initTemporaryDatabase() else {
                return migrationState = .downloadFailed(totalBytes: totalBytes, link: link, archivePath: archivePath)
            }
            let (ctrl, user) = ctrlAndUser
            chatReceiver = MigrationChatReceiver(ctrl: ctrl) { msg in
                Task {
                    await TerminalItems.shared.add(.resp(.now, msg))
                }
                logger.debug("processReceivedMsg: \(msg.responseType)")
                await MainActor.run {
                    switch msg {
                    case let .rcvFileProgressXFTP(_, _, receivedSize, totalSize, rcvFileTransfer):
                        migrationState = .downloadProgress(downloadedBytes: receivedSize, totalBytes: totalSize, fileId: rcvFileTransfer.fileId, link: link, archivePath: archivePath, ctrl: ctrl)
                    case .rcvStandaloneFileComplete:
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            migrationState = .archiveImport(archivePath: archivePath.path)
                        }
                    default:
                        logger.debug("unsupported event: \(msg.responseType)")
                    }
                }
            }
            chatReceiver?.start()

            let (res, error) = await downloadStandaloneFile(user: user, url: link, file: CryptoFile.plain(archivePath.lastPathComponent), ctrl: ctrl)
            if res == nil {
                migrationState = .downloadFailed(totalBytes: totalBytes, link: link, archivePath: archivePath)
                return alert = .error(title: "Error downloading the archive", error: error ?? "")
            }
        }
    }

    private func importArchive(_ archivePath: String) {
        Task {
            do {
                try await apiDeleteStorage()
                do {
                    let config = ArchiveConfig(archivePath: archivePath)
                    let archiveErrors = try await apiImportArchive(config: config)
                    if !archiveErrors.isEmpty {
                        alert = .chatImportedWithErrors()
                    }
                    migrationState = .passphraseEntering(passphrase: "")
                } catch let error {
                    await MainActor.run {
                        migrationState = .archiveImportFailed(archivePath: archivePath)
                    }
                    alert = .error(title: "Error importing chat database", error: responseError(error))
                }
            } catch let error {
                await MainActor.run {
                    migrationState = .archiveImportFailed(archivePath: archivePath)
                }
                alert = .error(title: "Error deleting chat database", error: responseError(error))
            }
        }
    }


    private func stopArchiveDownloading(_ fileId: Int64, _ ctrl: chat_ctrl) async {
        _ = await apiCancelFile(fileId: fileId, ctrl: ctrl)
    }

    private func cancelMigration(_ fileId: Int64, _ ctrl: chat_ctrl) {
        Task {
            await stopArchiveDownloading(fileId, ctrl)
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func startChat(_ passphrase: String) {
        _ = kcDatabasePassword.set(passphrase)
        storeDBPassphraseGroupDefault.set(true)
        initialRandomDBPassphraseGroupDefault.set(false)
        AppChatState.shared.set(.active)
        Task {
            do {
//                resetChatCtrl()
                try initializeChat(start: true, confirmStart: false, dbKey: passphrase, refreshInvitations: true)
                let appSettings = try apiGetAppSettings(settings: AppSettings.current)
                await MainActor.run {
                    appSettings.importIntoApp()
                    hideView()
                    AlertManager.shared.showAlertMsg(title: "Chat migrated!", message: "Notify another device")
                }
            } catch let error {
                hideView()
                AlertManager.shared.showAlert(Alert(title: Text("Error starting chat"), message: Text(responseError(error))))
            }
        }
    }

    private func hideView() {
        onboardingStageDefault.set(.onboardingComplete)
        m.onboardingStage = .onboardingComplete
        dismiss()
    }

    private func strHasSimplexFileLink(_ text: String) -> Bool {
        text.starts(with: "simplex:/file") || text.starts(with: "https://simplex.chat/file")
    }

    private static func urlForTemporaryDatabase() -> URL {
        URL(fileURLWithPath: generateNewFileName(getMigrationTempFilesDirectory().path + "/" + "migration", "db", fullPath: true))
    }
}

private struct PassphraseEnteringView: View {
    @Binding var migrationState: MigrationState
    @State private var useKeychain = storeDBPassphraseGroupDefault.get()
    @State var currentKey: String
    @State private var verifyingPassphrase: Bool = false
    @Binding var alert: MigrateFromAnotherDeviceViewAlert?

    var body: some View {
        ZStack {
            List {
                Section {
                    PassphraseField(key: $currentKey, placeholder: "Current passphrase…", valid: validKey(currentKey))
                    Button(action: {
                        verifyingPassphrase = true
                        hideKeyboard()
                        Task {
                            let (status, ctrl) = chatInitTemporaryDatabase(url: getAppDatabasePath(), key: currentKey)
                            let success = switch status {
                            case .ok, .invalidConfirmation: true
                            default: false
                            }
                            if success {
//                                if let ctrl {
//                                    chat_close_store(ctrl)
//                                }
                                applyChatCtrl(ctrl: ctrl, result: (currentKey != "", status))
                                migrationState = .migration(passphrase: currentKey)
                            } else {
                                showErrorOnMigrationIfNeeded(status, $alert)
                            }
                            verifyingPassphrase = false
                        }
                    }) {
                        settingsRow("key", color: .secondary) {
                            Text("Open chat")
                        }
                    }
                } header: {
                    Text("Enter passphrase")
                } footer: {
                    Text("Passphrase will be stored on device in Keychain. It's required for notifications to work. You can change it later in settings")
                        .font(.callout)
                }
            }
            if verifyingPassphrase {
                progressView()
            }
        }
    }
}

private func showErrorOnMigrationIfNeeded(_ status: DBMigrationResult, _ alert: Binding<MigrateFromAnotherDeviceViewAlert?>) {
    switch status {
    case .invalidConfirmation:
        alert.wrappedValue = .invalidConfirmation()
    case .errorNotADatabase:
        alert.wrappedValue = .wrongPassphrase()
    case .errorKeychain:
        alert.wrappedValue = .keychainError()
    case let .errorSQL(_, error):
        alert.wrappedValue = .databaseError(message: error)
    case let .unknown(error):
        alert.wrappedValue = .unknownError(message: error)
    case .errorMigration: ()
    case .ok: ()
    }
}

private func progressView() -> some View {
    VStack {
        ProgressView().scaleEffect(2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity )
}

private class MigrationChatReceiver {
    let ctrl: chat_ctrl
    let processReceivedMsg: (ChatResponse) async -> Void
    private var receiveLoop: Task<Void, Never>?
    private var receiveMessages = true

    init(ctrl: chat_ctrl, _ processReceivedMsg: @escaping (ChatResponse) async -> Void) {
        self.ctrl = ctrl
        self.processReceivedMsg = processReceivedMsg
    }

    func start() {
        logger.debug("MigrationChatReceiver.start")
        receiveMessages = true
        if receiveLoop != nil { return }
        receiveLoop = Task { await receiveMsgLoop() }
    }

    func receiveMsgLoop() async {
        // TODO use function that has timeout
        if let msg = await chatRecvMsg(ctrl) {
            await processReceivedMsg(msg)
        }
        if self.receiveMessages {
            _ = try? await Task.sleep(nanoseconds: 7_500_000)
            await receiveMsgLoop()
        }
    }

    func stop() {
        logger.debug("MigrationChatReceiver.stop")
        receiveMessages = false
        receiveLoop?.cancel()
        receiveLoop = nil
        chat_close_store(ctrl)
    }
}

struct MigrateFromAnotherDevice_Previews: PreviewProvider {
    static var previews: some View {
        MigrateFromAnotherDevice()
    }
}
