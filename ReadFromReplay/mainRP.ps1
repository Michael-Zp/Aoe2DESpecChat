$debug = $true


#-------------------------------------------------------------#
#----Initial Declarations-------------------------------------#
#-------------------------------------------------------------#

[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
Add-Type -AssemblyName PresentationCore, PresentationFramework

#Build the GUI
[xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    x:Name="Window" Title="Initial Window" WindowStartupLocation = "CenterScreen" 
    Width="800" Height="400" > 
    <Grid>
        <Button x:Name="btnOpenFile" Content="OpenFile" HorizontalAlignment="Center" VerticalAlignment="Top" Width="75" Margin="0,50,0,0"/>
        <ListBox x:Name="lbChat" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" BorderBrush="Black" BorderThickness="2" Margin="20,100,20,20" ScrollViewer.HorizontalScrollBarVisibility="Disabled" DisplayMemberPath="ChatLine">            
            <ListBox.ItemContainerStyle>
                <Style TargetType="{x:Type ListBoxItem}">
                    <Style.Triggers>
                        <DataTrigger Binding="{Binding Path=PlayerNumber}" Value="1">
                            <Setter Property="ListBoxItem.Foreground" Value="Blue" />
                        </DataTrigger>
                        <DataTrigger Binding="{Binding Path=PlayerNumber}" Value="2">
                            <Setter Property="ListBoxItem.Foreground" Value="Red" />
                        </DataTrigger>  
                        <DataTrigger Binding="{Binding Path=PlayerNumber}" Value="3">
                            <Setter Property="ListBoxItem.Foreground" Value="Lime" />
                        </DataTrigger>
                        <DataTrigger Binding="{Binding Path=PlayerNumber}" Value="4">
                            <Setter Property="ListBoxItem.Foreground" Value="Yellow" />
                        </DataTrigger>  
                        <DataTrigger Binding="{Binding Path=PlayerNumber}" Value="5">
                            <Setter Property="ListBoxItem.Foreground" Value="Cyan" />
                        </DataTrigger>
                        <DataTrigger Binding="{Binding Path=PlayerNumber}" Value="6">
                            <Setter Property="ListBoxItem.Foreground" Value="Fuchsia" />
                        </DataTrigger>  
                        <DataTrigger Binding="{Binding Path=PlayerNumber}" Value="7">
                            <Setter Property="ListBoxItem.Foreground" Value="SlateGray" />
                        </DataTrigger>
                        <DataTrigger Binding="{Binding Path=PlayerNumber}" Value="8">
                            <Setter Property="ListBoxItem.Foreground" Value="Orange" />
                        </DataTrigger>                                
                    </Style.Triggers>
                    <Setter Property="FontSize" Value="30"/>
                </Style>
            </ListBox.ItemContainerStyle>
        </ListBox>
    </Grid>
</Window>
"@

#-------------------------------------------------------------#
#----Control Event Handlers-----------------------------------#
#-------------------------------------------------------------#


#Write your code here


function OpenFile()
{
    $InitDir = [Environment]::GetFolderPath('UserProfile') + "\Games\Age of Empires 2 DE"
    Get-ChildItem $InitDir | % { if($_.Name -match "\d\d+") { $profilePath = $_ } }
    $InitDir = $InitDir + "\$profilePath\savegame"
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
    InitialDirectory =  $InitDir
    Filter = 'Replay-File (*.aoe2record)|*.aoe2record'
    }
    $null = $FileBrowser.ShowDialog()

    if($debug)
    {
        Write-Host $FileBrowser.FileName
    }

    if($FileBrowser.FileName -ne "" -and (Test-Path $FileBrowser.FileName))
    {
        if($debug)
        {
            $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
        }
    
        $observableCollection.Clear()
    
        $streamReader = New-Object System.IO.StreamReader($FileBrowser.FileName)

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
                        $line = "Player $playerNumber : $($Matches[2])"
                        #Write-Host $line
                 
                        $observableCollection.Add([PSCustomObject]@{
                            ChatLine = $line
                            PlayerNumber = $playerNumber
                        })
                    }
                }
            }
        }

        if($debug)
        {
            Write-Host "Done in" $stopwatch.Elapsed.TotalSeconds "seconds"
        }
    }
}

#endregion

#-------------------------------------------------------------#
#----Script Execution-----------------------------------------#
#-------------------------------------------------------------#

 
$reader=(New-Object System.Xml.XmlNodeReader $xaml)
$Window=[Windows.Markup.XamlReader]::Load( $reader )

#Connect to Controls
$btnOpenFile = $Window.FindName('btnOpenFile')
$lbChat = $Window.FindName('lbChat')

$Window.Add_Loaded({
    #Have to have something initially in the collection
    $Global:observableCollection = New-Object System.Collections.ObjectModel.ObservableCollection[System.Object]
    $lbChat.ItemsSource = $observableCollection
})

$btnOpenFile.Add_Click({OpenFile $this $_})

$Window.ShowDialog() | Out-Null