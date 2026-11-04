# [개발일지] 디바이스 네이티브 푸시 알림 연동 및 사전 알림 기능 구현

- **작성일**: 2026-11-05
- **작업자**: Antigravity AI Assistant
- **관련 커밋**: `feat(notification): 디바이스 네이티브 푸시 알림 연동 및 일정/할 일 사전 알림 지원`

---

## 1. 작업 개요 및 배경

기존 시스템은 일정 준비시간 알림 시 앱 내부 상단에 `MaterialBanner` 형태의 인앱 배너를 띄우는 방식이었습니다. 이 방식은 앱이 백그라운드에 있거나 완전히 종료(Killed)된 상태에서는 사용자가 알림을 인지할 수 없다는 치명적인 한계가 있었습니다.

이를 개선하여 **앱 내부 배너를 완전히 제거하고, 실제 휴대폰 OS의 상태 표시줄(상단 노티피케이션 바) 헤드업 네이티브 푸시 알림**으로 동작하도록 전면 개편했습니다. 또한 일정 준비시간뿐만 아니라 **투두리스트의 사전 마감 알림**까지 통합 관리하도록 확장했습니다.

---

## 2. 주요 요구사항 및 설계 결정 (/grill-me 인터뷰 결과)

1. **알림 전송 메커니즘**:
   - 앱이 종료되어 있어도 동작하도록 **OS 시스템 알람 스케줄러 (`flutter_local_notifications`의 `zonedSchedule`)** 채택.
2. **일정(Schedule) 알림 규칙**:
   - 일정 시작 정각 알림은 제외하고, 사용자가 설정한 **사전 준비시간(10분/15분/30분/1시간 전 등)**에만 1회 발송.
   - 기존의 인앱 상단 배너(`MaterialBanner`)는 완전히 삭제하고 네이티브 알림으로 일원화.
3. **할 일(Todo) 알림 규칙**:
   - 용어를 '준비 시간' 대신 **'알림 시간'**으로 정의.
   - 마감 정각 알림 없이, 사용자가 설정한 **'알림 시간' 시점에만 1회 발송** (`마감 시각 - 알림 시간`).
   - 시간 미지정 투두는 알림을 발송하지 않음.
   - 할 일 완료(체크) 또는 삭제 시 기기 OS에 등록된 예약 알람 즉시 취소.
4. **알림 탭 시 라우팅(딥링크)**:
   - 일정 알림 탭 시 **캘린더 화면(또는 연결된 상황 체크리스트)**으로 자동 이동.
   - 할 일 알림 탭 시 **할 일(Todo) 화면**으로 자동 탭 전환.
5. **권한 확인 시점**:
   - 앱 최초 구동 시 권한 요청.
   - **설정 탭에서 알림 스위치를 켰을 때(ON)에도 권한 상태를 즉시 재확인**하여 비활성화 시 설정 안내 스낵바 제공.

---

## 3. 세부 구현 내역

### 3.1. 네이티브 권한 및 설정 (`AndroidManifest.xml`, `pubspec.yaml`)
- `flutter_local_notifications: ^18.0.1`, `timezone: ^0.10.0`, `flutter_timezone: ^3.0.1` 의존성 추가.
- Android 13+ 알림 권한(`POST_NOTIFICATIONS`), 정밀 알람 권한(`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`), 기기 재부팅 시 알람 유지를 위한 수신자(`RECEIVE_BOOT_COMPLETED`, `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`) 등록.

### 3.2. 알림 전담 서비스 구현 (`lib/services/notification_service.dart`)
- **싱글톤 아키텍처**(`NotificationService.instance`)로 전역 알림 생명주기 관리.
- 디바이스 로컬 타임존 기반 시간 계산 및 High Importance 채널 등록(헤드업 알림, 소리, 진동 지원).
- 단일 일정/투두 알림 스케줄링 및 대량 동기화 메서드 구현 (`syncScheduleNotifications`, `syncTodoNotifications`).
- 알림 터치 이벤트 감지 및 `onNotificationPayload` ValueNotifier를 통한 화면 전환 중계.

