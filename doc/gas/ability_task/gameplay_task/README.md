# GameplayTask

> 소스: `Engine/Source/Runtime/GameplayTasks/`

GAS와 무관한 **범용 비동기 태스크 시스템**. `UAbilityTask`의 베이스 클래스.

| 파일 | 내용 |
|---|---|
| [01 개요](01_overview.md) | 왜 존재하는가, 클래스 구조 |
| [02 핵심 API](02_api.md) | ReadyForActivation / Activate / EndTask / OnDestroy / TickTask / bSimulatedTask |
| [03 생명주기](03_lifecycle.md) | 생성부터 소멸까지 전체 흐름 |
| [04 GameplayTasksComponent](04_tasks_component.md) | 태스크 관리 컴포넌트 내부 구조 |
| [05 복제](05_replication.md) | bSimulatedTask 패턴, RootMotion 예시, Lyra 서버 전용 태스크, NetworkSyncPoint |
