import Foundation

struct CaptureGenerationGate: Sendable {
    private var currentGeneration = 0

    mutating func begin() -> Int {
        currentGeneration += 1
        return currentGeneration
    }

    mutating func invalidate() {
        currentGeneration += 1
    }

    func accepts(_ generation: Int) -> Bool {
        generation == currentGeneration
    }
}
