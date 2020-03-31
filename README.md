<p align="center">
<!--<img src="scoop.png" alt="Long live Scoop!"/>-->
    <h1 align="center">Scoop</h1>
</p>
<p align="center">
<b><a href="https://github.com/L-Trump/scoop-CHS#Scoop可以做什么">功能</a></b>
|
<b><a href="https://github.com/L-Trump/scoop-CHS#安装">安装</a></b>
|
<b><a href="https://github.com/lukesampson/scoop/wiki">文档</a></b>
</p>
<p align="center" >
    <a href="https://github.com/L-Trump/scoop-CHS">
        <img src="https://img.shields.io/github/languages/code-size/L-Trump/Scoop-CHS.svg" alt="Code Size" />
    </a>
    <a href="https://github.com/L-Trump/scoop-CHS">
        <img src="https://img.shields.io/github/repo-size/L-Trump/Scoop-CHS.svg" alt="Repository size" />
    </a><!--
    <a href="https://ci.appveyor.com/project/lukesampson/scoop">
        <img src="https://ci.appveyor.com/api/projects/status/05foxatmrqo0l788?svg=true" alt="Build Status" />
    </a>
    <a href="https://discord.gg/s9yRQHt">
        <img src="https://img.shields.io/badge/chat-on%20discord-7289DA.svg" alt="Discord Chat" />
    </a>
    <a href="https://gitter.im/lukesampson/scoop">
        <img src="https://badges.gitter.im/lukesampson/scoop.png" alt="Gitter Chat" />
    </a>-->
    <a href="https://github.com/L-Trump/Scoop-CHS/blob/master/LICENSE">
        <img src="https://img.shields.io/github/license/L-Trump/Scoop-CHS.svg" alt="License" />
    </a>
</p>

Scoop是一个Windows上的命令行包管理器，

