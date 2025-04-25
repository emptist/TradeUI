import Foundation

public final class CSVMarketDataFile: @unchecked Sendable, MarketDataFile {
    public let fileUrl: URL
    private var continuation: AsyncStream<CandleData>.Continuation?
    private var fileHandle: FileHandle?
    private var symbol: String = ""
    private var barInterval: TimeInterval = 60
    private var interval: TimeInterval = 60
    private var delimiter: String = ";"
    
    public init(fileUrl: URL) {
        self.fileUrl = fileUrl
    }
    
    public func close() {
        fileHandle?.closeFile()
        fileHandle = nil
        continuation?.finish()
    }
    
    public func publish() {
        guard let fileHandle = fileHandle else {
            continuation?.finish()
            return
        }

        if let lineData = fileHandle.readLine() {
            let line = lineData.toString()
            let components = line?.split(separator: delimiter).map { String($0) } ?? []
            guard components.count >= 6,
                  let _ = parseTimeInterval(components[0]),
                  let open = Double(components[2]),
                  let high = Double(components[3]),
                  let low = Double(components[4]),
                  let close = Double(components[5]) else {
                Task {
                    try await Task.sleep(for: .milliseconds(200))
                    await MainActor.run { publish() }
                }
                return
            }
            let volume: Double? = components.count >= 7 ? Double(components[6]) : nil
            let bar = Bar(
                timeOpen: interval,
                interval: barInterval,
                priceOpen: open,
                priceHigh: high,
                priceLow: low,
                priceClose: close,
                volume: volume
            )
            interval += barInterval
            continuation?.yield(CandleData(symbol: symbol, interval: barInterval, bars: [bar]))
        } else {
            fileHandle.closeFile()
            self.interval = 0
            self.fileHandle = nil
            continuation?.finish()
        }
    }
    
    public func readBars(symbol: Symbol, interval: TimeInterval, loadAllAtOnce: Bool = false) throws -> AsyncStream<CandleData> {
        return AsyncStream { continuation in
            self.continuation = continuation
            self.symbol = symbol
            self.barInterval = interval

            if loadAllAtOnce {
                if let data = self.loadCandleData() {
                    continuation.yield(data)
                }
                continuation.finish()
            } else {
                do {
                    self.fileHandle = try FileHandle(forReadingFrom: self.fileUrl)
                    _ = self.fileHandle?.readLine() // Skip header
                } catch {
                    print("Failed to open file: \(error)")
                    continuation.finish()
                    return
                }
                Task {
                    try await Task.sleep(for: .milliseconds(200))
                    await MainActor.run { self.publish() }
                }
            }
        }
    }
    
    public func save(strategyName: String, candleData: CandleData) {
        let fileManager = FileManager.default
        let filePath = fileUrl.path
        
        do {
            if !fileManager.fileExists(atPath: filePath) {
                fileManager.createFile(atPath: filePath, contents: nil)
            }

            let fileHandle = try FileHandle(forWritingTo: fileUrl)
            defer { fileHandle.closeFile() }

            let newBars = candleData.bars.map { bar in
                "\(bar.timeOpen)\(delimiter)\(bar.priceOpen)\(delimiter)\(bar.priceHigh)\(delimiter)\(bar.priceLow)\(delimiter)\(bar.priceClose)"
            }

            if let data = newBars.joined(separator: "\n").data(using: .utf8) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
            }
        } catch {
            print("Failed to save CSV file: \(error)")
        }
    }
    
    public func loadCandleData() -> CandleData? {
        do {
            let fileHandle = try FileHandle(forReadingFrom: fileUrl)
            defer { fileHandle.closeFile() }
            
            if let firstLineData = fileHandle.readLine(),
               let firstLine = firstLineData.toString() {
                self.delimiter = firstLine.contains(";") ? ";" : ","
            }
            
            var bars: [Bar] = []
            while let line = fileHandle.readLine()?.toString() {
                let components = line.split(separator: Character(delimiter)).map { String($0) }
                guard components.count >= 5,
                      let timestamp = parseTimeInterval(components[0]),
                      let open = Double(components[1]),
                      let high = Double(components[2]),
                      let low = Double(components[3]),
                      let close = Double(components[4]) else {
                    continue
                }
                let volume: Double? = components.count >= 6 ? Double(components[5]) : nil
                let bar = Bar(
                    timeOpen: timestamp,
                    interval: 60.0,
                    priceOpen: open,
                    priceHigh: high,
                    priceLow: low,
                    priceClose: close,
                    volume: volume
                )
                bars.append(bar)
            }
            
            return bars.isEmpty ? nil : CandleData(symbol: "Unknown", interval: 60.0, bars: bars)
        } catch {
            print("Error loading candle data: \(error)")
            return nil
        }
    }
}

private func parseTimeInterval(_ value: String) -> TimeInterval? {
    // Check if value is numeric (e.g., 60.0, 1h, 5m)
    if let numericValue = Double(value) {
        return numericValue // Direct TimeInterval
    }

    // Handle interval formats like "5m", "1h"
    if value.hasSuffix("h") {
        return Double(value.dropLast()).flatMap { $0 * 3600 } // Convert hours to seconds
    } else if value.hasSuffix("m") {
        return Double(value.dropLast()).flatMap { $0 * 60 } // Convert minutes to seconds
    }

    // Attempt to parse custom date formats
    let dateFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss",
        "MM/dd/yyyy HH:mm:ss",
        "dd-MM-yyyy HH:mm:ss"
    ]

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")

    for format in dateFormats {
        dateFormatter.dateFormat = format
        if let date = dateFormatter.date(from: value) {
            return date.timeIntervalSince1970 // Convert Date to TimeInterval
        }
    }

    print("Warning: Could not parse time format for value \(value)")
    return nil
}
