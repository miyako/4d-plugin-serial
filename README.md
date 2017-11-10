# 4d-plugin-serial
[ORSSerialPort](https://github.com/armadsen/ORSSerialPort) wrapper

## Discussion

The native command ``RECEIVE BUFFER`` does not support BLOB.

The native command ``RECEIVE PACKET`` does not listen indefinitely.

Neither native commands do not take advantage of newer multiprocessing (Grand Central Dispatch).

Neither native commands handle sleep events.

ORSSerialPort is a simple, modern, serial port library.

* To use RS-232C on Mac

Find a USB to RS-232C converter and install its driver.

In my test I used RATOC [REX-USB60F](http://www.ratocsystems.com/products/subpage/convert/usb60f_siyou.html). It works on macOS 10.11 but [not 10.13](http://www.ratocsystems.com/services/driver/rs232c.html).


