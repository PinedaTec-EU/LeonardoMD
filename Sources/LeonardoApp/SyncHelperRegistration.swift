import ServiceManagement
import LeonardoDesktopSync

@MainActor
protocol SyncHelperRegistration {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
    func openApprovalSettings()
}

@MainActor
struct SystemSyncHelperRegistration: SyncHelperRegistration {
    private let service = SMAppService.agent(plistName: SyncHelperContract.plistName)
    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
}
