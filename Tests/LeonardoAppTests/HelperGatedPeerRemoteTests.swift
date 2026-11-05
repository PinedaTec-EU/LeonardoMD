import Foundation
import XCTest
import LeonardoSync
@testable import LeonardoApp

final class HelperGatedPeerRemoteTests: XCTestCase {
    func testDisabledHelperPreventsNetworkProbe() async throws {
        let state = GateProbeState(online: false)
        let remote = HelperGatedPeerRemote(remote: GateProbeRemote(state: state), requireOnline: { try await state.check() })
        do { _ = try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!); XCTFail("Disabled helper must deny networking") }
        catch GateProbeError.offline {}
        let calls = await state.calls
        XCTAssertEqual(calls, 0)
    }
    func testDisabledDuringNetworkOperationRejectsItsResult() async throws {
        let state = GateProbeState(online: true, disableDuringProbe: true)
        let remote = HelperGatedPeerRemote(remote: GateProbeRemote(state: state), requireOnline: { try await state.check() })
        do { _ = try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!); XCTFail("A result must not bypass a disabled helper") }
        catch GateProbeError.offline {}
        let calls = await state.calls
        XCTAssertEqual(calls, 1)
    }
    func testRunningHelperAllowsNetworkProbe() async throws {
        let state = GateProbeState(online: true)
        let remote = HelperGatedPeerRemote(remote: GateProbeRemote(state: state), requireOnline: { try await state.check() })
        let result = try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!)
        XCTAssertEqual(result, Data([1]))
    }
}
private enum GateProbeError: Error { case offline, unused }
private actor GateProbeState {
    var online: Bool
    let disableDuringProbe: Bool
    private(set) var calls = 0
    init(online: Bool, disableDuringProbe: Bool = false) { self.online = online; self.disableDuringProbe = disableDuringProbe }
    func check() throws { guard online else { throw GateProbeError.offline } }
    func probe() -> Data { calls += 1; if disableDuringProbe { online = false }; return Data([1]) }
}
private struct GateProbeRemote: DesktopPeerRemote {
    let state: GateProbeState
    func probe(endpoint: URL) async throws -> Data { await state.probe() }
    func begin(endpoint: URL, fingerprint: Data, invitation: PairingInvitation?, name: String, credential: String, now: Date) async throws -> PairingChallenge { throw GateProbeError.unused }
    func status(_ connection: DesktopPeerConnection, credential: String) async throws -> DirectDeviceStatus { throw GateProbeError.unused }
    func publish(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws { throw GateProbeError.unused }
    func receipt(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws -> DesktopPeerProposalReceipt? { throw GateProbeError.unused }
    func acknowledge(_ proposal: DesktopPeerProposal, receipt: DesktopPeerProposalReceipt, connection: DesktopPeerConnection, credential: String) async throws { throw GateProbeError.unused }
    func snapshot(_ descriptor: SharedProjectDescriptor, connection: DesktopPeerConnection, credential: String) async throws -> CorpusSnapshot { throw GateProbeError.unused }
}
