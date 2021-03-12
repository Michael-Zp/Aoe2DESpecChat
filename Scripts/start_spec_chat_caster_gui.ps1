#This should be in the common file, but then it is not compilable
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

$logFile = Get-LogFile "caster_gui"

./spec_chat_caster_gui.ps1 *> $logFile