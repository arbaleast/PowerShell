# 鈿?PowerShell 閰嶇疆

### 鈱笍 妯″潡鍖?PowerShell 閰嶇疆锛屾敮鎸?tmux 浼氳瘽绠＄悊銆丼tarship 鎻愮ず绗﹀拰璺ㄥ钩鍙板伐鍏?

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

[English Version](./README.md) 路 [鎶ュ憡闂](https://github.com/arbaleast/PowerShell/issues) 路 [鍔熻兘寤鸿](https://github.com/arbaleast/PowerShell/issues)

---

## 鉁?鍔熻兘鐗圭偣

### 馃殌 鎬ц兘
- **鎳掑姞杞?* 鈥?tmux 妯″潡浠呭湪浣犻娆¤緭鍏?`sss` 鏃舵墠鍔犺浇
- **蹇€熷惎鍔?* 鈥?鏈€灏忓寲瓒宠抗锛屾绉掔骇鍔犺浇

### 馃洜锔?寮€鍙戣€呭伐鍏?
- **Starship 鎻愮ず绗?* 鈥?璺?Shell 鎻愮ず绗︼紝鏄剧ず git 涓婁笅鏂囥€丯ode 鐗堟湰
- **Fnm 闆嗘垚** 鈥?cd 鍒囨崲椤圭洰鏃惰嚜鍔ㄥ垏鎹?Node 鐗堟湰
- **PSReadLine** 鈥?鍩轰簬鍘嗗彶鐨勮嚜鍔ㄨˉ鍏紝鏇村ソ鐨勫鑸綋楠?

### 馃敡 杩滅▼浼氳瘽
- **Tmux 绠＄悊鍣?* 鈥?浜や簰寮忚彍鍗曠鐞嗚繙绋?tmux 浼氳瘽
- **蹇€熻繛鎺?* 鈥?`sss <host>` 绔嬪嵆闄勫姞/鎭㈠/鍒涘缓浼氳瘽

### 馃搧 鏃ュ父浼樺寲
- **蹇嵎鍒悕** 鈥?`ll`銆乣..`銆乣~`銆乣which` 鍔犻€熷鑸?
- **妯″潡鍖栫粨鏋?* 鈥?鏄撲簬瀹氬埗锛屾槗浜庣淮鎶?

---

## 馃搨 鐩綍缁撴瀯

```
PowerShell/
鈹?
鈹溾攢鈹€ Microsoft.PowerShell_profile.ps1   # 馃幆 涓诲叆鍙?鈥?鍔犺浇鎵€鏈夋ā鍧?
鈹溾攢鈹€ Config.ps1                       # 鈿欙笍  璺緞銆侀鑹层€侀敭鐩樺竷灞€
鈹溾攢鈹€ Alias.ps1                        # 馃敆 鍒悕锛歭l, .., ~, reload, which
鈹溾攢鈹€ Utils.ps1                        # 馃О 杈呭姪鍑芥暟锛歭ogo, 缂撳瓨, 瀵煎叆
鈹斺攢鈹€ Remote.ps1                       # 馃枼锔? Tmux 浼氳瘽绠＄悊鍣紙鎳掑姞杞斤級
```

---

## 馃殌 蹇€熷紑濮?

### 1锔忊儯 瀹夎渚濊禆

璇风‘淇濈郴缁熷凡瀹夎浠ヤ笅宸ュ叿锛?

| 宸ュ叿 | 鐢ㄩ€?| 瀹夎鎸囧崡 |
|------|------|----------|
| [Starship](https://starship.rs/) | 缇庤鎻愮ず绗︼紝甯?git 涓婁笅鏂?| [瀹夎](https://starship.rs/guide/#馃殌-installation) |
| [Fnm](https://github.com/Schniz/fnm) | 蹇€?Node 鐗堟湰绠＄悊鍣?| [瀹夎](https://github.com/Schniz/fnm#installation) |
| [tmux](https://github.com/tmux/tmux) | 杩滅▼浼氳瘽淇濇寔 | [瀹夎](https://github.com/tmux/tmux/wiki) |

### 2锔忊儯 寤虹珛鐩綍缁撴瀯

鎸変互涓嬬粨鏋勫垱寤虹洰褰曪紙璺緞鍙嚜琛岃皟鏁达級锛?

```
D:\Env\                    # 鈫?$UserScoop_ROOT锛堟牴鐩綍锛?
鈹溾攢鈹€ quotes.txt             # 鈫?鍚姩璇綍锛堝彲閫夛級
鈹斺攢鈹€ UserScoop\
    鈹斺攢鈹€ apps\              # 鈫?$UserScoop_APPS锛堝伐鍏风洰褰曪級
        鈹溾攢鈹€ starship\
        鈹?  鈹斺攢鈹€ current\
        鈹?      鈹斺攢鈹€ starship.exe
        鈹斺攢鈹€ fnm\
            鈹斺攢鈹€ current\
                鈹斺攢鈹€ fnm.exe
```

涔熷彲浠ヤ娇鐢ㄤ换鎰忚嚜瀹氫箟鏍硅矾寰勶紝涔嬪悗鍦?`Config.ps1` 涓慨鏀瑰嵆鍙€?

### 3锔忊儯 瀹夎閰嶇疆鏂囦欢

```powershell
# 姝ラ A锛氭煡鐪?PowerShell 閰嶇疆鐩綍
$PROFILE

# 姝ラ B锛氬皢鎵€鏈?.ps1 鏂囦欢澶嶅埗鍒伴厤缃洰褰?
#         灏?"D:\path\to\PowerShell" 鏇挎崲涓哄疄闄呭厠闅嗚矾寰?
Copy-Item -Path "D:\path\to\PowerShell\*.ps1" `
           -Destination (Split-Path $PROFILE -Parent) `
           -Force

# 姝ラ C锛氶噸鍚?PowerShell 鎴栨墽琛岋細
reload
```

### 4锔忊儯 鑷畾涔夐厤缃紙鍙€夛級

缂栬緫 `Config.ps1` 鍖归厤浣犵殑鐩綍缁撴瀯锛?

```powershell
# 鏍圭洰褰?鈥?quotes.txt 鎵€鍦ㄤ綅缃?
$global:UserScoop_ROOT = "D:\Env"

# 宸ュ叿鐩綍 鈥?Starship銆丗nm 绛夋墍鍦ㄤ綅缃?
$global:UserScoop_APPS = "$global:UserScoop_ROOT\UserScoop\apps"
```

棰滆壊鏂规鍜岄敭鐩樼爜閰嶇疆瑙佷笅鏂?[閰嶇疆璇存槑](#-閰嶇疆璇存槑)銆?

---

## 鈿?鍛戒护涓€瑙?

| 鍛戒护 | 璇存槑 |
|------|------|
| `sss <host>` | 馃枼锔?鎵撳紑 tmux 绠＄悊鍣?鈫?杩炴帴杩滅▼涓绘満 |
| `reload` | 馃攧 閲嶈浇 PowerShell 閰嶇疆 |
| `ll` | 馃搵 璇︾粏鍒楀嚭鏂囦欢 |
| `..` | 猬嗭笍 璺宠浆鍒扮埗鐩綍 |
| `~` | 馃彔 璺宠浆鍒颁富鐩綍 |
| `which <cmd>` | 馃攳 鏌ユ壘鍛戒护鎵€鍦ㄤ綅缃?|

---

## 馃枼锔?Tmux 绠＄悊鍣?

`sss <host>` 鎵撳紑浜や簰寮忚彍鍗曪細

```
鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
鈹?        REMOTE TMUX SESSION             鈹?
鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
鈹? 鈻? RESUME  鈥?闄勫姞鍒?'main'            鈹?
鈹?    ATTACH  鈥?浠呴檮鍔犲埌鐜版湁浼氳瘽         鈹?
鈹?    NEW     鈥?鍒涘缓鏂颁細璇?              鈹?
鈹?    LIST    鈥?鏌ョ湅鎵€鏈変細璇?             鈹?
鈹?    KILL    鈥?缁堟鎵€鏈?tmux            鈹?
鈹?    EXIT    鈥?杩斿洖鏈湴缁堢             鈹?
鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
```

**鎿嶄綔锛?* `鈫戔啌` 绉诲姩 路 `Enter` 纭 路 `q` 閫€鍑?

---

## 馃帹 閰嶇疆璇存槑

### 鐩綍璺緞

```powershell
$global:UserScoop_ROOT                  # 鏍圭洰褰曪紙quotes.txt 鍦ㄦ锛?
$global:UserScoop_APPS                 # 宸ュ叿鐩綍锛圫tarship銆丗nm 绛夛級
```

### 棰滆壊鏂规

```powershell
$global:UserScoop_CONF.Colors.Cyan  # 涓昏壊璋?
$global:UserScoop_CONF.Colors.Gray  # 娆¤鏂囧瓧
$global:UserScoop_CONF.Colors.Rst   # 閲嶇疆鏍煎紡
```

### 閿洏鐮?

```powershell
$global:UserScoop_CONF.Keys.Up    # 38
$global:UserScoop_CONF.Keys.Down  # 40
$global:UserScoop_CONF.Keys.Enter # 13
$global:UserScoop_CONF.Keys.Esc   # 27
```

### 闅忔満璇綍

鍦?`$UserScoop_ROOT\quotes.txt` 鏀剧疆璇綍鏂囦欢锛屾瘡鏉¤褰曠敤 `%` 鍒嗛殧锛?

```
浣犲枩娆㈢殑绗竴鏉¤褰?
%
鍙堜竴鍙ユ縺鍔辩殑璇?
%
```

姣忔鍚姩 PowerShell 鏃朵細闅忔満鏄剧ず涓€鏉¤褰曘€傗湪

---

## 馃摐 寮€婧愬崗璁?

MIT 漏 arbaleast

---

> 馃挕 **鎻愮ず锛?* 濡傛灉瑙夊緱鏈夌敤锛屽埆蹇樹簡 star 猸?
