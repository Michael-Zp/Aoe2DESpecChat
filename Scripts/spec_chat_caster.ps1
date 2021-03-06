﻿. "$PSScriptRoot/spec_chat_common.ps1"

$DebugPreference = "Continue"
$release = $false
if($args.Count -gt 0)
{
    $release = $args[0]
}

Write-Debug "Started with release = $release"

$gameRootPath = Get-GameRootPath

if($gameRootPath -eq "" -and $release -eq $false)
{
    $gameRootPath = "H:\SteamLibrary\steamapps\common\AoE2DE" # This is for my pc if I want to test stuff, if any other person wants to work on this in debug mode they have to change this. Sorry. Vulpes / Michael-Zp
}

$programPart = [ProgramPartNames]::Caster
$newStatus = [Status]::Running

Set-Status $gameRootPath $programPart $newStatus

$PowerShell = [powershell]::Create()

$PowerShell.Streams.Debug.Add_DataAdded({
    param(
        [Parameter(Mandatory)][Object]$sender, 
        [Parameter(Mandatory)][System.Management.Automation.DataAddedEventArgs]$e
    );

    $newRecord = $sender[$e.Index] -as 'System.Management.Automation.PSDataCollection[psobject]'
    
    if(-not [System.String]::IsNullOrEmpty($newRecord.Item(0)))
    {
        Write-Debug $newRecord.Item(0)
    }
})


