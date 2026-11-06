import SwiftUI

struct MobileAboutView: View {
    @Environment(\.dismiss) private var dismiss
    private var installedVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { return "Desarrollo" }
        return "\(version) (\(build))"
    }
    private func informationLink(_ topic: MobileAboutInformation.Topic) -> some View {
        NavigationLink {
            MobileAboutInformation(topic: topic)
        } label: {
            HStack {
                Text(topic.rawValue)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote)
            }.padding(.vertical, 6)
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    MobileBrand()
                    VStack(spacing: 8) {
                        Text("Little Leonardo").font(.largeTitle.bold()).foregroundStyle(MobileClassic.heading)
                        Text("de PinedaTec").foregroundStyle(MobileClassic.secondary)
                    }
                    Text("Tus proyectos de LeonardoMD, disponibles sin conexión en tu iPhone y iPad.")
                        .multilineTextAlignment(.center)
                    Divider().overlay(MobileClassic.border)
                    LabeledContent("Versión", value: installedVersion)
                        .accessibilityIdentifier("about-version")
                    VStack(spacing: 0) {
                        informationLink(.help)
                        Divider().padding(.vertical, 12)
                        informationLink(.privacy)
                        Divider().padding(.vertical, 12)
                        informationLink(.licenses)
                    }
                    Label("Documentos de solo lectura", systemImage: "doc.text")
                    Label("Conexión autorizada desde tu Mac", systemImage: "lock.shield")
                    Text("Los proyectos descargados se conservan para consultarlos sin conexión. La sincronización automática funciona mientras la app está activa.")
                        .font(.callout).foregroundStyle(MobileClassic.secondary)
                    Text("Diseñado para acompañar a LeonardoMD")
                        .font(.footnote).foregroundStyle(MobileClassic.secondary)
                }.padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .classicSurface()
            .navigationTitle("Acerca de")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cerrar") { dismiss() } }
        }.tint(MobileClassic.accent)
    }
}

struct MobileStartupView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            MobileBrand(size: 112)
            Text("Little Leonardo").font(.largeTitle.bold()).foregroundStyle(MobileClassic.heading)
            Text("Tus documentos, contigo.").foregroundStyle(MobileClassic.secondary)
            ProgressView("Preparando biblioteca…").padding(.top, 20)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MobileClassic.paper).foregroundStyle(MobileClassic.ink)
            .accessibilityIdentifier("startup-splash")
    }
}
