#This should be in the common file, but then it is not compilable as it does not support includes
function Get-BaseDir
{
    $baseDirectory = "$($env:APPDATA)/Aoe2DE_SpecChat"

    if(-not (Test-Path $baseDirectory))
    {
        mkdir $baseDirectory | Out-Null
    }

    return $baseDirectory
}

function Get-LogFile
{
    Param(
        $suffix
    )

    $logPath = "$(Get-BaseDir)/logs"

    if(-not (Test-Path $logPath))
    {
        mkdir $logPath | Out-Null
    }

    return "$($logPath)/$(Get-Date -Format "yyyyMMdd_hhmmss")_$suffix.log"
}

$processName = (Get-Process -Id $PID)[0].ProcessName

if((Get-Process -Name $processName).Count -gt 1)
{
    return
}

$logFile = Get-LogFile "player"

./spec_chat_player.ps1 $true *> $logFile