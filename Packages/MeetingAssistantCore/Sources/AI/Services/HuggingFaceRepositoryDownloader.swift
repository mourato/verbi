@preconcurrency import FluidAudio
import Foundation

enum HuggingFaceRepositoryDownloader {
    struct RepositoryFile: Decodable {
        let path: String
        let type: String
        let size: Int?
    }

    enum DownloadError: LocalizedError {
        case accessDenied(repoPath: String, hasToken: Bool)
        case invalidResponse(statusCode: Int, path: String)

        var errorDescription: String? {
            switch self {
            case let .accessDenied(repoPath, hasToken):
                if hasToken {
                    return "Access denied when reading Hugging Face repository: \(repoPath). The token is present but does not have permission for this repository."
                }
                return "Access denied when reading Hugging Face repository: \(repoPath). No Hugging Face token was detected in the app process (HF_TOKEN/HUGGING_FACE_HUB_TOKEN/HUGGINGFACEHUB_API_TOKEN). Apps launched from Finder/DMG do not inherit shell environment variables."
            case let .invalidResponse(statusCode, path):
                return "Hugging Face request failed with HTTP \(statusCode) for path: \(path)."
            }
        }
    }

    static func listFilesRecursively(
        repoPath: String,
        startPath: String = ""
    ) async throws -> [RepositoryFile] {
        let apiPath = startPath.isEmpty ? "tree/main" : "tree/main/\(startPath)"
        let url = try ModelRegistry.apiModels(repoPath, apiPath)
        let request = authorizedRequest(url: url)
        let (data, response) = try await DownloadUtils.sharedSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse(statusCode: -1, path: apiPath)
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw DownloadError.accessDenied(repoPath: repoPath, hasToken: huggingFaceToken() != nil)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DownloadError.invalidResponse(statusCode: httpResponse.statusCode, path: apiPath)
        }

        let items = try JSONDecoder().decode([RepositoryFile].self, from: data)
        var collectedFiles: [RepositoryFile] = []

        for item in items {
            if item.type == "directory" {
                let nested = try await listFilesRecursively(repoPath: repoPath, startPath: item.path)
                collectedFiles.append(contentsOf: nested)
            } else if item.type == "file" {
                collectedFiles.append(item)
            }
        }

        return collectedFiles
    }

    static func downloadFiles(
        repoPath: String,
        files: [RepositoryFile],
        to rootDirectory: URL
    ) async throws {
        for file in files where file.type == "file" {
            try await downloadFile(repoPath: repoPath, file: file, to: rootDirectory)
        }
    }

    private static func downloadFile(
        repoPath: String,
        file: RepositoryFile,
        to rootDirectory: URL
    ) async throws {
        let destinationURL = rootDirectory.appendingPathComponent(file.path)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return
        }

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if file.size == 0 {
            FileManager.default.createFile(atPath: destinationURL.path, contents: Data())
            return
        }

        let encodedPath = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
        let fileURL = try ModelRegistry.resolveModel(repoPath, encodedPath)
        let request = authorizedRequest(url: fileURL)
        let (tempFileURL, response) = try await DownloadUtils.sharedSession.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse(statusCode: -1, path: file.path)
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw DownloadError.accessDenied(repoPath: repoPath, hasToken: huggingFaceToken() != nil)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DownloadError.invalidResponse(statusCode: httpResponse.statusCode, path: file.path)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: tempFileURL, to: destinationURL)
    }

    private static func authorizedRequest(url: URL, timeout: TimeInterval = 1800) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if let token = huggingFaceToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func huggingFaceToken() -> String? {
        ProcessInfo.processInfo.environment["HF_TOKEN"]
            ?? ProcessInfo.processInfo.environment["HUGGING_FACE_HUB_TOKEN"]
            ?? ProcessInfo.processInfo.environment["HUGGINGFACEHUB_API_TOKEN"]
    }
}
