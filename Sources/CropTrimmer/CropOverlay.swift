import SwiftUI
import CropTrimmerCore

/// All gestures use upright source pixels; the parent supplies the fitted image bounds.
struct CropOverlay: View {
    @Binding var crop: PixelRect
    let aspect: CropAspectRatio
    let sourceWidth: Int
    let sourceHeight: Int
    @State private var dragOrigin: PixelRect?
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geometry in
            let sx = geometry.size.width / CGFloat(sourceWidth)
            let sy = geometry.size.height / CGFloat(sourceHeight)
            let rect = CGRect(x: CGFloat(crop.x) * sx, y: CGFloat(crop.y) * sy, width: CGFloat(crop.width) * sx, height: CGFloat(crop.height) * sy)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRect(rect)
                }.fill(.black.opacity(0.6), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .overlay(Rectangle().stroke(focused ? Color.accentColor : .white, lineWidth: 1.5))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                    .gesture(DragGesture().onChanged { value in
                        focused = true
                        let origin = dragOrigin ?? crop
                        dragOrigin = origin
                        crop = PixelRect(x: origin.x + Int(value.translation.width / sx), y: origin.y + Int(value.translation.height / sy), width: origin.width, height: origin.height).constrained(toWidth: sourceWidth, height: sourceHeight)
                    }.onEnded { _ in dragOrigin = nil })
                ForEach(0..<4) { corner in
                    RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 10, height: 10)
                        .padding(8).contentShape(Rectangle())
                        .position(x: corner % 2 == 0 ? rect.minX : rect.maxX, y: corner < 2 ? rect.minY : rect.maxY)
                        .gesture(DragGesture().onChanged { value in
                            let origin = dragOrigin ?? crop
                            dragOrigin = origin
                            let dx = Int(value.translation.width / sx)
                            let dy = Int(value.translation.height / sy)
                            crop = CropGeometry.resized(origin, aspect: aspect, corner: corner, dx: dx, dy: dy,
                                                        sourceWidth: sourceWidth, sourceHeight: sourceHeight)
                        }.onEnded { _ in dragOrigin = nil })
                        .accessibilityLabel("Crop corner \(corner + 1)")
                }
            }
            .focusable().focused($focused)
            .onMoveCommand { direction in
                var next = crop
                if NSEvent.modifierFlags.contains(.shift) {
                    switch direction {
                    case .left: next = CropGeometry.dimension(crop, width: crop.width - 2, aspect: aspect, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
                    case .right: next = CropGeometry.dimension(crop, width: crop.width + 2, aspect: aspect, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
                    case .up: next = CropGeometry.dimension(crop, height: crop.height - 2, aspect: aspect, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
                    case .down: next = CropGeometry.dimension(crop, height: crop.height + 2, aspect: aspect, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
                    @unknown default: break
                    }
                } else {
                switch direction { case .left: next.x -= 2; case .right: next.x += 2; case .up: next.y -= 2; case .down: next.y += 2; @unknown default: break }
                }
                crop = next.constrained(toWidth: sourceWidth, height: sourceHeight)
            }
            .accessibilityLabel("Crop rectangle")
            .accessibilityValue("X \(crop.x), Y \(crop.y), width \(crop.width), height \(crop.height) pixels")
            .help("Drag to move; drag corners to resize. Focus and use arrow keys to move by 2 pixels; Shift-arrow resizes. Locked ratios are preserved with even-pixel rounding.")
        }
    }
}
