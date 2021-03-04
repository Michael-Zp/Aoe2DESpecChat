$tcpConnection = New-Object System.Net.Sockets.TcpClient("konosuba.zapto.org", 40321)
$tcpStream = $tcpConnection.GetStream()
$writer = New-Object System.IO.StreamWriter($tcpStream)
$writer.AutoFlush = $true

$debug = $true

$key = "KeyTest"
$keyMessage = "$($key.Length);$key"
$writer.Write($keyMessage)

$run = $true

while($run)
{
    $global:lastPositionInFile = 0

    while($true)
    {
        $InitDir = [Environment]::GetFolderPath('UserProfile') + "\Games\Age of Empires 2 DE"
        Get-ChildItem $InitDir | ForEach-Object { if($_.Name -match "\d\d+") { $profilePath = $_ } }
        $InitDir = $InitDir + "\$profilePath\savegame"
        $file = (Get-ChildItem $InitDir | Sort-Object LastWriteTime -Descending)[0].FullName

        if($file -ne "" -and (Test-Path $file))
        {    
            $tmpName = (New-TemporaryFile).FullName

            Copy-Item $file $tmpName
    
            $streamReader = New-Object System.IO.StreamReader($tmpName)
            $streamReader.BaseStream.Seek($global:lastPositionInFile, 'Begin') | Out-Null

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
            
            $global:lastPositionInFile = $streamReader.BaseStream.Position
            
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
}


$writer.Close()
$tcpConnection.Close()