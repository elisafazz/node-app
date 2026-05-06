import Foundation
import UIKit

/// Wraps the signed Cloudinary upload pattern Sunzzari/Miracles use.
/// Pre-signature comes from the cloudinary-sign Edge Function so we never embed the API secret in the iOS bundle.
@MainActor
final class CloudinaryService {
    static let shared = CloudinaryService()

    enum Kind: String { case story, photo }

    enum CloudinaryError: Error, LocalizedError {
        case signatureFetchFailed
        case imageEncodingFailed
        case uploadFailed(statusCode: Int, body: String?)
        case responseDecodingFailed

        var errorDescription: String? {
            switch self {
            case .signatureFetchFailed: return "Could not get an upload signature."
            case .imageEncodingFailed: return "Could not encode the image."
            case .uploadFailed(let code, let body): return "Cloudinary upload failed (\(code)) \(body ?? "")"
            case .responseDecodingFailed: return "Cloudinary returned an unexpected response."
            }
        }
    }

    private struct UploadSignature: Decodable {
        let signature: String
        let timestamp: Int
        let api_key: String
        let cloud_name: String
        let folder: String
        let upload_preset: String
    }

    private struct UploadResponse: Decodable {
        let public_id: String
        let secure_url: String
    }

    /// Uploads a UIImage to Cloudinary. Stories go to `user/{author_user_id}/stories/` (cross-node, ADR-012),
    /// photos to `node/{node_id}/photos/`. `nodeId` required for photos, ignored for stories.
    /// Images are downsampled to maxDimension 1920 before encoding to keep bandwidth and Cloudinary storage reasonable.
    func upload(image: UIImage, kind: Kind, nodeId: UUID? = nil) async throws -> String {
        let signature = try await fetchSignature(kind: kind, nodeId: nodeId)
        let compressed = compress(image)
        guard let imageData = compressed.jpegData(compressionQuality: 0.80) else {
            throw CloudinaryError.imageEncodingFailed
        }
        return try await postMultipart(imageData: imageData, signature: signature)
    }

    private func compress(_ image: UIImage, maxDimension: CGFloat = 1920) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private func fetchSignature(kind: Kind, nodeId: UUID?) async throws -> UploadSignature {
        var body: [String: String] = ["kind": kind.rawValue]
        if let nodeId { body["node_id"] = nodeId.uuidString }
        let result: UploadSignature = try await SupabaseService.shared.functions.invoke(
            "cloudinary-sign",
            options: .init(body: body)
        )
        return result
    }

    private func postMultipart(imageData: Data, signature: UploadSignature) async throws -> String {
        let url = URL(string: "https://api.cloudinary.com/v1_1/\(signature.cloud_name)/image/upload")!
        let boundary = "----NodeUploadBoundary\(UUID().uuidString)"

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("api_key", signature.api_key)
        appendField("timestamp", String(signature.timestamp))
        appendField("signature", signature.signature)
        appendField("folder", signature.folder)
        appendField("upload_preset", signature.upload_preset)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"node.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CloudinaryError.uploadFailed(statusCode: status, body: String(data: data, encoding: .utf8))
        }
        guard let parsed = try? JSONDecoder().decode(UploadResponse.self, from: data) else {
            throw CloudinaryError.responseDecodingFailed
        }
        return parsed.public_id
    }
}
