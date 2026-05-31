# 08. 전체 흐름 — Registry 생성부터 화면 표시까지

> 소스:
> `Plugins/GameSettings/Source/Private/Registry/GameSettingRegistry.cpp`
> `Plugins/GameSettings/Source/Private/Widgets/GameSettingScreen.cpp`
> `Plugins/GameSettings/Source/Private/Widgets/GameSettingPanel.cpp`

---

## 1단계 — Registry 생성 및 설정 트리 구성

화면이 처음 활성화될 때 `GetOrCreateRegistry()`가 호출되면서 시작된다.

```
Screen->GetOrCreateRegistry()
    └─ CreateRegistry()                          // 서브클래스 구현 (Lyra: ULyraGameSettingRegistry)
            └─ NewObject<ULyraGameSettingRegistry>()
            └─ Registry->Initialize(LocalPlayer)
                    └─ OnInitialize(LocalPlayer)  // 서브클래스 구현
                            └─ RegisterSetting(VideoCollection)
                            └─ RegisterSetting(AudioCollection)
                            └─ RegisterSetting(InputCollection)
```

`RegisterSetting()` 내부:

```
RegisterSetting(VideoCollection)
    ├─ TopLevelSettings.Add(VideoCollection)      // 루트 목록에 추가
    └─ RegisterInnerSettings(VideoCollection)     // 전체 재귀 등록
            ├─ RegisteredSettings.Add(VideoCollection)
            ├─ Setting->OnSettingChangedEvent 구독  (Registry가 변경 감지)
            └─ for ChildSetting in VideoCollection->GetChildSettings():
                    RegisterInnerSettings(ChildSetting)   // 하위까지 재귀
                        ├─ RegisteredSettings.Add(ChildSetting)
                        └─ ...
```

완료 후 상태:

```
TopLevelSettings    = [VideoCollection, AudioCollection, InputCollection]
RegisteredSettings  = [VideoCollection, 해상도Setting, VSync Setting,
                        AudioCollection, 볼륨Setting, ...,
                        InputCollection, IA_Jump Setting, IA_Move Setting, ...]
```

---

## 2단계 — Panel에 Registry 연결

```
GetOrCreateRegistry()
    └─ Settings_Panel->SetRegistry(NewRegistry)
            └─ Registry = NewRegistry
            └─ RegisterRegistryEvents()           // EditCondition·Navigation 이벤트 구독
            └─ RefreshSettingsList()              // 목록 갱신 예약 (다음 틱)
```

---

## 3단계 — 초기 목록 표시 (FilterState 기본값)

`RefreshSettingsList()`는 다음 틱에 실행된다. FilterState가 기본값(루트 없음)이므로 `TopLevelSettings`가 탐색 기준점이 된다.

```
RefreshSettingsList()
    └─ Registry->GetSettingsForFilter(FilterState, VisibleSettings)
            └─ RootSettings = TopLevelSettings    // 루트 미지정 → TopLevel 사용
            └─ for Setting in RootSettings:
                    if Collection → Collection->GetSettingsForFilter() // 내부 재귀 탐색
                    else         → VisibleSettings.Add(Setting)
    └─ ListView->SetListItems(VisibleSettings)
            └─ 각 항목에 ListEntry 위젯 할당
            └─ ListEntry->SetSetting(Setting)     // Model-View 연결
```

초기 `VisibleSettings`에는 TopLevelSettings 하위의 **모든 Setting**이 들어간다.  
실제로는 Blueprint가 화면 진입 직후 특정 탭을 선택해 FilterState를 교체하므로,  
이 초기 상태가 그대로 보이는 경우는 드물다.

---

## 4단계 — 탭 클릭 (FilterState 교체)

Blueprint에서 탭 버튼을 누르면 `NavigateToSettings()`를 호출한다.

```
[탭 "비디오" 클릭]
Screen->NavigateToSettings({"VideoSection"})
    └─ Registry->FindSettingByDevNameChecked("VideoSection")  // RegisteredSettings 검색
    └─ FilterState.AddSettingToRootList(VideoCollection)      // 루트를 VideoCollection으로 교체
    └─ Panel->SetFilterState(FilterState)
            └─ FilterNavigationStack.Reset()                  // 네비게이션 스택 초기화
            └─ RefreshSettingsList()

RefreshSettingsList()
    └─ Registry->GetSettingsForFilter(FilterState, VisibleSettings)
            └─ RootSettings = FilterState.GetSettingRootList()  // [VideoCollection]
            └─ VideoCollection->GetSettingsForFilter()          // 비디오 항목만 탐색
    └─ ListView->SetListItems(VisibleSettings)                  // 비디오 항목만 표시
```

---

## 5단계 — CollectionPage 클릭 (하위 페이지 진입)

```
[CollectionPage "키보드 바인딩" 클릭]
Panel->HandleSettingNavigation(KeyboardPage)
    └─ FilterNavigationStack.Push(현재 FilterState)  // 현재 상태 저장
    └─ NewFilterState.AddSettingToRootList(KeyboardPage)
    └─ SetFilterState(NewFilterState, bClearNavigationStack=false)
            └─ RefreshSettingsList()                 // 키보드 바인딩 항목만 표시
```

---

## 6단계 — 뒤로가기

```
Screen->AttemptToPopNavigation()
    └─ Panel->CanPopNavigationStack()  // FilterNavigationStack.Num() > 0
    └─ Panel->PopNavigationStack()
            └─ FilterState = FilterNavigationStack.Pop()  // 이전 FilterState 복원
            └─ RefreshSettingsList()                       // 이전 목록 다시 표시
```

---

## 전체 요약

```
[화면 열기]
GetOrCreateRegistry()
  → Registry::OnInitialize()
      → RegisterSetting() × N        TopLevelSettings + RegisteredSettings 구성
  → Panel::SetRegistry()
      → RefreshSettingsList()         FilterState 기본값 → TopLevel 전체 표시

[탭 클릭]
NavigateToSettings("VideoSection")
  → FilterState 루트 = VideoCollection
  → RefreshSettingsList()             비디오 항목만 표시

[CollectionPage 클릭]
HandleSettingNavigation(Page)
  → FilterNavigationStack.Push()
  → FilterState 루트 = Page
  → RefreshSettingsList()             하위 항목만 표시

[뒤로가기]
PopNavigationStack()
  → FilterState = Stack.Pop()
  → RefreshSettingsList()             이전 목록 복원
```
