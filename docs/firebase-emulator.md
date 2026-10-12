# Firebase 로컬 에뮬레이터

개발과 테스트 중에는 운영 Firebase(`cqb-wffmst`) 대신 맥에서 띄운 에뮬레이터에 붙는다.
요금이 생기지 않고, 운영 데이터와 규칙을 건드리지 않는다.
쓰지 않아도 된다. 설치하지 않거나 스위치를 켜지 않으면 앱은 지금처럼 운영 Firebase에 붙는다.

```
[터미널]  firebase emulators:start   맥에서 Firebase 흉내 서버를 켠다
[Xcode]   (Emulator) 스킴으로 실행    앱이 그 서버에 붙는다
```

| 서비스 | 포트 |
| --- | --- |
| Auth | 9099 |
| Firestore | 8080 |
| Storage | 9199 |
| 관리 화면 | 4000 (`http://localhost:4000`) |

설정은 저장소 루트의 `firebase.json`, 규칙은 `firebase/firestore.rules`, `firebase/storage.rules`에 있다.

## 설치 (처음 한 번)

1. Node.js와 Java 21 이상을 설치한다.

   ```bash
   brew install node openjdk@21
   ```

   Homebrew의 `openjdk@21`은 기본 `java`로 잡히지 않는다. `java -version`이 21 미만이면 `~/.zshrc`에 추가한다.

   ```bash
   export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
   ```

2. Firebase CLI를 설치하고 로그인한다.

   ```bash
   npm install -g firebase-tools
   firebase login
   ```

## 에뮬레이터 켜기

터미널에서 저장소 루트로 이동해 실행한다. 루트의 `firebase.json`을 읽으므로 다른 폴더에서 실행하면 안 된다.

```bash
cd 2026-C6-M15-WFFMST
firebase emulators:start
```

- `All emulators ready!`가 나오면 준비된 것이다.
- 쓰는 동안 터미널 창을 켜 둔다. 창을 닫거나 `Ctrl + C`를 누르면 꺼진다.
- 끄면 데이터가 사라진다.

데이터를 남기려면 종료할 때 저장하고, 다음에 불러온다.

```bash
firebase emulators:start --import firebase/emulator-data --export-on-exit
```

## 앱을 에뮬레이터에 붙이기

### 시뮬레이터

Xcode 위쪽에서 스킴을 고르고 실행한다.

| 스킴 | 연결 대상 |
| --- | --- |
| `InstructorApp`, `MemberApp` | 운영 Firebase |
| `InstructorApp (Emulator)`, `MemberApp (Emulator)` | 맥의 에뮬레이터 (`localhost`) |

실행하면 Xcode 콘솔에 `Firebase 에뮬레이터 사용: localhost`가 찍힌다.

- (Emulator) 스킴은 스킴의 환경 변수 `FIREBASE_EMULATOR_HOST`로 연결 대상을 바꾼다. 앱 코드는 `CQBFirebaseModule.configure()`에서 이 값을 읽는다.
- 로컬 Firestore는 TLS를 사용하지 않는다. 현재 Firebase SDK 12.19.2의 `useEmulator`는 주소만 바꾸므로, 에뮬레이터 분기에서 `settings.isSSLEnabled = false`를 명시한다. 운영 연결에는 적용하지 않는다.
- 에뮬레이터가 꺼져 있으면 운영으로 넘어가지 않고 요청이 실패한다. 먼저 에뮬레이터를 켠다.
- 디버그 빌드에서 Xcode로 실행할 때만 적용된다. 홈 화면에서 앱을 열거나 릴리스 빌드(TestFlight, App Store)는 항상 운영 Firebase에 붙는다.
- 공유 스킴(`InstructorApp`, `MemberApp`)에는 이 환경 변수를 넣지 않는다.

### 실제 기기

실제 기기에서는 `localhost`가 기기 자신을 가리키므로 맥의 IP를 넣어야 한다. 사람마다 IP가 달라서 저장소에 올리지 않는 개인 스킴을 만든다.

**처음 한 번: 개인 스킴 만들기**

1. 맥 IP를 확인한다.

   ```bash
   ipconfig getifaddr en0
   ```

2. Xcode에서 **Product → Scheme → Manage Schemes…**를 연다.
3. `MemberApp (Emulator)`(또는 `InstructorApp (Emulator)`)를 선택하고 아래 ⚙️ → **Duplicate**를 누른다.
4. 이름을 `MemberApp (Emulator Device)`처럼 바꾸고 **Shared 체크를 끈다.** 체크가 켜져 있으면 저장소에 올라간다.
5. 복제한 스킴의 **Edit Scheme → Run → Arguments → Environment Variables**에서 `FIREBASE_EMULATOR_HOST` 값을 1번의 IP(예: `192.168.0.12`)로 바꾼다.

