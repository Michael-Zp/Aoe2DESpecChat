. "$PSScriptRoot/spec_chat_common.ps1"

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

$programPart = [ProgramPartNames]::Player
$newStatus = [Status]::Running

Set-Status $gameRootPath $programPart $newStatus

$connected = $false
do
{
    try
    {
        $tcpConnection = New-Object System.Net.Sockets.TcpClient("konosuba.zapto.org", 40321)
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
    Param($toServerWriter, $commonIncludePath, $pDebugPref)

    . "$commonIncludePath"
    
    $DebugPreference = $pDebugPref

    $lastFileName = ""
    
    while($true)
    {
        $file = Get-LatestRecPath

        $updateKey = $false
        if($lastFileName -ne "")
        {
            if($lastFileName -ne $file)
            {
                $updateKey = $true
            }
        }
        else
        {
            $updateKey = $true
        }

        if($updateKey)
        {
            $metaData = Get-ReadCommandMetaData -FilePath $file
            Update-Key -BinaryWriter $toServerWriter
        }

        $lastFileName = $file

        if($file -ne "" -and (Test-Path $file))
        {
            ($metaData, $messages) = Read-Commands -MetaData $metaData
            
            foreach($message in $messages)
            {
                if($message.Text -match '{"player":(\d+),"channel":\d+,"message":"(.*?)","messageAGP":".*?"}') 
                { 
                    $text = $Matches[2]
                            
                    $textBytes = ([System.Text.Encoding]::Unicode).GetBytes($text)

                    $headerArr = New-Object -TypeName 'byte[]' -ArgumentList 8
                   
                    $lengthBytes = [System.BitConverter]::GetBytes($textBytes.Length + $headerArr.Count)
                    [System.Array]::Copy($lengthBytes, $headerArr, 2)  #Ints are converted into byte[4] and the text of one chat message should never exceed 65000 bytes. I hope
                   
                    $headerArr[2] = Get-MessageTypeChat
                   
                    $headerArr[3] = $Matches[1] #Player number is between 1-8 so one byte is enough.
                   
                    $timestampBytes = [System.BitConverter]::GetBytes($message.Timestamp)
                    [System.Array]::Copy($timestampBytes, 0, $headerArr, 4, 4) #4 bytes should be enough for a game which lasts ~49 days, should be fine.

                    $outArr = New-Object -TypeName 'byte[]' -ArgumentList ($textBytes.Count + $headerArr.Count)
                            
                    [System.Array]::Copy($headerArr, $outArr, $headerArr.Count)
                    [System.Array]::Copy($textBytes, 0, $outArr, $headerArr.Count, $textBytes.Count)

                    Write-Debug "Send Line $text at time $($message.Timestamp) from player $($outArr[3]) with length $($outArr[0] + $outArr[1] * 256)"
                    $toServerWriter.Write($outArr)
                }
            }
        }

        Start-Sleep -Milliseconds 500
    }

})

[void]$PowerShell.AddArgument($toServerWriter)
[void]$PowerShell.AddArgument("$PSScriptRoot/spec_chat_common.ps1")
[void]$PowerShell.AddArgument($DebugPreference)

$Handle = $PowerShell.BeginInvoke()

Loop-UntilEscPressOrGameClosed $release

$PowerShell.Dispose()
$PowerShell.Stop()

$toServerWriter.Close()
$tcpConnection.Close()

Write-Debug "Player closed correctly"

$programPart = [ProgramPartNames]::Player
$newStatus = [Status]::Stopped

Set-Status $gameRootPath $programPart $newStatus

if($release)
{
    Stop-Process -Id $PID
}