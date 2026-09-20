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

    // Corner brackets sit on the frame like Photos': a short arm along each edge,
    // thick enough to read against any footage.
    private static let bracketArm: CGFloat = 22
    private static let bracketThickness: CGFloat = 3
    private static let edgeArm: CGFloat = 28
    private static let grabPadding: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let sx = geometry.size.width / CGFloat(sourceWidth)
            let sy = geometry.size.height / CGFloat(sourceHeight)
            let rect = CGRect(x: CGFloat(crop.x) * sx, y: CGFloat(crop.y) * sy, width: CGFloat(crop.width) * sx, height: CGFloat(crop.height) * sy)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRect(rect)
                }.fill(.black.opacity(0.55), style: FillStyle(eoFill: true)).allowsHitTesting(false)

                thirdsGrid(rect: rect).allowsHitTesting(false)

                Rectangle().fill(.clear).contentShape(Rectangle())
                    .overlay(Rectangle().stroke(focused ? Color.accentColor : .white.opacity(0.9), lineWidth: 1))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                    .gesture(DragGesture().onChanged { value in
                        focused = true
                        let origin = dragOrigin ?? crop
                        dragOrigin = origin
                        crop = PixelRect(x: origin.x + Int(value.translation.width / sx), y: origin.y + Int(value.translation.height / sy), width: origin.width, height: origin.height).constrained(toWidth: sourceWidth, height: sourceHeight)
                    }.onEnded { _ in dragOrigin = nil })

                ForEach(0..<4) { corner in
                    let left = corner % 2 == 0, top = corner < 2
                    cornerBracket(left: left, top: top)
                        .padding(Self.grabPadding).contentShape(Rectangle())
                        .position(x: left ? rect.minX : rect.maxX, y: top ? rect.minY : rect.maxY)
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

                ForEach(Edge.allCases, id: \.self) { edge in
                    edgeHandle(edge)
                        .padding(Self.grabPadding).contentShape(Rectangle())
                        .position(x: edge.x(in: rect), y: edge.y(in: rect))
                        .gesture(DragGesture().onChanged { value in
                            let origin = dragOrigin ?? crop
                            dragOrigin = origin
                            crop = edge.resized(origin, aspect: aspect,
                                                dx: Int(value.translation.width / sx),
                                                dy: Int(value.translation.height / sy),
                                                sourceWidth: sourceWidth, sourceHeight: sourceHeight)
                        }.onEnded { _ in dragOrigin = nil })
                        .accessibilityLabel("Crop \(edge.label) edge")
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
            .help("Drag to move; drag corners or edges to resize. Focus and use arrow keys to move by 2 pixels; Shift-arrow resizes. Locked ratios are preserved with even-pixel rounding.")
        }
    }

    private func thirdsGrid(rect: CGRect) -> some View {
        Path { path in
            for step in 1...2 {
                let fraction = CGFloat(step) / 3
                let x = rect.minX + rect.width * fraction
                let y = rect.minY + rect.height * fraction
                path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }.stroke(.white.opacity(0.35), lineWidth: 0.5)
    }

    private func cornerBracket(left: Bool, top: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white)
                .frame(width: Self.bracketArm, height: Self.bracketThickness)
                .offset(x: left ? 0 : -(Self.bracketArm - Self.bracketThickness), y: 0)
            Rectangle().fill(.white)
                .frame(width: Self.bracketThickness, height: Self.bracketArm)
                .offset(x: 0, y: top ? 0 : -(Self.bracketArm - Self.bracketThickness))
        }
        .frame(width: Self.bracketArm, height: Self.bracketArm, alignment: top ? .topLeading : .bottomLeading)
        .shadow(color: .black.opacity(0.5), radius: 1)
    }

    private func edgeHandle(_ edge: Edge) -> some View {
        let horizontal = edge == .top || edge == .bottom
        return RoundedRectangle(cornerRadius: Self.bracketThickness / 2).fill(.white)
            .frame(width: horizontal ? Self.edgeArm : Self.bracketThickness,
                   height: horizontal ? Self.bracketThickness : Self.edgeArm)
            .shadow(color: .black.opacity(0.5), radius: 1)
    }

    /// One side of the crop. Dragging a side moves only that side when the ratio is
    /// free; a locked ratio resizes both dimensions from the same anchor.
    fileprivate enum Edge: CaseIterable {
        case top, bottom, left, right

        var label: String {
            switch self {
            case .top: return "top"; case .bottom: return "bottom"
            case .left: return "left"; case .right: return "right"
            }
        }

        func x(in rect: CGRect) -> CGFloat {
            switch self {
            case .top, .bottom: return rect.midX
            case .left: return rect.minX
            case .right: return rect.maxX
            }
        }

        func y(in rect: CGRect) -> CGFloat {
            switch self {
            case .left, .right: return rect.midY
            case .top: return rect.minY
            case .bottom: return rect.maxY
            }
        }

        /// The corner index that shares this edge's anchor, so a locked ratio resizes
        /// the same way a corner drag would.
        private var equivalentCorner: Int {
            switch self {
            case .top, .left: return 0
            case .bottom, .right: return 3
            }
        }

        func resized(_ rect: PixelRect, aspect: CropAspectRatio, dx: Int, dy: Int,
                     sourceWidth: Int, sourceHeight: Int) -> PixelRect {
            guard aspect.value(sourceWidth: sourceWidth, sourceHeight: sourceHeight) == nil else {
                return CropGeometry.resized(rect, aspect: aspect, corner: equivalentCorner,
                                            dx: self == .left || self == .right ? dx : 0,
                                            dy: self == .top || self == .bottom ? dy : 0,
                                            sourceWidth: sourceWidth, sourceHeight: sourceHeight)
            }
            var next = rect
            switch self {
            case .top:
                let bottom = rect.y + rect.height
                next.y = rect.y + dy; next.height = bottom - next.y
            case .bottom:
                next.height = rect.height + dy
            case .left:
                let right = rect.x + rect.width
                next.x = rect.x + dx; next.width = right - next.x
            case .right:
                next.width = rect.width + dx
            }
            next.width = max(2, next.width); next.height = max(2, next.height)
            next.x = max(0, next.x); next.y = max(0, next.y)
            return next.constrained(toWidth: sourceWidth, height: sourceHeight)
        }
    }
}
