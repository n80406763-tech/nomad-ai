import Foundation
import CoreLocation

/// Маршрут, построенный по офлайн-графу федеральных трасс.
struct RoadRoute {
    let polyline: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let durationSeconds: Double
    /// Расстояние от исходной/конечной точки до ближайшей известной трассы —
    /// этот "последний километр" в graph нет, он всегда прямая линия.
    let startSnapMeters: Double
    let endSnapMeters: Double
}

private struct RoadGraphFile: Decodable {
    let nodes: [[Double]]
    let edges: [[Double]]
    enum CodingKeys: String, CodingKey { case nodes = "n", edges = "e" }
}

/// Офлайн-граф "скелета" дорожной сети России (магистрали/трассы/дороги
/// первого класса — см. Tools/build-offline-road-graph.mjs) для прокладки
/// маршрута по дорогам без сети, вместо прямой линии между точками.
///
/// Сознательно не покрывает местные улицы: последняя миля от исходной/конечной
/// точки до ближайшей известной трассы всегда достраивается прямой линией.
actor OfflineRoadGraph {
    static let shared = OfflineRoadGraph()

    private struct Edge { let to: Int; let meters: Double; let speedKmh: Double }
    private struct GridKey: Hashable { let x: Int; let y: Int }

    private var nodes: [CLLocationCoordinate2D] = []
    private var adjacency: [[Edge]] = []
    private var grid: [GridKey: [Int]] = [:]
    private let gridCellDegrees = 0.2
    private var didLoad = false
    private var isAvailable = false
    private var didReportUnavailable = false

    /// Если снап дальше этого — считаем точку вне зоны покрытия графа (местная улица в дальнем посёлке и т.п).
    private static let maxSnapMeters: Double = 25_000

    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> RoadRoute? {
        loadIfNeeded()
        guard isAvailable,
              let start = nearestNode(to: from), start.distanceMeters <= Self.maxSnapMeters,
              let end = nearestNode(to: to), end.distanceMeters <= Self.maxSnapMeters else {
            reportUnavailableIfNeeded()
            return nil
        }

        guard let path = dijkstra(from: start.index, to: end.index) else { return nil }

        var polyline: [CLLocationCoordinate2D] = [from]
        polyline.append(contentsOf: path.nodeIndices.map { nodes[$0] })
        polyline.append(to)

        let lastMileMeters = start.distanceMeters + end.distanceMeters
        let lastMileSeconds = lastMileMeters / (40.0 * 1000 / 3600) // пешая/местная скорость ~40 км/ч как приближение

        return RoadRoute(
            polyline: polyline,
            distanceMeters: path.meters + lastMileMeters,
            durationSeconds: path.seconds + lastMileSeconds,
            startSnapMeters: start.distanceMeters,
            endSnapMeters: end.distanceMeters
        )
    }

    // MARK: - Загрузка графа

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        guard let url = Bundle.main.url(forResource: "russia_roads", withExtension: "json", subdirectory: "RoutingGraph")
            ?? Bundle.main.url(forResource: "russia_roads", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(RoadGraphFile.self, from: data) else {
            return
        }

        nodes = decoded.nodes.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        guard !nodes.isEmpty else { return }

        adjacency = Array(repeating: [], count: nodes.count)
        for edge in decoded.edges {
            guard edge.count == 4 else { continue }
            let from = Int(edge[0]), to = Int(edge[1])
            guard from >= 0, from < nodes.count, to >= 0, to < nodes.count else { continue }
            adjacency[from].append(Edge(to: to, meters: edge[2], speedKmh: max(edge[3], 5)))
        }

        for (idx, coordinate) in nodes.enumerated() {
            grid[gridKey(for: coordinate), default: []].append(idx)
        }
        isAvailable = true
    }

    private func reportUnavailableIfNeeded() {
        guard isAvailable == false, !didReportUnavailable else { return }
        didReportUnavailable = true
        Task { @MainActor in
            DiagnosticsStore.shared.report(
                title: "Офлайн-граф дорог не найден",
                details: "Пакет федеральных трасс России не попал в сборку. Маршрут будет показан прямой линией."
            )
        }
    }

    // MARK: - Поиск ближайшего узла

    private func gridKey(for coordinate: CLLocationCoordinate2D) -> GridKey {
        GridKey(x: Int(floor(coordinate.longitude / gridCellDegrees)), y: Int(floor(coordinate.latitude / gridCellDegrees)))
    }

    private func nearestNode(to coordinate: CLLocationCoordinate2D) -> (index: Int, distanceMeters: Double)? {
        let center = gridKey(for: coordinate)
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var best: (Int, Double)?
        let maxRing = 6 // ~1.2° ~ 130 км при шаге ячейки 0.2° — достаточно для maxSnapMeters

        for ring in 0...maxRing {
            var candidateFound = false
            for dx in -ring...ring {
                for dy in -ring...ring {
                    guard max(abs(dx), abs(dy)) == ring else { continue }
                    guard let indices = grid[GridKey(x: center.x + dx, y: center.y + dy)] else { continue }
                    candidateFound = true
                    for idx in indices {
                        let d = target.distance(from: CLLocation(latitude: nodes[idx].latitude, longitude: nodes[idx].longitude))
                        if best == nil || d < best!.1 { best = (idx, d) }
                    }
                }
            }
            // Нашли что-то — но проверим ещё одно кольцо на случай, если реально ближайший узел
            // лежит по диагонали в соседней ячейке (эвристика, не точная гарантия глобального минимума).
            if best != nil, candidateFound, ring > 0 { break }
        }
        return best
    }

    // MARK: - Dijkstra

    private struct HeapItem { let node: Int; let priority: Double }

    private func dijkstra(from start: Int, to goal: Int) -> (nodeIndices: [Int], meters: Double, seconds: Double)? {
        guard start != goal else { return ([], 0, 0) }

        var distance = [Double](repeating: .infinity, count: nodes.count)
        var timeCost = [Double](repeating: .infinity, count: nodes.count)
        var previous = [Int](repeating: -1, count: nodes.count)
        var visited = [Bool](repeating: false, count: nodes.count)
        distance[start] = 0
        timeCost[start] = 0

        var heap = BinaryHeap<HeapItem> { $0.priority < $1.priority }
        heap.insert(HeapItem(node: start, priority: 0))

        while let current = heap.extractMin() {
            let u = current.node
            if visited[u] { continue }
            visited[u] = true
            if u == goal { break }

            for edge in adjacency[u] {
                guard !visited[edge.to] else { continue }
                let newDist = distance[u] + edge.meters
                if newDist < distance[edge.to] {
                    distance[edge.to] = newDist
                    timeCost[edge.to] = timeCost[u] + edge.meters / (edge.speedKmh * 1000 / 3600)
                    previous[edge.to] = u
                    heap.insert(HeapItem(node: edge.to, priority: newDist))
                }
            }
        }

        guard distance[goal].isFinite else { return nil }

        var path: [Int] = []
        var cursor = goal
        while cursor != start {
            path.append(cursor)
            cursor = previous[cursor]
            if cursor == -1 { return nil }
        }
        path.reverse()
        return (path, distance[goal], timeCost[goal])
    }
}

/// Минимальная бинарная куча — используется вместо O(n) перебора для Dijkstra
/// на графах с десятками/сотнями тысяч узлов.
private struct BinaryHeap<Element> {
    private var storage: [Element] = []
    private let areInIncreasingOrder: (Element, Element) -> Bool

    init(areInIncreasingOrder: @escaping (Element, Element) -> Bool) {
        self.areInIncreasingOrder = areInIncreasingOrder
    }

    mutating func insert(_ element: Element) {
        storage.append(element)
        siftUp(from: storage.count - 1)
    }

    mutating func extractMin() -> Element? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let min = storage.removeLast()
        siftDown(from: 0)
        return min
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        var parent = (child - 1) / 2
        while child > 0, areInIncreasingOrder(storage[child], storage[parent]) {
            storage.swapAt(child, parent)
            child = parent
            parent = (child - 1) / 2
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = parent * 2 + 1
            let right = parent * 2 + 2
            var candidate = parent
            if left < storage.count, areInIncreasingOrder(storage[left], storage[candidate]) { candidate = left }
            if right < storage.count, areInIncreasingOrder(storage[right], storage[candidate]) { candidate = right }
            if candidate == parent { return }
            storage.swapAt(parent, candidate)
            parent = candidate
        }
    }
}
