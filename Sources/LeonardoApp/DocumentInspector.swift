import SwiftUI
import LeonardoCore

struct DocumentInspector: View {
    @Bindable var session: AppSession
    var body: some View {
        if session.mode == .fill, session.leonardoDocument?.isForm == true {
            LeonardoFieldHelp(session: session)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.text("In this document")).font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.headings, id: \.line) { heading in
                            Button(heading.title) { session.jumpToHeading(heading.line) }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.buttonStyle(PremiumButtonStyle(compact: true)).padding(20).frame(width: 320).background(.regularMaterial)
        }
    }
}
