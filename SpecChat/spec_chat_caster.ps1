. "$PSScriptRoot/spec_chat_common.ps1"

$DebugPreference = "Continue"
$release = $false

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
    Param($binaryWriter, $tcpStream, $baseDirectory, $commonIncludePath, $pDebugPref)
    
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

    $currentMatch = Get-LatestRecPath
    
    $buf = New-Object -TypeName 'byte[]' -ArgumentList (1024 * 50)

    $notFinishedMessageSize = 0

    while($true)
    {
        if((Get-LatestRecPath) -ne $currentMatch)
        {
            $currentMatch = Get-LatestRecPath
            
            Write-Debug "UpdateKeyFromOutside"
            for($i = 0; $i -lt $maxNumLastMessages; ++$i)
            {
                $lastMessages[$i] = Get-DefaultMessage
            }

            if(Test-Path "$baseDirectory/currentChat.txt")
            {
                Move-Item "$baseDirectory/currentChat.txt" "$baseDirectory/backups/$chatBackupFile" | Out-Null
            }

            Update-Key $binaryWriter
        }

        $task = $tcpStream.ReadAsync($buf, $notFinishedMessageSize, $buf.Count - $notFinishedMessageSize)

        while (-not $task.AsyncWaitHandle.WaitOne(200))
        {
            if((Get-LatestRecPath) -ne $currentMatch)
            {
                $currentMatch = Get-LatestRecPath

                Write-Debug "UpdateKeyFromInside"
                for($i = 0; $i -lt $maxNumLastMessages; ++$i)
                {
                    $lastMessages[$i] = Get-DefaultMessage
                }

                if(Test-Path "$baseDirectory/currentChat.txt")
                {
                    Move-Item "$baseDirectory/currentChat.txt" "$baseDirectory/backups/$chatBackupFile" | Out-Null
                }

                Update-Key $binaryWriter
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

                $lineWritten = $false

                while(-not $lineWritten)
                {
                    $outLine = "$($lastMessages[$currentMessage].PlayerInGameNumber)$($lastMessages[$currentMessage].Text)"
                    try
                    {
                        $outLine | Out-File -FilePath "$baseDirectory/currentChat.txt" -Encoding utf8 -Append
                        $lineWritten = $true
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

$tcpConnection = New-Object System.Net.Sockets.TcpClient("konosuba.zapto.org", 40320);
$tcpStream = $tcpConnection.GetStream()
$binaryWriter = New-Object System.IO.BinaryWriter($tcpStream)

$chatBackupFile = (Get-Date -Format "yyyyMMdd_hhmmss") + ".txt"
        
$baseDirectory = "$($env:APPDATA)/Aoe2DE_SpecChat"

if(-not (Test-Path $baseDirectory))
{
    mkdir $baseDirectory | Out-Null
}

if(-not (Test-Path "$baseDirectory/backups"))
{
    mkdir "$baseDirectory/backups" | Out-Null
}

if(Test-Path "$baseDirectory/currentChat.txt")
{
    Move-Item "$baseDirectory/currentChat.txt" "$baseDirectory/backups/$chatBackupFile" | Out-Null
}

Update-Key $binaryWriter
    
[void]$PowerShell.AddArgument($binaryWriter)
[void]$PowerShell.AddArgument($tcpStream)
[void]$PowerShell.AddArgument($baseDirectory)
[void]$PowerShell.AddArgument("$PSScriptRoot/spec_chat_common.ps1")
[void]$PowerShell.AddArgument($DebugPreference)

$Handle = $PowerShell.BeginInvoke()

Loop-UntilEscPressOrGameClosed

$PowerShell.Dispose()

$binaryWriter.Close()
$tcpConnection.Close()

if($release)
{
    Stop-Process -Id $PID
}