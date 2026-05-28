# 키 바인딩 변경 (런타임 리맵핑)

> 이 문서는 상세 폴더로 이전되었습니다.
>
> **→ [keybinding/ 폴더 전체 문서 보기](keybinding/README.md)**

---

## 빠른 링크

| 문서 | 내용 |
|------|------|
| [01. 전체 아키텍처](keybinding/01_architecture.md) | 왜 이렇게 설계했는가, 계층 분리 의도, 엔진 vs Lyra |
| [02. 데이터 계층](keybinding/02_data_layer.md) | UserSettings / Profile / KeyMappingRow / PlayerKeyMapping 구조 |
| [03. IMC 등록](keybinding/03_imc_registration.md) | 어떤 키가 리맵 가능한가, bRegisterWithSettings |
| [04. 설정 레지스트리](keybinding/04_settings_registry.md) | 설정 화면 항목 동적 생성, ULyraSettingKeyboardInput |
| [05. UI 위젯](keybinding/05_ui_widget.md) | PressAnyKey 모달, 중복 경고, 상태 다이어그램 |
| [06. 적용 & 저장](keybinding/06_apply_and_save.md) | MapPlayerKey → ApplySettings → SaveSettings 3단계 |
