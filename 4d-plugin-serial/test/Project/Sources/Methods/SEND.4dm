//%attributes = {}
$ports:=SERIAL Get available ports

$path:=$ports[0].path
$options:=New object:C1471

var $data : Blob

SET BLOB SIZE:C606($data; 10)

SERIAL SEND DATA($path; $data)