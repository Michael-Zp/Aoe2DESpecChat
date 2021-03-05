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
    Param($pDebugPref, $test_run)
    
    $DebugPreference = $pDebugPref

    Write-Debug "Hello"
    if($test_run)
    {
        Write-Debug "TEST"
    }

    Start-Sleep -Seconds 3

    Write-Debug "Bye"
})

$test_run = $true

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