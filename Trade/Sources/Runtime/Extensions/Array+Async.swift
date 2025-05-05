import Foundation

extension Array {
    func asyncMap<T>(_ transform: @escaping (Element) async -> T) async -> [T] {
        var result: [T] = []
        for element in self {
            let mapped = await transform(element)
            result.append(mapped)
        }
        return result
    }
}
