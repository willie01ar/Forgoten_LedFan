import SwiftUI

/// Plots one revolution in polar coordinates — what the spinning arm would paint in the air.
/// Static on purpose: the still image is what the eye sees once the fan spins. The faint
/// ring is the LED band; columns without light stay dark within it.
struct FanSimulatorView: View {
    let frame: POVFrame
    let accessibilityDescription: String
    /// "scrolling" or "still", so assistive technology and tests can tell motion from rest.
    var motionDescription: String = "still"

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let hubRadius = size.width * Layout.simulatorHubRatio
            let tipRadius = size.width * Layout.simulatorTipRatio

            context.fill(Self.band(centre: centre, inner: hubRadius, outer: tipRadius),
                         with: .color(Palette.unlitLED), style: FillStyle(eoFill: true))

            let ledsPerArm = frame.geometry.ledsPerArm
            guard ledsPerArm > 0, !frame.columns.isEmpty else { return }

            for (index, column) in frame.columns.enumerated() where column != 0 {
                let angle = 2 * .pi * Double(index) / Double(frame.columns.count) - .pi / 2
                for led in 0..<ledsPerArm where column & (1 << UInt16(led)) != 0 {
                    let progress = Double(led) / Double(max(1, ledsPerArm - 1))
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
        .accessibilityLabel(motionDescription == "scrolling" ? "\(accessibilityDescription), scrolling" : accessibilityDescription)
    }

    private static func band(centre: CGPoint, inner: CGFloat, outer: CGFloat) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: centre.x - outer, y: centre.y - outer, width: outer * 2, height: outer * 2))
        path.addEllipse(in: CGRect(x: centre.x - inner, y: centre.y - inner, width: inner * 2, height: inner * 2))
        return path
    }
}

#Preview {
    let strip = ColumnRasterizer().strip(for: "HELLO", ledsPerArm: 11)
    FanSimulatorView(
        frame: RevolutionComposer().frame(from: strip, geometry: .preview, columnOffset: -strip.columns.count / 2),
        accessibilityDescription: "Fan preview showing HELLO"
    )
    .padding()
}
