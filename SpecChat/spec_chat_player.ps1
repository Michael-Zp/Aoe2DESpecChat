$DebugPreference = "Continue"

$tcpConnection = New-Object System.Net.Sockets.TcpClient("konosuba.zapto.org", 40321)
$tcpStream = $tcpConnection.GetStream()
$writer = New-Object System.IO.StreamWriter($tcpStream)
$writer.AutoFlush = $true

$key = "KeyTest"
$keyMessage = "$($key.Length);$key"
$writer.Write($keyMessage)

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
    Param($writer, $pDebugPref)
    
    $DebugPreference = $pDebugPref

    $lastPositionInFile = 0

    $lastFileName = ""

    while($true)
    {
        $InitDir = [Environment]::GetFolderPath('UserProfile') + "\Games\Age of Empires 2 DE"
        Get-ChildItem $InitDir | ForEach-Object { if($_.Name -match "\d\d+") { $profilePath = $_ } }
        $InitDir = $InitDir + "\$profilePath\savegame"
        $file = (Get-ChildItem $InitDir | Sort-Object LastWriteTime -Descending)[0].FullName

        if($lastFileName -ne "")
        {
            if($lastFileName -ne $file)
            {
                $lastPositionInFile = 0
            }
        }

        $lastFileName = $file

        if($file -ne "" -and (Test-Path $file))
        {    
            $tmpName = (New-TemporaryFile).FullName

            Copy-Item $file $tmpName
    
            $streamReader = New-Object System.IO.StreamReader($tmpName)
            $streamReader.BaseStream.Seek($lastPositionInFile, 'Begin') | Out-Null

            while(($currentLine = $streamReader.ReadLine()) -ne $null)
            {
                if($currentLine -match '{"player"')
                {
                    $parts = $currentLine -split '{'

                    for($i = 0; $i -lt $parts.Length; ++$i)
                    {
                        if($parts[$i] -match '"player":(\d+),"channel":\d+,"message":"(.*?)","messageAGP":".*?"}') 
                        { 
                            $playerNumber = $Matches[1]
                            $line = "$playerNumber;$($Matches[2])"
                            $line = "$($line.Length);$line"
                    
                            if($debug)
                            {
                                Write-Host "Send Line: $line"
                            }

                            $writer.Write($line)
                        }
                    }
                }
            }
            
            $lastPositionInFile = $streamReader.BaseStream.Position
            
            $streamReader.Close()
            Remove-Item $tmpName
        }
    }

    for($i = 0; $i -lt 20; ++$i)
    {
        Start-Sleep -Milliseconds 25
        
        if ([System.Console]::KeyAvailable)
        {    
            $key = [System.Console]::ReadKey()
            if ($key.Key -eq '27') 
            {
                $run = $false
            }
        }
    }
})

[void]$PowerShell.AddArgument($writer)
[void]$PowerShell.AddArgument($DebugPreference)

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


$writer.Close()
$tcpConnection.Close()