enum ProgramPartNames
{
    Player = 0
    Caster = 1
    CasterGUI = 2
}

enum Status
{
    Running = 0
    Stopped = 1
    Error = 2
}

function Get-GameRootPath
{    
    $runningPrograms = Get-Process | ? { $_.Name -eq "AoE2DE_s" }

    if($runningPrograms.Count -eq 1)
    {
        $path = Split-Path $runningPrograms.Path
    }
    else
    {
        Write-Debug "Failed to get root path of the game, because game was not running."
        return ""
    }

    return $path
}

function Init-StatusUI($jsonPath)
{
    $json = ConvertFrom-Json (Get-Content $jsonPath -Raw)

    if($json.Collection.Widgets.Count -eq 1)
    {
        $json.Collection.Widgets += $json.Collection.Widgets[0]
        $json.Collection.Widgets += $json.Collection.Widgets[0]
        $json.Collection.Widgets += $json.Collection.Widgets[0]

        #Copy the json tree, because duplicating the first widget will be done as a reference, so a change to
        #any of the widgets will apply to all widgets. After the copy the references are no longer there
        #There might be a better solution, but it is a 180 line file so it should not have any impact. Hopefully.
        $jsonCopied = ConvertTo-Json $json -Depth 20
        $json = ConvertFrom-Json $jsonCopied
    
        $json.Collection.Widgets[1].Widget.Image.xorigin = 440
        $json.Collection.Widgets[1].Widget.Image.yorigin = 1570
        $json.Collection.Widgets[1].Widget.Image.width = 220
        $json.Collection.Widgets[1].Widget.Image.height = 80
        $json.Collection.Widgets[1].Widget.StateMaterials.StateNormal.Material = "PlayerGreyGameIcon"
    
        $json.Collection.Widgets[2].Widget.Image.xorigin = 675
        $json.Collection.Widgets[2].Widget.Image.yorigin = 1570
        $json.Collection.Widgets[2].Widget.Image.width = 220
        $json.Collection.Widgets[2].Widget.Image.height = 80
        $json.Collection.Widgets[2].Widget.StateMaterials.StateNormal.Material = "PlayerGreyGameIcon"
    
        $json.Collection.Widgets[3].Widget.Image.xorigin = 970
        $json.Collection.Widgets[3].Widget.Image.yorigin = 1570
        $json.Collection.Widgets[3].Widget.Image.width = 330
        $json.Collection.Widgets[3].Widget.Image.height = 80
        $json.Collection.Widgets[3].Widget.StateMaterials.StateNormal.Material = "PlayerGreyGameIcon"
    }

    $outJson = ConvertTo-Json $json -Depth 20

    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllLines($jsonPath, $outJson, $Utf8NoBomEncoding)
}

function Get-StatusColor($status)
{
    switch($status)
    {
        ([Status]::Running) {
            $newColor = "Green"
        }
        ([Status]::Stopped) {
            $newColor = "Grey"
        }
        ([Status]::Error) {
            $newColor = "Red"
        }
        default {
            Write-Debug "Failed to set status of $partOfProgram to $status, because parameter status was illegal."
            return
        }
    }
    $newColor = "Player$($newColor)GameIcon"

    return $newColor
}

function Set-Status($gameRootPath, $partOfProgram, $status)
{
    $jsonPath = "$gameRootPath/widgetui/screenmainmenu.json"
    Init-StatusUI $jsonPath

    switch($partOfProgram)
    {
        ([ProgramPartNames]::Player) {
            $indexToSwitch = 1
        }
        ([ProgramPartNames]::Caster) {
            $indexToSwitch = 2
        }
        ([ProgramPartNames]::CasterGUI) {
            $indexToSwitch = 3
        }
        default {
            Write-Debug "Failed to set status of $partOfProgram to $status, because parameter partOfProgram was illegal."
            return
        }
    }

    $newColor = Get-StatusColor $status
    
    $json = ConvertFrom-Json (Get-Content $jsonPath -Raw)
    
    $json.Collection.Widgets[$indexToSwitch].Widget.StateMaterials.StateNormal.Material = $newColor

    $outJson = ConvertTo-Json $json -Depth 20
    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllLines($jsonPath, $outJson, $Utf8NoBomEncoding)
}

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

function Deflate-Replay
{
    Param(
        $inputPath,
        $outputPath
    )
    
    Add-Type -Assembly "System.IO.Compression"

    $inFileStream = [System.IO.File]::OpenRead($inputPath)
    [void]$inFileStream.Seek(8, 'Begin')
    $outFileStream = [System.IO.File]::OpenWrite($outputPath)
    $deflateStream = New-Object System.IO.Compression.DeflateStream($inFileStream, [System.IO.Compression.CompressionMode]::Decompress)
    
    $deflateStream.CopyTo($outFileStream)

    $outFileStream.Close()
    $inFileStream.Close()
    $deflateStream.Close()
}

function Get-MessageTypeKey
{
    return 11
}

function Get-MessageTypeChat
{
    return 22
}

