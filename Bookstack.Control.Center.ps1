#Requires -Version 5.1
# =====================================================================================
# BOOKSTACK CONTROL CENTER v3.0
# Single-file PowerShell WPF Dashboard
# Refactored with improved architecture, error handling, and maintainability
# =====================================================================================

using namespace System.Windows
using namespace System.Windows.Controls
using namespace System.Windows.Documents
using namespace System.Windows.Media
using namespace System.IO

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# =====================================================================================
# CONFIGURATION CLASS
# =====================================================================================

class BookStackConfig {
    [string]$RootPath = "C:\BookStack"
    [int]$WebPort = 8080
    [int]$RefreshIntervalSeconds = 3
    [int]$LogTailLines = 150
    [int]$MaxUnifiedLogEntries = 500
    [int]$MaxNewLinesPerRead = 50
    [int]$InitialLogBytesToRead = 5000
    
    [string]$ApacheExePath
    [string]$MariaDBExePath
    [string]$MariaDBConfigPath
    [string]$PHPExePath
    
    [hashtable]$SourceColors = @{
        SYSTEM     = "#1E90FF"
        SUPERVISOR = "#9932CC"
        Apache     = "#FF6B35"
        ApacheAcc  = "#FFA500"
        MariaDB    = "#00CED1"
        PHP        = "#8A2BE2"
        Laravel    = "#DC143C"
        BookStack  = "#228B22"
        Queue      = "#FF69B4"
        Scheduler  = "#4169E1"
        Debug      = "#808080"
    }
    
    [hashtable]$StatusColors = @{
        OK      = "#2E8B57"
        Warning = "#E6A700"
        Error   = "#C00000"
        Idle    = "#606060"
    }
    
    BookStackConfig() {
        $this.ApacheExePath = Join-Path $this.RootPath "apache\bin\httpd.exe"
        $this.MariaDBExePath = Join-Path $this.RootPath "mariadb\bin\mysqld.exe"
        $this.MariaDBConfigPath = Join-Path $this.RootPath "mariadb\my.ini"
        $this.PHPExePath = Join-Path $this.RootPath "php\php.exe"
    }
    
    [string[]] GetLogSearchPaths([string]$LogType) {
        $paths = switch ($LogType) {
            'ApacheError' {
                @(
                    "$($this.RootPath)\logs\apache_error.log"
                    "$($this.RootPath)\apache\logs\error.log"
                    "$($this.RootPath)\apache\logs\apache_error.log"
                )
            }
            'ApacheAccess' {
                @(
                    "$($this.RootPath)\logs\apache_access.log"
                    "$($this.RootPath)\apache\logs\access.log"
                    "$($this.RootPath)\apache\logs\apache_access.log"
                )
            }
            'MariaDB' {
                @(
                    "$($this.RootPath)\logs\mariadb_error.log"
                    "$($this.RootPath)\mariadb\data\*.err"
                    "$($this.RootPath)\data\mysql\*.err"
                )
            }
            'PHP' {
                @(
                    "$($this.RootPath)\php\logs\php_errors.log"
                    "$($this.RootPath)\logs\php_errors.log"
                    "$($this.RootPath)\app\storage\logs\php_errors.log"
                )
            }
            'Laravel' {
                @(
                    "$($this.RootPath)\app\storage\logs\laravel-*.log"
                    "$($this.RootPath)\app\storage\logs\laravel.log"
                    "$($this.RootPath)\www\storage\logs\laravel.log"
                )
            }
            'BookStack' {
                @(
                    "$($this.RootPath)\app\storage\logs\bookstack.log"
                    "$($this.RootPath)\www\storage\logs\bookstack.log"
                )
            }
            'Queue' {
                @("$($this.RootPath)\app\storage\logs\queue.log")
            }
            'Scheduler' {
                @("$($this.RootPath)\app\storage\logs\scheduler.log")
            }
            default { @() }
        }
        return $paths
    }
    
    [string[]] GetLogFolders() {
        return @(
            "$($this.RootPath)\logs"
            "$($this.RootPath)\app\storage\logs"
            "$($this.RootPath)\www\storage\logs"
            "$($this.RootPath)\apache\logs"
        )
    }
}

# =====================================================================================
# SESSION STATISTICS
# =====================================================================================

class SessionStatistics {
    [int]$LogEntryCount = 0
    [int]$ErrorCount = 0
    [int]$WarningCount = 0
    [int]$AutoRestartCount = 0
    [datetime]$StartTime = (Get-Date)
    
    [void] IncrementLogCount() { $this.LogEntryCount++ }
    [void] IncrementErrors() { $this.ErrorCount++ }
    [void] IncrementWarnings() { $this.WarningCount++ }
    [void] IncrementRestarts() { $this.AutoRestartCount++ }
    
    [void] Reset() {
        $this.LogEntryCount = 0
        $this.ErrorCount = 0
        $this.WarningCount = 0
    }
    
    [TimeSpan] GetUptime() {
        return (Get-Date) - $this.StartTime
    }
}

# =====================================================================================
# LOG FILE MANAGER
# =====================================================================================

class LogFileManager {
    hidden [hashtable]$FilePositions = @{}
    hidden [BookStackConfig]$Config
    hidden [hashtable]$ResolvedPaths = @{}
    
    LogFileManager([BookStackConfig]$config) {
        $this.Config = $config
        $this.RefreshLogPaths()
    }
    
    [void] RefreshLogPaths() {
        $logTypes = @('ApacheError', 'ApacheAccess', 'MariaDB', 'PHP', 'Laravel', 'BookStack', 'Queue', 'Scheduler')
        
        foreach ($logType in $logTypes) {
            $this.ResolvedPaths[$logType] = $this.FindLogFile($logType)
        }
    }
    
    hidden [string] FindLogFile([string]$logType) {
        $searchPaths = $this.Config.GetLogSearchPaths($logType)
        
        foreach ($path in $searchPaths) {
            if ($path -match '\*') {
                $files = Get-ChildItem -Path $path -ErrorAction SilentlyContinue |
                         Sort-Object LastWriteTime -Descending |
                         Select-Object -First 1
                if ($files) {
                    return $files.FullName
                }
            }
            elseif (Test-Path -Path $path -PathType Leaf) {
                return $path
            }
        }
        return $null
    }
    
    [string] GetLogPath([string]$logType) {
        return $this.ResolvedPaths[$logType]
    }
    
    [hashtable] GetAllResolvedPaths() {
        return $this.ResolvedPaths.Clone()
    }
    
