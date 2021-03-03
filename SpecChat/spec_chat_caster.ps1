$tcpConnection = New-Object System.Net.Sockets.TcpClient("konosuba.zapto.org", 40320);
$tcpStream = $tcpConnection.GetStream()
$writer = New-Object System.IO.StreamWriter($tcpStream)
$writer.AutoFlush = $true
$reader = New-Object System.IO.StreamReader($tcpStream)

$debug = $false
$run = $true


$chatBackupFile = (Get-Date -Format "yyyyMMdd_hhmmss") + ".txt"

if(-not (Test-Path "./backups"))
{
    mkdir "./backups" | Out-Null
}

if(Test-Path "./currentChat.txt")
{
    Move-Item "./currentChat.txt" "./backups/$chatBackupFile" | Out-Null
}

$writer.WriteLine("KeyTest")

while($run)
{
    $line = $reader.ReadLine()

    if($line -match "^KillMe")
    {
        break;
    }

    if($line.Length -gt 0)
    {
        if($debug)
        {
            Write-Host $line
        }
        
        $fileWritten = $false

        while(-not $fileWritten)
        {
            try
            {
                $line | Out-File -FilePath "./currentChat.txt" -Encoding utf8 -Append
                $fileWritten = $true
            }
            catch
            {
                Start-Sleep -Milliseconds (Get-Random -Minimum 70 -Maximum 120)
            }
        }
    }

    if ([System.Console]::KeyAvailable)
    {    
        $key = [System.Console]::ReadKey()
        if ($key.Key -eq '27') 
        {
            $run = $false
        }
    }
}



$reader.Close()
$tcpConnection.Close()