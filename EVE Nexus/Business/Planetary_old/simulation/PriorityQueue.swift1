import Foundation

/// 优先队列
struct PriorityQueue<T> {
    // MARK: - Properties
    
    /// 存储元素的数组
    private var heap: [T]
    
    /// 排序函数
    private let ordered: (T, T) -> Bool
    
    /// 是否为空
    var isEmpty: Bool {
        return heap.isEmpty
    }
    
    /// 元素数量
    var count: Int {
        return heap.count
    }
    
    /// 第一个元素
    var first: T? {
        return heap.first
    }
    
    // MARK: - Initialization
    
    /// 初始化优先队列
    /// - Parameter sort: 排序函数，用于确定元素的优先级
    init(sort: @escaping (T, T) -> Bool) {
        self.heap = []
        self.ordered = sort
    }
    
    // MARK: - Methods
    
    /// 入队
    mutating func enqueue(_ element: T) {
        heap.append(element)
        siftUp(from: heap.count - 1)
    }
    
    /// 出队
    @discardableResult
    mutating func dequeue() -> T? {
        guard !isEmpty else { return nil }
        
        if heap.count == 1 {
            return heap.removeLast()
        }
        
        let first = heap[0]
        heap[0] = heap.removeLast()
        siftDown(from: 0)
        
        return first
    }
    
    /// 移除指定元素
    mutating func remove(_ element: T, by areEqual: (T, T) -> Bool) {
        guard let index = heap.firstIndex(where: { areEqual($0, element) }) else {
            return
        }
        
        let last = heap.count - 1
        if index != last {
            heap.swapAt(index, last)
            siftDown(from: index)
            siftUp(from: index)
        }
        heap.removeLast()
    }
    
    /// 查找满足条件的第一个元素
    func first(where predicate: (T) -> Bool) -> T? {
        return heap.first(where: predicate)
    }
    
    /// 清空队列
    mutating func clear() {
        heap.removeAll()
    }
    
    // MARK: - Private Methods
    
    /// 向上调整
    private mutating func siftUp(from index: Int) {
        var child = index
        var parent = parentIndex(of: child)
        
        while child > 0 && ordered(heap[child], heap[parent]) {
            heap.swapAt(child, parent)
            child = parent
            parent = parentIndex(of: child)
        }
    }
    
    /// 向下调整
    private mutating func siftDown(from index: Int) {
        var parent = index
        
        while true {
            let leftChild = leftChildIndex(of: parent)
            let rightChild = rightChildIndex(of: parent)
            var candidate = parent
            
            if leftChild < heap.count && ordered(heap[leftChild], heap[candidate]) {
                candidate = leftChild
            }
            
            if rightChild < heap.count && ordered(heap[rightChild], heap[candidate]) {
                candidate = rightChild
            }
            
            if candidate == parent {
                return
            }
            
            heap.swapAt(parent, candidate)
            parent = candidate
        }
    }
    
    /// 获取父节点索引
    private func parentIndex(of index: Int) -> Int {
        return (index - 1) / 2
    }
    
    /// 获取左子节点索引
    private func leftChildIndex(of index: Int) -> Int {
        return 2 * index + 1
    }
    
    /// 获取右子节点索引
    private func rightChildIndex(of index: Int) -> Int {
        return 2 * index + 2
    }
} 