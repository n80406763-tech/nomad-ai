import UIKit
import WebKit
import CoreLocation

final class OSMVectorMapView: UIView, WKNavigationDelegate, WKScriptMessageHandler {
    private let resourceHandler = NomadMapResourceHandler()
    private let webView: WKWebView
    private var mapReady = false
    private var pendingScripts: [String] = []
    private var route: [CLLocationCoordinate2D] = []
    private var userLocation: CLLocation?

    override init(frame: CGRect) {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        configuration.setURLSchemeHandler(resourceHandler, forURLScheme: "nomad")
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)

        contentController.add(self, name: "nomadMap")
        webView.navigationDelegate = self
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 0.88, green: 0.90, blue: 0.86, alpha: 1)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let url = URL(string: "nomad://app/index.html")!
        webView.load(URLRequest(url: url))
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nomadMap")
    }

    func setRoute(_ coordinates: [CLLocationCoordinate2D], fitCamera: Bool) {
        route = coordinates
        let points = coordinates.map { [$0.longitude, $0.latitude] }
        run("window.nomadSetRoute(\(jsonLiteral(points)), \(fitCamera ? "true" : "false"));")
    }

    func clearRoute() {
        route = []
        run("window.nomadClearRoute();")
    }

    func setUserLocation(_ location: CLLocation) {
        userLocation = location
        run("window.nomadSetUser(\(jsonLiteral([location.coordinate.longitude, location.coordinate.latitude])));")
    }

    func center(on coordinate: CLLocationCoordinate2D) {
        run("window.nomadCenterOn(\(jsonLiteral([coordinate.longitude, coordinate.latitude])));")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !OfflineMapPack.isBundled else { return }
        DiagnosticsStore.shared.report(
            title: "Офлайн-карта не найдена",
            details: "Пакет России не попал в сборку приложения. Установите IPA из последней успешной сборки."
        )
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            mapReady = true
            let scripts = pendingScripts
            pendingScripts = []
            scripts.forEach(execute)
        } else if type == "error", let text = body["message"] as? String {
            DiagnosticsStore.shared.report(title: "Ошибка офлайн-карты", details: text)
        }
    }

    private func run(_ script: String) {
        guard mapReady else {
            pendingScripts.append(script)
            return
        }
        execute(script)
    }

    private func execute(_ script: String) {
        webView.evaluateJavaScript(script) { _, _ in }
    }

    private func jsonLiteral(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}

private final class NomadMapResourceHandler: NSObject, WKURLSchemeHandler {
    private let queue = DispatchQueue(label: "com.nomadai.app.offlinemap", qos: .userInitiated, attributes: .concurrent)

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        queue.async {
            self.respond(to: urlSchemeTask)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func respond(to task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let fileURL = resourceURL(for: url) else {
            send(status: 404, headers: [:], data: Data(), to: task)
            return
        }

        if fileURL.pathExtension == "pmtiles" {
            sendRange(of: fileURL, request: task.request, to: task)
        } else if let data = try? Data(contentsOf: fileURL) {
            send(status: 200, headers: ["Content-Type": mimeType(for: fileURL)], data: data, to: task)
        } else {
            send(status: 404, headers: [:], data: Data(), to: task)
        }
    }

    private func resourceURL(for url: URL) -> URL? {
        guard url.host == "app" else { return nil }
        let components = url.pathComponents.dropFirst()
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }),
              let resourcesURL = Bundle.main.resourceURL else { return nil }

        let relativePath = components.joined(separator: "/")
        let candidateRoots = [
            resourcesURL.appendingPathComponent(OfflineMapPack.resourceDirectory, isDirectory: true),
            resourcesURL
        ]
        for root in candidateRoots {
            let candidate = root.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        if let fileName = components.last {
            for root in candidateRoots {
                let flattenedCandidate = root.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: flattenedCandidate.path) {
                    return flattenedCandidate
                }
            }
        }
        return nil
    }

    private func sendRange(of fileURL: URL, request: URLRequest, to task: WKURLSchemeTask) {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize, size > 0 else {
            send(status: 404, headers: [:], data: Data(), to: task)
            return
        }

        let requestedRange = byteRange(from: request.value(forHTTPHeaderField: "Range"), size: size)
        let lowerBound = requestedRange?.lowerBound ?? 0
        let upperBound = requestedRange?.upperBound ?? size - 1
        guard lowerBound >= 0, lowerBound <= upperBound, upperBound < size,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            send(status: 416, headers: ["Content-Range": "bytes */\(size)"], data: Data(), to: task)
            return
        }

        defer { try? handle.close() }
        handle.seek(toFileOffset: UInt64(lowerBound))
        let data = handle.readData(ofLength: upperBound - lowerBound + 1)
        var headers = [
            "Content-Type": "application/octet-stream",
            "Accept-Ranges": "bytes",
            "Access-Control-Allow-Origin": "*"
        ]
        if requestedRange != nil {
            headers["Content-Range"] = "bytes \(lowerBound)-\(upperBound)/\(size)"
        }
        send(status: requestedRange == nil ? 200 : 206, headers: headers, data: data, to: task)
    }

    private func byteRange(from header: String?, size: Int) -> ClosedRange<Int>? {
        guard let header, header.hasPrefix("bytes=") else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        if parts[0].isEmpty, let suffixLength = Int(parts[1]), suffixLength > 0 {
            return max(0, size - suffixLength)...(size - 1)
        }

        guard let start = Int(parts[0]), start < size else { return nil }
        let end = min(Int(parts[1]) ?? size - 1, size - 1)
        return start...end
    }

    private func send(status: Int, headers: [String: String], data: Data, to task: WKURLSchemeTask) {
          var responseHeaders = headers
          responseHeaders["Content-Length"] = "\(data.count)"
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: responseHeaders) else { return }
        task.didReceive(response)
        if !data.isEmpty { task.didReceive(data) }
        task.didFinish()
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension {
        case "html": return "text/html"
        case "js": return "application/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}