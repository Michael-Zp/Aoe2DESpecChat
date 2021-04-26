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
        [Parameter(Mandatory=$true)][PSCustomObject]$LastMetaData
    )

    $MetaData = $LastMetaData

    $FoundMessages = @()
    
    $inputPath = (New-TemporaryFile).FullName

    Copy-Item $LastMetaData.FilePath $inputPath

    $binaryReader = [System.IO.BinaryReader]([System.IO.File]::OpenRead($inputPath))

    $header = New-Object -TypeName 'int'

    $endOfHeader = $binaryReader.ReadInt32()
    Write-Host "Header ends at $endOfHeader"
    
    [void]$binaryReader.BaseStream.Seek($endOfHeader + 4 + 4 + 12 + 12, 'Begin')

    $bufferSize = $binaryReader.BaseStream.Length - $binaryReader.BaseStream.Position - $MetaData.CurrentPos
    $buffer = New-Object -TypeName 'byte[]' -ArgumentList $bufferSize

    [void]$binaryReader.Read($buffer, 0, $bufferSize)
    $currentIndex = 0
    
    while($currentIndex -lt $bufferSize)
    {
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
                Write-Error "Not known at $currentIndex"
                $currentIndex = $bufferSize
            }
        }
    }

    $binaryReader.Close()

    Remove-Item $inputPath

    $MetaData.CurrentPos += $currentIndex

    return ($MetaData, $FoundMessages)
}

$MetaData = Get-ReadCommandMetaData -FilePath "C:\Users\Admin\Documents\GitHub\Aoe2DESpecChat\TestSavefiles\VulpesVSAi_Specated\FinishedSpectator.aoe2record"
#$MetaData = Get-ReadCommandMetaData -FilePath "C:\Users\Admin\Documents\GitHub\Aoe2DESpecChat\TestSavefiles\SomeLongGame.aoe2record"
#$MetaData = Get-ReadCommandMetaData -FilePath "C:\Users\Admin\Games\Age of Empires 2 DE\76561198045530039\savegame\SP Replay v101.101.46295.0 @2021.04.24 015113.aoe2record"

for($i = 0; $i -lt 1; ++$i)
{
    Write-Host "Run #$i"

    ($MetaData, $messages) = Read-Commands -LastMetaData $MetaData

    Write-Host "Time: $($MetaData.Time)"
    Write-Host "CurrentPos: $($MetaData.CurrentPos)"
    Write-Host "Messages:"
    Write-Host $messages

    Write-Host ""
    Write-Host ""
}

Write-Host $MetaData.Time.GetType()