**실행하기**

1. 기기와 맥을 같은 와이파이에 연결한다.
2. 개인 스킴과 기기를 고르고 실행한다.
3. "로컬 네트워크의 기기를 찾고 연결하도록 허용" 팝업이 뜨면 **허용**하고, 앱을 멈춘 뒤 한 번 더 실행한다. 첫 실행에서는 팝업이 뜨는 동안 로그인 요청이 먼저 나가 `Local network prohibited`로 실패한다. 거부했다면 기기의 **설정 → 개인정보 보호 및 보안 → 로컬 네트워크**에서 앱을 켠다.
   - 이 권한은 맥에 접속하는 개발 중에만 필요하다. 운영 Firebase는 인터넷으로 접속하므로 실제 사용자에게는 팝업이 뜨지 않는다.
4. Xcode 콘솔에 `Firebase 에뮬레이터 사용: <맥 IP>`가 찍히는지 확인한다.

와이파이를 바꾸면 맥 IP가 달라질 수 있다. 갑자기 연결되지 않으면 IP를 다시 확인해 스킴 값을 고친다.

## 잘 붙었는지 확인

1. Xcode 콘솔에 `Firebase 에뮬레이터 사용: …`이 찍힌다. 없으면 운영에 붙은 것이므로 스킴을 확인한다.
2. `http://localhost:4000/auth`에 콘솔의 `익명 로그인 완료 uid: …`와 같은 uid가 있다.
3. 앱에서 만든 데이터가 `http://localhost:4000/firestore`, `/storage`에 보이고, 운영 콘솔에는 없다.

세션 생성 검증에는 Auth·Firestore·Storage가 모두 필요하다. `--only auth,storage`로 실행하면 Firestore가 빠지므로 전체를 실행하거나 `--only auth,firestore,storage`를 사용한다. 관리 화면에서 세 서비스가 모두 `On`인지 확인한다.

InstructorApp에서 도면을 등록하고 세션을 생성하면 팀 준비 화면에 6자리 PIN이 표시된다. Firestore 관리 화면에서 `sessions/{세션ID}`의 `status`가 `waiting`이고 `pin`이 화면과 같은지, `pins/{PIN}`의 `sessionID`가 해당 세션을 가리키는지 확인한다. 준비 화면에서 뒤로 가면 세션이 종료되고 PIN 문서가 삭제된다. REST 요청만 사용하는 테스트는 앱의 Firebase SDK 초기화·연결 경로를 검증하지 않으므로 이 시뮬레이터 확인을 대체하지 않는다.

### 시뮬레이터에서 준비 상태 실시간 반영 확인

시뮬레이터는 AR 추적을 지원하지 않으므로 실제 준비 조건을 충족할 수 없다. **Debug + iOS 시뮬레이터 + `FIREBASE_EMULATOR_HOST` 설정**을 모두 만족할 때만 MemberApp 대기 화면에 `준비 완료 전송 (테스트)` 스위치가 표시된다.

1. 두 앱을 `(Emulator)` 스킴으로 실행하고, MemberApp에서 교관 화면의 PIN으로 참가한다.
2. 출발 위치와 방향을 선택하고 `좌표 고정`을 누른다.
3. 테스트 스위치를 켜면 기존 Firebase SDK/Repository 경로로 `sessions/{세션ID}/members/{대원ID}.isReady`가 `true`로 저장된다. 교관 화면의 해당 대원이 준비 완료로 바뀌고 준비 인원이 증가하는지 확인한다.
4. 스위치를 끄면 `false`와 설정 중으로 되돌아간다. 위치를 다시 지정해도 테스트 상태는 해제된다. 5초 간격의 활동 보고는 선택한 테스트 상태를 유지한다.

이 스위치는 서버 보고만 대체하며 실제 AR 준비 상태나 녹화 시작 조건을 우회하지 않는다. 따라서 MemberApp의 카메라 영역에는 여전히 AR 미지원 안내가 표시된다. 실기기, 운영 Firebase 연결, Release 빌드에는 테스트 스위치가 없으며 기존 준비 판정을 그대로 사용한다. 이 검증에서는 교관 앱의 훈련 시작 버튼을 누르지 않는다. 실제 녹화 검증은 실기기에서 진행한다.

## 주의

- 로그인 정보는 키체인에 있어 앱을 지워도 남는다. 운영과 에뮬레이터를 오가면 앱이 시작할 때 자동으로 로그아웃하고 새로 익명 로그인한다. 콘솔에 `Firebase 연결 대상이 바뀌어 로그아웃`이 찍힌다.
- 규칙 파일은 Firebase 콘솔 규칙과 같게 유지한다. 규칙을 바꿀 때는 에뮬레이터에서 먼저 확인한 뒤 콘솔에 반영한다.
