import SwiftUI
import TradingStrategy
import Runtime

public struct ChartCanvasView: View {
    public let scale: Scale
    public let data: [Klines]
    public let patterns: [(index: Int, pattern: PricePattern)]
    public let trades: [Trade]
    
    private var lineWidth: Double = 1
    private var lineStrokeColor: Color = Color.gray.opacity(0.4)
    
    private var canvasOverlay: (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void
    private var canvasBackground: (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void
    
    public init(
        scale: Scale,
        data: [Klines],
        trades: [Trade],
        patterns: [(index: Int, pattern: PricePattern)],
        overlay: @escaping (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void = { _, _, _ in },
        background: @escaping (_ context: inout GraphicsContext, _ scale: Scale, _ frame: CGRect) -> Void = { _, _, _ in }
    ) {
        self.scale = scale
        self.data = data
        self.trades = trades
        self.patterns = patterns
        self.canvasOverlay = overlay
        self.canvasBackground = background
    }
    
    public var body: some View {
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size)
            drawScales(context: &context, frame: frame)
            canvasBackground(&context, scale, frame)
            drawCandles(context: &context, data: data, scale: scale, frame: frame)
            canvasOverlay(&context, scale, frame)
        }
        .clipped()
    }
    
    private func drawCandles(context: inout GraphicsContext, data: [Klines], scale: Scale, frame: CGRect) {
        let candleWidth = (frame.width / Double(scale.candlesPerScreen)) * 0.9
        let volumeHeight: Double = 40
        let volumeTopY = frame.maxY - volumeHeight

        let firstVisibleIndex = max(0, scale.index(forX: frame.minX, size: frame.size))
        let lastVisibleIndex = min(data.count - 1, scale.index(forX: frame.maxX, size: frame.size))
        guard firstVisibleIndex <= lastVisibleIndex else { return }

        let maxVolume = data[firstVisibleIndex...lastVisibleIndex].compactMap(\.volume).max() ?? 1.0

        for index in firstVisibleIndex...lastVisibleIndex {
            let kline = data[index]
            drawCandle(context: &context, kline: kline, index: index, frame: frame, candleWidth: candleWidth)
            drawTrades(context: &context, kline: kline, index: index, frame: frame, candleWidth: candleWidth)
            drawPatterns(
                context: &context,
                kline: kline,
                index: index,
                frame: frame,
                candleWidth: candleWidth,
                patterns: patterns
            )
            drawVolume(
                context: &context,
                maxVolume: maxVolume,
                volumeHeight: volumeHeight,
                volumeTopY: volumeTopY,
                kline: kline,
                index: index,
                frame: frame,
                candleWidth: candleWidth
            )
        }
    }
    
    private func drawPatterns(
        context: inout GraphicsContext,
        kline: Klines,
        index: Int,
        frame: CGRect,
        candleWidth: Double,
        patterns: [(index: Int, pattern: PricePattern)]
    ) {
        guard let pattern = patterns.first(where: { $0.index == index }) else { return }

        let offsetX = scale.x(index, size: frame.size)
        let isAbove = pattern.pattern == .high || pattern.pattern == .higherHigh || pattern.pattern == .lowerHigh
        let y = scale.y(isAbove ? kline.priceHigh : kline.priceLow, size: frame.size)
        let offsetY: CGFloat = isAbove ? -10 : 10

        let label = Text(pattern.pattern.rawValue)
            .font(.system(size: 10))
            .foregroundColor(.yellow)

        context.draw(
            label,
            at: CGPoint(x: offsetX, y: y + offsetY),
            anchor: .center
        )
    }
    
    private func drawVolume(
        context: inout GraphicsContext,
        maxVolume: Double,
        volumeHeight: Double,
        volumeTopY: Double,
        kline: Klines,
        index: Int,
        frame: CGRect,
        candleWidth: Double
    ) {
        // Draw volume bar
        let offsetX = scale.x(index, size: frame.size)
        let volumeRatio = Double((kline.volume ?? 0) / maxVolume)
        let barHeight = volumeRatio * volumeHeight
        let barRect = CGRect(
            x: offsetX - candleWidth / 2.0,
            y: volumeTopY + volumeHeight - barHeight,
            width: candleWidth,
            height: barHeight
        )
        let color: Color = kline.isLong ? .green.opacity(0.4) : .red.opacity(0.4)
        context.fill(Path(barRect), with: .color(color))
    }
    
    private func drawCandle(context: inout GraphicsContext, kline: Klines, index: Int, frame: CGRect, candleWidth: Double) {
        let offsetX = scale.x(index, size: frame.size)
        let highY = scale.y(kline.priceHigh, size: frame.size)
        let lowY = scale.y(kline.priceLow, size: frame.size)
        let openY = scale.y(kline.priceOpen, size: frame.size)
        let closeY = scale.y(kline.priceClose, size: frame.size)
        
        let candleColor: Color = kline.isLong ? .green : .red
        
        // Skip drawing if the candle is completely outside the frame
        if offsetX + candleWidth < frame.minX || offsetX - candleWidth > frame.maxX {
            return
        }
        
        // Wick (Vertical line)
        var wickPath = Path()
        wickPath.move(to: CGPoint(x: offsetX, y: highY))
        wickPath.addLine(to: CGPoint(x: offsetX, y: lowY))
        context.stroke(wickPath, with: .color(candleColor.opacity(0.6)), lineWidth: candleWidth * 0.2)
        // Body (Rectangle)
        let bodyRect = CGRect(
            x: offsetX - candleWidth / 2,
            y: min(openY, closeY),
            width: candleWidth,
            height: abs(openY - closeY)
        )
        
        context.fill(Path(bodyRect), with: .color(candleColor))
    }
        
    private func drawScales(context: inout GraphicsContext, frame: CGRect) {
        let yStep = scale.yGuideStep
        let xStep = scale.xGuideStep
        let textFont = Font.system(size: 10)
        let lineColor = Color.gray.opacity(0.5)
        let lineWidth: Double = 0.8

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm\ndd.MM.yy"

        var gridPath = Path()
        for i in 0...10 {
            let price = scale.y.lowerBound + (yStep * Double(i))
            let yPos = scale.y(price, size: frame.size)

            guard yPos >= frame.minY, yPos <= frame.maxY else { continue }

            gridPath.move(to: CGPoint(x: frame.minX, y: yPos))
            gridPath.addLine(to: CGPoint(x: frame.maxX, y: yPos))


            let priceString = String(format: "%.2f", price)
            let text = Text(priceString).font(textFont).foregroundColor(.gray)
            context.draw(
                text,
                at: CGPoint(x: frame.minX + 20, y: yPos - 5),
                anchor: .leading
            )
        }

        for i in stride(from: max(0, scale.x.lowerBound), to: scale.x.upperBound, by: xStep) {
            let xPos = scale.x(i, size: frame.size)

            guard xPos >= frame.minX, xPos <= frame.maxX, i < data.count else { continue }

            let date = Date(timeIntervalSince1970: data[i].timeOpen)
            let timeString = formatter.string(from: date)

            gridPath.move(to: CGPoint(x: xPos, y: frame.minY))
            gridPath.addLine(to: CGPoint(x: xPos, y: frame.maxY))

            let text = Text(timeString).font(textFont).foregroundColor(.gray)
            context.draw(
                text,
                at: CGPoint(x: xPos, y: frame.maxY),
                anchor: .bottomLeading
            )
        }

        context.stroke(gridPath, with: .color(lineColor), lineWidth: lineWidth)
    }
    
    private func drawTrades(context: inout GraphicsContext, kline: Klines, index: Int, frame: CGRect, candleWidth: Double) {
        let offsetX = scale.x(index, size: frame.size)
        
        // Skip if candle is outside horizontal bounds
        if offsetX + candleWidth < frame.minX || offsetX - candleWidth > frame.maxX {
            return
        }
        
        // Find trades for this candle
        let tradesForCandle = trades.filter { $0.entryBar.timeOpen == kline.timeOpen }
        
        for trade in tradesForCandle {
            let entryY = scale.y(trade.price, size: frame.size)
            
            // Skip if entry price is outside vertical bounds
            guard entryY >= frame.minY && entryY <= frame.maxY else { continue }
            
            // Draw entry marker (triangle)
            let markerSize: Double = candleWidth * 0.5
            var markerPath = Path()
            let isLong = trade.isLong
            if isLong {
                // Downward triangle below candle for Long
                markerPath.move(to: CGPoint(x: offsetX, y: entryY + markerSize))
                markerPath.addLine(to: CGPoint(x: offsetX - markerSize / 2, y: entryY + markerSize * 2))
                markerPath.addLine(to: CGPoint(x: offsetX + markerSize / 2, y: entryY + markerSize * 2))
                markerPath.closeSubpath()
            } else {
                // Upward triangle above candle for Short
                markerPath.move(to: CGPoint(x: offsetX, y: entryY - markerSize))
                markerPath.addLine(to: CGPoint(x: offsetX - markerSize / 2, y: entryY - markerSize * 2))
                markerPath.addLine(to: CGPoint(x: offsetX + markerSize / 2, y: entryY - markerSize * 2))
                markerPath.closeSubpath()
            }
            context.fill(markerPath, with: .color(.white))
            
            // Dashed line style for TP/SL
            let dashStyle = StrokeStyle(lineWidth: 1, dash: [5, 5])
            
            // Draw Take Profit line
            if let takeProfit = trade.targets.takeProfit {
                let tpY = scale.y(takeProfit, size: frame.size)
                if tpY >= frame.minY && tpY <= frame.maxY {
                    var tpPath = Path()
                    tpPath.move(to: CGPoint(x: offsetX, y: tpY))
                    tpPath.addLine(to: CGPoint(x: frame.maxX, y: tpY))
                    context.stroke(tpPath, with: .color(.green), style: dashStyle)
                    
                    // Add TP label
                    let tpLabel = Text(String(format: "TP: %.2f", takeProfit)).font(.system(size: 8)).foregroundColor(.green)
                    context.draw(tpLabel, at: CGPoint(x: frame.maxX - 40, y: tpY - 5), anchor: .trailing)
                }
            }
            
            // Draw Stop Loss line
            if let stopLoss = trade.targets.stopLoss {
                let slY = scale.y(stopLoss, size: frame.size)
                if slY >= frame.minY && slY <= frame.maxY {
                    var slPath = Path()
                    slPath.move(to: CGPoint(x: offsetX, y: slY))
                    slPath.addLine(to: CGPoint(x: frame.maxX, y: slY))
                    context.stroke(slPath, with: .color(.red), style: dashStyle)
                    
                    // Add SL label
                    let slLabel = Text(String(format: "SL: %.2f", stopLoss)).font(.system(size: 8)).foregroundColor(.red)
                    context.draw(slLabel, at: CGPoint(x: frame.maxX - 40, y: slY + 10), anchor: .trailing)
                }
            }
        }
    }
}
