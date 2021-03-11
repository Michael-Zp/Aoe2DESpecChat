Add-Type -Assembly "System.IO.Compression"
Add-Type -Assembly "System.Runtime"

#$filePath = "C:/Users/Admin/Documents/GitHub/Aoe2DESpecChat/TestSavefiles/VulpesVSAi_Specated/Deflate/OngoingPlayer_OnlyVerFile"
#$filePath = "C:/Users/Admin/Documents/GitHub/Aoe2DESpecChat/TestSavefiles/VulpesVSAi_Specated/Deflate/OngoingPlayer_OnlyVerFile_NoHeader"
$filePath = "C:/Users/Admin/Documents/GitHub/Aoe2DESpecChat/TestSavefiles/VulpesVSAi_Specated/Deflate/OngoingPlayer.aoe2record"
#$filePath = "C:/Users/Admin/Documents/GitHub/Aoe2DESpecChat/TestSavefiles/VulpesVSAi_Specated/Deflate/MultiplePlayers.aoe2record"
$outputPath = "C:/Users/Admin/Documents/GitHub/Aoe2DESpecChat/TestSavefiles/VulpesVSAi_Specated/Deflate/powershell_output/out"
$inFileStream = [System.IO.File]::OpenRead($filePath)
[void]$inFileStream.Seek(8, 'Begin')

$outFileStream = [System.IO.File]::Create($outputPath)

$deflateStream = New-Object System.IO.Compression.DeflateStream($inFileStream, [System.IO.Compression.CompressionMode]::Decompress)
#$deflateStream = New-Object System.IO.Compression.GZipStream($inFileStream, [System.IO.Compression.CompressionMode]::Decompress)

$deflateStream.CopyTo($outFileStream)

$outFileStream.Close()

$fileStream.Close()

$streamReader = New-Object System.IO.StreamReader($outputPath)

$inBufSize = 704
$outBufSize = 128

$buf = New-Object -TypeName 'char[]' -ArgumentList $inBufSize
$addBuf = New-Object -TypeName 'int[]' -ArgumentList $outBufSize
$outByteBuf = New-Object -TypeName 'byte[]' -ArgumentList $outBufSize

[void]$streamReader.Read($buf, 0, 704) # Reads all player headers including names, so it should be unique

for($i = 0; $i -lt $outBufSize; ++$i)
{
    $addBuf[$i] = 0
}

for($i = 0; $i -lt $inBufSize; ++$i)
{
    $addBuf[$i % $outBufSize] += $buf[$i]
}

for($i = 0; $i -lt $outBufSize; ++$i)
{
    $outByteBuf[$i] = $addBuf[$i] % 255
}

$streamReader.Close()