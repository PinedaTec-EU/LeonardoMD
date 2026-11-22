import SwiftUI
import LeonardoCore

struct MobileGuidedRubricSheet: View {
    @Binding var rubric: LeonardoRubric
    let spanish: Bool
    var profileCapture = false
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var color = "#111111"
    @State private var width = 4.0
    @State private var style = LeonardoInkStyle.solid
    @State private var limitReached = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(profileCapture
                     ? (spanish ? "Dibuja una rúbrica para reutilizar con este perfil." : "Draw a rubric to reuse with this profile.")
                     : (spanish ? "Lee el contexto y dibuja una rúbrica nueva." : "Read the context and draw a new rubric."))
                    .font(.footnote).foregroundStyle(MobileClassic.secondary)
                MobileRubricInkTools(color: $color, width: $width, style: $style, enabled: true, spanish: spanish)
                MobileRubricCanvas(rubric: $rubric, color: color, width: width, style: style,
                                   isInteractive: true, limitReached: $limitReached)
                    .aspectRatio(3, contentMode: .fit)
                    .background(MobileClassic.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if limitReached {
                    Text(spanish ? "La rúbrica supera el límite portable." : "Rubric exceeds the portable limit.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button(profileCapture ? (spanish ? "Usar rúbrica" : "Use rubric")
                       : (spanish ? "Confirmar aparición" : "Confirm occurrence"), action: confirm)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(MobileClassic.paper)
                    .disabled(!rubric.isValid || limitReached)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .classicSurface()
            .navigationTitle(spanish ? "Rúbrica" : "Rubric")
            .toolbar { Button(spanish ? "Cancelar" : "Cancel") { dismiss() } }
        }
    }
}

struct MobileSigningCredentialEnrollment: View {
    let spanish: Bool
    let onEnroll: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(spanish
                         ? "La contraseña personal cifra la clave privada antes de guardarla en el llavero."
                         : "The personal password encrypts the private key before it is stored in the keychain.")
                        .font(.footnote)
                    SecureField(spanish ? "Contraseña" : "Password", text: $password)
                    SecureField(spanish ? "Confirmar" : "Confirm", text: $confirmation)
                }
                Button(spanish ? "Inscribir" : "Enroll") { onEnroll(password) }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(MobileClassic.paper)
                    .disabled(password.count < 8 || password != confirmation)
            }
            .navigationTitle(spanish ? "Credencial" : "Credential")
            .toolbar { Button(spanish ? "Cerrar" : "Close") { dismiss() } }
        }
    }
}

struct MobileSigningPassword: View {
    let spanish: Bool
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField(spanish ? "Contraseña personal" : "Personal password", text: $password)
                Button(spanish ? "Firmar" : "Sign") { onSubmit(password) }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(MobileClassic.paper)
                    .disabled(password.isEmpty)
            }
            .navigationTitle(spanish ? "Autorizar firma" : "Authorize signature")
            .toolbar { Button(spanish ? "Cancelar" : "Cancel") { dismiss() } }
        }
    }
}