### 3.3. 투두 모델 및 UI 확장 (`lib/models/todo_model.dart`, `lib/screens/todo_screen.dart`)
- `TodoItem` 모델에 `reminderMinutesBefore` 필드, JSON 직렬화/역직렬화 및 헬퍼 게터(`hasReminder`, `reminderDateTime`, `reminderSummaryText`) 추가.
- 할 일 추가/수정 다이얼로그에 '알림 시간' 드롭다운(10분/15분/30분/1시간/2시간 전) 추가.
- 할 일 카드 목록에 설정된 알림 뱃지(`🔔 30분 전`) 표시.

### 3.4. 메인 화면 및 기존 배너 정리 (`lib/main.dart`)
- 앱 시작 시 초기 알림 초기화 및 권한 요청, 기존 데이터 스케줄링 동기화.
- 기존 `_showPrepPushBanner` 및 `MaterialBanner` 코드 완전 삭제.
- 구글 캘린더/태스크 동기화 및 로컬 데이터 변경 시 OS 시스템 알람 자동 재동기화 연동.

### 3.5. 환경설정 화면 연동 (`lib/screens/settings_screen.dart`)
- '일정 준비시간 알림' 및 '할 일(Todo) 알림' On/Off 스위치 추가.
- 스위치를 켰을 때(ON) `NotificationService.instance.requestPermissions()`를 즉시 호출하여 권한 허용 여부 점검 및 안내 스낵바 처리.

---

## 4. 트러블슈팅 (빌드 오류 해결 과정)

### 문제 1: JVM Target Compatibility 불일치 오류
- **현상**: Gradle 9 환경에서 `compileDebugKotlin`(1.8)과 `compileDebugJavaWithJavac`(17) 간 JVM 타깃 버전 불일치로 빌드 실패.
- **원인**: 서드파티 플러그인(`flutter_timezone`)의 구버전 JVM 타깃 설정 충돌.
- **해결**: `android/gradle.properties`에 `kotlin.jvm.target.validation.mode=warning` 추가.

### 문제 2: Core Library Desugaring 요구 오류
- **현상**: `flutter_local_notifications` 최신 자바 시간 API 사용으로 인해 `core library desugaring` 필수 요구.
- **원인**: Android Gradle Plugin의 최신 호환성 검사.
- **해결**: `android/app/build.gradle.kts`의 `compileOptions`에 `isCoreLibraryDesugaringEnabled = true` 활성화 및 `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` 의존성 추가.

### 문제 3: Kotlin DSL 플러그인 미인식
- **현상**: `app/build.gradle.kts`의 `kotlin { compilerOptions { ... } }` 블록이 인식되지 않고 컴파일 에러 발생.
- **원인**: `plugins` 블록에 `kotlin-android` 플러그인 누락.
- **해결**: `plugins` 블록에 `id("kotlin-android")` 명시 추가 후 디버그 APK 빌드 성공 (`√ Built build\app\outputs\flutter-apk\app-debug.apk`).

---

## 5. 테스트 및 검증 결과

1. **정적 분석**: `flutter analyze` 실행 결과 경고/에러 0건 (`No issues found!`)
2. **단위 테스트**: `test/notification_unit_test.dart` 작성 및 실행
   - 투두 알림 시간 계산 및 시간 미지정 예외 케이스 검증
   - 일정 준비 시간 역산 검증
   - 모델 JSON 직렬화/역직렬화 및 copyWith 유지 검증
   - 테스트 결과 전체 통과 (`5/5 passed`)
3. **빌드 검증**: `flutter build apk --debug` 컴파일 및 패키징 정상 성공.



---

# [개발일지] 상황 체크리스트 완료 시 캘린더 기록 정책 및 인터랙션 고도화

