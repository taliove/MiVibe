import CryptoKit
import Foundation

/// 语音模型文件管理：下载（含进度）、SHA256 校验、列举、删除。
/// 模型存 `~/Library/Application Support/MiVibe/models/`，不随 App 分发。
///
/// 第一版不做断点续传：最大模型 1.6GB，失败重下可接受；但写入走临时文件 +
/// 校验通过后才落位，绝不留下"半个模型被当成下好了"的状态。
@MainActor
public final class ModelStore: ObservableObject {
    public enum StoreError: Error, LocalizedError {
        case checksumMismatch
        case http(Int)
        case allSourcesFailed

        public var errorDescription: String? {
            switch self {
            case .checksumMismatch: return "下载的文件校验失败（内容损坏或被篡改），请重试"
            case .http(let code): return "下载失败（HTTP \(code)）"
            case .allSourcesFailed: return "所有下载源都失败了，请检查网络后重试"
            }
        }
    }

    public enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(String)
    }

    /// 每个模型的状态，设置页直接观察。
    @Published public private(set) var states: [String: State] = [:]

    public static let modelsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MiVibe/models")

    public init() { refresh() }

    public func url(for model: ModelCatalog.Model) -> URL {
        Self.modelsDir.appendingPathComponent(model.fileName)
    }

    public func isDownloaded(_ model: ModelCatalog.Model) -> Bool {
        FileManager.default.isReadableFile(atPath: url(for: model).path)
    }

    public func refresh() {
        for model in ModelCatalog.all {
            if case .downloading = states[model.id] { continue }
            states[model.id] = isDownloaded(model) ? .downloaded : .notDownloaded
        }
    }

    private var activeTasks: [String: Task<Void, Never>] = [:]

    /// 下载模型：依次尝试主源与备用源，成功后 SHA256 校验落位。
    public func download(_ model: ModelCatalog.Model) {
        if case .downloading = states[model.id] { return }
        states[model.id] = .downloading(progress: 0)
        activeTasks[model.id] = Task { [weak self] in
            guard let self else { return }
            var lastError: Error = StoreError.allSourcesFailed
            for source in model.downloadURLs {
                do {
                    try await self.downloadFrom(source, model: model)
                    self.states[model.id] = .downloaded
                    Log.chain.notice("model downloaded: \(model.id) from \(source.host ?? "?", privacy: .public)")
                    self.activeTasks[model.id] = nil
                    return
                } catch is CancellationError {
                    self.activeTasks[model.id] = nil
                    return  // 状态由 cancelDownload 复位
                } catch {
                    Log.chain.error("model \(model.id) from \(source.host ?? "?", privacy: .public) failed: \(error.localizedDescription)")
                    lastError = error
                }
            }
            self.states[model.id] = .failed(lastError.localizedDescription)
            self.activeTasks[model.id] = nil
        }
    }

    public func cancelDownload(_ model: ModelCatalog.Model) {
        activeTasks[model.id]?.cancel()
        activeTasks[model.id] = nil
        states[model.id] = isDownloaded(model) ? .downloaded : .notDownloaded
    }

    public func delete(_ model: ModelCatalog.Model) throws {
        cancelDownload(model)
        try FileManager.default.removeItem(at: url(for: model))
        refresh()
    }

    // MARK: - 内部

    /// URLSessionDownloadTask 的进度/完成回调桥。AsyncBytes 逐字节迭代慢到服务器
    /// 断连（实测 77MB 下载中途 connection lost），所以走下载任务。
    private final class DownloadBridge: NSObject, URLSessionDownloadDelegate, Sendable {
        let modelID: String
        let expected: Int64
        /// 下载完成的暂存位（校验通过后才落到正式位置）。
        let staging: URL
        let onProgress: @Sendable (Double) -> Void
        let continuation: CheckedContinuation<URL, Error>

        init(modelID: String, expected: Int64, staging: URL,
             onProgress: @escaping @Sendable (Double) -> Void,
             continuation: CheckedContinuation<URL, Error>) {
            self.modelID = modelID
            self.expected = expected
            self.staging = staging
            self.onProgress = onProgress
            self.continuation = continuation
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
            onProgress(min(1, Double(totalBytesWritten) / Double(total)))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            // location 只在这个回调里有效，return 后系统就删掉——必须当场移走。
            do {
                try? FileManager.default.removeItem(at: staging)
                try FileManager.default.moveItem(at: location, to: staging)
                continuation.resume(returning: staging)
            } catch {
                continuation.resume(throwing: error)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            if let error {
                continuation.resume(throwing: error)
            } else if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                continuation.resume(throwing: StoreError.http(http.statusCode))
            }
        }
    }

    /// 可取消的任务句柄盒（continuation 闭包里创建，cancel 回调里使用）。
    private final class TaskBox: @unchecked Sendable { var task: URLSessionDownloadTask? }

    private func downloadFrom(_ url: URL, model: ModelCatalog.Model) async throws {
        try FileManager.default.createDirectory(at: Self.modelsDir, withIntermediateDirectories: true)

        let box = TaskBox()
        let staging = Self.modelsDir.appendingPathComponent(model.fileName + ".partial")
        let downloaded: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let bridge = DownloadBridge(modelID: model.id, expected: model.sizeBytes, staging: staging,
                                            onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.states[model.id] = .downloading(progress: progress)
                    }
                }, continuation: continuation)
                // session 强引用 bridge，任务活跃期间桥不会提前释放。
                let session = URLSession(configuration: .ephemeral, delegate: bridge, delegateQueue: nil)
                let task = session.downloadTask(with: url)
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }

        // 校验：流式读文件算 SHA256，不必整个读进内存。
        let digest = try SHA256.hash(fileAt: downloaded)
        guard digest == model.sha256 else {
            Log.chain.error("model \(model.id) checksum mismatch: \(digest)")
            throw StoreError.checksumMismatch
        }

        let dest = self.url(for: model)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: downloaded, to: dest)
    }
}

extension SHA256 {
    /// 分块读文件算 SHA256（大模型 1.6GB，不能 Data(contentsOf:)）。
    static func hash(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 22) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
