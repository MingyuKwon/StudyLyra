# 플러그인 ini에서 태그 로드

> **GASDoc**: 4.2.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-gt-loadfromplugin"></a>
### 플러그인 자체 .ini 파일에 정의된 GameplayTag를 엔진 시작 시 자동으로 로드하는 방법은?

플러그인의 `StartupModule()`에서 `UGameplayTagsManager::AddTagIniSearchPath()`로 태그 .ini 디렉터리를 등록한다. 엔진이 시작될 때 해당 경로의 .ini 파일을 자동으로 읽어 프로젝트에 태그를 로드한다.

```c++
void FCommonConversationRuntimeModule::StartupModule()
{
    TSharedPtr<IPlugin> ThisPlugin = IPluginManager::Get().FindPlugin(TEXT("CommonConversation"));
    check(ThisPlugin.IsValid());

    UGameplayTagsManager::Get().AddTagIniSearchPath(ThisPlugin->GetBaseDir() / TEXT("Config") / TEXT("Tags"));

    //...
}
```

위 예시는 `Plugins\CommonConversation\Config\Tags` 디렉터리를 등록한다.

---