- **작성일**: 2026-11-05
- **작업자**: Antigravity AI Assistant
- **관련 커밋**: `feat(situation): 동일 상황 체크리스트 재완료 시 캘린더 기록 정책 및 인터랙션 개선`

---

## 1. 작업 개요 및 배경

기존 시스템은 외출 체크리스트를 100% 완료했을 때 당일 캘린더에 완료 기록 일정(`isAutoRecord: true`)을 자동 생성해 왔습니다. 그러나 하루에 동일한 외출 상황(예: "출근", "산책") 체크리스트를 여러 번 완료할 경우, **당일 1개의 기록만 유지하고 마지막 완료 시각으로 무조건 덮어쓰기(시간 갱신)**하는 방식이었습니다.

이로 인해 다음과 같은 문제점이 발생했습니다:
1. **실제 다중 외출 이력 누락**: 하루 중 오전 산책과 저녁 산책 등 실제로 여러 번 독립적으로 외출한 경우에도 이전 기록이 지워지고 마지막 완료 기록 1개만 남음.
2. **사용자 의도 미반영**: 단순 실수나 항목 수정 후 다시 체크한 것인지, 새로운 외출인지를 구분하지 못함.

이를 개선하여 **직전 완료 후 경과 시간(30분 임계값)을 기준으로 스마트하게 분기**하고, 빠른 시간 내 재완료 시에는 **사용자 확인 모달 바텀시트**를 제공하여 사용자가 의도에 맞게 선택할 수 있도록 인터랙션을 고도화했습니다.

---

## 2. 주요 요구사항 및 설계 결정 (/grill-me 인터뷰 결과)

1. **30분 임계값 기반 분기 정책**:
   - **30분 이내 재완료**: 체크리스트 수정이나 실수 보정일 가능성이 높으므로 **확인 모달 바텀시트**를 띄워 사용자에게 선택권 부여.
   - **30분 초과 재완료**: 별도의 외출로 판단하여 사용자 방해 없이 **캘린더에 새로운 외출 기록으로 자동 추가**.
2. **확인 모달 바텀시트 UI & 액션**:
   - 직전 완료 시각과 현재 시각을 한눈에 알기 쉽게 안내 *(예: "방금 전(09:00) 완료된 '출근' 기록이 있습니다. 현재 시각(09:15)으로 어떻게 처리할까요?")*.
   - 가로 2버튼 구성:
     - 좌측 (서브): `OutlinedButton` — **[기존 시간 갱신]**
     - 우측 (메인 강조): `FilledButton` — **[새 기록 추가]**
   - 바깥 영역 탭 또는 뒤로가기(Dismiss) 시: 캘린더 기록을 변경하지 않고 **기존 기록 그대로 유지**.
3. **일정 제목(Title) 일관성 유지**:
   - 동일 상황 일정이 하루에 여러 개 기록되더라도 제목은 접미사 없이 `'${situation.name} 체크리스트 완료'`로 일관성 유지 (캘린더 리스트에서 각 일정의 시각으로 직관적 구분 가능).
4. **피드백 및 실행 취소 지원**:
   - 새 기록 추가 시 스낵바에 `[실행 취소]` 액션을 제공하여 즉시 롤백 가능하도록 지원.

---

## 3. 세부 구현 내역 (`lib/screens/situation_screen.dart`)

### 3.1. 최근 완료 기록 탐색 및 시각 계산
- `_parseRecordDateTime(DateTime date, String timeStr)`:
  - 일정의 날짜와 "HH:mm" 포맷 문자열을 결합하여 정확한 `DateTime` 객체로 파싱.
- `_handleChecklistCompletedRecord(Situation situation)`:
  - 당일 동일 상황의 완료 기록 중 가장 최신의 기록(`latestRecord`)과 기록 시각(`latestRecordTime`)을 탐색.
  - 당일 첫 완료인 경우 즉시 추가.
  - 기존 기록이 있는 경우 `now.difference(latestRecordTime).inMinutes`를 계산하여 30분 이내 여부를 판별.

