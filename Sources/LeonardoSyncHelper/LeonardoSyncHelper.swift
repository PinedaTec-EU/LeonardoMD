import Foundation
import OSLog
import LeonardoSync
import LeonardoCore
import LeonardoDesktopSync

private final class HelperEndpoint: NSObject, SyncHelperXPC, @unchecked Sendable {
    let host: SyncHelperHost
    init(host: SyncHelperHost) { self.host = host }
    func perform(_ request: Data, withReply reply: @escaping @Sendable (Data?, Int, String?) -> Void) {
        Task {
            do {
                let command = try JSONDecoder().decode(SyncHelperCommand.self, from: request)
                reply(try await host.perform(command), SyncHelperErrorCode.none.rawValue, nil)
            } catch {
                let code: SyncHelperErrorCode = (error as? ReconciliationError) == .staleComparison ? .staleComparison : .failed
                reply(nil, code.rawValue, error.localizedDescription)
            }
        }
    }
}

private final class HelperListener: NSObject, NSXPCListenerDelegate {
    let endpoint: HelperEndpoint
    init(host: SyncHelperHost) { endpoint = HelperEndpoint(host: host) }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else { return false }
        connection.exportedInterface = NSXPCInterface(with: SyncHelperXPC.self)
        connection.exportedObject = endpoint
        connection.resume()
        return true
    }
}

@main struct LeonardoSyncHelper {
    static func main() throws {
        let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "sync-helper")
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // Prevent a second manually launched helper from opening the persistent stores.
        let lock = try ProcessFileLock(at: SyncHelperContract.preferencesURL.deletingLastPathComponent()
            .appendingPathComponent("MobileSync/helper.lock"))
        let host = SyncHelperHost()
        let delegate = HelperListener(host: host)
        let listener = NSXPCListener(machServiceName: SyncHelperContract.serviceName)
        listener.setConnectionCodeSigningRequirement(try SyncHelperSigning.requirement(for: bundle, identifier: SyncHelperContract.appIdentifier, matching: executable))
        listener.delegate = delegate
        listener.resume()
        logger.info("sync_helper_started")
        Task {
            while !Task.isCancelled {
                do { try await host.reload() } catch { logger.error("sync_helper_recovery_pending") }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        withExtendedLifetime((lock, delegate, listener)) { RunLoop.main.run() }
    }
}
