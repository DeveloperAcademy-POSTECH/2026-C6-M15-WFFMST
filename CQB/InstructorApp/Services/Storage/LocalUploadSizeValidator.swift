import CQBCore
import Foundation

/// CQBFirebase와 Storage 규칙의 기존 파일별 제한으로, 업로드 시작 전에 파일 묶음을 검사한다.
nonisolated enum LocalUploadSizeValidator {
    static let maximumFileBytes = 20 * 1_024 * 1_024
    static let maximumWorldMapBytes = 50 * 1_024 * 1_024
    static let maximumWorldMapSetupBytes = 1_024 * 1_024

    static func validate(_ files: FloorPlanFiles) throws {
        for (name, count) in [
            ("도면 이미지", files.imagePNG.count),
            ("장애물 파일", files.resolvedMask.count),
            ("도면 좌표 정보", files.navigationMapJSON.count)
        ] {
            try validate(byteCount: count, fileName: name, maximumBytes: maximumFileBytes)
        }
    }

    static func validate(_ files: WorldMapFiles, compression: WorldMapCompression) throws {
        try validateWorldMapArchive(files.worldMapArchive, compression: compression)
        try validate(
            byteCount: files.setupJSON.count,
            fileName: "공간 스캔 설정 파일",
            maximumBytes: maximumWorldMapSetupBytes
        )
    }

    static func validateWorldMapArchive(_ archive: Data, compression: WorldMapCompression) throws {
        try validate(
            byteCount: archive.count,
            fileName: "공간 스캔 파일",
            maximumBytes: maximumWorldMapBytes,
            isCompressed: compression == .lzfse
        )
    }

    static func validate(
        byteCount: Int,
        fileName: String,
        maximumBytes: Int,
        isCompressed: Bool = false
    ) throws {
        guard byteCount <= maximumBytes else {
            throw LocalUploadFileSizeError(
                fileName: fileName,
                actualBytes: byteCount,
                maximumBytes: maximumBytes,
                isCompressed: isCompressed
            )
        }
    }
}

nonisolated struct LocalUploadFileSizeError: LocalizedError, Equatable, Sendable {
    let fileName: String
    let actualBytes: Int
    let maximumBytes: Int
    let isCompressed: Bool

    var errorDescription: String? {
        let label = isCompressed ? "압축 후 용량" : "파일 용량"
        return "\(fileName)의 용량이 업로드 한도를 초과했습니다.\n"
            + "\(label): \(Self.formattedBytes(actualBytes))\n"
            + "최대 허용 용량: \(Self.formattedBytes(maximumBytes))"
    }

    /// Storage와 동일하게 1024 단위로 표시하고, 경계에서도 초과 여부를 알 수 있게 바이트 수를 병기한다.
    static func formattedBytes(_ bytes: Int) -> String {
        String(format: "%.1fMB (%lld바이트)", locale: Locale(identifier: "en_US_POSIX"),
               Double(bytes) / 1_048_576, Int64(bytes))
    }
}
