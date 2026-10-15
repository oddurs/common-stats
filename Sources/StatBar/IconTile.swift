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
            .background(metric.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension Metric {
    var tint: Color {
        switch self {
        case .cpu: .blue
        case .gpu: .purple
        case .memory: .pink
        case .network: .cyan
        case .disk: .orange
        case .storage: .gray
        case .battery: .green
        }
    }
}
