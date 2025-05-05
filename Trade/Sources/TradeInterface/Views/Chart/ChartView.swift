import SwiftUI
import TradingStrategy

public struct ChartView: View {
    @State private var scale = Scale()
    @State private var scaleDrag: Scale? = nil
    @State private var canvasSize: CGSize = .zero
    @State private var isManuallyDisplaced: Bool = false
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    public let data: [Klines]
    public let interval: TimeInterval
    public let lastUpdate: Date
    public var scaleOriginal: Scale
    private var canvasOverlay: (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void
    private var canvasBackground: (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void
    
    private var isScaleMoved: Bool {
        scale.x != scaleOriginal.x || scale.y != scaleOriginal.y
    }
    
    private var formattedElapsedTime: String {
        let seconds = Int(now.timeIntervalSince(lastUpdate))

        switch seconds {
        case ..<60: return "\(seconds)s ago"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        case ..<604_800: return "\(seconds / 86_400)d ago"
        default:
            if seconds < 1_000_000 {
                return String(format: "%.1fk s ago", Double(seconds) / 1_000)
            } else {
                return String(format: "%.1fM s ago", Double(seconds) / 1_000_000)
            }
        }
    }
    
    public init(
        interval: TimeInterval,
        lastUpdate: Date,
        data: [Klines],
        scale: Scale,
        overlay: @escaping (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void = { _, _, _ in },
        background: @escaping (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void = { _, _, _ in }
    ) {
        self.data = data
        self.interval = interval
        self.lastUpdate = lastUpdate
        self.scaleOriginal = scale
        self.canvasOverlay = overlay
        self.canvasBackground = background
    }
    
    public var body: some View {
        ChartCanvasView(
            scale: scale,
            data: data,
            overlay: canvasOverlay,
            background: canvasBackground
        )
        .onSizeChange($canvasSize)
        .contentShape(Rectangle())
        .gesture(canvasGesture())
        .border(Color.gray, width: 1)
        .overlay(alignment: .topLeading) {
            IntervalLabelView(interval: interval, backgroundColor: Color.black.opacity(0.7))
        }
        .overlay(alignment: .topTrailing) {
            Text(formattedElapsedTime)
                .font(.caption)
                .padding(6)
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding()
        }
        .overlay(alignment: .bottomLeading) {
            resetButton
        }
        .onChange(of: data.last?.timeOpen, initial: true) {
            if !isManuallyDisplaced {
                self.scale = scaleOriginal
            }
        }
        .onChange(of: scaleOriginal) {
            guard !isManuallyDisplaced else { return }
            resetScales()
        }
        .onReceive(timer) { now = $0 }
    }
    
    @ViewBuilder
    private var resetButton: some View {
        if isScaleMoved {
            Text("Reset")
                .minimumScaleFactor(0.01)
                .lineLimit(1)
                .frame(width: 80, height: 50)
                .foregroundColor(Color.white)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.7))
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: resetScales)
                .padding()
        }
    }
    
    // MARK: – Gestures
    
    private func canvasGesture() -> some Gesture {
        DragGesture().onChanged { gesture in
            let scaleX = scaleDrag?.x ?? scaleOriginal.x
            let scaleY = scaleDrag?.y ?? scaleOriginal.y
            let barCount = scale.barCount(forLength: abs(gesture.translation.width), size: canvasSize)
            let xValueChange = gesture.translation.width > 0 ? barCount : -barCount
            let yValueChange = (gesture.translation.height / canvasSize.height) * scale.yAmplitude
            scale = Scale(
                x: (scaleX.lowerBound - xValueChange)..<(scaleX.upperBound - xValueChange),
                y: (scaleY.lowerBound + yValueChange)..<(scaleY.upperBound + yValueChange),
                candlesPerScreen: scaleOriginal.candlesPerScreen
            )
        }.onEnded { _ in
            scaleDrag = scale
            isManuallyDisplaced = true
        }
    }
    
    private func resetScales() {
        guard isScaleMoved else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            scaleDrag = scaleOriginal
            scale = scaleOriginal
            isManuallyDisplaced = false
        }
    }
    
    // MARK: Modifiers
    
    public func chartBackground(canvasOverlay: @escaping (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void) -> ChartView {
        ChartView(
            interval: interval,
            lastUpdate: lastUpdate,
            data: data,
            scale: scaleOriginal,
            overlay: canvasOverlay,
            background: canvasBackground
        )
    }
    
    public func chartOverlay(canvasBackground: @escaping (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void) -> ChartView {
        ChartView(
            interval: interval,
            lastUpdate: lastUpdate,
            data: data,
            scale: scaleOriginal,
            overlay: canvasOverlay,
            background: canvasBackground
        )
    }
}

struct ChartView_Previews: PreviewProvider {
    static var previews: some View {
        ChartView(interval: 60, lastUpdate: Date(), data: [], scale: Scale())
    }
}