    [string[]] ReadNewLines([string]$logType) {
        $path = $this.GetLogPath($logType)
        if (-not $path -or -not (Test-Path -Path $path)) {
            return @()
        }
        
        try {
            $fileInfo = Get-Item -Path $path
            $lastPosition = $this.FilePositions[$path]
            
            if ($null -eq $lastPosition) {
                $lastPosition = [Math]::Max(0, $fileInfo.Length - $this.Config.InitialLogBytesToRead)
            }
            
            # Handle log rotation
            if ($fileInfo.Length -lt $lastPosition) {
                $lastPosition = 0
            }
            
            $newLines = [System.Collections.Generic.List[string]]::new()
            
            if ($fileInfo.Length -gt $lastPosition) {
                $stream = $null
                $reader = $null
                
                try {
                    $stream = [FileStream]::new(
                        $path,
                        [FileMode]::Open,
                        [FileAccess]::Read,
                        [FileShare]::ReadWrite
                    )
                    $reader = [StreamReader]::new($stream)
                    
                    [void]$stream.Seek($lastPosition, [SeekOrigin]::Begin)
                    
                    $lineCount = 0
                    while (-not $reader.EndOfStream -and $lineCount -lt $this.Config.MaxNewLinesPerRead) {
                        $line = $reader.ReadLine()
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            $newLines.Add($line)
                            $lineCount++
                        }
                    }
                    
                    $this.FilePositions[$path] = $stream.Position
                }
                finally {
                    if ($reader) { $reader.Dispose() }
                    if ($stream) { $stream.Dispose() }
                }
            }
            
            return $newLines.ToArray()
        }
        catch {
            Write-Warning "Failed to read log file '$path': $_"
            return @()
        }
    }
    
    [string] GetFullContent([string]$logType) {
        $path = $this.GetLogPath($logType)
        
        if (-not $path) {
            return "Log file not configured for type: $logType"
        }
        
        if (-not (Test-Path -Path $path)) {
            return "Log file not found: $path"
        }
        
        try {
            $content = Get-Content -Path $path -Tail $this.Config.LogTailLines -ErrorAction Stop
            return ($content -join "`r`n")
        }
        catch {
            return "Error reading log file: $_"
        }
    }
    
    [void] ResetPositions() {
        $this.FilePositions.Clear()
    }
}

# =====================================================================================
# SERVICE MANAGER
# =====================================================================================

class ServiceManager {
    hidden [BookStackConfig]$Config
    
    ServiceManager([BookStackConfig]$config) {
        $this.Config = $config
    }
    
    [System.Diagnostics.Process[]] GetApacheProcesses() {
        return Get-Process -Name "httpd" -ErrorAction SilentlyContinue
    }
    
    [System.Diagnostics.Process[]] GetMariaDBProcesses() {
        return Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
    }
    
    [bool] IsApacheRunning() {
        return ($null -ne $this.GetApacheProcesses())
    }
    
    [bool] IsMariaDBRunning() {
        return ($null -ne $this.GetMariaDBProcesses())
    }
    
    [bool] IsWebPortResponding() {
        try {
            $tcpClient = [System.Net.Sockets.TcpClient]::new()
            $asyncResult = $tcpClient.BeginConnect("127.0.0.1", $this.Config.WebPort, $null, $null)
            $waitResult = $asyncResult.AsyncWaitHandle.WaitOne(1000, $false)
            
            $isConnected = $waitResult -and $tcpClient.Connected
            $tcpClient.Close()
            
            return $isConnected
        }
        catch {
            return $false
        }
    }
    
    [string] GetPHPVersion() {
        if (-not (Test-Path -Path $this.Config.PHPExePath)) {
            return "Not Found"
        }
        
        try {
            $output = & $this.Config.PHPExePath -v 2>&1 | Select-Object -First 1
            if ($output -match 'PHP (\d+\.\d+\.\d+)') {
                return $Matches[1]
            }
            return "Unknown"
        }
        catch {
            return "Error"
        }
    }
    
