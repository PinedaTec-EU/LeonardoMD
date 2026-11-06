import SwiftUI
import LeonardoCore

struct MobileRubricInkTools: View {
    @Binding var color: String
    @Binding var width: Double
    @Binding var style: LeonardoInkStyle
    let enabled: Bool
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { selectors; thickness }
            VStack(alignment: .leading) { selectors; thickness }
        }.disabled(!enabled)
    }
    private var selectors: some View {
        HStack {
            Picker("Color", selection: $color) {
                Text("Negro").tag("#111111")
                Text("Azul").tag("#1C5D99")
                Text("Rojo").tag("#A52A2A")
            }.pickerStyle(.menu)
            Picker("Trazo", selection: $style) {
                Text("Sólido").tag(LeonardoInkStyle.solid)
                Text("Pincel").tag(LeonardoInkStyle.brush)
            }.pickerStyle(.menu)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var thickness: some View {
        HStack(spacing: 8) {
            Slider(value: $width, in: 0.5...12, step: 0.5)
                .frame(minWidth: 80, maxWidth: 140).accessibilityLabel("Ancho del trazo")
            Text(width, format: .number.precision(.fractionLength(1)))
                .monospacedDigit().frame(width: 34)
        }
    }
}
