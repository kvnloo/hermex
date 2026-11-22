import SwiftUI
import UniformTypeIdentifiers

struct ForkClientCertificateView: View {
    let scope: ForkClientCertificateScope
    let isStaged: Bool
    let save: (ForkClientCertificate) throws -> Void
    let remove: () throws -> Void
    @State private var installed: Bool
    @State private var isPickingFile = false
    @State private var archive: Data?
    @State private var password = ""
    @State private var error: String?

    init(scope: ForkClientCertificateScope, staged: Bool? = nil,
         save: ((ForkClientCertificate) throws -> Void)? = nil, remove: (() throws -> Void)? = nil) {
        self.scope = scope
        isStaged = staged != nil
        self.save = save ?? { try ForkClientCertificateStore.save($0, for: scope) }
        self.remove = remove ?? { try ForkClientCertificateStore.remove(scope) }
        _installed = State(initialValue: staged ?? false)
    }

    var body: some View {
        AppForm {
            Section {
                LabeledContent("Client certificate", value: installed ? String(localized: "Installed") : String(localized: "None"))
                Button("Choose PKCS#12 File…") {
                    error = nil
                    isPickingFile = true
                }
                if archive != nil {
                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save", action: importCertificate)
                    Button("Cancel", role: .cancel, action: clearImport)
                }
                if installed {
                    Button("Remove", role: .destructive) {
                        do {
                            try remove()
                            installed = false
                            clearImport()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            } appFooter: {
                if isStaged {
                    Text("Browser sign-in does not use this certificate.")
                } else {
                    Text("Stored in Keychain for this server only.")
                }
            }
        }
        .settingsPage(String(localized: "Client certificate"))
        .task {
            guard !isStaged else { return }
            do { installed = try ForkClientCertificateStore.load(scope) != nil }
            catch { self.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [
            .pkcs12, UTType(filenameExtension: "pfx") ?? .pkcs12
        ]) { result in
            clearImport()
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let bytes = try FileHandle(forReadingFrom: url).read(upToCount: 1_048_577)
                guard let bytes, !bytes.isEmpty, bytes.count <= 1_048_576 else {
                    throw ForkClientCertificateError.invalidFile
                }
                archive = bytes
            } catch {
                self.error = String(localized: "Could not read the selected PKCS#12 file.")
            }
        }
    }

    private func clearImport() {
        archive = nil
        password = ""
        error = nil
    }

    private func importCertificate() {
        guard let archive else { return }
        do {
            try save(ForkClientCertificate(archive: archive, password: password))
            installed = true
            clearImport()
        } catch { self.error = error.localizedDescription }
    }
}
