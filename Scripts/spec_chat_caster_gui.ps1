$DebugPreference = "Continue"

. "$PSScriptRoot/spec_chat_common.ps1"



#-------------------------------------------------------------#
#----Initial Declarations-------------------------------------#
#-------------------------------------------------------------#

Add-Type -AssemblyName PresentationCore, PresentationFramework


#Build the GUI
[xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    x:Name="Window" Title="Initial Window" WindowStartupLocation = "CenterScreen" 
    Width="800" Height="400"  AllowsTransparency="True" WindowStyle="None" ResizeMode="CanResize" Background="Transparent"> 
    <WindowChrome.WindowChrome>
        <WindowChrome 
            CaptionHeight="0"
            ResizeBorderThickness="5" 
        />
    </WindowChrome.WindowChrome>
    <Grid>
        <ListBox x:Name="lbChat" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" BorderBrush="Black" 
        BorderThickness="2" ScrollViewer.HorizontalScrollBarVisibility="Disabled" DisplayMemberPath="ChatLine"
        Background="#88cccccc" ScrollViewer.VerticalScrollBarVisibility="Hidden">
            <ListBox.ItemContainerStyle>
                <Style TargetType="ListBoxItem">
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="ListBoxItem">
                                <StackPanel>
                                    <TextBlock Text="{Binding Path=ChatLine}" FontSize="30" TextWrapping="Wrap" Margin="30, 0, 30, 0"/>
                                    <Rectangle HorizontalAlignment="Stretch" Fill="Black" Height="2"/>
                                </StackPanel>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>

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
                        <DataTrigger Binding="{Binding Path=PlayerNumber}" Value="9">
                            <Setter Property="ListBoxItem.Foreground" Value="Black" />
                        </DataTrigger>                                
                    </Style.Triggers>
                    
                </Style>
            </ListBox.ItemContainerStyle> 

            
        </ListBox>
    </Grid>
</Window>
"@

#-------------------------------------------------------------#
#----Control Event Handlers-----------------------------------#
#-------------------------------------------------------------#

$Global:LinesRead = 0

function Update-Chat()
{
    $contentChanged = $false

    $file = "$global:baseDirectory/currentChat.txt"
    if($file -ne "" -and (Test-Path -Path $file))
    {            
        $fileRead = $false

        while(-not $fileRead)
        {
            try
            {
                $allLines = (Get-Content $file -Encoding Unicode) -split "\n"
                $fileRead = $true
            }
            catch
            {
                Start-Sleep -Milliseconds (Get-Random -Minimum 20 -Maximum 70)
            }
        }

        if($allLines.Length -ne $Global:LinesRead)
        {
            $observableCollection.Clear()
            $contentChanged = $true
            $Global:LinesRead = 0

            for($i = 0; $i + 2 -lt $allLines.Length; $i += 3)
            {
                $Global:LinesRead = $Global:LinesRead + 3

                $playerNumber = $allLines[$i + 0]
                $playerName = $allLines[$i + 1]
                $message = $allLines[$i + 2]

                $chatLine = "$($playerName): $message"
                 
                $observableCollection.Add([PSCustomObject]@{
                    ChatLine = $chatLine
                    PlayerNumber = $playerNumber
                })
            }
        }
    }

    if($contentChanged)
    {
        $border = [Windows.Media.VisualTreeHelper]::GetChild($lbChat, 0) -as [System.Windows.Controls.Decorator]
        $scrollViewer = $border.Child -as [System.Windows.Controls.ScrollViewer]
        $scrollViewer.ScrollToBottom()
    }
}

#endregion

#-------------------------------------------------------------#
#----Script Execution-----------------------------------------#
#-------------------------------------------------------------#
    
$global:baseDirectory = Get-BaseDir
 
$reader=(New-Object System.Xml.XmlNodeReader $xaml)
$Window=[Windows.Markup.XamlReader]::Load( $reader )

#Connect to Controls
$lbChat = $Window.FindName('lbChat')

$Window.Add_Loaded({
    #Have to have something initially in the collection
    $Global:observableCollection = New-Object System.Collections.ObjectModel.ObservableCollection[System.Object]
    $lbChat.ItemsSource = $observableCollection
    
    # Before the window's even displayed ...            
    # We'll create a timer            
    $script:timer = new-object System.Windows.Threading.DispatcherTimer            
    # Which fire 1 time each second
    $timer.Interval = [TimeSpan]"0:0:1.0"            
    # And will invoke the $updateBlock          
    $timer.Add_Tick.Invoke({ Update-Chat })           
    # Now start the timer running            
    $timer.Start()  
    if( $timer.IsEnabled -eq $false) { 
       Write-Debug "Timer didn't start"      
    }  
})

$Window.Add_KeyDown({ 
    param(
        [Parameter(Mandatory)][Object]$sender, 
        [Parameter(Mandatory)][Windows.Input.KeyEventArgs]$keyEventArgs
    ); 

    if($keyEventArgs.Key -eq 'C')
    {
        if($Global:LinesRead -ne 0)
        {
            Push-Backup

            $observableCollection.clear()
            $Global:LinesRead = 0

            Update-Chat
        }
    } 
})

$lbChat.Add_MouseDown({$Window.DragMove()})

$Window.ShowDialog() | Out-Null