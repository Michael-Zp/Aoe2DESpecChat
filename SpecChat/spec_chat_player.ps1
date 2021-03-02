$tcpConnection = New-Object System.Net.Sockets.TcpClient("konosuba.zapto.org", 40321)
$tcpStream = $tcpConnection.GetStream()
$writer = New-Object System.IO.StreamWriter($tcpStream)
$writer.AutoFlush = $true

$debug = $false

$jobCode = {
    param($writer)
    
    #Write-Host "Begin"
    $writer.WriteLine("Begin")

    $global:lastPositionInFile = 0

    while($true)
    {
        Start-Sleep -Milliseconds 500
        $InitDir = [Environment]::GetFolderPath('UserProfile') + "\Games\Age of Empires 2 DE"
        Get-ChildItem $InitDir | ForEach-Object { if($_.Name -match "\d\d+") { $profilePath = $_ } }
        $InitDir = $InitDir + "\$profilePath\savegame"
        $file = (Get-ChildItem $InitDir | Sort-Object LastWriteTime -Descending)[0].FullName

        if($debug)
        {
            Write-Host $file
        }

        if($file -ne "" -and (Test-Path $file))
        {
            if($debug)
            {
                $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
            }
    
            $tmpName = (New-TemporaryFile).FullName

            Copy-Item $file $tmpName
    
            $streamReader = New-Object System.IO.StreamReader($tmpName)
            $streamReader.BaseStream.Seek($global:lastPositionInFile, 'Begin')

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
                            $line = "$playerNumber$($Matches[2])"
                    
                            #Write-Host $line
                            $writer.WriteLine($line)
                        }
                    }
                }
            }
            
            $global:lastPositionInFile = $streamReader.BaseStream.Position
            
            $streamReader.Close()
            Remove-Item $tmpName


            if($debug)
            {
                Write-Host "Now at position: $lastPositionInFile"
                Write-Host "Done in" $stopwatch.Elapsed.TotalSeconds "seconds"
            }
        }
    }
}

$p = [PowerShell]::Create()
$null = $p.AddScript($jobCode).AddArgument($writer)
$p.BeginInvoke() | Out-Null

#Invoke-Command -ScriptBlock $jobCode

while($true)
{
    $key = [console]::ReadKey()
    if ($key.Key -eq '27') 
    {
        break
    }
}

$writer.WriteLine("KillMe")

$p.Stop()
$p.Dispose()
#$p.EndInvoke($job)


$writer.Close()
$tcpConnection.Close()