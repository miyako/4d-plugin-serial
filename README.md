![version](https://img.shields.io/badge/version-18%2B-EB8E5F)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-serial)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-serial/total)

# 4d-plugin-serial
[armadsen/ORSSerialPort 2.1.0](https://github.com/armadsen/ORSSerialPort/releases/tag/2.1.0)を使用しています。

ただし，シリアルポート付け外しの通知を受け取るため，``CFRunLoopGetCurrent``を``CFRunLoopGetMain``に書き換えてビルドしました。

## 用途

標準コマンドの``RECEIVE BUFFER``は非Unicodeモードの遺物であり，BLOBに対応していません。

一方，``RECEIVE PACKET``はバックグランドで「待ち受け」することができません。

プラグインは，スリープの開始と解除・シリアルポートの取り外しと取り付けに反応し，バイナリデータを扱うことができます。

## 例題

```4d
$ports:=SERIAL Get available ports

$usbserial:=$ports.query("path == :1"; "/dev/cu.usbserial@")

If ($usbserial.length#0)
	
	$path:=$usbserial[0].path
	
	$options:=New object
	
	$status:=SERIAL Open path($path; $options; "serial_receive_method")
	
	var $data : Blob
	
	SET BLOB SIZE($data; 10)
	
	$status:=SERIAL Send data($path; $data)
	
	$status:=SERIAL Close path($path)
	
End if 
```

---

## SERIAL Get available ports

```4d
ports:=SERIAL Get available ports()
```

|パラメーター|データ型|説明|
|-|-|-|
|ports[]|Collection|シリアルポート|
|ports[]|Collection||
|ports[].allowsNonStandardBaudRates|Boolean||
|ports[].baudRate|Number||
|ports[].CTS|Boolean||
|ports[].DCD|Boolean||
|ports[].DSR|Boolean||
|ports[].DTR|Boolean||
|ports[].isOpen|Boolean||
|ports[].name|Text||
|ports[].numberOfStopBits|Number||
|ports[].parity|Text|`none` `odd` `even`|
|ports[].path|Text||
|ports[].RTS|Boolean||
|ports[].shouldEchoReceivedData|Boolean||
|ports[].usesDCDOutputFlowControl|Boolean||
|ports[].usesDTRDSRFlowControl|Boolean||
|ports[].usesRTSCTSFlowControl|Boolean||

## SERIAL Open path

```4d
status:=SERIAL Open path(path{;options})
```

|パラメーター|データ型|説明|
|-|-|-|
|status|Object||
|status.success|Boolean||
|status.port|Object||

シリアル通信コールバック実行用のプロセス`$SERIAL`が起動します。

<img width="852" alt="process" src="https://user-images.githubusercontent.com/1725068/152618331-55247ca8-ac9f-42e9-881d-3050dacec386.png">

シリアル通信を受信すると，下記のパラメーターでコールバックメソッドが実行されます。

```4d
#DECLARE($path : Text; $data : Blob)
```

## SERIAL Close path

```4d
status:=SERIAL Close path(path)
```

|パラメーター|データ型|説明|
|-|-|-|
|status|Object||
|status.success|Boolean||

## SERIAL Send data

```4d
status:=SERIAL Send data(path)
```

|パラメーター|データ型|説明|
|-|-|-|
|status|Object||
|status.success|Boolean||

## 動作検証

|USB⇄RS-232Cコンバーター|チップ|VCM Driver|macOS|4D|対応|
|-|-|-|-|-|:-:|
|[REX-USB60F](http://www.ratocsystems.com/products/subpage/convert/usb60f_siyou.html)|[FTDI](https://ftdichip.com/drivers/vcp-drivers/)|2.4.4|Catalina|19|OK|
||||Monterey x86_64|19||
|||2.4.4|Monterey arm64|19|×|
||||Monterey arm64|19||