    [hashtable] StartServices() {
        $results = @{
            Apache = @{ Success = $false; Message = "" }
            MariaDB = @{ Success = $false; Message = "" }
        }
        
        # Start MariaDB first
        if (-not $this.IsMariaDBRunning()) {
            try {
                $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = $this.Config.MariaDBExePath
                $startInfo.Arguments = "--defaults-file=`"$($this.Config.MariaDBConfigPath)`""
                $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $startInfo.UseShellExecute = $true
                
                [void][System.Diagnostics.Process]::Start($startInfo)
                $results.MariaDB.Success = $true
                $results.MariaDB.Message = "MariaDB started successfully"
            }
            catch {
                $results.MariaDB.Message = "Failed to start MariaDB: $_"
            }
        }
        else {
            $results.MariaDB.Success = $true
            $results.MariaDB.Message = "MariaDB already running"
        }
        
        Start-Sleep -Milliseconds 500
        
        # Start Apache
        if (-not $this.IsApacheRunning()) {
            try {
                $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = $this.Config.ApacheExePath
                $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $startInfo.UseShellExecute = $true
                
                [void][System.Diagnostics.Process]::Start($startInfo)
                $results.Apache.Success = $true
                $results.Apache.Message = "Apache started successfully"
            }
            catch {
                $results.Apache.Message = "Failed to start Apache: $_"
            }
        }
        else {
            $results.Apache.Success = $true
            $results.Apache.Message = "Apache already running"
        }
        
        return $results
    }
    
    [hashtable] StopServices() {
        $results = @{
            StoppedProcesses = [System.Collections.Generic.List[string]]::new()
            Errors = [System.Collections.Generic.List[string]]::new()
        }
        
        $processes = @()
        $processes += $this.GetApacheProcesses()
        $processes += $this.GetMariaDBProcesses()
        
        foreach ($proc in $processes) {
            if ($null -ne $proc) {
                try {
                    $procName = $proc.Name
                    $procId = $proc.Id
                    $proc | Stop-Process -Force -ErrorAction Stop
                    $results.StoppedProcesses.Add("$procName (PID: $procId)")
                }
                catch {
                    $results.Errors.Add("Failed to stop $($proc.Name): $_")
                }
            }
        }
        
        return $results
    }
    
    [hashtable] GetServiceStatus() {
        $apacheProcs = $this.GetApacheProcesses()
        $mariaProcs = $this.GetMariaDBProcesses()
        
        return @{
            Apache = @{
                Running = ($null -ne $apacheProcs)
                PIDs = if ($apacheProcs) { $apacheProcs.Id -join ', ' } else { $null }
            }
            MariaDB = @{
                Running = ($null -ne $mariaProcs)
                PIDs = if ($mariaProcs) { $mariaProcs.Id -join ', ' } else { $null }
            }
            PHP = @{
                Available = (Test-Path -Path $this.Config.PHPExePath)
                Version = $this.GetPHPVersion()
            }
            Web = @{
                Responding = $this.IsWebPortResponding()
                Port = $this.Config.WebPort
            }
        }
    }
}

# =====================================================================================
# LOG LEVEL DETECTOR
# =====================================================================================

class LogLevelDetector {
    static [string] Detect([string]$line) {
        $lowerLine = $line.ToLowerInvariant()
        
        $errorPatterns = @(
            'error', 'exception', 'fatal', 'critical', 'fail',
            '\[error\]', '\[crit\]', '\[alert\]', '\[emerg\]'
        )
        
        $warningPatterns = @(
            'warn', 'warning', 'notice', '\[warn\]', '\[notice\]'
        )
        
        foreach ($pattern in $errorPatterns) {
            if ($lowerLine -match $pattern) {
                return "ERROR"
            }
        }
        
        foreach ($pattern in $warningPatterns) {
            if ($lowerLine -match $pattern) {
                return "WARNING"
            }
        }
        
        return "INFO"
    }
}

# =====================================================================================
# CONSOLE LOGGER
# =====================================================================================

class ConsoleLogger {
    static [void] Write([string]$level, [string]$message) {
        $timestamp = Get-Date -Format "HH:mm:ss.fff"
        $color = switch ($level) {
            "ERROR"      { "Red" }
            "WARNING"    { "Yellow" }
            "SYSTEM"     { "Cyan" }
            "SUPERVISOR" { "Magenta" }
            default      { "White" }
        }
        Write-Host "[$level][$timestamp] $message" -ForegroundColor $color
    }
}

# =====================================================================================
# UI MANAGER
# =====================================================================================

class UIManager {
    hidden [Window]$Window
    hidden [BookStackConfig]$Config
    hidden [hashtable]$Elements = @{}
    hidden [BrushConverter]$BrushConverter = [BrushConverter]::new()
    
    UIManager([string]$xaml, [BookStackConfig]$config) {
        $this.Config = $config
        $this.Window = [Markup.XamlReader]::Parse($xaml)
        $this.CacheUIElements()
    }
    
    hidden [void] CacheUIElements() {
        $elementNames = @(
            # Labels
            'LblTime', 'LblUptime',
            'LblApache', 'LblApachePID',
            'LblMaria', 'LblMariaPID',
            'LblPHP', 'LblPHPVersion',
            'LblWeb', 'LblWebPort',
            
            # Buttons
            'BtnStart', 'BtnStop', 'BtnRestart', 'BtnClearLogs',
            'BtnOpenBrowser', 'BtnOpenLogFolder', 'BtnRefreshNow',
            
            # Checkboxes
            'ChkSupervisor', 'ChkAutoScroll', 'ChkShowTimestamps',
            
            # Log displays
            'LogUnified', 'LogApacheError', 'LogApacheAccess',
            'LogMaria', 'LogPHP', 'LogLaravel', 'LogBookStack',
            'LogQueue', 'LogScheduler',
            
            # Info displays
            'TxtOverview', 'TxtLogPaths',
            
            # Statistics
            'StatLogCount', 'StatErrors', 'StatWarnings', 'StatRestarts'
        )
        
        foreach ($name in $elementNames) {
            $element = $this.Window.FindName($name)
            if ($element) {
                $this.Elements[$name] = $element
            }
        }
    }
    
    [object] GetElement([string]$name) {
        return $this.Elements[$name]
    }
    
    [Window] GetWindow() {
        return $this.Window
    }
    
    [void] SetText([string]$elementName, [string]$text) {
        $element = $this.Elements[$elementName]
        if ($element) {
            $element.Text = $text
        }
    }
    
    [void] SetForeground([string]$elementName, [string]$colorHex) {
        $element = $this.Elements[$elementName]
        if ($element) {
            $element.Foreground = $this.BrushConverter.ConvertFromString($colorHex)
        }
    }
    
    [void] SetEnabled([string]$elementName, [bool]$enabled) {
        $element = $this.Elements[$elementName]
        if ($element) {
            $element.IsEnabled = $enabled
        }
    }
    
    [bool] IsChecked([string]$elementName) {
        $element = $this.Elements[$elementName]
        if ($element) {
            return $element.IsChecked -eq $true
        }
        return $false
    }
    
    [void] AppendToUnifiedLog([string]$source, [string]$message, [string]$level, [bool]$showTimestamp) {
        $logBox = $this.Elements['LogUnified']
        if (-not $logBox) { return }
        
        try {
            $paragraph = [Paragraph]::new()
            $paragraph.Margin = [Thickness]::new(0, 2, 0, 2)
            $paragraph.LineHeight = 1
            
            # Timestamp
            if ($showTimestamp) {
                $timestamp = Get-Date -Format "HH:mm:ss.fff"
                $timeRun = [Run]::new("[$timestamp] ")
                $timeRun.Foreground = $this.BrushConverter.ConvertFromString("#888888")
                [void]$paragraph.Inlines.Add($timeRun)
            }
            
            # Source tag
            $sourceColor = $this.Config.SourceColors[$source]
            if (-not $sourceColor) { $sourceColor = "#FFFFFF" }
            
            $sourceRun = [Run]::new("[$source]")
            $sourceRun.Foreground = $this.BrushConverter.ConvertFromString($sourceColor)
            $sourceRun.FontWeight = [FontWeights]::Bold
            [void]$paragraph.Inlines.Add($sourceRun)
            
            # Space
            [void]$paragraph.Inlines.Add([Run]::new(" "))
            
            # Level indicator
            if ($level -eq "ERROR") {
                $levelRun = [Run]::new("[ERROR] ")
                $levelRun.Foreground = $this.BrushConverter.ConvertFromString("#FF4444")
                $levelRun.FontWeight = [FontWeights]::Bold
                [void]$paragraph.Inlines.Add($levelRun)
            }
            elseif ($level -eq "WARNING") {
                $levelRun = [Run]::new("[WARN] ")
                $levelRun.Foreground = $this.BrushConverter.ConvertFromString("#FFD700")
                $levelRun.FontWeight = [FontWeights]::Bold
                [void]$paragraph.Inlines.Add($levelRun)
            }
            
            # Message
            $displayMessage = if ($message.Length -gt 500) {
                $message.Substring(0, 500) + "..."
            } else {
                $message
            }
            
            $messageColor = switch ($level) {
                "ERROR"   { "#FF6666" }
                "WARNING" { "#FFD700" }
                "INFO"    { "#AAFFAA" }
                default   { "#D4D4D4" }
            }
            
            $messageRun = [Run]::new($displayMessage)
            $messageRun.Foreground = $this.BrushConverter.ConvertFromString($messageColor)
            [void]$paragraph.Inlines.Add($messageRun)
            
            # Add to document
            [void]$logBox.Document.Blocks.Add($paragraph)
            
            # Trim old entries
            while ($logBox.Document.Blocks.Count -gt $this.Config.MaxUnifiedLogEntries) {
                [void]$logBox.Document.Blocks.Remove($logBox.Document.Blocks.FirstBlock)
            }
            
            # Auto-scroll
            if ($this.IsChecked('ChkAutoScroll')) {
                $logBox.ScrollToEnd()
            }
        }
        catch {
            [ConsoleLogger]::Write("ERROR", "Failed to write to unified log: $_")
        }
    }
    
    [void] ClearUnifiedLog() {
        $logBox = $this.Elements['LogUnified']
        if ($logBox) {
            $logBox.Document.Blocks.Clear()
        }
    }
    
    [void] UpdateLogTextBox([string]$elementName, [string]$content) {
        $element = $this.Elements[$elementName]
        if ($element) {
            $element.Text = $content
            if ($this.IsChecked('ChkAutoScroll')) {
                $element.ScrollToEnd()
            }
        }
    }
}

# =====================================================================================
# XAML DEFINITION
# =====================================================================================

$XamlDefinition = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="BookStack Control Center v3.0"
        WindowState="Maximized"
        Background="#F5F5F5"
        Foreground="#202020"
        FontFamily="Segoe UI">

    <Window.Resources>
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Opacity" Value="0.9"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Opacity" Value="0.5"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        
        <Style x:Key="LogTextBox" TargetType="TextBox">
            <Setter Property="IsReadOnly" Value="True"/>
            <Setter Property="AcceptsReturn" Value="True"/>
            <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
            <Setter Property="HorizontalScrollBarVisibility" Value="Auto"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Background" Value="#1E1E1E"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        
        <Style x:Key="StatusCard" TargetType="Border">
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="12"/>
            <Setter Property="Margin" Value="4,0"/>
        </Style>
        
        <Style x:Key="SectionBorder" TargetType="Border">
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#E0E0E0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
            <Setter Property="Padding" Value="14"/>
        </Style>
    </Window.Resources>

    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- HEADER -->
        <Border CornerRadius="6" Padding="18">
            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                    <GradientStop Color="#1a365d" Offset="0"/>
                    <GradientStop Color="#2563eb" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>
            <Border.Effect>
                <DropShadowEffect ShadowDepth="2" Opacity="0.25" BlurRadius="8"/>
            </Border.Effect>
            <DockPanel>
                <StackPanel DockPanel.Dock="Left">
                    <TextBlock Text="📚 BOOKSTACK CONTROL CENTER" FontSize="26" FontWeight="Bold" Foreground="White"/>
                    <TextBlock Text="Service Monitor and Log Aggregator v3.0" FontSize="12" Foreground="#93c5fd" Margin="0,4,0,0"/>
                </StackPanel>
                <StackPanel DockPanel.Dock="Right" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <TextBlock Name="LblTime" FontSize="18" Foreground="White" FontWeight="SemiBold" HorizontalAlignment="Right"/>
                    <TextBlock Name="LblUptime" FontSize="11" Foreground="#93c5fd" HorizontalAlignment="Right" Margin="0,2,0,0"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- STATUS BAR -->
        <Border Grid.Row="1" Margin="0,12,0,12" Background="#FFFFFF" BorderBrush="#E0E0E0" BorderThickness="1" CornerRadius="6">
            <Border.Effect>
                <DropShadowEffect ShadowDepth="1" Opacity="0.12" BlurRadius="4"/>
            </Border.Effect>
            <Grid Margin="16">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Apache Status -->
                <Border Style="{StaticResource StatusCard}" Background="#fef3c7" BorderBrush="#fcd34d">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                            <TextBlock Text="🌐" FontSize="18" Margin="0,0,8,0"/>
                            <TextBlock Text="Apache HTTP" FontWeight="SemiBold" FontSize="14" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Name="LblApache" FontWeight="Bold" FontSize="13"/>
                        <TextBlock Name="LblApachePID" FontSize="10" Foreground="#666" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <!-- MariaDB Status -->
                <Border Grid.Column="1" Style="{StaticResource StatusCard}" Background="#cffafe" BorderBrush="#22d3d3">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                            <TextBlock Text="🗄" FontSize="18" Margin="0,0,8,0"/>
                            <TextBlock Text="MariaDB" FontWeight="SemiBold" FontSize="14" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Name="LblMaria" FontWeight="Bold" FontSize="13"/>
                        <TextBlock Name="LblMariaPID" FontSize="10" Foreground="#666" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <!-- PHP Status -->
                <Border Grid.Column="2" Style="{StaticResource StatusCard}" Background="#ede9fe" BorderBrush="#a78bfa">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                            <TextBlock Text="🐘" FontSize="18" Margin="0,0,8,0"/>
                            <TextBlock Text="PHP Engine" FontWeight="SemiBold" FontSize="14" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Name="LblPHP" FontWeight="Bold" FontSize="13"/>
                        <TextBlock Name="LblPHPVersion" FontSize="10" Foreground="#666" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <!-- BookStack Web -->
                <Border Grid.Column="3" Style="{StaticResource StatusCard}" Background="#dcfce7" BorderBrush="#4ade80">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                            <TextBlock Text="📖" FontSize="18" Margin="0,0,8,0"/>
                            <TextBlock Text="BookStack Web" FontWeight="SemiBold" FontSize="14" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Name="LblWeb" FontWeight="Bold" FontSize="13"/>
                        <TextBlock Name="LblWebPort" FontSize="10" Foreground="#666" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <!-- Control Buttons -->
                <StackPanel Grid.Column="4" Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,0,0">
                    <Button Name="BtnStart" Style="{StaticResource ActionButton}" Background="#22c55e" Foreground="White" Margin="4">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="▶" Margin="0,0,6,0"/>
                            <TextBlock Text="Start"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnStop" Style="{StaticResource ActionButton}" Background="#ef4444" Foreground="White" Margin="4">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="■" Margin="0,0,6,0"/>
                            <TextBlock Text="Stop"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnRestart" Style="{StaticResource ActionButton}" Background="#3b82f6" Foreground="White" Margin="4">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="↻" Margin="0,0,6,0"/>
                            <TextBlock Text="Restart"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnClearLogs" Style="{StaticResource ActionButton}" Background="#6b7280" Foreground="White" Margin="4">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="🗑" Margin="0,0,6,0"/>
                            <TextBlock Text="Clear"/>
                        </StackPanel>
                    </Button>
                </StackPanel>
            </Grid>
        </Border>

        <!-- MAIN CONTENT -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="360"/>
            </Grid.ColumnDefinitions>

            <!-- LEFT: LOG TABS -->
            <TabControl Background="#FFFFFF" BorderBrush="#E0E0E0" BorderThickness="1">
                <TabControl.Resources>
                    <Style TargetType="TabItem">
                        <Setter Property="Padding" Value="12,8"/>
                    </Style>
                </TabControl.Resources>

                <!-- Unified Logs Tab -->
                <TabItem>
                    <TabItem.Header>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="📋" Margin="0,0,6,0"/>
                            <TextBlock Text="Unified Logs"/>
                        </StackPanel>
                    </TabItem.Header>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <Border Background="#f8fafc" BorderBrush="#e2e8f0" BorderThickness="0,0,0,1" Padding="12,10">
                            <WrapPanel>
                                <TextBlock Text="Sources: " FontWeight="SemiBold" Margin="0,0,12,0" VerticalAlignment="Center"/>
                                <Border Background="#FF6B35" CornerRadius="4" Padding="10,4" Margin="3">
                                    <TextBlock Text="Apache" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
                                </Border>
                                <Border Background="#00CED1" CornerRadius="4" Padding="10,4" Margin="3">
                                    <TextBlock Text="MariaDB" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
                                </Border>
                                <Border Background="#8A2BE2" CornerRadius="4" Padding="10,4" Margin="3">
                                    <TextBlock Text="PHP" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
                                </Border>
                                <Border Background="#DC143C" CornerRadius="4" Padding="10,4" Margin="3">
                                    <TextBlock Text="Laravel" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
                                </Border>
                                <Border Background="#228B22" CornerRadius="4" Padding="10,4" Margin="3">
                                    <TextBlock Text="BookStack" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
                                </Border>
                                <Border Background="#9932CC" CornerRadius="4" Padding="10,4" Margin="3">
                                    <TextBlock Text="Supervisor" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
                                </Border>
                                <Border Background="#1E90FF" CornerRadius="4" Padding="10,4" Margin="3">
                                    <TextBlock Text="System" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
                                </Border>
                            </WrapPanel>
                        </Border>
                        
                        <RichTextBox Name="LogUnified" Grid.Row="1"
                                     IsReadOnly="True"
                                     VerticalScrollBarVisibility="Auto"
                                     HorizontalScrollBarVisibility="Auto"
                                     FontFamily="Consolas"
                                     FontSize="11"
                                     Background="#1E1E1E"
                                     Foreground="#D4D4D4"
                                     BorderThickness="0"
                                     Padding="8">
                            <RichTextBox.Resources>
                                <Style TargetType="Paragraph">
                                    <Setter Property="Margin" Value="0,1,0,1"/>
                                </Style>
                            </RichTextBox.Resources>
                        </RichTextBox>
                    </Grid>
                </TabItem>

                <!-- Apache Logs Tab -->
                <TabItem>
                    <TabItem.Header>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="🌐" Margin="0,0,6,0"/>
                            <TextBlock Text="Apache"/>
                        </StackPanel>
                    </TabItem.Header>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <Border Background="#fef3c7" Padding="12">
                            <TextBlock Text="Apache HTTP Server Logs" FontWeight="SemiBold" FontSize="13"/>
                        </Border>
                        
                        <GroupBox Grid.Row="1" Header="Error Log" Margin="8" BorderBrush="#FF6B35">
                            <TextBox Name="LogApacheError" Style="{StaticResource LogTextBox}" Foreground="#FF6B35"/>
                        </GroupBox>
                        
                        <GroupBox Grid.Row="2" Header="Access Log" Margin="8" BorderBrush="#FFA500">
                            <TextBox Name="LogApacheAccess" Style="{StaticResource LogTextBox}" Foreground="#FFA500"/>
                        </GroupBox>
                    </Grid>
                </TabItem>

                <!-- MariaDB Logs Tab -->
                <TabItem>
                    <TabItem.Header>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="🗄" Margin="0,0,6,0"/>
                            <TextBlock Text="MariaDB"/>
                        </StackPanel>
                    </TabItem.Header>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <Border Background="#cffafe" Padding="12">
                            <TextBlock Text="MariaDB Database Server Logs" FontWeight="SemiBold" FontSize="13"/>
                        </Border>
                        
                        <TextBox Name="LogMaria" Grid.Row="1" Style="{StaticResource LogTextBox}" Foreground="#00CED1" Margin="8"/>
                    </Grid>
                </TabItem>

                <!-- PHP Logs Tab -->
                <TabItem>
                    <TabItem.Header>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="🐘" Margin="0,0,6,0"/>
                            <TextBlock Text="PHP"/>
                        </StackPanel>
                    </TabItem.Header>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <Border Background="#ede9fe" Padding="12">
                            <TextBlock Text="PHP Error Logs" FontWeight="SemiBold" FontSize="13"/>
                        </Border>
                        
                        <TextBox Name="LogPHP" Grid.Row="1" Style="{StaticResource LogTextBox}" Foreground="#8A2BE2" Margin="8"/>
                    </Grid>
                </TabItem>

                <!-- Laravel/BookStack Logs Tab -->
                <TabItem>
                    <TabItem.Header>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="📖" Margin="0,0,6,0"/>
                            <TextBlock Text="BookStack/Laravel"/>
                        </StackPanel>
                    </TabItem.Header>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <Border Background="#dcfce7" Padding="12">
                            <TextBlock Text="BookStack Application and Laravel Framework Logs" FontWeight="SemiBold" FontSize="13"/>
                        </Border>
                        
                        <GroupBox Grid.Row="1" Header="Laravel Log" Margin="8" BorderBrush="#DC143C">
                            <TextBox Name="LogLaravel" Style="{StaticResource LogTextBox}" Foreground="#DC143C"/>
                        </GroupBox>
                        
                        <GroupBox Grid.Row="2" Header="BookStack Application Log" Margin="8" BorderBrush="#228B22">
                            <TextBox Name="LogBookStack" Style="{StaticResource LogTextBox}" Foreground="#228B22"/>
                        </GroupBox>
                    </Grid>
                </TabItem>

                <!-- Queue/Scheduler Tab -->
                <TabItem>
                    <TabItem.Header>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="⚙" Margin="0,0,6,0"/>
                            <TextBlock Text="Queue/Scheduler"/>
                        </StackPanel>
                    </TabItem.Header>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <Border Background="#fce7f3" Padding="12">
                            <TextBlock Text="Background Jobs and Scheduled Tasks" FontWeight="SemiBold" FontSize="13"/>
                        </Border>
                        
                        <GroupBox Grid.Row="1" Header="Queue Worker Log" Margin="8" BorderBrush="#FF69B4">
                            <TextBox Name="LogQueue" Style="{StaticResource LogTextBox}" Foreground="#FF69B4"/>
                        </GroupBox>
                        
                        <GroupBox Grid.Row="2" Header="Scheduler Log" Margin="8" BorderBrush="#4169E1">
                            <TextBox Name="LogScheduler" Style="{StaticResource LogTextBox}" Foreground="#4169E1"/>
                        </GroupBox>
                    </Grid>
                </TabItem>
            </TabControl>

            <!-- RIGHT: CONTROL PANEL -->
            <Border Grid.Column="1" Margin="12,0,0,0" Background="#FFFFFF" BorderBrush="#E0E0E0" BorderThickness="1" CornerRadius="6">
                <Border.Effect>
                    <DropShadowEffect ShadowDepth="1" Opacity="0.12" BlurRadius="4"/>
                </Border.Effect>

                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16">
                    <StackPanel>
                        <TextBlock Text="🎛 CONTROL PANEL" FontSize="18" FontWeight="Bold" Margin="0,0,0,16"/>

                        <!-- Auto-Recovery Settings -->
                        <Border Style="{StaticResource SectionBorder}" Background="#eff6ff">
                            <StackPanel>
                                <TextBlock Text="Auto-Recovery Settings" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,12"/>
                                <CheckBox Name="ChkSupervisor" Content="🔄 Automatically restart crashed services" FontSize="12" IsChecked="True" Margin="0,0,0,8"/>
                                <CheckBox Name="ChkAutoScroll" Content="📜 Auto-scroll logs to bottom" FontSize="12" IsChecked="True" Margin="0,0,0,8"/>
                                <CheckBox Name="ChkShowTimestamps" Content="🕐 Show timestamps in unified log" FontSize="12" IsChecked="True"/>
                            </StackPanel>
                        </Border>

                        <!-- Statistics -->
                        <Border Style="{StaticResource SectionBorder}" Background="#f8fafc">
                            <StackPanel>
                                <TextBlock Text="📊 Session Statistics" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="26"/>
                                        <RowDefinition Height="26"/>
                                        <RowDefinition Height="26"/>
                                        <RowDefinition Height="26"/>
                                    </Grid.RowDefinitions>
                                    
                                    <TextBlock Text="Total Log Entries:" FontSize="12" VerticalAlignment="Center"/>
                                    <TextBlock Name="StatLogCount" Text="0" Grid.Column="1" FontSize="12" FontWeight="Bold" Foreground="#1E90FF"/>
                                    
                                    <TextBlock Grid.Row="1" Text="Errors Detected:" FontSize="12" VerticalAlignment="Center"/>
                                    <TextBlock Name="StatErrors" Grid.Row="1" Grid.Column="1" Text="0" FontSize="12" FontWeight="Bold" Foreground="#C00000"/>
                                    
                                    <TextBlock Grid.Row="2" Text="Warnings Detected:" FontSize="12" VerticalAlignment="Center"/>
                                    <TextBlock Name="StatWarnings" Grid.Row="2" Grid.Column="1" Text="0" FontSize="12" FontWeight="Bold" Foreground="#E6A700"/>
                                    
                                    <TextBlock Grid.Row="3" Text="Auto-Restarts:" FontSize="12" VerticalAlignment="Center"/>
                                    <TextBlock Name="StatRestarts" Grid.Row="3" Grid.Column="1" Text="0" FontSize="12" FontWeight="Bold" Foreground="#9932CC"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <!-- Service Overview -->
                        <Border Style="{StaticResource SectionBorder}">
                            <StackPanel>
                                <TextBlock Text="📋 Service Overview" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,12"/>
                                <TextBox Name="TxtOverview" IsReadOnly="True" TextWrapping="Wrap" FontFamily="Consolas" FontSize="11" Background="Transparent" BorderThickness="0" Height="150"/>
                            </StackPanel>
                        </Border>

                        <!-- Log File Paths -->
                        <Border Style="{StaticResource SectionBorder}" Background="#fefce8">
                            <StackPanel>
                                <TextBlock Text="📂 Monitored Log Files" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,12"/>
                                <TextBox Name="TxtLogPaths" IsReadOnly="True" TextWrapping="Wrap" FontFamily="Consolas" FontSize="9" Background="Transparent" BorderThickness="0" Height="140"/>
                            </StackPanel>
                        </Border>

                        <!-- Quick Actions -->
                        <Border Style="{StaticResource SectionBorder}" Background="#f0fdf4">
                            <StackPanel>
                                <TextBlock Text="⚡ Quick Actions" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,12"/>
                                <Button Name="BtnOpenBrowser" Content="🌐 Open BookStack in Browser" Margin="0,4" Padding="12,8" HorizontalContentAlignment="Left" Cursor="Hand"/>
                                <Button Name="BtnOpenLogFolder" Content="📁 Open Log Folder" Margin="0,4" Padding="12,8" HorizontalContentAlignment="Left" Cursor="Hand"/>
                                <Button Name="BtnRefreshNow" Content="🔄 Force Refresh Now" Margin="0,4" Padding="12,8" HorizontalContentAlignment="Left" Cursor="Hand"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

# =====================================================================================
# APPLICATION CONTROLLER
# =====================================================================================

class BookStackController {
    hidden [BookStackConfig]$Config
    hidden [UIManager]$UI
    hidden [ServiceManager]$Services
    hidden [LogFileManager]$LogManager
    hidden [SessionStatistics]$Stats
    hidden [Threading.DispatcherTimer]$Timer
    
    BookStackController() {
        $this.Config = [BookStackConfig]::new()
        $this.Stats = [SessionStatistics]::new()
        $this.Services = [ServiceManager]::new($this.Config)
        $this.LogManager = [LogFileManager]::new($this.Config)
        
        [ConsoleLogger]::Write("SYSTEM", "Initializing BookStack Control Center v3.0")
        
        try {
            $this.UI = [UIManager]::new($script:XamlDefinition, $this.Config)
            [ConsoleLogger]::Write("SYSTEM", "UI initialized successfully")
        }
        catch {
            [ConsoleLogger]::Write("ERROR", "Failed to initialize UI: $_")
            throw
        }
        
        $this.SetupEventHandlers()
        $this.SetupTimer()
        $this.InitializeDisplay()
    }
    
    hidden [void] SetupEventHandlers() {
        $controller = $this
        
        # Start button
        $this.UI.GetElement('BtnStart').Add_Click({
            $controller.StartServices()
        }.GetNewClosure())
        
        # Stop button
        $this.UI.GetElement('BtnStop').Add_Click({
            $controller.StopServices()
        }.GetNewClosure())
        
        # Restart button
        $this.UI.GetElement('BtnRestart').Add_Click({
            $controller.RestartServices()
        }.GetNewClosure())
        
        # Clear logs button
        $this.UI.GetElement('BtnClearLogs').Add_Click({
            $controller.ClearLogs()
        }.GetNewClosure())
        
        # Open browser button
        $this.UI.GetElement('BtnOpenBrowser').Add_Click({
            $controller.OpenBrowser()
        }.GetNewClosure())
        
        # Open log folder button
        $this.UI.GetElement('BtnOpenLogFolder').Add_Click({
            $controller.OpenLogFolder()
        }.GetNewClosure())
        
        # Force refresh button
        $this.UI.GetElement('BtnRefreshNow').Add_Click({
            $controller.WriteLog("SYSTEM", "Manual refresh triggered", "INFO")
            $controller.UpdateAllLogs()
        }.GetNewClosure())
    }
    
    hidden [void] SetupTimer() {
        $controller = $this
        
        $this.Timer = [Threading.DispatcherTimer]::new()
        $this.Timer.Interval = [TimeSpan]::FromSeconds($this.Config.RefreshIntervalSeconds)
        
        $this.Timer.Add_Tick({
            $controller.OnTimerTick()
        }.GetNewClosure())
    }
    
    hidden [void] InitializeDisplay() {
        # Display detected log paths
        $paths = $this.LogManager.GetAllResolvedPaths()
        
        $pathsText = @"
Detected Log Files:
-------------------
Apache Error:  $(if($paths.ApacheError){$paths.ApacheError}else{"Not found"})
Apache Access: $(if($paths.ApacheAccess){$paths.ApacheAccess}else{"Not found"})
MariaDB:       $(if($paths.MariaDB){$paths.MariaDB}else{"Not found"})
PHP:           $(if($paths.PHP){$paths.PHP}else{"Not found"})
Laravel:       $(if($paths.Laravel){$paths.Laravel}else{"Not found"})
BookStack:     $(if($paths.BookStack){$paths.BookStack}else{"Not found"})

Scan Folders:
$($this.Config.GetLogFolders() -join "`n")
"@
        $this.UI.SetText('TxtLogPaths', $pathsText)
        
        # Log startup messages
        $this.WriteLog("SYSTEM", "BookStack Control Center v3.0 initialized", "INFO")
        $this.WriteLog("SYSTEM", "Root path: $($this.Config.RootPath)", "INFO")
        $this.WriteLog("SYSTEM", "Refresh interval: $($this.Config.RefreshIntervalSeconds) seconds", "INFO")
        
        foreach ($key in $paths.Keys) {
            if ($paths[$key]) {
                $this.WriteLog("SYSTEM", "Found $key log: $($paths[$key])", "INFO")
            }
        }
    }
    
    hidden [void] OnTimerTick() {
        # Update time display
        $this.UI.SetText('LblTime', (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
        $uptime = $this.Stats.GetUptime()
        $this.UI.SetText('LblUptime', "Uptime: {0:hh\:mm\:ss}" -f $uptime)
        
        # Get service status
        $status = $this.Services.GetServiceStatus()
        
        # Update Apache status
        $this.UpdateServiceDisplay(
            'Apache', 'LblApache', 'LblApachePID',
            $status.Apache.Running,
            $status.Apache.PIDs
        )
        
        # Update MariaDB status
        $this.UpdateServiceDisplay(
            'MariaDB', 'LblMaria', 'LblMariaPID',
            $status.MariaDB.Running,
            $status.MariaDB.PIDs
        )
        
        # Update PHP status
        if ($status.PHP.Available -and $status.PHP.Version -ne "Not Found") {
            $this.UI.SetText('LblPHP', "AVAILABLE")
            $this.UI.SetForeground('LblPHP', $this.Config.StatusColors.OK)
        }
        else {
            $this.UI.SetText('LblPHP', "NOT FOUND")
            $this.UI.SetForeground('LblPHP', $this.Config.StatusColors.Warning)
        }
        $this.UI.SetText('LblPHPVersion', "Version: $($status.PHP.Version)")
        
        # Update Web status
        if ($status.Web.Responding) {
            $this.UI.SetText('LblWeb', "ONLINE")
            $this.UI.SetForeground('LblWeb', $this.Config.StatusColors.OK)
            $this.UI.SetText('LblWebPort', "Port: $($status.Web.Port)")
        }
        else {
            $this.UI.SetText('LblWeb', "OFFLINE")
            $this.UI.SetForeground('LblWeb', $this.Config.StatusColors.Warning)
            $this.UI.SetText('LblWebPort', "Port: $($status.Web.Port) (not responding)")
        }
        
        # Auto-restart logic
        if ($this.UI.IsChecked('ChkSupervisor')) {
            if (-not $status.Apache.Running) {
                $this.WriteLog("SUPERVISOR", "Apache is down - auto-restarting...", "WARNING")
                $this.Stats.IncrementRestarts()
                $this.Services.StartServices()
            }
            if (-not $status.MariaDB.Running) {
                $this.WriteLog("SUPERVISOR", "MariaDB is down - auto-restarting...", "WARNING")
                $this.Stats.IncrementRestarts()
                $this.Services.StartServices()
            }
        }
        
        # Update button states
        $servicesRunning = $status.Apache.Running -and $status.MariaDB.Running
        $this.UI.SetEnabled('BtnStart', -not $servicesRunning)
        
        # Update statistics display
        $this.UI.SetText('StatLogCount', $this.Stats.LogEntryCount.ToString())
        $this.UI.SetText('StatErrors', $this.Stats.ErrorCount.ToString())
        $this.UI.SetText('StatWarnings', $this.Stats.WarningCount.ToString())
        $this.UI.SetText('StatRestarts', $this.Stats.AutoRestartCount.ToString())
        
        # Update overview
        $overviewText = @"
Service Status Summary
----------------------
Apache HTTP:    $(if($status.Apache.Running){"RUNNING"}else{"STOPPED"})
MariaDB:        $(if($status.MariaDB.Running){"RUNNING"}else{"STOPPED"})
PHP Engine:     $($status.PHP.Version)
BookStack Web:  $(if($status.Web.Responding){"ONLINE"}else{"OFFLINE"})

Configuration
----------------------
Root Path:      $($this.Config.RootPath)
Web Port:       $($this.Config.WebPort)
Refresh Rate:   $($this.Config.RefreshIntervalSeconds)s
Supervisor:     $($this.UI.IsChecked('ChkSupervisor'))
"@
        $this.UI.SetText('TxtOverview', $overviewText)
        
        # Update logs
        $this.UpdateAllLogs()
    }
    
    hidden [void] UpdateServiceDisplay([string]$serviceName, [string]$statusLabel, [string]$pidLabel, [bool]$running, [string]$pids) {
        if ($running) {
            $this.UI.SetText($statusLabel, "RUNNING")
            $this.UI.SetForeground($statusLabel, $this.Config.StatusColors.OK)
            $this.UI.SetText($pidLabel, "PIDs: $pids")
        }
        else {
            $this.UI.SetText($statusLabel, "STOPPED")
            $this.UI.SetForeground($statusLabel, $this.Config.StatusColors.Error)
            $this.UI.SetText($pidLabel, "No process")
        }
    }
    
    hidden [void] UpdateAllLogs() {
        $logMappings = @{
            ApacheError  = @{ Source = "Apache"; TextBox = "LogApacheError" }
            ApacheAccess = @{ Source = "ApacheAcc"; TextBox = "LogApacheAccess" }
            MariaDB      = @{ Source = "MariaDB"; TextBox = "LogMaria" }
            PHP          = @{ Source = "PHP"; TextBox = "LogPHP" }
            Laravel      = @{ Source = "Laravel"; TextBox = "LogLaravel" }
            BookStack    = @{ Source = "BookStack"; TextBox = "LogBookStack" }
            Queue        = @{ Source = "Queue"; TextBox = "LogQueue" }
            Scheduler    = @{ Source = "Scheduler"; TextBox = "LogScheduler" }
        }
        
        foreach ($logType in $logMappings.Keys) {
            $mapping = $logMappings[$logType]
            
            # Read new lines for unified log
            $newLines = $this.LogManager.ReadNewLines($logType)
            foreach ($line in $newLines) {
                $level = [LogLevelDetector]::Detect($line)
                $this.WriteLog($mapping.Source, $line, $level)
            }
            
            # Update individual log textbox
            $content = $this.LogManager.GetFullContent($logType)
            $this.UI.UpdateLogTextBox($mapping.TextBox, $content)
        }
    }
    
    [void] WriteLog([string]$source, [string]$message, [string]$level) {
        $showTimestamp = $this.UI.IsChecked('ChkShowTimestamps')
        $this.UI.AppendToUnifiedLog($source, $message, $level, $showTimestamp)
        
        $this.Stats.IncrementLogCount()
        if ($level -eq "ERROR") { $this.Stats.IncrementErrors() }
        if ($level -eq "WARNING") { $this.Stats.IncrementWarnings() }
        
        [ConsoleLogger]::Write($source, $message)
    }
    
    [void] StartServices() {
        $this.WriteLog("SUPERVISOR", "Starting services...", "INFO")
        $results = $this.Services.StartServices()
        
        foreach ($service in @('MariaDB', 'Apache')) {
            $result = $results[$service]
            $level = if ($result.Success) { "INFO" } else { "ERROR" }
            $this.WriteLog($service, $result.Message, $level)
        }
    }
    
    [void] StopServices() {
        $this.WriteLog("SUPERVISOR", "Stopping services...", "WARNING")
        $results = $this.Services.StopServices()
        
        foreach ($proc in $results.StoppedProcesses) {
            $this.WriteLog("SUPERVISOR", "Stopped: $proc", "WARNING")
        }
        
        foreach ($error in $results.Errors) {
            $this.WriteLog("SUPERVISOR", $error, "ERROR")
        }
        
        if ($results.StoppedProcesses.Count -eq 0 -and $results.Errors.Count -eq 0) {
            $this.WriteLog("SUPERVISOR", "No services were running", "INFO")
        }
    }
    
    [void] RestartServices() {
        $this.StopServices()
        Start-Sleep -Seconds 2
        $this.StartServices()
    }
    
    [void] ClearLogs() {
        $this.UI.ClearUnifiedLog()
        $this.Stats.Reset()
        $this.LogManager.ResetPositions()
        $this.WriteLog("SYSTEM", "Logs cleared by user", "INFO")
    }
    
    [void] OpenBrowser() {
        $url = "http://127.0.0.1:$($this.Config.WebPort)"
        Start-Process $url
        $this.WriteLog("SYSTEM", "Opening browser to $url", "INFO")
    }
    
    [void] OpenLogFolder() {
        foreach ($folder in $this.Config.GetLogFolders()) {
            if (Test-Path -Path $folder) {
                Start-Process "explorer.exe" -ArgumentList $folder
                $this.WriteLog("SYSTEM", "Opening log folder: $folder", "INFO")
                return
            }
        }
        
        Start-Process "explorer.exe" -ArgumentList $this.Config.RootPath
        $this.WriteLog("SYSTEM", "Opening root folder: $($this.Config.RootPath)", "INFO")
    }
    
    [void] Run() {
        $this.Timer.Start()
        [void]$this.UI.GetWindow().ShowDialog()
        $this.Timer.Stop()
    }
}

# =====================================================================================
# MAIN ENTRY POINT
# =====================================================================================

try {
    $controller = [BookStackController]::new()
    $controller.Run()
}
catch {
    [ConsoleLogger]::Write("ERROR", "Fatal error: $_")
    [ConsoleLogger]::Write("ERROR", $_.ScriptStackTrace)
    Read-Host "Press Enter to exit"
    exit 1
}