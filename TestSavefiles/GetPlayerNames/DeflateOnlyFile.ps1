Add-Type -Assembly "System.IO.Compression"
Add-Type -Assembly "System.Runtime"

$fileName = "single"
$filePath = "$PSScriptRoot/Replay/$fileName.aoe2record"
$outputPath = "$PSScriptRoot/DeflateHeader/$fileName"
$inFileStream = [System.IO.File]::OpenRead($filePath)
[void]$inFileStream.Seek(8, 'Begin')

$outFileStream = [System.IO.File]::Create($outputPath)

$deflateStream = New-Object System.IO.Compression.DeflateStream($inFileStream, [System.IO.Compression.CompressionMode]::Decompress)

$deflateStream.CopyTo($outFileStream)

$deflateStream.Close()

$outFileStream.Close()

$inFileStream.Close()