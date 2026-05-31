import Foundation
import Supabase
import UIKit

enum AttachmentsAPIError: LocalizedError {
    case encodeFailed
    case empty
    case unsupportedImage

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "Couldn't compress the image."
        case .empty:
            return "Couldn't read the saved attachment row."
        case .unsupportedImage:
            return "Couldn't read that image."
        }
    }
}

@MainActor
enum AttachmentsAPI {
    /// Bucket id used for all task image attachments.
    private static let bucketID = "todo-attachments"

    /// Long edge in points to resize before uploading. Keeps bandwidth and
    /// downstream model token costs reasonable while still being readable.
    private static let maxLongEdge: CGFloat = 1280

    /// JPEG compression quality used after resize.
    private static let jpegQuality: CGFloat = 0.8

    /// Lists every attachment for a todo, oldest first (matches creation order).
    static func list(forTodoID todoID: UUID) async throws -> [TodoAttachment] {
        try await Supa.client
            .from("todo_attachments")
            .select()
            .eq("todo_id", value: todoID)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Resizes + JPEG-encodes the image and uploads it to Storage at
    /// `<userID>/<todoID>/<uuid>.jpg`, then inserts a `todo_attachments` row.
    static func upload(
        image: UIImage,
        todoID: UUID,
        userID: UUID
    ) async throws -> TodoAttachment {
        let (data, size) = try resize(image: image)

        let filename = "\(UUID().uuidString).jpg"
        let storagePath = "\(userID.uuidString.lowercased())/\(todoID.uuidString.lowercased())/\(filename)"

        try await Supa.client.storage
            .from(bucketID)
            .upload(
                storagePath,
                data: data,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: false
                )
            )

        let row = NewTodoAttachment(
            todo_id: todoID,
            user_id: userID,
            storage_path: storagePath,
            mime_type: "image/jpeg",
            width: Int(size.width),
            height: Int(size.height)
        )
        let result: [TodoAttachment] = try await Supa.client
            .from("todo_attachments")
            .insert(row)
            .select()
            .execute()
            .value
        guard let attachment = result.first else { throw AttachmentsAPIError.empty }
        return attachment
    }

    /// Deletes the row and the underlying Storage object. Best-effort: we
    /// remove the storage object first so a partial failure leaves no dangling
    /// row pointing at a missing file.
    static func delete(_ attachment: TodoAttachment) async throws {
        try? await Supa.client.storage
            .from(bucketID)
            .remove(paths: [attachment.storage_path])
        _ = try await Supa.client
            .from("todo_attachments")
            .delete()
            .eq("id", value: attachment.id)
            .execute()
    }

    /// Short-lived signed URL for in-app thumbnail / full-screen viewing.
    static func signedURL(
        for attachment: TodoAttachment,
        expiresIn seconds: Int = 3600
    ) async throws -> URL {
        try await Supa.client.storage
            .from(bucketID)
            .createSignedURL(
                path: attachment.storage_path,
                expiresIn: seconds
            )
    }

    // MARK: - Private

    private static func resize(image: UIImage) throws -> (Data, CGSize) {
        let original = image.size
        guard original.width > 0, original.height > 0 else {
            throw AttachmentsAPIError.unsupportedImage
        }

        let longEdge = max(original.width, original.height)
        let scale = longEdge > maxLongEdge ? maxLongEdge / longEdge : 1
        let target = CGSize(
            width: floor(original.width * scale),
            height: floor(original.height * scale)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else {
            throw AttachmentsAPIError.encodeFailed
        }
        return (data, target)
    }
}
