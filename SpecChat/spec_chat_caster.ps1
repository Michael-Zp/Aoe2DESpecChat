$DebugPreference = "Continue"
$test_run = $false

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
    Param($writer, $reader, $baseDirectory, $pDebugPref, $test_run)
    
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

    if($test_run)
    {
        $test_run_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
        $test_run_index = 0
        $lastMessages[$test_run_index].Initialized        = $true
        $lastMessages[$test_run_index].PlayerID           = 1111
        $lastMessages[$test_run_index].PlayerInGameNumber = 1
        $lastMessages[$test_run_index].Text               = "Message from P1"
        $lastMessages[$test_run_index].Timestamp          = $test_run_timestamp
        $test_run_index++

        $lastMessages[$test_run_index].Initialized        = $true
        $lastMessages[$test_run_index].PlayerID           = 2222
        $lastMessages[$test_run_index].PlayerInGameNumber = 2
        $lastMessages[$test_run_index].Text               = "Message from P2"
        $lastMessages[$test_run_index].Timestamp          = $test_run_timestamp
        $test_run_index++

        $lastMessages[$test_run_index].Initialized        = $true
        $lastMessages[$test_run_index].PlayerID           = 2222
        $lastMessages[$test_run_index].PlayerInGameNumber = 1
        $lastMessages[$test_run_index].Text               = "Message from P1"
        $lastMessages[$test_run_index].Timestamp          = $test_run_timestamp
        $test_run_index++

        $lastMessages[$test_run_index].Initialized        = $true
        $lastMessages[$test_run_index].PlayerID           = 1111
        $lastMessages[$test_run_index].PlayerInGameNumber = 1
        $lastMessages[$test_run_index].Text               = "Message from P1"
        $lastMessages[$test_run_index].Timestamp          = $test_run_timestamp - 35
        $test_run_index++

        $lastMessages[$test_run_index].Initialized        = $true
        $lastMessages[$test_run_index].PlayerID           = 2222
        $lastMessages[$test_run_index].PlayerInGameNumber = 1
        $lastMessages[$test_run_index].Text               = "Message from P1"
        $lastMessages[$test_run_index].Timestamp          = $test_run_timestamp - 35
        $test_run_index++

        $lastMessages[$test_run_index].Initialized        = $true
        $lastMessages[$test_run_index].PlayerID           = 1111
        $lastMessages[$test_run_index].PlayerInGameNumber = 2
        $lastMessages[$test_run_index].Text               = "Message from P2"
        $lastMessages[$test_run_index].Timestamp          = $test_run_timestamp - 35
        $test_run_index++
    }


    while($true)
    {
        if($test_run)
        {
            $line = "3333;1;Different Message"
        }
        else
        {
            $task = $reader.ReadLineAsync()
            while (-not $task.AsyncWaitHandle.WaitOne(100)) { }
            $line = $task.GetAwaiter().GetResult()
        }

        if($line.Length -gt 0)
        {
            Write-Debug $line

            if(-not($line -match "\d+;\d+;.*"))
            {
                continue;
            }

            $splits = $line -split ";"
            $playerID = $splits[0]
            $playerInGameNumber = $splits[1]
            $messageText = $line.Substring($playerID.Length + $playerInGameNumber.Length + 2)
        
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
        }
        else
        {
            break;
        }
    }
})

if(-not $test_run)
{
    $tcpConnection = New-Object System.Net.Sockets.TcpClient("konosuba.zapto.org", 40320);
    $tcpStream = $tcpConnection.GetStream()
    $writer = New-Object System.IO.StreamWriter($tcpStream)
    $writer.AutoFlush = $true
    $reader = New-Object System.IO.StreamReader($tcpStream)

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
    
    $key = "KeyTest"
    $keyMessage = "$($key.Length);$key"
    $writer.Write($keyMessage)
    
    [void]$PowerShell.AddArgument($writer)
    [void]$PowerShell.AddArgument($reader)
}

[void]$PowerShell.AddArgument($baseDirectory)
[void]$PowerShell.AddArgument($DebugPreference)
[void]$PowerShell.AddArgument($test_run)

$Handle = $PowerShell.BeginInvoke()

while($true)
{
    Start-Sleep -Milliseconds 25
        
    if ([System.Console]::KeyAvailable)
    {    
        $key = [System.Console]::ReadKey()
        if ($key.Key -eq '27') 
        {
            break;
        }
    }
}

$PowerShell.Dispose()

if(-not $test_run)
{
    $writer.Close()
    $reader.Close()
    $tcpConnection.Close()
}