### 3.2. 30분 이내 확인 모달 바텀시트 구현
- `_showDuplicateRecordBottomSheet(...)`:
  - Material 3 디자인의 라운드 코너(20dp) 바텀시트 적용.
  - 상황 이름과 직전 기록 시각, 현재 시각을 표시하는 간결한 텍스트와 상단 핸들 바 배치.
  - `OutlinedButton`(기존 시간 갱신)과 `FilledButton`(새 기록 추가)을 가로 정렬하고, 각 탭 시 햅틱 피드백(`HapticFeedback.lightImpact()`) 적용.

### 3.3. 기록 갱신 및 다중 기록 분리 처리
- `_updateExistingCompletedRecord(...)`:
  - 직전 기록의 `time`, `title`, `lastEditedTime`을 갱신하고 스낵바 표시.
- `_addNewCompletedRecord(...)`:
  - 고유 ID(`record_${now.microsecondsSinceEpoch}`)를 부여하여 신규 `Schedule` 생성 및 추가.
  - 추가 직후 스낵바에 `[실행 취소]` 버튼을 노출하여 사용자 오조작 방지.

---

## 4. 검증 및 확인

1. **당일 첫 체크리스트 완료 시**:
   - 캘린더에 정상 추가되며 "체크리스트 완료! 캘린더에 기록이 자동 추가되었습니다." 스낵바 및 실행 취소 버튼 동작 확인.
2. **완료 후 30분 이내 항목 재체크 시**:
   - 확인 모달 바텀시트 정상 노출 확인.
   - [기존 시간 갱신] 선택 시: 기존 일정 시각이 현재 시각으로 갱신됨을 확인.
   - [새 기록 추가] 선택 시: 캘린더에 동일한 제목의 새로운 시간대 일정이 추가됨을 확인.
   - 바깥 탭으로 닫을 시: 기존 일정이 유지되며 캘린더에 중복 추가되지 않음 확인.
3. **완료 후 30분 초과 시점 재완료 시**:
   - 팝업 없이 새로운 외출 기록으로 자동 추가됨을 확인.


---

# [개발일지] 구글 캘린더 / 태스크 양방향 동기화 및 구글 드라이브 앱데이터 자동 백업 연동

- **작성일**: 2026-11-05
- **작업자**: Antigravity AI Assistant
- **관련 커밋**: `feat(sync): 구글 캘린더/태스크 양방향 동기화 및 구글 드라이브 백업/복원 연동`

---

## 1. 작업 개요 및 배경

기존 Bygo 앱은 로컬 SharedPreferences 및 JSON 내보내기/가져오기를 통해서만 데이터를 관리하여, 기기 분실이나 외부 캘린더/할 일 관리 앱과의 연동성이 부족했습니다.

이를 해결하기 위해 **구글 공식 API(Google Calendar, Tasks, Drive)**를 연동하여:
1. **Google 캘린더**: 일정·반복(RRULE)·외출상황/태그 메타데이터의 양방향 동기화 및 상황 완료 시 자동 기록 연동.
2. **Google 태스크**: `@default` 리스트와 시간/체크리스트의 양방향 동기화 (기존 사용자 메모 보존).
3. **Google 드라이브**: 숨김 앱폴더(`appDataFolder`)를 활용한 일일 주기적 JSON 자동 백업 및 롤링 버전 관리(최신 5개)와 복원 UX를 구축했습니다.

---

## 2. 주요 설계 및 정책 결정 (/grill-me 인터뷰 결과)

