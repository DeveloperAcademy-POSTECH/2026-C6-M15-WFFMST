import Foundation

/// Repository 구현이 앱에 알려 주는 공통 실패다.
public enum RepositoryError: Error, Equatable, Sendable {
    /// 없는 PIN이나 문서, 파일
    case notFound
    /// 이미 다른 세션이 쓰고 있는 PIN
    case pinTaken
    /// 올릴 파일이 크기 제한(20MB)을 넘는다.
    case fileTooLarge
    /// 받은 도면 파일이 `FloorPlanReference.navigationSHA256`과 맞지 않는다.
    case integrityMismatch
}
