![version](https://img.shields.io/badge/version-18%2B-EB8E5F)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-serial)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-serial/total)

# 4d-plugin-serial
[armadsen/ORSSerialPort 2.1.0](https://github.com/armadsen/ORSSerialPort/releases/tag/2.1.0)を使用しています。

ただし，シリアルポート付け外しの通知を受け取るため，``CFRunLoopGetCurrent``を``CFRunLoopGetMain``に書き換えてビルドしました。

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

## SERIAL Close path

```4d
status:=SERIAL Close path(path)
```

## Discussion

The native command ``RECEIVE BUFFER`` does not support BLOB.

The native command ``RECEIVE PACKET`` does not listen indefinitely.

Neither native commands do not take advantage of newer multiprocessing (Grand Central Dispatch).

Neither native commands handle sleep events.

ORSSerialPort is a simple, modern, serial port library.

## 動作検証

|USB⇄RS-232Cコンバーター|チップ|macOS|対応|
|-|-|-|-|
|[REX-USB60F](http://www.ratocsystems.com/products/subpage/convert/usb60f_siyou.html)|FTDI|10.11|OK|
||FTDI|10.13|NG|
||FTDI|10.15|NG|
||FTDI|12 Silicon|NG|

