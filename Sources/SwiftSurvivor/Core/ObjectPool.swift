/// Small free-list pool for high-frequency gameplay values.
/// Systems keep indices instead of removing elements from the middle of arrays.
final class ObjectPool<Element> {
    private var storage: [Element?]
    private var freeIndices: [Int]
    private(set) var activeCount = 0

    init(capacity: Int = 64) {
        storage = Array(repeating: nil, count: max(0, capacity))
        freeIndices = Array((0..<max(0, capacity)).reversed())
    }

    var capacity: Int { storage.count }

    func acquire(_ make: () -> Element) -> Int {
        let index: Int
        if let reused = freeIndices.popLast() {
            index = reused
        } else {
            index = storage.count
            storage.append(nil)
        }
        storage[index] = make()
        activeCount += 1
        return index
    }

    func value(at index: Int) -> Element? {
        guard storage.indices.contains(index) else { return nil }
        return storage[index]
    }

    func update(at index: Int, _ update: (inout Element) -> Void) {
        guard storage.indices.contains(index), storage[index] != nil else { return }
        update(&storage[index]!)
    }

    func release(_ index: Int) {
        guard storage.indices.contains(index), storage[index] != nil else { return }
        storage[index] = nil
        freeIndices.append(index)
        activeCount = max(0, activeCount - 1)
    }

    func removeAll(keepingCapacity: Bool = true) {
        storage = keepingCapacity ? Array(repeating: nil, count: storage.count) : []
        freeIndices = Array((0..<storage.count).reversed())
        activeCount = 0
    }
}
