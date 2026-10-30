import Foundation

/// Repository 구현이 앱에 알려 주는 공통 실패다.
public enum RepositoryError: Error, Equatable, Sendable {
    /// 없는 PIN이나 문서, 파일
    case notFound
    /// 이미 다른 세션이 쓰고 있는 PIN
    case pinTaken
    /// 올릴 파일이 크기 제한(스캔 파일 50MB, 스캔 setup.json 1MB, 나머지 20MB)을 넘는다.
    case fileTooLarge
    /// 받은 도면·스캔 파일이 참조의 SHA-256과 맞지 않는다.
    case integrityMismatch
    /// 세션 상태를 이전 단계로 되돌리려 함 (예: ended → running)
    case invalidStatusChange
    /// 이미 시작했거나 끝난 세션이라 입장할 수 없음
    case sessionClosed
}