1. **점진적 권한 인가 (Incremental Auth & On-demand Sign-in)**:
   - 앱 구동 시 강제 로그인을 요구하지 않고, 설정 화면에서 사용자가 명시적으로 **'Google 계정으로 로그인'** 버튼을 누를 때 계정 인증을 진행.
   - 로그인 완료 후 캘린더, 태스크, 드라이브 백업 각 기능을 켤 때 필요한 Scope(`calendar`, `tasks`, `drive.appdata`)를 점진적으로 요청.
   - 권한 거부 시 스위치는 자동으로 Off 원복되며, 실패 원인 안내 메시지를 제공.
   - 연동 해제 또는 로그아웃 시 로컬 기기에 저장된 기존 일정/할 일 데이터는 삭제 없이 온전히 유지(`Retain`).
2. **구글 캘린더 동기화 규칙 (Schedule ↔ Calendar Event)**:
   - **동기화 범위**: 최근 3개월 ~ 향후 1년으로 쿼리 범위를 제한하여 네트워크/로컬 부하 방지.
   - **충돌 해결**: 최종 수정 시간 우선(`Latest Wins`)을 기본으로 하되, **로컬 휴지통(Soft Delete) vs 원격 수정 충돌 시 '로컬 우선(Local Wins)'**을 적용하여 삭제 의도를 철저히 반영.
   - **커스텀 메타데이터 보존**: 외출상황명, 다중 태그, 사전 준비시간 등은 이벤트의 `extendedProperties.private`에 JSON 형태로 격리 저장. 외부 캘린더 앱에서 일정이 수정되더라도 메타데이터를 유지하며 표준 필드(제목, 시간 등)만 병합.
   - **색상 매핑**: Bygo 테마 컬러와 구글 캘린더 표준 이벤트 팔레트(ColorId 1~11) 간 RGB 유클리디안 거리 최소값 자동 매핑.
   - **반복 일정(RRULE)**: RFC 5545 표준 기반 상호 변환 및 수정/삭제 시 3가지 범위("이 일정만 / 이후 모든 일정 / 전체") 분기 처리.
   - **외출 체크리스트 완료 연동**: 상황 체크리스트 100% 완료 시 당일 캘린더에 상황명으로 완료 기록 일정을 자동 생성 및 동기화.
3. **구글 태스크 동기화 규칙 (TodoItem ↔ Google Task)**:
   - **기본 리스트**: `@default` 작업 목록과 연동.
   - **Notes 필드 구분선 공존**: 구글 태스크 웹/앱에서 사용자가 직접 입력한 일반 메모를 보존하기 위해 구분선(`--- Bygo Info ---`)을 두고 마감 시간(`⏰ 시간: HH:mm`) 및 체크리스트(`[x]`, `[ ]`) 직렬화/역직렬화.
   - **반복 할 일 재활성화 연동**: 원격에서 완료(`status = 'completed'`) 처리 시 로컬의 자정 재활성화 엔진과 호환되도록 `completedAt` 및 `lastEditedTime` 동기화.
4. **구글 드라이브 앱데이터 자동 백업 및 복원**:
   - 사용자 구글 드라이브 화면을 어지럽히지 않도록 숨김 전용 폴더(`appDataFolder`)에 `bygo_backup_YYYYMMDD_HHmmss.json` 파일로 저장.
   - **자동 백업 주기**: 앱 진입 시 마지막 백업으로부터 24시간 경과 확인 후 자동 백업 수행.
   - **버전 롤링 관리**: 최신 5개 버전만 보관하며 초과된 과거 파일은 자동 삭제(Prune).
   - **복원 UX**: '드라이브에서 복원' 클릭 시 저장된 백업 목록(날짜/시간, 용량) 팝업을 제공하여 선택 복원 지원.

---

## 3. 세부 구현 내역

