import SwiftUI
import CoreLocation

// MARK: - View Model

@MainActor
final class TripPlannerVM: ObservableObject {
    enum Step: Int { case addresses = 0, building, selecting, downloadOffer, downloading, ready }
    enum Field { case from, to }

    @Published var step: Step = .addresses

    @Published var fromText = ""
    @Published var toText = ""
    @Published var fromCoordinate: CLLocationCoordinate2D?
    @Published var toCoordinate: CLLocationCoordinate2D?
    @Published var fromName = ""
    @Published var toName = ""

    @Published var fromResults: [NominatimResult] = []
    @Published var toResults: [NominatimResult] = []
    @Published var activeField: Field?
    @Published var isSearching = false

    @Published var buildProgress: Double = 0
    @Published var buildStatusText = "Ищу лучшие дороги…"
    @Published var routeOptions: [RoutingService.RouteResult] = []
    @Published var selectedIndex: Int = 0
    @Published var isOfflineFallback = false

    @Published var errorMessage: String?
    @Published var savedRoute: SavedRoute?
    @Published var estimatedRegions = 0

    private var searchTask: Task<Void, Never>?

    var canBuild: Bool { fromCoordinate != nil && toCoordinate != nil }
    var selectedRoute: RoutingService.RouteResult? {
        routeOptions.indices.contains(selectedIndex) ? routeOptions[selectedIndex] : nil
    }

    func search(_ field: Field, query: String) {
        searchTask?.cancel()
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            if field == .from { fromResults = [] } else { toResults = [] }
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            let res = await NominatimService.shared.search(query: query)
            guard !Task.isCancelled else { return }
            if field == .from { fromResults = res } else { toResults = res }
            isSearching = false
        }
    }

    func selectResult(_ result: NominatimResult, field: Field) {
        if field == .from {
            fromCoordinate = result.coordinate
            fromName = result.displayName
            fromText = result.displayName
            fromResults = []
        } else {
            toCoordinate = result.coordinate
            toName = result.displayName
            toText = result.displayName
            toResults = []
        }
        activeField = nil
    }

    func useMyLocation() {
        guard let loc = LocationManager.shared.location else {
            errorMessage = "Текущая позиция ещё не определена. Подождите сигнал GPS."
            return
        }
        fromCoordinate = loc.coordinate
        fromName = "Моя позиция"
        fromText = "Моя позиция"
        fromResults = []
    }

    func swapDirections() {
        swap(&fromCoordinate, &toCoordinate)
        swap(&fromName, &toName)
        swap(&fromText, &toText)
    }

    func buildRoutes() {
        guard let from = fromCoordinate, let to = toCoordinate else { return }
        step = .building
        buildProgress = 0
        buildStatusText = "Ищу лучшие дороги…"
        routeOptions = []
        isOfflineFallback = false

        Task {
            let results = await RoutingService.shared.buildAlternatives(from: from, to: to, maxCount: 20) { found, total in
                Task { @MainActor in
                    self.buildProgress = total > 0 ? min(Double(found) / Double(total), 0.98) : 0
                    self.buildStatusText = "Найдено вариантов: \(found)…"
                }
            }

            guard !results.isEmpty else {
                let offline = RoutingService.shared.buildOfflineRoute(waypoints: [from, to])
                self.routeOptions = [offline]
                self.isOfflineFallback = true
                self.selectedIndex = 0
                self.buildProgress = 1
                self.estimatedRegions = RouteDownloadService.regionsAlong(polyline: offline.polyline).count
                self.step = .selecting
                return
            }

            self.routeOptions = results
            self.selectedIndex = 0
            self.buildProgress = 1
            self.buildStatusText = "Готово: \(results.count) вариант(ов) маршрута"
            self.estimatedRegions = RouteDownloadService.regionsAlong(polyline: results[0].polyline).count
            self.step = .selecting
        }
    }

    func selectIndex(_ index: Int) {
        guard routeOptions.indices.contains(index) else { return }
        selectedIndex = index
        estimatedRegions = RouteDownloadService.regionsAlong(polyline: routeOptions[index].polyline).count
    }

    func confirmSelection() {
        guard let chosen = selectedRoute, let from = fromCoordinate, let to = toCoordinate else { return }
        let route = SavedRoute(
            name: "\(shortName(fromName)) → \(shortName(toName))",
            waypoints: [
                Waypoint(name: fromName.isEmpty ? "Старт" : fromName, latitude: from.latitude, longitude: from.longitude),
                Waypoint(name: toName.isEmpty ? "Финиш" : toName, latitude: to.latitude, longitude: to.longitude)
            ],
            polyline: chosen.polyline,
            totalDistanceKm: chosen.distanceKm
        )
        RouteStore.shared.save(route)
        RouteStore.shared.activate(route)
        savedRoute = route
        step = .downloadOffer
    }

    func startDownload() {
        guard let route = savedRoute else { return }
        step = .downloading
        RouteDownloadService.shared.startDownload(for: route)
    }

    func skipDownload() {
        step = .ready
    }

    func finishAndGo() {
        AppState.shared.startTrip()
    }

    func planAnotherTrip() {
        step = .addresses
        fromText = ""; toText = ""
        fromCoordinate = nil; toCoordinate = nil
        fromName = ""; toName = ""
        routeOptions = []; selectedIndex = 0
        savedRoute = nil
        buildProgress = 0
        isOfflineFallback = false
    }

    private func shortName(_ full: String) -> String {
        String(full.split(separator: ",").first.map(String.init) ?? full)
    }
}

