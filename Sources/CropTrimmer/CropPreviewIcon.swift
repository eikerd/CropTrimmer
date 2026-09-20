import SwiftUI

/// An eye inside crop marks: viewing the picture as cropped. No SF Symbol pairs
/// the two, so the marks are drawn around a symbol eye.
struct CropPreviewIcon: View {
    /// True while the monitor is zoomed to the crop.
    let active: Bool

    private let size = CGSize(width: 22, height: 16)
    private let arm: CGFloat = 5
    private let thickness: CGFloat = 1.5

    var body: some View {
        ZStack {
            Image(systemName: "eye")
                .font(.system(size: 10, weight: .regular))
            ForEach(0..<4) { corner in
                mark(left: corner % 2 == 0, top: corner < 2)
            }
        }
        .frame(width: size.width, height: size.height)
        .foregroundStyle(active ? Color.accentColor : .primary)
        .contentShape(Rectangle())
    }

    private func mark(left: Bool, top: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().frame(width: arm, height: thickness)
                .offset(x: left ? 0 : arm - thickness)
            Rectangle().frame(width: thickness, height: arm)
                .offset(y: top ? 0 : arm - thickness)
        }
        .frame(width: arm, height: arm)
        .position(x: left ? arm / 2 : size.width - arm / 2,
                  y: top ? arm / 2 : size.height - arm / 2)
    }
}
