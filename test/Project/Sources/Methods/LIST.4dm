//%attributes = {}
$ports:=SERIAL Get available ports

$usbserial:=$ports.query("path == :1"; "/dev/cu.usbserial@")

If ($usbserial.length#0)
	
	$path:=$usbserial[0].path
	
	$options:=New object:C1471
	
	$status:=SERIAL Open path($path; $options; "serial_receive_method")
	
	var $data : Blob
	
	SET BLOB SIZE:C606($data; 10)
	
	$status:=SERIAL Send data($path; $data)
	
	$status:=SERIAL Close path($path)
	
End if 