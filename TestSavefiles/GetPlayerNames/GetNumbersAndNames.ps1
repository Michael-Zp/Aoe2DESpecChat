function Get-Names
{
    Param(
        $filePath
    )
    $ret = @()

    $binaryReader = [System.IO.BinaryReader]([System.IO.File]::OpenRead($filePath))

    $header = New-Object -TypeName 'byte[]' -ArgumentList 1024

    [void]$binaryReader.Read($header, 0, $header.Count)
    $binaryReader.Close()

    $numPlayers = $header[0x74]

    Write-Host "There are $numPlayers players"

    $currentIdx = 0xA3

    for($i = 0; $i -lt $numPlayers; ++$i)
    {
        $playerNum = $header[$currentIdx] + 1
        $currentIdx += (0xC4 - 0xA3)
        $nameStartIdx = $currentIdx
        $nameLength = 0

        while($header[$currentIdx] -ne 0x02)
        {
            ++$currentIdx
            ++$nameLength
        }

        $playerName = [System.Text.Encoding]::UTF8.GetString($header, $nameStartIdx, $nameLength)

        $currentIdx += (0xE8 - 0xCA)

        $ret += [PSCustomObject]@{
            Number = $playerNum
            Name = $playerName
        }

        Write-Host "Player $playerNum is called $playerName"
    }

    return $ret
}


$fileName = "multiple"
$filePath = "$PSScriptRoot/DeflateHeader/$fileName"

Get-Names $filePath | Sort-Object Number