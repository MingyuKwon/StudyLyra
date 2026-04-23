# 플러그인 ini에서 태그 로드

> **GASDoc**: 4.2.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-gt-loadfromplugin"></a>
### 4.2.2 Loading Gameplay Tags from Plugin .ini Files
If you create a plugin with its own .ini files with `GameplayTags`, you can load that plugin's `GameplayTag` .ini directory in your plugin's `StartupModule()` function.

For example, this is how the CommonConversation plugin that comes with Unreal Engine does it:

```c++
void FCommonConversationRuntimeModule::StartupModule()
{
	TSharedPtr<IPlugin> ThisPlugin = IPluginManager::Get().FindPlugin(TEXT("CommonConversation"));
	check(ThisPlugin.IsValid());
	
	UGameplayTagsManager::Get().AddTagIniSearchPath(ThisPlugin->GetBaseDir() / TEXT("Config") / TEXT("Tags"));

	//...
}
```

This would look for the directory `Plugins\CommonConversation\Config\Tags` and load any .ini files with `GameplayTags` in them into your project when the Engine starts up if the plugin is enabled.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
