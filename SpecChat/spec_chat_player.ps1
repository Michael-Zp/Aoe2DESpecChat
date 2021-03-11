. "$PSScriptRoot/spec_chat_common.ps1"

$DebugPreference = "Continue"
$release = $false

$tcpConnection = New-Object System.Net.Sockets.TcpClient("konosuba.zapto.org", 40321)
$tcpStream = $tcpConnection.GetStream()
$binaryWriter = New-Object System.IO.BinaryWriter($tcpStream)

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
    Param($binaryWriter, $commonIncludePath, $pDebugPref)

    . "$commonIncludePath"
    
    $DebugPreference = $pDebugPref

    $lastPositionInFile = 0

    $lastFileName = ""

    while($true)
    {
        $file = Get-LatestRecPath

        $updateKey = $false
        if($lastFileName -ne "")
        {
            if($lastFileName -ne $file)
            {
                $lastPositionInFile = 0
                $updateKey = $true
            }
        }
        else
        {
            $updateKey = $true
        }

        if($updateKey)
        {
            Update-Key -BinaryWriter $binaryWriter
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
                            #$playerNumber = $Matches[1]
                            #$line = "$playerNumber;$($Matches[2])"
                            #$line = "$($line.Length);$line"

                            $line = $Matches[2]
                            
                            $textBytes = ([System.Text.Encoding]::Unicode).GetBytes($line)

                            $headerArr = New-Object -TypeName 'byte[]' -ArgumentList 4
                            $lengthBytes = [System.BitConverter]::GetBytes($textBytes.Length + $headerArr.Count)
                            $headerArr[0] = $lengthBytes[0]
                            $headerArr[1] = $lengthBytes[1]
                            $headerArr[2] = 22
                            $headerArr[3] = $Matches[1]

                            $outArr = New-Object -TypeName 'byte[]' -ArgumentList ($textBytes.Count + $headerArr.Count)
                            
                            #Ints are converted into byte[4], but as we will never have a text longer than the range of 2 bytes and the player number is between 1-8 this will be fine
                            
                            [System.Array]::Copy($headerArr, $outArr, $headerArr.Count)
                            [System.Array]::Copy($textBytes, 0, $outArr, $headerArr.Count, $textBytes.Count)

                            Write-Debug "Send Line: $line from player $($outArr[3])"
                            Write-Debug $outArr[0]
                            $binaryWriter.Write($outArr)
                        }
                    }
                }
            }
            
            $lastPositionInFile = $streamReader.BaseStream.Position
            
            $streamReader.Close()
            Remove-Item $tmpName
        }

        Start-Sleep -Milliseconds 500
    }

})

[void]$PowerShell.AddArgument($binaryWriter)
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