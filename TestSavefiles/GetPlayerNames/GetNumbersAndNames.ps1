$DebugPreference = "Continue"

function Get-Names
{
    Param(
        $filePath
    )
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


$fileName = "multiple"
#$fileName = "multipleDifferentBots"
#$fileName = "multipleBots"
$filePath = "$PSScriptRoot/DeflateHeader/$fileName"

Get-Names $filePath