function Get-MessageTypeTimestamp
{
    return 33
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

    Deflate-Replay $inputPath $outputPath

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
    $headerArr[2] = Get-MessageTypeKey

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

function Get-Names
{
    Param(
        $filePath
    )
    
    $inputPath = (New-TemporaryFile).FullName
    $deflatedPath = (New-TemporaryFile).FullName

    Copy-Item $filePath $inputPath

    Deflate-Replay $inputPath $deflatedPath

    Remove-Item $inputPath

    $ret = @()

    $binaryReader = [System.IO.BinaryReader]([System.IO.File]::OpenRead($filePath))

    $header = New-Object -TypeName 'byte[]' -ArgumentList 2048

    [void]$binaryReader.Read($header, 0, $header.Count)
    $binaryReader.Close()

    $numPlayers = $header[0x74]

    Write-Host "There are $numPlayers players"

    $currentIdx = 0xA3
    $suffixLength = 0

    $sectionOffsets = @(0, 5, 4)

    for($i = 0; $i -lt $numPlayers; ++$i)
    {
        $playerNum = $header[$currentIdx] + 1
        $currentIdx += 16 + 4 # offset of 1 rows 4 columns in any hex editor

        $sections = @()
        $sections += [PScustomObject]@{
            Start = $currentIdx
            Length = 0
            String = ""
        }

        for($k = 0; $k -lt 3; ++$k)
        {
            $nextStart = $sections[$k].Start + $sectionOffsets[$k] + $sections[$k].Length
            $nextLength = $header[$nextStart + 2]
            $nextString = [System.Text.Encoding]::UTF8.GetString($header, $nextStart + 4, $nextLength)
            
            $sections += [PSCustomObject]@{
                Start = $nextStart
                Length = $nextLength
                String = $nextString
            }
        }
        
        if($sections[1].Length -gt 0)
        {
            $ret += [PSCustomObject]@{
                Number = $playerNum
                Name = $sections[2].String
            }
        }
        else
        {
            $ret += [PSCustomObject]@{
                Number = $playerNum
                Name = $sections[3].String
            }
        }
        
        $currentIdx = $sections[3].Start + $sections[3].Length + 16 + 16 + 2 # offset of 2 rows 2 columns in any hex editor

        Write-Host "Player $playerNum is called $playerName"
    }

    return $ret | Sort-Object Number
}


function Convert-LittleEndianBytesToInt
{
    Param(
        $bytes,
        $startIndex
    )

    return [convert]::ToInt32($bytes[$startIndex + 0] * [math]::Pow(2, 0) + 
             $bytes[$startIndex + 1] * [math]::Pow(2, 8) + 
             $bytes[$startIndex + 2] * [math]::Pow(2, 16) + 
             $bytes[$startIndex + 3] * [math]::Pow(2, 24))
}


function Get-ReadCommandMetaData
{
    Param(
        [Parameter(Mandatory=$true)][String]$FilePath
    )

    return [PSCustomObject]@{
        FilePath = $FilePath
        Time = 0
        CurrentPos = 0
    }
}


function Read-Commands
{
    Param(
        [Parameter(Mandatory=$true)][PSCustomObject]$MetaData
    )
    
    $FoundMessages = @()
    
    $inputPath = (New-TemporaryFile).FullName

    Copy-Item $MetaData.FilePath $inputPath

    $binaryReader = [System.IO.BinaryReader]([System.IO.File]::OpenRead($inputPath))

    $header = New-Object -TypeName 'int'

    $endOfHeader = $binaryReader.ReadInt32()

    if($MetaData.CurrentPos -eq 0)
    {
        Write-Debug "Header of $($MetaData.FilePath) ends at $endOfHeader"
    }
    
    [void]$binaryReader.BaseStream.Seek($endOfHeader + 4 + 4 + 12 + 12, 'Begin')

    $bufferSize = $binaryReader.BaseStream.Length - $binaryReader.BaseStream.Position - $MetaData.CurrentPos
    $buffer = New-Object -TypeName 'byte[]' -ArgumentList $bufferSize

    [void]$binaryReader.Read($buffer, 0, $bufferSize)
    $currentIndex = 0

    while($currentIndex -lt $bufferSize)
    {
        --$commandMax
        #For the command structure look at 'ReplayFileFormatFindings.ods:Body commands'
        switch($buffer[$currentIndex])
        {
            1 {
                $currentIndex += 4
                $length = Convert-LittleEndianBytesToInt -bytes $buffer -startIndex $currentIndex
                $currentIndex += 4 + $length + 4
            }

            2 {
                $currentIndex += 4
                $MetaData.Time += Convert-LittleEndianBytesToInt -bytes $buffer -startIndex $currentIndex
                $currentIndex += 4
            }

            3 {
                $currentIndex += 16
            }

            4 {
                $currentIndex += 8
                $length = Convert-LittleEndianBytesToInt -bytes $buffer -startIndex $currentIndex
                $currentIndex += 4
                $text = [System.Text.Encoding]::UTF8.GetString($buffer, $currentIndex, $length)
                $currentIndex += $length
                
                $FoundMessages += [PSCustomObject]@{
                    Timestamp = $MetaData.Time
                    Text = $text
                }
            }

            0 {
                $currentIndex += 360
            }

            default {
                Write-Debug "Not known at $currentIndex"
                $currentIndex = $bufferSize
            }
        }
    }

    $binaryReader.Close()

    Remove-Item $inputPath

    $MetaData.CurrentPos += $currentIndex

    if($FoundMessages.Length -gt 0)
    {
        Write-Debug "Found $($FoundMessages.Length) messages is the replay file."
    }

    return ($MetaData, $FoundMessages)
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