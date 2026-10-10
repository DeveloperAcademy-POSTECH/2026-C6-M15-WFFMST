import Foundation

/// Repository 구현이 앱에 알려 주는 공통 실패다.
public enum RepositoryError: Error, Equatable, Sendable {
    /// 없는 PIN이나 문서
    case notFound
    /// 이미 다른 세션이 쓰고 있는 PIN
    case pinTaken
}