### 3.1. GoogleSyncService 핵심 엔진 구현 (`lib/services/google_sync_service.dart`)
- **로그인/로그아웃 및 점진적 인가**:
  - `signIn()`: 초기 `email` 기본 Scope로 단일 로그인 수행. 재시도 시 이전 실패/취소 캐시를 초기화하여 먹통 현상 방지.
  - `restoreSessionSilently()`: 앱 시작 시 대화형 창을 띄우지 않고 기존 세션만 조용히 복원.
  - `ensureScope()`: Android 플랫폼에서 예외를 유발하는 `canAccessScopes()` 대신 `requestScopes()`를 직접 호출하고, 권한 거부/취소 시 인스턴스를 재구성(`_rebuildGoogleSignInInstance()`)하여 네이티브 `requestedScopes` 오염 방지(재시도 무한 가능).
  - 모의(Mock) 폴백 계정 생성을 완전히 제거하고 실제 인증 결과만 정직하게 반영.
- **캘린더 양방향 동기화 (`syncSchedules`)**:
  - `timeMin`/`timeMax` 쿼리 최적화 및 로컬 휴지통(Soft Delete) 우선 원격 이벤트 삭제 처리.
  - `_findNearestCalendarColorId()`: 상황 컬러와 구글 캘린더 Color 1~11 간 RGB 델타 최단 거리 변환.
  - `_scheduleToRRule()`, `_applyRRuleToSchedule()`: RFC 5545 반복 규칙 완벽 상호 변환.
- **태스크 양방향 동기화 (`syncTodos`)**:
  - `_todoToGoogleTask(todo, existingRemote: remote)`: 원격에 작성된 기존 사용자 메모를 구분선 상단에 보존하고 하단에 Bygo 시간/서브태스크 병합.
- **드라이브 백업/복원 엔진**:
  - `backupJsonToDrive()`, `listDriveBackups()`, `downloadDriveBackupJson()`, `_pruneDriveBackups()`.

### 3.2. TodoItem 메모 직렬화/역직렬화 개선 (`lib/models/todo_model.dart`)
- `bygoNotesDivider`(`--- Bygo Info ---`) 도입.
- 기존 메모 파싱 시 Bygo 정보 구간과 사용자 일반 메모 구간을 분리하여 양방향 동기화 시 텍스트 유실 방지.

### 3.3. StorageService 드라이브 백업 지원 (`lib/services/storage_service.dart`)
- `buildBackupJsonString()`: 전체 로컬 데이터(일정, 상황, 할 일, 테마, 일일 리셋 시간 등)를 종합 JSON 문자열로 빌드.
- 마지막 구글 드라이브 백업 시각(`loadLastGoogleDriveBackupTime`, `saveLastGoogleDriveBackupTime`) 관리.

### 3.4. 설정 화면 UI 전면 개편 (`lib/screens/settings_screen.dart`)
- **로그인 전/후 조건부 렌더링**:
  - 로그인 전: 기능 소개와 함께 **'Google 계정으로 로그인'** 버튼만 간결하게 표시.
  - 로그인 후: 계정 이메일 칩 및 **'로그아웃'** 버튼 노출, 캘린더/태스크/드라이브 개별 토글 및 '지금 드라이브에 백업' / '드라이브에서 복원(최대 5개 목록 다이얼로그)' 제공.
- **실패 원인별 실시간 스낵바 안내**:
  - 취소, 권한 거부, OAuth 클라이언트 미등록 등 구체적 에러 메시지 피드백.

### 3.5. 메인 앱 생명주기 및 AppBar 동기화 연동 (`lib/main.dart`)
- `_triggerBackgroundAutoSync()`: 앱 실행 및 포그라운드 복귀(`resumed`) 시 세션 확인 후 캘린더/태스크 자동 동기화 및 24시간 주기 드라이브 자동 백업 실행.
- 캘린더 탭 및 할 일 탭 상단 AppBar에 각 기능이 활성화되었을 때만 수동 동기화(🔄) 버튼이 나타나도록 실시간 Notifier 구독.

---

## 4. 검증 및 결과

1. **정적 분석 검사 (`flutter analyze`)**:
   - `No issues found!` (에러 및 린트 경고 0건).