// MARK: - View

struct TripPlannerView: View {
    @StateObject private var vm = TripPlannerVM()
    @ObservedObject private var downloader = RouteDownloadService.shared
    @ObservedObject private var locationManager = LocationManager.shared

    var body: some View {
        Group {
            if hasLocationAccess {
                VStack(spacing: 0) {
                    header
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            switch vm.step {
                            case .addresses: addressesSection
                            case .building: buildingSection
                            case .selecting: selectingSection
                            case .downloadOffer: downloadOfferSection
                            case .downloading: downloadingSection
                            case .ready: readySection
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            } else {
                locationAccessScreen
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .alert("Не получилось", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("ОК") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
        .onAppear {
            locationManager.requestPermission()
        }
        .onReceive(downloader.$state) { state in
            if state == .completed, vm.step == .downloading {
                vm.step = .ready
            }
        }
    }

    private var hasLocationAccess: Bool {
        locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse
    }

    private var locationAccessScreen: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "location.circle.fill")
                .font(.system(size: 66))
                .foregroundColor(.cyan)
            Text("Нужна геолокация")
                .font(.title2.bold())
            Text(locationAccessMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button(action: requestOrOpenLocationSettings) {
                Label(locationAccessActionTitle, systemImage: locationAccessActionIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.black)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var locationAccessMessage: String {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Без доступа к геолокации навигатор не может определить вашу позицию и начать маршрут."
        default:
            return "Разрешите доступ к геолокации. Сначала Nomad определит текущую позицию, затем позволит выбрать маршрут."
        }
    }

    private var locationAccessActionTitle: String {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Открыть настройки GPS"
        default:
            return "Разрешить геолокацию"
        }
    }

    private var locationAccessActionIcon: String {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "gearshape.fill"
        default:
            return "location.fill"
        }
    }

    private func requestOrOpenLocationSettings() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            locationManager.openLocationSettings()
        default:
            locationManager.requestPermission()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Nomad")
                    .font(.title3.bold())
                    .foregroundColor(.cyan)
                Spacer()
                if vm.step != .addresses {
                    Button(action: vm.planAnotherTrip) {
                        Label("Новая", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<TripPlannerVM.Step.allCases.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= vm.step.rawValue ? Color.cyan : Color.gray.opacity(0.25))
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: Step 1 — адреса

    private var addressesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Куда едем?")
                .font(.title3.bold())
                .padding(.top, 12)
            Text("Сперва разрешите доступ к GPS и выберите пункт отправления и назначения.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            addressBlock(
                title: "Откуда",
                icon: "smallcircle.filled.circle.fill",
                iconColor: .green,
                text: Binding(get: { vm.fromText }, set: { vm.fromText = $0; vm.search(.from, query: $0) }),
                results: vm.fromResults,
                field: .from
            )

            Button(action: vm.useMyLocation) {
                Label("Использовать мою текущую позицию", systemImage: "location.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.cyan)

            HStack {
                Spacer()
                Button(action: vm.swapDirections) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
            }

            addressBlock(
                title: "Куда",
                icon: "mappin.circle.fill",
                iconColor: .red,
                text: Binding(get: { vm.toText }, set: { vm.toText = $0; vm.search(.to, query: $0) }),
                results: vm.toResults,
                field: .to
            )

            Button(action: vm.buildRoutes) {
                Label("Построить маршруты", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.canBuild ? Color.cyan : Color.gray.opacity(0.3))
                    .foregroundColor(.black)
                    .cornerRadius(16)
            }
            .disabled(!vm.canBuild)
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
    }

    private func addressBlock(title: String, icon: String, iconColor: Color, text: Binding<String>, results: [NominatimResult], field: TripPlannerVM.Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            HStack {
                Image(systemName: icon).foregroundColor(iconColor)
                TextField("Город, адрес или место…", text: text)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)

            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results.prefix(5)) { result in
                        Button(action: { vm.selectResult(result, field: field) }) {
                            Text(result.displayName)
                                .font(.footnote)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Color(UIColor.secondarySystemBackground).opacity(0.6))
                .cornerRadius(10)
            }
        }
    }

    // MARK: Step 2 — построение

    private var buildingSection: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 60)
            ProgressView(value: vm.buildProgress)
                .tint(.cyan)
                .padding(.horizontal, 40)
            Text(vm.buildStatusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Строим до 20 вариантов пути между точками…")
                .font(.footnote)
                .foregroundColor(.gray)
            Spacer(minLength: 100)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Step 3 — выбор маршрута

    private var selectingSection: some View {
        VStack(spacing: 0) {
            if let route = vm.selectedRoute {
                MapView(previewPolyline: route.polyline, showsHUD: false)
                    .frame(height: 280)
                    .cornerRadius(20)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            if vm.isOfflineFallback {
                Label("Нет интернета — построена прямая линия между точками", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .padding(.top, 8)
            } else {
                Text("Найдено \(vm.routeOptions.count) вариант(ов) — пролистайте карточки")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            TabView(selection: $vm.selectedIndex) {
                ForEach(Array(vm.routeOptions.enumerated()), id: \.offset) { index, route in
                    routeCard(route: route, index: index)
                        .tag(index)
                        .padding(.horizontal, 20)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 168)
            .onChange(of: vm.selectedIndex) { newValue in
                vm.selectIndex(newValue)
            }

            Button(action: vm.confirmSelection) {
                Label("Сохранить этот маршрут", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
    }

    private func routeCard(route: RoutingService.RouteResult, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(route.label).font(.headline)
                Spacer()
                if index == fastestIndex { Badge(text: "Быстрый", color: .cyan) }
                if index == shortestIndex { Badge(text: "Короткий", color: .green) }
            }
            HStack(spacing: 20) {
                Label("\(route.distanceKm, specifier: "%.0f") км", systemImage: "road.lanes")
                Label(formatDuration(route.durationMin), systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    private var fastestIndex: Int {
        vm.routeOptions.indices.min { vm.routeOptions[$0].durationMin < vm.routeOptions[$1].durationMin } ?? 0
    }
    private var shortestIndex: Int {
        vm.routeOptions.indices.min { vm.routeOptions[$0].distanceKm < vm.routeOptions[$1].distanceKm } ?? 0
    }

    // MARK: Step 4 — предложение скачать офлайн-данные

    private var downloadOfferSection: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.cyan)
                .padding(.top, 30)
            Text("Маршрут сохранён!")
                .font(.title2.bold())
            Text("Скачать заранее точки на пути (АЗС, отели, кафе, аптеки, шиномонтаж, банкоматы) для \(vm.estimatedRegions) регион(ов) вдоль маршрута, чтобы пользоваться ими офлайн в поездке?")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Загрузка идёт в фоне — можно свернуть приложение. Если соединение медленное, оставьте телефон включённым и подключённым к Wi-Fi на несколько часов, чтобы всё точно докачалось.")
                .font(.footnote)
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: vm.startDownload) {
                Label("Скачать для офлайн-поездки", systemImage: "icloud.and.arrow.down.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.black)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 20)

            Button(action: vm.skipDownload) {
                Text("Пропустить, поеду онлайн")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Step 5 — прогресс загрузки

    private var downloadingSection: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: downloader.progress)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: downloader.progress)
                Text("\(Int(downloader.progress * 100))%")
                    .font(.title.bold())
            }
            .frame(width: 140, height: 140)
            .padding(.horizontal, 40)

            Text(downloader.statusText)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if !downloader.etaText.isEmpty {
                Text(downloader.etaText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Text("Можно свернуть приложение — загрузка продолжится в фоне.")
                .font(.footnote)
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: vm.skipDownload) {
                Text("Продолжить без ожидания")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)
            Spacer(minLength: 40)
        }
    }

    // MARK: Step 6 — готово

    private var readySection: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
                .padding(.top, 20)
            Text("Всё скачано успешно!")
                .font(.title2.bold())
            Text("Перед поездкой откройте этот навигатор и нажмите «Начать поездку» — приложение сразу перенесёт вас к текущему месту, как в обычном навигаторе.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: vm.finishAndGo) {
                Label("Начать поездку", systemImage: "location.north.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.black)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            Spacer(minLength: 40)
        }
    }

    private func formatDuration(_ min: Double) -> String {
        let h = Int(min) / 60
        let m = Int(min) % 60
        return h > 0 ? "\(h) ч \(m) мин" : "\(m) мин"
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

extension TripPlannerVM.Step: CaseIterable {}
