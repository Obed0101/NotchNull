import SwiftUI

/// Ten cells, each representing ten percentage points. Partial cells preserve exact usage.
struct UsageCellBar: View {
    let percent: Double
    let tint: Color
    let marker: Double?

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let cellWidth = max(0, (proxy.size.width - 9 * gap) / 10)
            HStack(spacing: gap) {
                ForEach(0..<10) { index in
                    let fraction = max(0, min(1, percent / 10 - Double(index)))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Palette.track)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(tint).frame(width: cellWidth * fraction)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            if let marker {
                Rectangle().fill(Theme.Palette.textPrimary)
                    .frame(width: 1.5, height: 12)
                    .offset(x: max(0, min(proxy.size.width - 1.5, proxy.size.width * marker - 0.75)), y: -2)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
