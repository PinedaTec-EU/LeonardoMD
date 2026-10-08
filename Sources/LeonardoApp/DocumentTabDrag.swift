import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// An internal tab transfer deliberately has no file URL or text representation.
struct DocumentTabDrag: Codable, Transferable, Sendable {
    let ownerID: UUID
    let tabID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "eu.pinedatec.LeonardoMD.document-tab", conformingTo: .data))
    }
}
