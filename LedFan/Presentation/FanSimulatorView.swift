import SwiftUI

/// Plots the frame in polar coordinates — what the spinning arm would paint in the air.
/// Static on purpose: the still image is what the eye sees once the fan spins.
struct FanSimulatorView: View {
    let frame: POVFrame
    let accessibilityDescription: String

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let hubRadius = size.width * 0.12
            let tipRadius = size.width * 0.46

            guard frame.ledsPerArm > 0, !frame.columns.isEmpty else { return }

            for (index, column) in frame.columns.enumerated() {
                let angle = 2 * .pi * Double(index) / Double(frame.columns.count) - .pi / 2
                for led in 0..<frame.ledsPerArm where column & (1 << UInt16(led)) != 0 {
                    let progress = Double(led) / Double(max(1, frame.ledsPerArm - 1))
                    let radius = hubRadius + (tipRadius - hubRadius) * progress
                    let dot = CGRect(
                        x: centre.x + radius * cos(angle) - Layout.ledDiameter / 2,
                        y: centre.y + radius * sin(angle) - Layout.ledDiameter / 2,
                        width: Layout.ledDiameter,
                        height: Layout.ledDiameter
                    )
                    context.fill(Path(ellipseIn: dot), with: .color(Palette.litLED))
                }
            }
        }
        .frame(width: Layout.simulatorSide, height: Layout.simulatorSide)
        .background(Palette.simulatorBackground, in: .circle)
        .shadow(color: Palette.simulatorShadow, radius: Layout.shadowRadius)
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription.isEmpty ? "Fan preview, empty" : "Fan preview showing \(accessibilityDescription)")
    }
}

#Preview {
    FanSimulatorView(frame: ColumnRasterizer().frame(for: "HELLO", ledsPerArm: 11), accessibilityDescription: "HELLO")
        .padding()
}
