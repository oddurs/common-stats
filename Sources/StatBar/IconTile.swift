import StatKit
import SwiftUI

/// A System Settings–style icon: a white glyph on a tinted rounded square.
/// Shared by Settings and the dropdown so each metric keeps one identity.
struct IconTile: View {
    let metric: Metric
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: metric.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Color(nsColor: metric.tint).gradient,
                in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
