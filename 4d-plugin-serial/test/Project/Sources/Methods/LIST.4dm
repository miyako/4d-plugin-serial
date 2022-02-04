//%attributes = {}
$ports:=SERIAL Get available ports

$path:=$ports[0].path
$options:=New object:C1471

$status:=SERIAL Open path($path; $options; "serial_receive_method")

$status:=SERIAL Close path($path)