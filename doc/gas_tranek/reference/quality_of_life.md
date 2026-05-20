# QoL 제안

> **GASDoc**: 8 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="qol"></a>
## GAS 작업 효율을 높이기 위한 편의성 개선 방법에는 어떤 것들이 있는가?

<a name="qol-gameplayeffectcontainers"></a>
### GameplayEffectContainer는 무엇이며 발사체 GE 전달 패턴에 어떻게 적합한가?

GameplayEffectSpec, TargetData, 간단한 타겟팅 기능을 하나의 구조체로 묶은 래퍼다. GA에서 발사체를 스폰할 때 GE Spec을 발사체에 전달하고, 충돌 시 꺼내서 적용하는 패턴에 매우 적합하다.

<a name="qol-asynctasksascdelegates"></a>
### Blueprint AsyncTask를 이용해 UMG Widget에서 ASC 델리게이트를 직접 바인딩하는 방법은?

C++로 Blueprint AsyncTask를 만들면 ASC의 주요 변경 델리게이트를 UMG 블루프린트 그래프에서 직접 바인딩할 수 있다. 위젯이 소멸될 때 반드시 수동으로 파괴해야 한다. 그렇지 않으면 메모리에 영구적으로 남는다.

샘플 프로젝트에 포함된 세 가지 AsyncTask:

| AsyncTask | 감지 대상 |
|---|---|
| Listen for Attribute Changes | Attribute 값 변경 |
| Listen for Cooldown Change | 쿨다운 시작·종료 |
| Listen for GameplayEffect Stack Change | GE 스택 수 변경 |

---