2. **인증 플로우 검증**:
   - 앱 구동 시 로그인 창이 강제로 뜨지 않음 확인.
   - 설정 화면에서 로그인 실패/취소 시 스위치가 On 되지 않고 실패 안내 스낵바가 정확히 출력됨 확인.
   - 권한 요청을 거부하더라도 다시 스위치를 켰을 때 영구 차단 없이 권한 요청 팝업이 재호출됨 확인.
3. **데이터 정합성 및 백업 검증**:
   - 태스크 동기화 시 외부 작성 메모가 지워지지 않고 구분선과 함께 안전하게 보존됨 확인.
   - 드라이브 백업 시 최대 5개 버전 유지 및 선택 복원 다이얼로그 정상 작동 확인.

---

## 2026-11-05: Google 캘린더 연동 오류 수정 및 사용자 친화적 에러 메시지 정돈

### 1. 문제 분석
- **Google Calendar API 미활성화 (403 Forbidden)**:
  - GCP 콘솔 프로젝트(`1069776834440`)에서 Tasks API는 켜져 있었으나 Google Calendar API(`calendar-json.googleapis.com`)가 활성화되어 있지 않아 403 오류 반환.
- **`cal.EventDateTime` 포맷 충돌**:
  - `dateTime: startDt.toUtc()`와 `timeZone: 'Asia/Seoul'`을 동시 전달하여 발생하던 API 400 오류 해결.
- **기술적 상세 오류 원문 노출**:
  - `DetailedApiRequestError(status: 403, ...)` 등 긴 URL 및 프로젝트 식별자가 포함된 원문 오류가 화면 스낵바에 그대로 출력되던 문제.

### 2. 개선 및 수정 내용
1. **오류 메시지 사용자 친화적 변환 (`GoogleSyncService.formatSyncError`)**:
   - GCP API 미활성화 시: `"Google Cloud Console에서 [기능명] API 활성화가 필요합니다."`로 간결하게 요약 표시.
   - 접근 권한 거부 시: `"[기능명] 접근 권한이 없거나 거부되었습니다."`
   - 네트워크 이상 시: `"네트워크 연결 상태를 확인한 후 다시 시도해 주세요."`
   - 긴 시스템 URL, 패키지 내부 예외 클래스명, 프로젝트 ID 등의 원문 노출 전면 차단.
2. **양방향 동기화 및 목(Mock) ID 정제**:
   - 목(Mock) 폴백 완전 제거 및 기존 목 ID(`gcal_`, `gtask_`) 자동 감지 후 실제 Google ID로 재발급 `insert`.
   - `CalendarScreen` 및 `TodoScreen`에서 변경 시 실시간 자동 동기화 트리거 바인딩.

### 3. 검증 결과
- `flutter analyze` 0 issues (No issues found!).

---

## 2026-11-05: 일정 탭 한달 뷰 및 축소 애니메이션 시 하단 4.3px 오버플로우 오류 해결

### 1. 문제 원인 분석
- **현상**: 일정 탭에서 한달 뷰(`_CalendarHeightStage.month`) 표시 중이거나 드래그/단계 변경 애니메이션으로 캘린더 높이가 줄어들 때 `A RenderFlex overflowed by 4.3 pixels on the bottom.` 오류 발생.
- **원인**:
  - `markerBuilder`에서 날짜 셀 상단 패딩을 고정 `top: 32`로 지정하여, 한달 뷰 및 축소 애니메이션 시 셀 높이(`rowHeight`)가 38~50px 수준으로 작아지면 배지 렌더링에 남는 높이가 6~18px에 불과해짐.
  - 이 좁은 공간에 `events.take(2)`로 최대 2개의 텍스트 칩 배지(높이 약 22px 이상)를 `Column`으로 렌더링하면서, 남은 공간(약 16px) 대비 약 4.3px 초과 발생.

