// The JIT helper's work: connect back to the app, then enable JIT for the app's process with
// StikJIT (device reachability, developer disk image, universal script). StikJIT's calls are
// synchronous and blocking, so they run in order on one serial queue, as its guide requires.
import Foundation
import StikJIT

/// The extension's principal class: receives the app's XPC endpoint and serves one worker.
@objc(WKJITRequestHandler)
final class JITRequestHandler: NSObject, NSExtensionRequestHandling {
    // The connections this process serves; kept alive for the life of the helper.
    private static var connections: [NSXPCConnection] = []

    func beginRequest(with context: NSExtensionContext) {
        // Same string as WK_JIT_ENDPOINT_KEY in WKJITProtocol.h.
        guard let item = context.inputItems.first as? NSExtensionItem,
              let endpoint = item.userInfo?["WKJITEndpoint"] as? NSXPCListenerEndpoint else {
            context.cancelRequest(withError: NSError(domain: "WolkaraForever.JIT", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The JIT request carried no endpoint.",
            ]))
            return
        }
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: WKJITHostEvents.self)
        connection.exportedInterface = NSXPCInterface(with: WKJITWorker.self)
        connection.exportedObject = JITWorker(connection: connection)
        // The app ended the request or went away: nothing is left to do in this process.
        connection.invalidationHandler = { exit(0) }
        connection.resume()
        Self.connections.append(connection)
    }
}

final class JITWorker: NSObject, WKJITWorker {
    private let queue = DispatchQueue(label: "wolkaraforever.jit.helper")
    private weak var connection: NSXPCConnection?

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    private var host: WKJITHostEvents? {
        connection?.remoteObjectProxyWithErrorHandler { _ in } as? WKJITHostEvents
    }

    func enableJIT(forProcess pid: Int32, pairingFile: Data, reply: @escaping (String?) -> Void) {
        queue.async { [self] in
            let fileManager = FileManager.default
            // The pairing file exists on disk only for the length of this call.
            let pairingURL = fileManager.temporaryDirectory.appendingPathComponent("pairing-\(UUID().uuidString).plist")
            do {
                try pairingFile.write(to: pairingURL, options: [.atomic, .completeFileProtection])
                defer { try? fileManager.removeItem(at: pairingURL) }
                // The developer disk image cache: this helper's own Library, kept across launches.
                let cache = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("StikJIT", isDirectory: true)
                try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
                try StikJIT.enableJIT(
                    targetPID: pid,
                    pairingFile: pairingURL,
                    ddiPaths: DDIPaths.default(in: cache),
                    script: .universal,
                    preparationProgress: { [weak self] stage in self?.host?.jitStage(Self.describe(stage)) },
                    progress: { [weak self] line in self?.host?.jitLog(line) }
                )
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    private static func describe(_ stage: StikJIT.PreparationStage) -> String {
        switch stage {
        case .checkingReachability: return "Reaching the device through LocalDevVPN"
        case .checkingDDI: return "Checking the developer disk image"
        case .downloadingDDI(let fraction, let status):
            return "Downloading the developer disk image \(Int(fraction * 100)) % \(status)"
        case .mountingDDI(let fraction): return "Mounting the developer disk image \(Int(fraction * 100)) %"
        case .verifyingDDI: return "Verifying the developer disk image"
        case .ready: return "Attaching to the app"
        @unknown default: return "Preparing the device"
        }
    }
}
