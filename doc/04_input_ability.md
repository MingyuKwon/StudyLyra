# 입력 → Ability 연결 흐름

## 전체 흐름

```
ULyraInputConfig (DataAsset)
  └─ InputAction ↔ GameplayTag (InputTag) 매핑 정의

ULyraHeroComponent
  └─ InputComponent 바인딩 설정
  └─ AbilityInputTagPressed(Tag) 호출

ULyraAbilitySystemComponent
  ├─ InputPressedSpecHandles  ← 이번 프레임에 눌린 Ability 핸들
  ├─ InputHeldSpecHandles     ← 입력 유지 중인 Ability 핸들
  └─ InputReleasedSpecHandles ← 이번 프레임에 놓인 Ability 핸들

ProcessAbilityInput() (매 프레임 호출)
  └─ 각 핸들을 순회하며 GA 활성화 / 입력 이벤트 전달
```

## 단계별 설명

### 1. ULyraInputConfig (DataAsset)
- `InputAction` 에셋과 `GameplayTag(InputTag)`를 1:1로 매핑하는 DataAsset
- Ability를 등록할 때 이 태그를 `InputTag`로 지정하면 입력과 자동 연결됨

### 2. ULyraHeroComponent
- Pawn이 초기화될 때 `InputComponent`에 바인딩을 설정
- 입력 발생 시 `ULyraAbilitySystemComponent::AbilityInputTagPressed(Tag)` 호출
- 입력 해제 시 `AbilityInputTagReleased(Tag)` 호출

### 3. ULyraAbilitySystemComponent
- 입력 태그에 매칭되는 `FGameplayAbilitySpec`을 찾아 핸들 큐에 추가
- `ProcessAbilityInput()`에서 매 프레임 큐를 소비하며 실제 GA 활성화

### 4. ActivationPolicy와의 연동
| Policy | 동작 |
|--------|------|
| `OnInputTriggered` | `InputPressedSpecHandles`에서 한 번 활성화 시도 |
| `WhileInputActive` | `InputHeldSpecHandles`에서 매 프레임 활성화 유지 시도 |
| `OnSpawn` | 입력과 무관, 아바타 등록 시 자동 활성화 |