### 2. 개선 및 수정 내용
1. **셀 높이(`rowHeight`) 비례 반응형 상단 오프셋 및 높이 계산**:
   - `topOffset = (rowHeight * 0.40).clamp(18.0, 27.0)`으로 날짜 숫자 영역과 배지 영역을 동적으로 분할.
   - `availableHeight = (rowHeight - topOffset).clamp(0.0, rowHeight)` 계산.
2. **높이에 따른 단계별 지능형 마커 렌더링**:
   - `availableHeight < 14.0` (극단적 축소/드래그 중): 텍스트 배지 대신 4px 원형 도트 마커로 표시하여 레이아웃 깨짐 원천 차단.
   - `14.0 <= availableHeight < 27.0` (일반적인 한달 뷰): 배지 1개 + 초과 건수(`+$extraCount`)로 표시하여 1줄 내에서 모든 일정 정보 전달 및 오버플로우 방지.
   - `availableHeight >= 27.0` (확장 뷰 및 2주 뷰): 배지 최대 2개 렌더링.
3. **오버플로우 방어막 구축**:
   - 배지 컨테이너의 높이를 `height: 12.5`, 텍스트 `fontSize: 8.5, height: 1.1`로 콤팩트하게 정렬.
   - `ClipRect` + `SizedBox` + `SingleChildScrollView(physics: NeverScrollableScrollPhysics())`로 감싸 시스템 글꼴 크기 변경이나 프레임 단위 애니메이션 중간에도 RenderFlex overflow 경고가 구조적으로 발생하지 않도록 완전 방어.

---

## 2026-11-05: 동기화 버튼 쓰로틀링(5초) 및 백그라운드 디바운스(2초) 구현

### 1. 요구사항 및 문제 배경
- **과도한 연속 호출 방지**: 사용자가 캘린더나 할 일 상단/내부 동기화 버튼(🔄)을 빠르게 연속 클릭할 경우 불필요한 구글 API 호출 및 네트워크 트래픽이 낭비되는 문제 방지.
- **백그라운드 자동 동기화 경합 방지**: 체크박스를 연속으로 체크하거나 일정 정보를 연속 수정할 때마다 즉시 동기화가 발생하여 구글 서버와의 레이스 컨디션 및 쿼터 초과 위험 완화.

### 2. 개선 및 수정 내용
1. **수동 동기화 버튼 5초 쓰로틀링 (쿨다운) 적용**:
   - 캘린더 및 할 일 수동 동기화 완료 시점(`finally`)을 기준으로 5초간(`_syncThrottleDuration = Duration(seconds: 5)`) 쿨다운 타이머 가동.
   - 5초 쿨다운 도중 사용자가 다시 동기화 버튼을 누르면 `HapticFeedback.lightImpact()`와 함께 `"방금 동기화되었습니다. 잠시 후 다시 시도해 주세요."` 안내 스낵바를 띄우고 즉시 차단.
   - 동기화 진행 중에는 기존과 동일하게 프로그레스 인디케이터 표시 및 버튼 비활성화(`onPressed: null`) 유지.
2. **백그라운드 자동 동기화 2초 디바운스 (Debounce) 분리 적용**:
   - `_scheduleCalendarAutoSync()` 및 `_scheduleTasksAutoSync()` 구현.
   - 일정이나 할 일이 등록/수정/삭제될 때 즉시 네트워크 요청을 보내지 않고 2초간(`Duration(seconds: 2)`) 타이머 대기.
   - 2초 이내 추가 수정이 발생하면 기존 타이머를 취소하고 새로 2초를 기다려 최종 상태만 1회 백그라운드 동기화(`silent: true`) 수행.
3. **생명주기 안전성 보장**:
   - `dispose()`에서 `_calendarDebounceTimer` 및 `_tasksDebounceTimer` 취소 처리로 메모리 누수 방지.

### 3. 검증 결과
- `flutter analyze` 0 issues (No issues found!).
