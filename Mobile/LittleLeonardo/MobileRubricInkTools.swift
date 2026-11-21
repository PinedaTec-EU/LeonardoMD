import SwiftUI
import LeonardoCore

struct MobileRubricInkTools: View {
    @Binding var color: String
    @Binding var width: Double
    @Binding var style: LeonardoInkStyle
    let enabled: Bool
    var spanish = MobileErrorNotice.isSpanishLanguage(Locale.preferredLanguages.first)
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { selectors; thickness }
            VStack(alignment: .leading) { selectors; thickness }
        }.disabled(!enabled)
    }
    private var selectors: some View {
        HStack {
            Picker("Color", selection: $color) {
                Text(spanish ? "Negro" : "Black").tag("#111111")
                Text(spanish ? "Azul" : "Blue").tag("#1C5D99")
                Text(spanish ? "Rojo" : "Red").tag("#A52A2A")
            }.pickerStyle(.menu)
            Picker(spanish ? "Trazo" : "Stroke", selection: $style) {
                Text(spanish ? "Sólido" : "Solid").tag(LeonardoInkStyle.solid)
                Text(spanish ? "Pincel" : "Brush").tag(LeonardoInkStyle.brush)
            }.pickerStyle(.menu)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var thickness: some View {
        HStack(spacing: 8) {
            Slider(value: $width, in: 0.5...12, step: 0.5)
                .frame(minWidth: 80, maxWidth: 140)
                .accessibilityLabel(spanish ? "Ancho del trazo" : "Stroke width")
            Text(width, format: .number.precision(.fractionLength(1)))
                .monospacedDigit().frame(width: 34)
        }
    }
}
