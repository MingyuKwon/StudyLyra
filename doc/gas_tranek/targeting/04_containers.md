# GE Container Targeting

> **GASDoc**: 4.11.5 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-targeting-containers"></a>
#### GE Container 타게팅은 TargetActor 방식과 비교해 어떤 장단점이 있는가?

`GameplayEffectContainers`는 `TargetData`를 생성하는 선택적이고 효율적인 수단을 내장하고 있다. 이 타게팅은 클라이언트와 서버 양쪽에서 `EffectContainer`가 적용될 때 즉시 실행된다. `TargetActors`보다 효율적인 이유는 타게팅 오브젝트의 CDO에서 실행되기 때문에(`Actor`의 스폰 및 파괴가 없음)이지만, 플레이어 입력을 받지 않고, 확인 없이 즉시 발생하며, 취소할 수 없고, 클라이언트에서 서버로 데이터를 전송할 수 없다는 단점이 있다(양쪽에서 독립적으로 데이터를 생성한다). 즉각적인 트레이스와 콜리전 오버랩에 잘 맞는다. Epic의 [Action RPG Sample Project](https://www.unrealengine.com/marketplace/en-US/product/action-rpg)는 컨테이너에서 두 가지 예시 타게팅 타입을 포함한다 — 어빌리티 소유자를 타겟으로 하는 방식과 이벤트에서 `TargetData`를 가져오는 방식. 또한 Blueprint에서 플레이어로부터 일정 오프셋(자식 Blueprint 클래스가 설정)만큼 떨어진 위치에 즉각적인 구체 트레이스를 수행하는 구현도 포함한다. `URPGTargetType`을 C++ 또는 Blueprint에서 서브클래싱하면 자신만의 커스텀 타게팅 타입을 만들 수 있다.

---

