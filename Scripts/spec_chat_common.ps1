function Get-BaseDir
{
    $baseDirectory = "$($env:APPDATA)/Aoe2DE_SpecChat"

    if(-not (Test-Path $baseDirectory))
    {
        mkdir $baseDirectory | Out-Null
    }

    return $baseDirectory
}

function Push-Backup
{
    $baseDirectory = Get-BaseDir
    $chatBackupFile = (Get-Date -Format "yyyyMMdd_hhmmss") + ".txt"

    if(-not (Test-Path "$baseDirectory/backups"))
    {
        mkdir "$baseDirectory/backups" | Out-Null
    }

    if(Test-Path "$baseDirectory/currentChat.txt")
    {
        Move-Item "$baseDirectory/currentChat.txt" "$baseDirectory/backups/$chatBackupFile" | Out-Null
    }
}

function Get-LatestRecPath
{
    $InitDir = [Environment]::GetFolderPath('UserProfile') + "\Games\Age of Empires 2 DE"
    Get-ChildItem $InitDir | ForEach-Object { if($_.Name -match "\d\d+") { $profilePath = $_ } }
    $InitDir = $InitDir + "\$profilePath\savegame"
    $file = (Get-ChildItem $InitDir | Sort-Object LastWriteTime -Descending)[0].FullName
    return $file
}

function Get-Key
{
    [OutputType([char[]])]
    param()

    Add-Type -Assembly "System.IO.Compression"
    Add-Type -Assembly "System.Runtime"


    $filePath = Get-LatestRecPath
    $inputPath = (New-TemporaryFile).FullName
    $outputPath = (New-TemporaryFile).FullName

    Copy-Item $filePath $inputPath

    $inFileStream = [System.IO.File]::OpenRead($inputPath)
    [void]$inFileStream.Seek(8, 'Begin')
    $outFileStream = [System.IO.File]::OpenWrite($outputPath)
    $deflateStream = New-Object System.IO.Compression.DeflateStream($inFileStream, [System.IO.Compression.CompressionMode]::Decompress)
    
    $deflateStream.CopyTo($outFileStream)

    $outFileStream.Close()
    $inFileStream.Close()
    $deflateStream.Close()

    Remove-Item $inputPath


    $binaryReader = New-Object System.IO.BinaryReader(([System.IO.File]::OpenRead($outputPath)));
    
    $inputBuf = New-Object -TypeName 'byte[]' -ArgumentList 704
    $outByteBuf = New-Object -TypeName 'byte[]' -ArgumentList 128
    $addBuf = New-Object -TypeName 'int[]' -ArgumentList ($outByteBuf.Count)

    [void]$binaryReader.Read($inputBuf, 0, $inputBuf.Count) # Reads all player headers including names, so it should be unique

    for($i = 0; $i -lt $outByteBuf.Count; ++$i)
    {
        $addBuf[$i] = 0
    }

    for($i = 0; $i -lt $inputBuf.Count; ++$i)
    {
        $addBuf[$i % ($outByteBuf.Count)] += $inputBuf[$i]
    }

    for($i = 0; $i -lt $outByteBuf.Count; ++$i)
    {
        $outByteBuf[$i] = $addBuf[$i] % 255
    }

    $binaryReader.Close()

    Remove-Item $outputPath

    $headerArr = New-Object -TypeName 'byte[]' -ArgumentList 3
    $headerArr[0] = $outByteBuf.Count + $headerArr.Count
    $headerArr[1] = 0
    $headerArr[2] = 11

    $combinedBuf = New-Object -TypeName 'byte[]' -ArgumentList ($outByteBuf.Count + $headerArr.Count)

    [System.Array]::Copy($headerArr, $combinedBuf, $headerArr.Count)
    [System.Array]::Copy($outByteBuf, 0, $combinedBuf, $headerArr.Count, $outByteBuf.Count - 1)
    
    ,$combinedBuf
}

function Update-Key
{
    Param(
        [parameter(Mandatory=$true)]
        [System.IO.BinaryWriter]
        $binaryWriter
    )
    
    $key = Get-Key
    $binaryWriter.Write($key)
    Write-Debug "Wrote $($key.Count) bytes as key"
    $binaryWriter.Flush()
}

function Loop-UntilEscPressOrGameClosed
{
    Param(
        $release
    )

    if(-not $release)
    {
        Write-Debug "Will not break even if game is closed"
    }

    while($true)
    {
        Start-Sleep -Milliseconds 25
        
        # Check if a console is available, otherwise KeyAvailable throws an exception
        if ([System.Console]::OpenStandardInput(1) -ne [System.IO.Stream]::Null)
        {
            if ([System.Console]::KeyAvailable)
            {    
                $key = [System.Console]::ReadKey()
                if ($key.Key -eq '27') 
                {
                    break;
                }
            }
        }
        elseif($release -and ((Get-Process | Where-Object { $_.Name -eq "AoE2DE_s" }).Count) -lt 1)
        {
            break;
        }
    }
}