import Foundation
import VTuberMeetCore

enum AvatarResourceLoader {
    static func loadPresets() throws -> [AvatarPreset] {
        let url = try resourceURL(path: "Avatars/manifest.json")
        let data = try Data(contentsOf: url)
        return try AvatarManifest.decode(data)
    }

    static func resourceURL(path: String) throws -> URL {
        let root = try resourceRootURL()
        let url = root.appendingPathComponent(path)

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        throw CocoaError(.fileNoSuchFile)
    }

    static func resourceRootURL() throws -> URL {
        if let rootURL = resourceRootURL(from: Bundle.main.resourceURL) {
            return rootURL
        }

        if let rootURL = resourceRootURL(from: Bundle.module.resourceURL) {
            return rootURL
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private static func resourceRootURL(from resourceURL: URL?) -> URL? {
        guard let resourceURL else { return nil }

        let directLive2DViewer = resourceURL.appendingPathComponent("Live2DViewer")
        if FileManager.default.fileExists(atPath: directLive2DViewer.path) {
            fputs("[VTuberMeet] resourceRoot: \(resourceURL.path) (direct)\n", stderr)
            return resourceURL
        }

        let copiedResources = resourceURL.appendingPathComponent("Resources")
        let copiedLive2DViewer = copiedResources.appendingPathComponent("Live2DViewer")
        if FileManager.default.fileExists(atPath: copiedLive2DViewer.path) {
            fputs("[VTuberMeet] resourceRoot: \(copiedResources.path) (copied)\n", stderr)
            return copiedResources
        }

        return nil
    }
}