更详细教程请移步[我的博客](https://blog.xqh.ma/_posts/2020-03-09-Windows%E5%8C%85%E7%AE%A1%E7%90%86%E5%99%A8-Scoop%E7%9A%84%E5%AE%89%E8%A3%85%E4%B8%8E%E4%BD%BF%E7%94%A8&%E5%B8%B8%E7%94%A8%E8%BD%AF%E4%BB%B6%E6%8E%A8%E8%8D%90/)

## 在开始之前

由于Powershell控制台对中文编码的支持默认使用GBK字符页，因此Scoop的所有脚本文件已被转成UTF-8-BOM格式，支持GBK页显示，如需使用UTF-8版本见分支[utf8](https://github.com/L-Trump/scoop-CHS/tree/utf8)

## 从英文版Scoop升级

**你不需要重装Scoop**！真的！

打开`C:\Users\<username>\.config\scoop\config.json`，修改SCOOP_REPO项为本项目地址：

![Snipaste_2020-03-28_12-16-10.png](https://xqhma.oss-cn-hangzhou.aliyuncs.com/image/Snipaste_2020-03-28_12-16-10.png)

然后执行`scoop update`即可。如果你需要使用UTF8，那么把下面的master换成utf8即可

## 和英文版的区别

- 是中文的了（废话）
- 为`Manifest`中的`checkver`增加了`cookie`和并为`bin\checkver.ps1`增加了`-cookie`以及`-useragent`选项
- 在`Manifest`中增加主项`nocurrent`，在设定为`true`时（默认为`false`，是布尔值）将不使用current软链接，以此解决某些软件(e.g. [Adobe After Effects](https://github.com/L-Trump/scoop-raresoft/blob/master/bucket/AdobeAfterEffectsCC2020.json))识别软链接的问题
- 解决了shim链接启动某些应用时控制台窗口一直停留的问题，为此在`Manifest`中添加了项`wait_process`，设定为`true`时（默认为`false`，是布尔值）shim窗口将等待进程结束再关闭，否则调用进程后就关闭。

## Scoop可以做什么

Scoop 能够十分方便地从命令控制台Powershell中安装软件，它尝试消除以下情况

- 权限弹出窗口
- GUI向导式安装程序
- 安装过多程序后乱七八糟的目录结构
- 安装或者卸载应用后那些不令人愉快地副作用
- 各种麻烦的依赖
- 需要执行额外的设置步骤才能运行的程序（如要求设置环境变量）

Scoop的脚本配置十分齐全，你可以有多种方式来安装应用 e.g.:

```powershell
scoop install sudo
sudo scoop install 7zip git openssh --global
scoop install aria2 curl grep sed less touch
scoop install python ruby go perl
```

如果你构建了你自己的软件并想要其他人使用, Scoop是其他类型安装程序的替代品 (e.g. MSI 或 InnoSetup) — 你只需要把你的程序打包成压缩包，然后写一个Json格式的文件来告诉Scoop基本信息就行。

## 系统环境

- Windows 7 SP1+ / Windows Server 2008+

- [PowerShell 5](https://aka.ms/wmf5download) (或者更新版本, 包括 [PowerShell Core](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows?view=powershell-6)) 以及 [.NET Framework 4.5](https://www.microsoft.com/net/download) (或者更新版本)

- Powershell对当前用户来说必须可用

   e.g. `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

## 安装

运行下面命令将Scoop安装到默认目录 (`C:\Users\<user>\scoop`)

```powershell
Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/L-Trump/Scoop-CHS/master/bin/install.ps1')

# 或者简写为
iwr -useb https://raw.githubusercontent.com/L-Trump/Scoop-CHS/master/bin/install.ps1 | iex
```

安装完后使用`scoop help`来获取帮助

默认情况下所有用户会安装scoop软件到各自的用户目录 `C:\Users\<user>\scoop`.
进行全局安装的软件 (`--global`) 将会存在于 `C:\ProgramData\scoop`.
这些设置可以通过调整环境变量来更改

### 通过环境变量`SCOOP`将Scoop安装到自定义目录

```powershell
$env:SCOOP='D:\Applications\Scoop'
[Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')
# 然后安装Scoop
```

### 通过环境变量`SCOOP_GLOBAL`将全局应用安装到自定义目录

```powershell
$env:SCOOP_GLOBAL='F:\GlobalScoopApps'
[Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', $env:SCOOP_GLOBAL, 'Machine')
# run the installer
```

## [Documentation](https://github.com/L-Trump/scoop-CHS/wiki)

## 通过 `aria2` 进行多线程下载

Scoop能够通过Aria2进行多线程下载来提速，先安装Aria2：

```powershell
scoop install aria2
```

你可以通过`scoop config`命令来更改一些Aria2设置

- aria2-enabled (default: true)
- [aria2-retry-wait](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-retry-wait) (default: 2)
- [aria2-split](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-s) (default: 5)
- [aria2-max-connection-per-server](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-x) (default: 5)
- [aria2-min-split-size](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-k) (default: 5M)

## 灵感来源

- [Homebrew](http://mxcl.github.io/homebrew/)
- [sub](https://github.com/37signals/sub#readme)

## Scoop可以安装哪些应用?

Scoop兼容性性最佳的通常是 "便携式" 应用: 即解压后就能独立运行并且不依赖于额外的外部条件，如注册表、额外的应用目录等。

而另外一些常见的应用, Scoop也可以安装（当然也可以卸载）.

Scoop也支持单文件和Powershell脚本. 例如 [runat](https://github.com/ScoopInstaller/Main/blob/master/bucket/runat.json): 这只是 GitHub gist.

## 内置的Bucket仓库

以下仓库可以直接添加:

- [main](https://github.com/ScoopInstaller/Main) - Scoop默认仓库，里面基本都是CLI命令行应用
- [extras](https://github.com/lukesampson/scoop-extras) - 不符合Main仓库[标准](https://github.com/lukesampson/scoop/wiki/Criteria-for-including-apps-in-the-main-bucket)的应用很多都到了这里
- [raresoft](https://github.com/L-Trump/scoop-raresoft) - 夹带私货
- [games](https://github.com/Calinou/scoop-games) - 开源/免费的游戏以及与游戏相关的应用
- [nerd-fonts](https://github.com/matthewjberger/scoop-nerd-fonts) -  Nerd 字体库
- [nirsoft](https://github.com/kodybrown/scoop-nirsoft) - [250](https://github.com/rasa/scoop-directory/blob/master/by-score.md#MCOfficer_scoop-nirsoft) [Nirsoft](https://nirsoft.net) 应用的集合
- [java](https://github.com/ScoopInstaller/Java) - Oracle Java, OpenJDK, Zulu, ojdkbuild, AdoptOpenJDK, Amazon Corretto, BellSoft Liberica & SapMachine的安装仓库
- [jetbrains](https://github.com/Ash258/Scoop-JetBrains) - 所有 JetBrains 程序和IDE的集合
<!-- * [nightlies](https://github.com/ScoopInstaller/Nightlies) - No longer used -->
- [nonportable](https://github.com/TheRandomLabs/scoop-nonportable) - 非便携式应用 (也许需要 UAC 权限)
- [php](https://github.com/ScoopInstaller/PHP) - 绝大部分版本PHP的安装仓库
- [versions](https://github.com/ScoopInstaller/Versions) - 在其他仓库中找到的应用的一些额外版本

Main主仓库是默认添加的，如果需要添加其他内置仓库:
```
scoop bucket add 仓库名
```
例如添加Extras仓库:
```
scoop bucket add extras
```

## 其他应用

其他存在于Github上的Scoop仓库可以在这里找到 [Scoop Directory](https://github.com/rasa/scoop-directory).