[void]$PowerShell.AddScript({
    Param($toServerWriter, $tcpStream, $commonIncludePath, $pDebugPref)
    
    . "$commonIncludePath"

    $DebugPreference = $pDebugPref

    $maxNumLastMessages = 20
    $currentMessage = 0
    $lastMessages = @()

    function Get-DefaultMessage
    {
        [PSCustomObject]@{
            Initialized        = $false
            PlayerID           = -1
            PlayerInGameNumber = -1
            Text               = ""
            Timestamp          = -1
        }
    }

    for($i = 0; $i -lt $maxNumLastMessages; ++$i)
    {
        $lastMessages += Get-DefaultMessage
    }

    $currentGame = Get-LatestRecPath

    Write-Debug "Opening match: $currentGame"
    
    $names = Get-Names $currentGame

    $buf = New-Object -TypeName 'byte[]' -ArgumentList (1024 * 50)

    $notFinishedMessageSize = 0

    $metaData = Get-ReadCommandMetaData -FilePath $currentGame
    $lastTimestamp = $metaData.Time

    while($true)
    {
        Start-Sleep -Milliseconds 200
        
        if((Get-LatestRecPath) -ne $currentGame)
        {
            $currentGame = Get-LatestRecPath
            
            Write-Debug "UpdateKeyFromOutside"
            for($i = 0; $i -lt $maxNumLastMessages; ++$i)
            {
                $lastMessages[$i] = Get-DefaultMessage
            }

            Push-Backup

            Update-Key $toServerWriter

            $names = Get-Names $currentGame
        }
        
        $task = $tcpStream.ReadAsync($buf, $notFinishedMessageSize, $buf.Count - $notFinishedMessageSize)

        while (-not $task.AsyncWaitHandle.WaitOne(200))
        {
            #Update timestamp on server side
            ($metaData, $_) = Read-Commands -MetaData $metaData
        
            $headerArr = New-Object -TypeName 'byte[]' -ArgumentList 7
                   
            $headerArr[0] = $headerArr.Length
            $headerArr[1] = 0

            $headerArr[2] = Get-MessageTypeTimestamp

            $timestampBytes = [System.BitConverter]::GetBytes($metaData.Time)
            [System.Array]::Copy($timestampBytes, 0, $headerArr, 3, 4) #4 bytes should be enough for a game which lasts ~49 days, should be fine.
        
            if($metaData.Time -gt $lastTimestamp)
            {
                Write-Debug "Updating caster timestamp to $($metaData.Time)"
                $toServerWriter.Write($headerArr)
                $lastTimestamp = $metaData.Time
            }

            if((Get-LatestRecPath) -ne $currentGame)
            {
                $currentGame = Get-LatestRecPath

                Write-Debug "UpdateKeyFromInside"
                for($i = 0; $i -lt $maxNumLastMessages; ++$i)
                {
                    $lastMessages[$i] = Get-DefaultMessage
                }
                
                Push-Backup

                Update-Key $toServerWriter
                
                $names = Get-Names $currentGame
            }
        }

        $readBytes = $task.GetAwaiter().GetResult()
                        
        $startOfNextMessage = 0
        $availableBytes = $readBytes

        # While there is enough data for at least a header to exist
        while($availableBytes -ge 7)
        {
            $byteValue0 = 1
            $byteValue1 = ([System.Math]::Pow(2, 8) - 1)
            $byteValue2 = ([System.Math]::Pow(2, 16) - 1)
            $byteValue3 = ([System.Math]::Pow(2, 24) - 1)
            $lineLength = $buf[$startOfNextMessage + 0] * $byteValue0 + $buf[$startOfNextMessage + 1] * $byteValue1
            $playerID = $buf[$startOfNextMessage + 2] * $byteValue0 + $buf[$startOfNextMessage + 3] * $byteValue1
            $playerID += $buf[$startOfNextMessage + 4] * $byteValue2 + $buf[$startOfNextMessage + 5] * $byteValue3
            $playerInGameNumber = $buf[$startOfNextMessage + 6]

            if($availableBytes -lt $lineLength)
            {
                break;
            }
            
            Write-Debug "Read message with $readBytes bytes"

            $messageText = ([System.Text.Encoding]::Unicode).GetString($buf, $startOfNextMessage + 7, $lineLength - 7)

            Write-Debug "Read message: $messageText from player $playerInGameNumber with line length: $lineLength"
        
            $foundDuplicate = $false

            #Remove messages that are older than 30 seconds from duplication search
            for($i = 0; $i -lt $maxNumLastMessages; ++$i)
            {
                if(-not $lastMessages[$i].Initialized)
                {
                    continue;
                }

                $currentTimestamp = [int][double]::Parse((Get-Date -UFormat %s))
                if(($currentTimestamp - $lastMessages[$i].Timestamp) -gt 30)
                {
                    $lastMessages[$i] = Get-DefaultMessage
                }
            }

            #Filter out duplicated messages send from different sources as most messages will be send by multiple people
            foreach($message in $lastMessages)
            {
                if(-not $message.Initialized)
                {
                    continue;
                }

                $sendFromDifferentSource = $playerID -ne $message.PlayerID
                $samePlayerInGame = $playerInGameNumber -eq $message.PlayerInGameNumber

                if($sendFromDifferentSource -and $samePlayerInGame)
                {
                    $textIsEqual = $messageText -eq $message.Text
                    if($textIsEqual)
                    {
                        $foundDuplicate = $true
                        break;
                    }
                }
            }


            if(-not $foundDuplicate)
            {
                $currentMessage = ($currentMessage + 1) % $maxNumLastMessages

                $lastMessages[$currentMessage].Initialized        = $true
                $lastMessages[$currentMessage].PlayerID           = $playerID
                $lastMessages[$currentMessage].PlayerInGameNumber = $playerInGameNumber
                $lastMessages[$currentMessage].Text               = $messageText
                $lastMessages[$currentMessage].Timestamp          = [int][double]::Parse((Get-Date -UFormat %s))

                $numberWritten = $false
                
                while(-not $numberWritten)
                {
                    $outLine = "$($lastMessages[$currentMessage].PlayerInGameNumber)"
                    $outLine = $outLine -replace '\n',''
                    try
                    {
                        $outLine | Out-File -FilePath "$(Get-BaseDir)/currentChat.txt" -Encoding Unicode -Append
                        $numberWritten = $true
                    }
                    catch
                    {
                        Start-Sleep -Milliseconds (Get-Random -Minimum 70 -Maximum 120)
                    }
                }

                $nameWritten = $false

                while(-not $nameWritten)
                {
                    $outLine = "$($names[$lastMessages[$currentMessage].PlayerInGameNumber - 1].Name)"
                    $outLine = $outLine -replace '\n',''
                    try
                    {
                        $outLine | Out-File -FilePath "$(Get-BaseDir)/currentChat.txt" -Encoding Unicode -Append
                        $nameWritten = $true
                    }
                    catch
                    {
                        Start-Sleep -Milliseconds (Get-Random -Minimum 70 -Maximum 120)
                    }
                }

                $messageWritten = $false

                while(-not $messageWritten)
                {
                    $outLine = "$($lastMessages[$currentMessage].Text)"
                    $outLine = $outLine -replace '\n',''
                    try
                    {
                        $outLine | Out-File -FilePath "$(Get-BaseDir)/currentChat.txt" -Encoding Unicode -Append
                        $messageWritten = $true
                    }
                    catch
                    {
                        Start-Sleep -Milliseconds (Get-Random -Minimum 70 -Maximum 120)
                    }
                }
            }
                
            $startOfNextMessage = $startOfNextMessage + $lineLength
            $availableBytes = $availableBytes - $lineLength
            

        }
        
        $notFinishedMessageSize = $readBytes - $startOfNextMessage

    }
})

$connected = $false
do
{
    try
    {
        $tcpConnection = New-Object System.Net.Sockets.TcpClient("konosuba.zapto.org", 40320);
        $connected = $true
    }
    catch
    {
        $connected = $false
        Start-Sleep -Seconds 1
    }

} while(-not $connected)
$tcpStream = $tcpConnection.GetStream()
$toServerWriter = New-Object System.IO.BinaryWriter($tcpStream)
        
Push-Backup

Update-Key $toServerWriter
    
[void]$PowerShell.AddArgument($toServerWriter)
[void]$PowerShell.AddArgument($tcpStream)
[void]$PowerShell.AddArgument("$PSScriptRoot/spec_chat_common.ps1")
[void]$PowerShell.AddArgument($DebugPreference)

$Handle = $PowerShell.BeginInvoke()

Loop-UntilEscPressOrGameClosed $release

$PowerShell.Dispose()

$toServerWriter.Close()
$tcpConnection.Close()

Write-Debug "Spectator closed correctly"

$programPart = [ProgramPartNames]::Caster
$newStatus = [Status]::Stopped

Set-Status $gameRootPath $programPart $newStatus

if($release)
{
    Stop-Process -Id $PID
}