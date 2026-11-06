import SwiftUI

struct MobileAboutInformation: View {
    enum Topic: String {
        case help = "Ayuda", privacy = "Privacidad", licenses = "Licencias"
    }
    let topic: Topic
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch topic {
                case .help:
                    section("Conecta tu Mac", "En LeonardoMD activa el servicio para compartir. En Little Leonardo pulsa Conectar, escanea el QR o introduce IP y puerto. Comprueba el código en ambos equipos y autoriza los proyectos desde el Mac.")
                    section("Consulta sin conexión", "Abre un proyecto y después un documento. La lectura y la vista de texto no modifican el original. Las copias descargadas están disponibles sin conexión. La sincronización automática solo funciona mientras la app está activa.")
                    section("Dibuja una rúbrica", "Acepta la solicitud del Mac. Gira a horizontal para ampliar el lienzo o pulsa Ampliar lienzo. Al volver a vertical recuperas la página y el dibujo. Deshacer, Limpiar y Vista previa no envían nada; Enviar rúbrica requiere tu acción explícita.")
                case .privacy:
                    section("Datos en este dispositivo", "Los documentos descargados y los borradores de rúbrica se guardan localmente. Las credenciales de conexión se conservan en el llavero del dispositivo.")
                    section("Intercambio con tu Mac", "El Mac autoriza los proyectos que puedes consultar. Solo se envía la rúbrica al pulsar Enviar rúbrica. La cámara se utiliza para leer el QR de conexión cuando autorizas su uso.")
                    section("Acceso retirado", "Cuando el dispositivo vuelve a contactar con un Mac que ha retirado su autorización, se bloquea el acceso y se elimina la copia autorizada. Sin conexión no se puede garantizar la eliminación inmediata.")
                case .licenses:
                    Text(license("LICENSE.txt")).textSelection(.enabled)
                    Divider()
                    Text(license("THIRD_PARTY_NOTICES.txt")).textSelection(.enabled)
                    ForEach(licenseFiles, id: \.self) { name in
                        NavigationLink(name) {
                            ScrollView { Text(license("licenses/" + name)).textSelection(.enabled).padding(24) }
                                .classicSurface().navigationTitle(name).navigationBarTitleDisplayMode(.inline)
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.classicSurface().navigationTitle(topic.rawValue).navigationBarTitleDisplayMode(.inline)
    }
    private func section(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold()).foregroundStyle(MobileClassic.heading)
            Text(content)
        }
    }
    private func license(_ name: String) -> String {
        guard let root = Bundle.main.resourceURL else { return "Recurso no disponible" }
        return (try? String(contentsOf: root.appendingPathComponent("Legal/" + name), encoding: .utf8))
            ?? "Recurso no disponible"
    }
    private var licenseFiles: [String] {
        guard let root = Bundle.main.resourceURL else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Legal/licenses").path)) ?? [])
            .filter { $0.hasSuffix(".txt") }.sorted()
    }
}
