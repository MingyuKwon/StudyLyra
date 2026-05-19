# QoL 제안

> **GASDoc**: 8 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="qol"></a>
## 8. 편의성(Quality of Life) 제안

<a name="qol-gameplayeffectcontainers"></a>
### 8.1 Gameplay Effect Containers

GameplayEffectContainers는 GameplayEffectSpec, TargetData, 간단한 타겟팅 기능과 관련 기능들을 하나의 사용하기 쉬운 구조체로 묶은 것이다. GameplayAbility에서 발사체를 스폰할 때 GameplayEffectSpec을 전달하고, 나중에 발사체 충돌 시 적용하는 패턴에 매우 적합하다.

<a name="qol-asynctasksascdelegates"></a>
### 8.2 ASC 델리게이트에 바인딩하는 Blueprint AsyncTask

특히 UI용 UMG Widget을 설계할 때처럼 디자이너 친화적인 이터레이션 속도를 높이기 위해, C++로 Blueprint AsyncTask를 만들어 ASC의 주요 변경 델리게이트를 UMG Blueprint 그래프에서 직접 바인딩할 수 있다. 단, 위젯이 소멸될 때처럼 더 이상 필요 없어지면 반드시 수동으로 파괴해야 한다. 그렇지 않으면 메모리에 영구적으로 남는다. 샘플 프로젝트에는 세 가지 Blueprint AsyncTask가 포함되어 있다.

Attribute 변경 감지:

![Listen for Attributes Changes BP Node](https://github.com/tranek/GASDocumentation/raw/master/Images/attributeschange.png)

쿨다운 변경 감지:

![Listen for Cooldown Change BP Node](https://github.com/tranek/GASDocumentation/raw/master/Images/cooldownchange.png)

GE 스택 변경 감지:

![Listen for GameplayEffect Stack Change BP Node](https://github.com/tranek/GASDocumentation/raw/master/Images/gestackchange.png)

---

