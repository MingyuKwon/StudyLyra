# GameSettings 플러그인 기반

> `Plugins/GameSettings/` — Lyra가 설정 화면 전체를 구축하는 데 사용하는 Lyra 번들 플러그인.  
> 엔진 기본 제공이 아니라 Lyra 프로젝트에 포함된 플러그인이다.

---

## 문서 목록

| 번호 | 문서 | 핵심 내용 |
|------|------|-----------|
| [01](01_core_model.md) | UGameSetting base | DevName/Tags/EditCondition 연결, 초기화 lifecycle |
| [02](02_value_types.md) | Value 타입 계층 | Discrete/Scalar/Action — StoreInitial/Restore 동작 |
| [03](03_dynamic_value.md) | Dynamic Value + DataSource | DiscreteDynamic 서브클래스, FGameSettingDataSource 패턴 |
| [04](04_edit_condition.md) | EditCondition 시스템 | FGameSettingEditableState, WhenCondition/Platform/Player, FilterState |
| [05](05_registry_collection.md) | Registry & Collection | 설정 항목 등록/구조화, SaveChanges, ChangeTracker |
| [06](06_widget_system.md) | 위젯 시스템 | Screen/Panel/ListEntry 계층, Model-View 바인딩 방식 |
| [07](07_key_widgets.md) | 키 바인딩 전용 위젯 | PressAnyKey InputPreProcessor 구조, KeyAlreadyBoundWarning |

---

## 왜 이 플러그인이 존재하는가

설정 화면을 직접 만들면 두 가지 문제가 반복된다:

1. **값 관리 중복**: "화면 열 때 스냅샷 → 취소 시 복원"을 각 위젯이 각자 구현
2. **UI-데이터 결합**: 위젯이 실제 설정 값을 직접 들고 있어서 구조 변경이 어려움

GameSettings 플러그인은 이 두 문제를 **MVC 구조**로 해결한다:

```
Model  : UGameSetting / UGameSettingValue  — 설정 값과 상태
Control: UGameSettingRegistry              — 설정 항목 목록 관리, SaveChanges 진입점
View   : UGameSettingListEntry*            — 위젯, Model을 표시하고 이벤트 전달
```

---

## 전체 클래스 지도

```
[모델 계층]
UGameSetting                         ← base (DevName, Tags, EditCondition)
    ├─ UGameSettingValue             ← 취소 가능한 값 (StoreInitial / Restore)
    │       ├─ UGameSettingValueDiscrete   ← 선택지 목록
    │       │       └─ UGameSettingValueDiscreteDynamic  ← DataSource 기반 동적 선택지
    │       │               ├─ _Bool / _Number / _Enum / _Color / _Vector2D
    │       └─ UGameSettingValueScalar    ← 슬라이더
    ├─ UGameSettingAction            ← 버튼 클릭 동작 (값 없음)
    └─ UGameSettingCollection        ← 설정 그룹 컨테이너
            └─ UGameSettingCollectionPage ← 하위 페이지 이동 항목

[컨트롤 계층]
UGameSettingRegistry                 ← 설정 목록 소유, SaveChanges/Regenerate
FGameSettingRegistryChangeTracker    ← Dirty 상태 추적

[뷰 계층]
UGameSettingScreen                   ← 설정 화면 최상위 위젯
    └─ UGameSettingPanel             ← 설정 목록 + 상세 패널
            ├─ UGameSettingListView  ← ListView (UGameSettingListEntry* 바인딩)
            └─ UGameSettingDetailView← 선택된 항목 상세 설명

UGameSettingListEntryBase            ← 항목 위젯 base (IUserObjectListEntry)
    └─ UGameSettingListEntry_Setting
            ├─ *_Discrete            ← 좌우 버튼 선택
            ├─ *_Scalar              ← 슬라이더
            ├─ *_Action              ← 버튼 클릭
            └─ *_Navigation          ← 하위 페이지 이동
    (Lyra 확장)
    └─ ULyraSettingsListEntrySetting_KeyboardInput

[키 바인딩 특화]
UGameSettingPressAnyKey              ← 키 캡처 모달 (InputPreProcessor)
    └─ UKeyAlreadyBoundWarning       ← 중복 경고 모달

[EditCondition]
FGameSettingEditCondition            ← 비활성/숨김 조건 base
    ├─ FWhenCondition                ← 인라인 람다 조건
    ├─ FWhenPlatformHasTrait         ← 플랫폼 기능 태그 확인
    └─ FWhenPlayingAsPrimaryPlayer   ← 1P 확인
FGameSettingEditableState            ← visible/enabled/resetable 상태 결과
FGameSettingFilterState              ← 검색·필터 상태
```

---

## Lyra 확장 지점 요약

| GameSettings 플러그인 | Lyra 서브클래스 | 위치 |
|----------------------|----------------|------|
| `UGameSettingRegistry` | `ULyraGameSettingRegistry` | keybinding/04 |
| `UGameSettingValue` | `ULyraSettingKeyboardInput` | keybinding/04 |
| `UGameSettingListEntryBase` | `ULyraSettingsListEntrySetting_KeyboardInput` | keybinding/05 |
| `UGameSettingScreen` | `ULyraGameSettingScreen` | Lyra Settings UI |
| `UGameSettingPressAnyKey` | 그대로 사용 | — |
| `UKeyAlreadyBoundWarning` | 그대로 사용 | — |
