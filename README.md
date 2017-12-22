# 4d-plugin-serial
Simple [ORSSerialPort](https://github.com/armadsen/ORSSerialPort) wrapper

### Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
||<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|||

Because ORSSerialPort uses [Automatic Reference Counting](https://developer.apple.com/library/content/documentation/Darwin/Conceptual/64bitPorting/indications/indications.html#//apple_ref/doc/uid/TP40001064-CH206-TPXREF101), 32-bit is not supported.

### Version

<img src="https://cloud.githubusercontent.com/assets/1725068/18940649/21945000-8645-11e6-86ed-4a0f800e5a73.png" width="32" height="32" /> <img src="https://cloud.githubusercontent.com/assets/1725068/18940648/2192ddba-8645-11e6-864d-6d5692d55717.png" width="32" height="32" />

## Discussion

The native command ``RECEIVE BUFFER`` does not support BLOB.

The native command ``RECEIVE PACKET`` does not listen indefinitely.

Neither native commands do not take advantage of newer multiprocessing (Grand Central Dispatch).

Neither native commands handle sleep events.

ORSSerialPort is a simple, modern, serial port library.

* To use RS-232C on Mac

Find a USB to RS-232C converter and install its driver.

In my tests I used RATOC [REX-USB60F](http://www.ratocsystems.com/products/subpage/convert/usb60f_siyou.html) (FTDI). It works on macOS 10.11 but [not 10.13](http://www.ratocsystems.com/services/driver/rs232c.html).

### Build Information

``ORSSerialPortManager`` is changed from ``CFRunLoopGetCurrent`` to ``CFRunLoopGetMain`` to process notifications. (alternatively the shared instance could be created via ``PA_RunInMainProcess``

---

## Syntax

```
SERIAL GET AVAILABLE PORTS (paths)
```

param|type|description
------------|------|----
paths|ARRAY TEXT|element ``0`` is ``JSON`` array of ``options``

``paths`` are basically the same as ``$2`` of ``GET SERIAL PORT MAPPING``

* Properties for ``options``

```
//pins states
RTS : BOOL
DTR : BOOL
CTS : BOOL
DSR : BOOL
DCD : BOOL
//device info
name : string
path : string
isOpen : BOOL
//options
baudRate : number
numberOfStopBits : number
parity : number
usesRTSCTSFlowControl : BOOL
usesDTRDSRFlowControl : BOOL
usesDCDOutputFlowControl : BOOL
shouldEchoReceivedData : BOOL
```

the following properties are modifiable:  

``RTS``  
``DTR``  
``baudRate`` : ``standard rates (0, 50, 75, 110, 134, 150, 200, 300, 600, 1200, 1800, 2400, 4800, 9600, 19200, 38400, 7200, 14400, 28800, 57600, 76800, 115200, 230400)``  
``numberOfStopBits`` : ``1 or 2``  
``parity``: ``0 (none), 1 (odd), 2 (even)``  
``usesRTSCTSFlowControl``  
``usesDTRDSRFlowControl``  
``usesDCDOutputFlowControl``  
``shouldEchoReceivedData``  

```
SERIAL OPEN PATH (path{;options{;method{;context}}})
```

param|type|description
------------|------|----
path|TEXT|
options|TEXT| ``JSON``
method|TEXT|callback to execute when data is received (optional)
context|TEXT| (optional)

```
SERIAL CLOSE PATH (path)
```

param|type|description
------------|------|----
path|TEXT|

```
SERIAL SEND DATA (path;data)
```

param|type|description
------------|------|----
path|TEXT|
data|BLOB|

* Signature for callback method

param|type|description
------------|------|----
path|TEXT|
data|BLOB|
context|TEXT|

a local process named ``$SERIAL_PORT`` is used to process incoming data. the ``context`` passed to ``SERIAL OPEN PATH`` is available in the callback method.
