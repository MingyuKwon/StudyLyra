# 플러그인 ini에서 태그 로드

> **GASDoc**: 4.2.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-gt-loadfromplugin"></a>
### 4.2.2 플러그인 .ini 파일에서 GameplayTag 로드하기

자체 .ini 파일에 GameplayTag를 포함하는 플러그인을 만든다면, 플러그인의 `StartupModule()` 함수에서 해당 플러그인의 GameplayTag .ini 디렉터리를 로드할 수 있다.

예를 들어, 언리얼 엔진에 포함된 CommonConversation 플러그인은 다음과 같이 처리한다.

```c++
void FCommonConversationRuntimeModule::StartupModule()
{
	TSharedPtr<IPlugin> ThisPlugin = IPluginManager::Get().FindPlugin(TEXT("CommonConversation"));
	check(ThisPlugin.IsValid());
	
	UGameplayTagsManager::Get().AddTagIniSearchPath(ThisPlugin->GetBaseDir() / TEXT("Config") / TEXT("Tags"));

	//...
}
```

이 코드는 `Plugins\CommonConversation\Config\Tags` 디렉터리를 검색하여, 플러그인이 활성화된 상태에서 엔진이 시작될 때 해당 디렉터리의 GameplayTag가 담긴 .ini 파일을 프로젝트에 로드한다.

---

## 내 분석
