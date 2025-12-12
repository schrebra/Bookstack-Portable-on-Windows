#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Portable BookStack Complete Installation Script for Windows

.DESCRIPTION
    Creates a fully portable, self-contained BookStack installation.
    Everything is installed to a single folder including:
    - PHP 8.x
    - Composer
    - Portable Git
    - MariaDB (portable database)
    - BookStack application

    The entire folder can be copied to another Windows machine and run.

.NOTES
    Version: 7.0 (Simplified download system - WebClient only)

    Structure:
    C:\BookStack\
    ├── app\              # BookStack application
    ├── php\              # PHP installation
    ├── composer\         # Composer
    ├── git\              # Portable Git
    ├── mariadb\          # MariaDB database
    ├── data\             # Database files
    ├── logs\             # All logs
    ├── temp\             # Temporary files
    ├── downloads\        # Downloaded files
    ├── START-BOOKSTACK.bat
    ├── STOP-BOOKSTACK.bat
    └── README.txt

.PARAMETER RootPath
    The root installation directory. Default: C:\BookStack

.PARAMETER AppPort
    The port for the BookStack web server. Default: 8080

.PARAMETER DBPort
    The port for MariaDB. Default: 3366

.EXAMPLE
    .\Install-BookStack-Portable.ps1

.EXAMPLE
    .\Install-BookStack-Portable.ps1 -RootPath "D:\BookStack" -AppPort "8000"
#>

param(
    [string]$RootPath = "C:\BookStack",
    [string]$AppPort = "8080",
    [string]$DBPort = "3366",
    [string]$DBName = "bookstack",
    [string]$DBUser = "bookstack",
    [string]$DBPassword = "bookstack123",
    [string]$DBRootPassword = "",
    [switch]$SkipDownloadCache,
    [switch]$Verbose
)

# ============================================================
# INITIALIZATION AND CONFIGURATION
# ============================================================

$ErrorActionPreference = "Continue"
$ProgressPreference = 'SilentlyContinue'
$script:VerboseMode = $Verbose

# Fix TLS/SSL for downloads
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# Create UTF8 encoder without BOM for config files
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# Download statistics
$script:DownloadStats = @{
    Attempted = 0
    Succeeded = 0
    Failed = 0
    TotalBytes = 0
    TotalTime = [TimeSpan]::Zero
}

# ============================================================
# GLOBAL PATH CONFIGURATION
# ============================================================

$script:Paths = @{
    Root        = $RootPath
    App         = "$RootPath\app"
    PHP         = "$RootPath\php"
    Composer    = "$RootPath\composer"
    Git         = "$RootPath\git"
    MariaDB     = "$RootPath\mariadb"
    Data        = "$RootPath\data"
    DataDB      = "$RootPath\data\mysql"
    Logs        = "$RootPath\logs"
    Temp        = "$RootPath\temp"
    Downloads   = "$RootPath\downloads"
    UrlCache    = "$RootPath\downloads\.url_cache.json"
}

$script:Files = @{
    PHPExe          = "$RootPath\php\php.exe"
    PHPIni          = "$RootPath\php\php.ini"
    ComposerPhar    = "$RootPath\composer\composer.phar"
    ComposerBat     = "$RootPath\composer\composer.bat"
    GitExe          = "$RootPath\git\cmd\git.exe"
    MySQLExe        = "$RootPath\mariadb\bin\mysql.exe"
    MySQLDExe       = "$RootPath\mariadb\bin\mysqld.exe"
    MySQLAdminExe   = "$RootPath\mariadb\bin\mysqladmin.exe"
    MySQLInstallDb  = "$RootPath\mariadb\bin\mysql_install_db.exe"
    MariaDBIni      = "$RootPath\mariadb\my.ini"
    EnvBat          = "$RootPath\SETUP-ENVIRONMENT.bat"
    StartBat        = "$RootPath\START-BOOKSTACK.bat"
    StopBat         = "$RootPath\STOP-BOOKSTACK.bat"
    StartDBBat      = "$RootPath\START-DATABASE.bat"
    StopDBBat       = "$RootPath\STOP-DATABASE.bat"
    ReadMe          = "$RootPath\README.txt"
}

# ============================================================
# DISPLAY HELPER FUNCTIONS
# ============================================================

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "                                                                " -ForegroundColor Cyan
    Write-Host "         PORTABLE BOOKSTACK INSTALLER FOR WINDOWS               " -ForegroundColor White
    Write-Host "                      Version 7.0                               " -ForegroundColor Gray
    Write-Host "                                                                " -ForegroundColor Cyan
    Write-Host "         Installation Path: $RootPath" -ForegroundColor Yellow
    Write-Host "                                                                " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host " $Message" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Write-SubStep {
    param([string]$Message)
    Write-Host ""
    Write-Host "--- $Message ---" -ForegroundColor White
}

function Write-OK {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[i] $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[X] $Message" -ForegroundColor Red
}

function Write-Debug {
    param([string]$Message)
    if ($script:VerboseMode) {
        Write-Host "[DEBUG] $Message" -ForegroundColor Gray
    }
}

# ============================================================
# FILE WRITING HELPER (NO BOM)
# ============================================================

function Write-FileNoBom {
    param(
        [string]$Path,
        [string]$Content,
        [switch]$Ascii
    )

    $parentDir = Split-Path $Path -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if ($Ascii) {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
    } else {
        [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
    }
}

# ============================================================
# URL CACHE SYSTEM
# ============================================================

function Get-UrlCache {
    if ($SkipDownloadCache) { return @{} }
    
    $cachePath = $script:Paths.UrlCache
    if (Test-Path $cachePath) {
        try {
            $cacheContent = Get-Content $cachePath -Raw | ConvertFrom-Json
            $cacheAge = (Get-Date) - [DateTime]::Parse($cacheContent.Timestamp)
            
            # Cache valid for 24 hours
            if ($cacheAge.TotalHours -lt 24) {
                Write-Debug "Using cached URLs (age: $([int]$cacheAge.TotalHours) hours)"
                return $cacheContent.Urls
            }
        } catch {
            Write-Debug "Cache invalid, will refresh"
        }
    }
    return @{}
}

function Set-UrlCache {
    param([hashtable]$Urls)
    
    if ($SkipDownloadCache) { return }
    
    $cachePath = $script:Paths.UrlCache
    $cacheDir = Split-Path $cachePath -Parent
    
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    
    $cacheContent = @{
        Timestamp = (Get-Date).ToString("o")
        Urls = $Urls
    }
    
    $cacheContent | ConvertTo-Json -Depth 5 | Set-Content $cachePath -Force
    Write-Debug "URL cache updated"
}

# ============================================================
# SIMPLIFIED DOWNLOAD SYSTEM (WebClient Only)
# ============================================================

function Format-FileSize {
    param([long]$Bytes)
    
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    if ($Bytes -lt 1GB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    return "{0:N2} GB" -f ($Bytes / 1GB)
}

function Download-WithProgress {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Description = "file",
        [int]$TimeoutSeconds = 600,
        [int]$RetryCount = 3,
        [int]$RetryDelaySeconds = 3
    )
    
    $script:DownloadStats.Attempted++
    
    $parentDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    # Remove existing file
    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
    }
    
    $tempPath = "$OutputPath.tmp"
    if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
    
    Write-Info "Downloading: $Description"
    Write-Host "    $Url" -ForegroundColor Gray
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        if ($attempt -gt 1) {
            Write-Host "    Retry $attempt of $RetryCount..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RetryDelaySeconds
            
            # Cleanup failed attempt
            if (Test-Path $tempPath) {
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
        
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
            
            Write-Host "    Downloading..." -ForegroundColor Gray
            $webClient.DownloadFile($Url, $tempPath)
            $webClient.Dispose()
            
            # Verify download
            if ((Test-Path $tempPath) -and (Get-Item $tempPath).Length -gt 1000) {
                Move-Item $tempPath $OutputPath -Force
                $finalSize = (Get-Item $OutputPath).Length
                $stopwatch.Stop()
                $elapsed = $stopwatch.Elapsed.TotalSeconds
                $speed = if ($elapsed -gt 0) { Format-FileSize ([long]($finalSize / $elapsed)) } else { "N/A" }
                
                Write-OK "Complete: $(Format-FileSize $finalSize) in $([math]::Round($elapsed, 1))s ($speed/s)"
                
                $script:DownloadStats.Succeeded++
                $script:DownloadStats.TotalBytes += $finalSize
                $script:DownloadStats.TotalTime += $stopwatch.Elapsed
                
                return $true
            } else {
                $size = if (Test-Path $tempPath) { (Get-Item $tempPath).Length } else { 0 }
                Write-Host "    Downloaded file too small or missing ($size bytes)" -ForegroundColor Yellow
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            if ($_.Exception.InnerException) {
                $errorMsg = $_.Exception.InnerException.Message
            }
            
            if ($attempt -eq $RetryCount) {
                Write-Host "    Failed: $errorMsg" -ForegroundColor Red
            } else {
                Write-Debug "Attempt $attempt failed: $errorMsg"
            }
        }
        finally {
            if ($webClient) {
                try { $webClient.Dispose() } catch {}
            }
        }
    }
    
    # Cleanup
    if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
    
    $stopwatch.Stop()
    $script:DownloadStats.Failed++
    
    Write-Warn "Download failed after $RetryCount attempts"
    return $false
}

function Test-UrlAccessible {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 10
    )
    
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "HEAD"
        $request.Timeout = $TimeoutSeconds * 1000
        $request.AllowAutoRedirect = $true
        $request.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        
        $response = $request.GetResponse()
        $statusCode = [int]$response.StatusCode
        $contentLength = $response.ContentLength
        $response.Close()
        
        return @{
            Accessible = ($statusCode -ge 200 -and $statusCode -lt 400)
            StatusCode = $statusCode
            ContentLength = $contentLength
        }
    } catch [System.Net.WebException] {
        $statusCode = [int]$_.Exception.Response.StatusCode
        return @{
            Accessible = $false
            StatusCode = $statusCode
            Error = $_.Exception.Message
        }
    } catch {
        return @{
            Accessible = $false
            StatusCode = -1
            Error = $_.Exception.Message
        }
    }
}

function Find-WorkingUrl {
    param(
        [string[]]$Urls,
        [int]$MinSize = 0
    )
    
    Write-Debug "Testing $($Urls.Count) URLs..."
    
    foreach ($url in $Urls) {
        $test = Test-UrlAccessible -Url $url
        
        if ($test.Accessible) {
            if ($MinSize -eq 0 -or $test.ContentLength -ge $MinSize -or $test.ContentLength -eq -1) {
                Write-Debug "Found working URL: $url (Size: $($test.ContentLength))"
                return $url
            }
            Write-Debug "URL accessible but too small: $url (Size: $($test.ContentLength))"
        } else {
            Write-Debug "URL not accessible: $url (Status: $($test.StatusCode))"
        }
    }
    
    return $null
}

function Download-WithFallback {
    param(
        [string[]]$Urls,
        [string]$OutputPath,
        [string]$Description = "",
        [long]$MinSize = 1000
    )
    
    # First, find a working URL
    Write-Info "Trying: $($Urls[0])"
    
    foreach ($url in $Urls) {
        $result = Download-WithProgress -Url $url -OutputPath $OutputPath -Description $Description
        
        if ($result) {
            $fileSize = (Get-Item $OutputPath -ErrorAction SilentlyContinue).Length
            if ($fileSize -ge $MinSize) {
                return $true
            }
            Write-Debug "Downloaded file too small: $fileSize < $MinSize"
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }
        
        # Try next URL if available
        $currentIndex = [Array]::IndexOf($Urls, $url)
        if ($currentIndex -lt ($Urls.Count - 1)) {
            Write-Info "Trying fallback URL..."
        }
    }
    
    return $false
}

# ============================================================
# DYNAMIC URL DISCOVERY
# ============================================================

function Get-PHPDownloadUrls {
    Write-Info "Discovering PHP download URLs..."
    
    # Check cache first
    $cache = Get-UrlCache
    if ($cache.PHP) {
        Write-Debug "Using cached PHP URL"
        return @($cache.PHP)
    }
    
    $urls = @()
    
    # Strategy 1: Parse windows.php.net releases page
    try {
        $response = Invoke-WebRequest -Uri "https://windows.php.net/downloads/releases/" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $content = $response.Content
        
        # Find all PHP 8.x Win32 vs16 x64 zip files
        $pattern = 'href="(php-8\.[234]\.\d+-Win32-vs16-x64\.zip)"'
        $matches = [regex]::Matches($content, $pattern)
        
        foreach ($match in $matches) {
            $filename = $match.Groups[1].Value
            $url = "https://windows.php.net/downloads/releases/$filename"
            $urls += $url
        }
        
        # Sort by version descending (newest first)
        $urls = $urls | Sort-Object { 
            if ($_ -match 'php-(\d+)\.(\d+)\.(\d+)') {
                [int]$matches[1] * 10000 + [int]$matches[2] * 100 + [int]$matches[3]
            } else { 0 }
        } -Descending
        
        if ($urls.Count -gt 0) {
            Write-OK "Found $($urls.Count) PHP versions"
            Write-Debug "Latest: $($urls[0])"
        }
    } catch {
        Write-Debug "Failed to parse PHP releases: $_"
    }
    
    # Strategy 2: Try archives if no current releases found
    if ($urls.Count -eq 0) {
        try {
            $response = Invoke-WebRequest -Uri "https://windows.php.net/downloads/releases/archives/" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $content = $response.Content
            
            $pattern = 'href="(php-8\.[234]\.\d+-Win32-vs16-x64\.zip)"'
            $matches = [regex]::Matches($content, $pattern)
            
            foreach ($match in $matches) {
                $filename = $match.Groups[1].Value
                $url = "https://windows.php.net/downloads/releases/archives/$filename"
                $urls += $url
            }
            
            $urls = $urls | Sort-Object { 
                if ($_ -match 'php-(\d+)\.(\d+)\.(\d+)') {
                    [int]$matches[1] * 10000 + [int]$matches[2] * 100 + [int]$matches[3]
                } else { 0 }
            } -Descending | Select-Object -First 5
            
            if ($urls.Count -gt 0) {
                Write-OK "Found $($urls.Count) PHP versions in archives"
            }
        } catch {
            Write-Debug "Failed to parse PHP archives: $_"
        }
    }
    
    # Fallback: Known stable versions
    if ($urls.Count -eq 0) {
        Write-Info "Using fallback PHP URLs..."
        $urls = @(
            "https://windows.php.net/downloads/releases/php-8.3.14-Win32-vs16-x64.zip",
            "https://windows.php.net/downloads/releases/archives/php-8.3.14-Win32-vs16-x64.zip",
            "https://windows.php.net/downloads/releases/archives/php-8.3.13-Win32-vs16-x64.zip",
            "https://windows.php.net/downloads/releases/archives/php-8.2.26-Win32-vs16-x64.zip"
        )
    }
    
    # Cache the first working URL
    $workingUrl = Find-WorkingUrl -Urls $urls -MinSize 20MB
    if ($workingUrl) {
        $cacheData = Get-UrlCache
        if (-not $cacheData) { $cacheData = @{} }
        $cacheData.PHP = $workingUrl
        Set-UrlCache -Urls $cacheData
    }
    
    return $urls
}

function Get-GitDownloadUrls {
    Write-Info "Discovering Git download URLs..."
    
    # Check cache first
    $cache = Get-UrlCache
    if ($cache.Git) {
        Write-Debug "Using cached Git URL"
        return @($cache.Git)
    }
    
    $urls = @()
    
    # Strategy 1: GitHub API
    try {
        $apiUrl = "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $headers = @{ "User-Agent" = "PowerShell-BookStack-Installer" }
        
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop
        
        foreach ($asset in $response.assets) {
            if ($asset.name -match "PortableGit.*64-bit.*\.7z\.exe$") {
                $urls += $asset.browser_download_url
                Write-OK "Found Git: $($response.tag_name)"
                break
            }
        }
    } catch {
        Write-Debug "GitHub API failed: $_"
    }
    
    # Strategy 2: Check recent releases
    if ($urls.Count -eq 0) {
        try {
            $apiUrl = "https://api.github.com/repos/git-for-windows/git/releases?per_page=5"
            $headers = @{ "User-Agent" = "PowerShell-BookStack-Installer" }
            
            $releases = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop
            
            foreach ($release in $releases) {
                foreach ($asset in $release.assets) {
                    if ($asset.name -match "PortableGit.*64-bit.*\.7z\.exe$") {
                        $urls += $asset.browser_download_url
                    }
                }
            }
            
            if ($urls.Count -gt 0) {
                Write-OK "Found $($urls.Count) Git versions"
            }
        } catch {
            Write-Debug "GitHub releases API failed: $_"
        }
    }
    
    # Fallback
    if ($urls.Count -eq 0) {
        Write-Info "Using fallback Git URLs..."
        $urls = @(
            "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/PortableGit-2.47.1.2-64-bit.7z.exe",
            "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/PortableGit-2.47.1-64-bit.7z.exe",
            "https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.2/PortableGit-2.47.0.2-64-bit.7z.exe"
        )
    }
    
    # Cache the first working URL
    $workingUrl = Find-WorkingUrl -Urls $urls -MinSize 30MB
    if ($workingUrl) {
        $cacheData = Get-UrlCache
        if (-not $cacheData) { $cacheData = @{} }
        $cacheData.Git = $workingUrl
        Set-UrlCache -Urls $cacheData
    }
    
    return $urls
}

function Get-MariaDBDownloadUrls {
    Write-Info "Discovering MariaDB download URLs..."
    
    # Check cache first
    $cache = Get-UrlCache
    if ($cache.MariaDB) {
        Write-Debug "Using cached MariaDB URL"
        return @($cache.MariaDB)
    }
    
    # MariaDB archive is very stable - use known versions
    # 10.6 LTS is recommended for stability
    $urls = @(
        "https://archive.mariadb.org/mariadb-10.6.20/winx64-packages/mariadb-10.6.20-winx64.zip",
        "https://archive.mariadb.org/mariadb-10.6.19/winx64-packages/mariadb-10.6.19-winx64.zip",
        "https://archive.mariadb.org/mariadb-10.6.18/winx64-packages/mariadb-10.6.18-winx64.zip",
        "https://archive.mariadb.org/mariadb-10.11.10/winx64-packages/mariadb-10.11.10-winx64.zip",
        "https://archive.mariadb.org/mariadb-10.5.27/winx64-packages/mariadb-10.5.27-winx64.zip"
    )
    
    # Test and cache
    $workingUrl = Find-WorkingUrl -Urls $urls -MinSize 50MB
    if ($workingUrl) {
        $cacheData = Get-UrlCache
        if (-not $cacheData) { $cacheData = @{} }
        $cacheData.MariaDB = $workingUrl
        Set-UrlCache -Urls $cacheData
        Write-OK "Found MariaDB: $(Split-Path $workingUrl -Leaf)"
    }
    
    return $urls
}

function Get-ComposerDownloadUrls {
    Write-Info "Discovering Composer download URLs..."
    
    $urls = @(
        "https://getcomposer.org/download/latest-stable/composer.phar",
        "https://getcomposer.org/composer-stable.phar"
    )
    
    # Try GitHub API for specific version
    try {
        $apiUrl = "https://api.github.com/repos/composer/composer/releases/latest"
        $headers = @{ "User-Agent" = "PowerShell-BookStack-Installer" }
        
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        
        foreach ($asset in $response.assets) {
            if ($asset.name -eq "composer.phar") {
                $urls = @($asset.browser_download_url) + $urls
                Write-OK "Found Composer: $($response.tag_name)"
                break
            }
        }
    } catch {
        Write-Debug "GitHub API failed: $_"
    }
    
    return $urls
}

# ============================================================
# PROCESS EXECUTION HELPER (ISE COMPATIBLE)
# ============================================================

function Invoke-SafeCommand {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [switch]$ShowOutput,
        [switch]$ShowErrors,
        [string]$WorkingDirectory = "",
        [int]$TimeoutSeconds = 300
    )

    if (-not (Test-Path $Executable)) {
        return @{
            ExitCode = -1
            StdOut = ""
            StdErr = "Executable not found: $Executable"
            Success = $false
        }
    }

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $Executable
    $pinfo.Arguments = $Arguments -join ' '
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) {
        $pinfo.WorkingDirectory = $WorkingDirectory
    } else {
        $pinfo.WorkingDirectory = (Get-Location).Path
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo

    try {
        $process.Start() | Out-Null

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $completed = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $completed) {
            $process.Kill()
            return @{
                ExitCode = -1
                StdOut = ""
                StdErr = "Process timed out after $TimeoutSeconds seconds"
                Success = $false
            }
        }

        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result

        if ($ShowOutput -and $stdout) {
            $stdout -split "`n" | ForEach-Object {
                $line = $_.Trim()
                if ($line -and $line -notmatch "SSL/TLS protection disabled") {
                    Write-Host $line
                }
            }
        }

        if ($ShowErrors -and $stderr) {
            $stderr -split "`n" | ForEach-Object {
                $line = $_.Trim()
                if ($line -and $line -notmatch "SSL/TLS protection disabled") {
                    Write-Host $line -ForegroundColor Yellow
                }
            }
        }

        return @{
            ExitCode = $process.ExitCode
            StdOut = $stdout
            StdErr = $stderr
            Success = ($process.ExitCode -eq 0)
        }
    } catch {
        return @{
            ExitCode = -1
            StdOut = ""
            StdErr = $_.Exception.Message
            Success = $false
        }
    } finally {
        if ($process) {
            $process.Dispose()
        }
    }
}

function Invoke-PHP {
    param(
        [string[]]$Arguments,
        [switch]$ShowOutput,
        [string]$WorkingDirectory = ""
    )

    if (-not $WorkingDirectory) {
        $WorkingDirectory = $script:Paths.App
    }

    return Invoke-SafeCommand -Executable $script:Files.PHPExe -Arguments $Arguments -ShowOutput:$ShowOutput -WorkingDirectory $WorkingDirectory
}

function Invoke-Composer {
    param(
        [string[]]$Arguments,
        [switch]$ShowOutput,
        [string]$WorkingDirectory = ""
    )

    if (-not $WorkingDirectory) {
        $WorkingDirectory = $script:Paths.App
    }

    $allArgs = @($script:Files.ComposerPhar) + $Arguments
    return Invoke-SafeCommand -Executable $script:Files.PHPExe -Arguments $allArgs -ShowOutput:$ShowOutput -WorkingDirectory $WorkingDirectory -TimeoutSeconds 900
}

function Invoke-Artisan {
    param(
        [string[]]$Arguments,
        [switch]$ShowOutput
    )

    $allArgs = @("artisan") + $Arguments
    return Invoke-PHP -Arguments $allArgs -ShowOutput:$ShowOutput -WorkingDirectory $script:Paths.App
}

function Invoke-MySQL {
    param(
        [string]$SQL,
        [switch]$ShowOutput
    )

    $mysqlExe = $script:Files.MySQLExe
    $sqlFile = "$($script:Paths.Temp)\query_$(Get-Random).sql"

    Write-FileNoBom -Path $sqlFile -Content $SQL

    $result = Invoke-SafeCommand -Executable $mysqlExe -Arguments @(
        "-u", "root",
        "-P", $DBPort,
        "-h", "127.0.0.1",
        "--skip-password",
        "-e", "source `"$sqlFile`""
    ) -ShowOutput:$ShowOutput -WorkingDirectory $script:Paths.MariaDB

    Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue

    return $result
}

# ============================================================
# FILE SYSTEM HELPER FUNCTIONS
# ============================================================

function Extract-Archive {
    param(
        [string]$ArchivePath,
        [string]$DestinationPath,
        [switch]$StripFirstFolder
    )

    Write-Info "Extracting: $(Split-Path $ArchivePath -Leaf)"

    if (-not (Test-Path $ArchivePath)) {
        Write-Err "Archive not found: $ArchivePath"
        return $false
    }

    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    $extension = [System.IO.Path]::GetExtension($ArchivePath).ToLower()

    try {
        if ($extension -eq ".zip") {
            if ($StripFirstFolder) {
                $tempPath = "$($script:Paths.Temp)\extract_$(Get-Random)"
                if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }
                New-Item -ItemType Directory -Path $tempPath -Force | Out-Null

                Expand-Archive -Path $ArchivePath -DestinationPath $tempPath -Force

                $subFolder = Get-ChildItem $tempPath -Directory | Select-Object -First 1
                if ($subFolder) {
                    Get-ChildItem $subFolder.FullName | ForEach-Object {
                        Move-Item $_.FullName $DestinationPath -Force
                    }
                } else {
                    Get-ChildItem $tempPath | ForEach-Object {
                        Move-Item $_.FullName $DestinationPath -Force
                    }
                }

                Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
            }
            Write-OK "Extraction complete"
            return $true
        }
        elseif ($ArchivePath -match "\.7z\.exe$" -or $ArchivePath -match "\.7z$") {
            Write-Info "Running self-extracting archive..."
            $process = Start-Process -FilePath $ArchivePath -ArgumentList "-o`"$DestinationPath`"", "-y" -Wait -PassThru -NoNewWindow
            if ($process.ExitCode -eq 0) {
                Write-OK "Extraction complete"
                return $true
            }
        }
        else {
            try {
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $DestinationPath)
                Write-OK "Extraction complete"
                return $true
            } catch {
                Write-Warn "System.IO.Compression failed: $_"
            }
        }
    } catch {
        Write-Err "Extraction error: $_"
    }

    return $false
}

function Remove-FolderSafely {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $true
    }

    # Kill processes that might lock files
    @("git", "php", "mysqld", "mysql", "composer") | ForEach-Object {
        Stop-Process -Name "$_*" -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2

    # Try PowerShell Remove-Item
    try {
        Remove-Item $Path -Recurse -Force -ErrorAction Stop
        return $true
    } catch {}

    # Try cmd rmdir
    cmd /c "rmdir /s /q `"$Path`"" 2>$null
    if (-not (Test-Path $Path)) { return $true }

    # Try robocopy empty folder trick
    try {
        $emptyDir = "$env:TEMP\empty_$(Get-Random)"
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        robocopy $emptyDir $Path /mir /r:1 /w:1 2>$null | Out-Null
        Remove-Item $emptyDir -Force -ErrorAction SilentlyContinue
        Remove-Item $Path -Force -ErrorAction SilentlyContinue
    } catch {}

    return -not (Test-Path $Path)
}

function Set-FullPermissions {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return }

    try {
        $acl = Get-Acl $Path
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl $Path $acl -ErrorAction SilentlyContinue
    } catch {}

    # Also try icacls
    Start-Process -FilePath "icacls" -ArgumentList "`"$Path`"", "/grant:r", "`"$env:USERNAME`":(OI)(CI)F", "/t", "/q" -Wait -NoNewWindow -ErrorAction SilentlyContinue
}

function Request-ManualDownload {
    param(
        [string]$Description,
        [string]$Url,
        [string]$SavePath,
        [string]$SearchPattern = "",
        [int]$MinSizeMB = 1
    )

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Yellow
    Write-Host "  MANUAL DOWNLOAD REQUIRED: $Description" -ForegroundColor Yellow
    Write-Host "  ================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Go to: $Url" -ForegroundColor Cyan
    Write-Host "  2. Download the appropriate file" -ForegroundColor White
    Write-Host "  3. Save to: $SavePath" -ForegroundColor Green
    Write-Host ""

    Start-Process $Url

    $minSize = $MinSizeMB * 1MB

    do {
        Read-Host "Press Enter after downloading..."

        if ((Test-Path $SavePath) -and (Get-Item $SavePath).Length -gt $minSize) {
            return $true
        }

        # Check user's Downloads folder
        if ($SearchPattern) {
            $found = Get-Item "$env:USERPROFILE\Downloads\$SearchPattern" -ErrorAction SilentlyContinue |
                     Where-Object { $_.Length -gt $minSize } |
                     Sort-Object LastWriteTime -Descending |
                     Select-Object -First 1

            if ($found) {
                Copy-Item $found.FullName $SavePath -Force
                Write-OK "Found and copied: $($found.Name)"
                return $true
            }
        }

        Write-Warn "File not found or too small. Please try again."
        $retry = Read-Host "Try again? (Y/n)"
        if ($retry -eq 'n') {
            return $false
        }
    } while ($true)
}

# ============================================================
# DIRECTORY INITIALIZATION
# ============================================================

function Initialize-Directories {
    Write-Step "Creating Directory Structure"

    foreach ($key in $script:Paths.Keys) {
        $path = $script:Paths[$key]
        if ($path -notmatch "\.json$" -and -not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Info "Created: $path"
        }
    }

    # Set permissions on root
    Set-FullPermissions -Path $RootPath

    Write-OK "Directory structure ready"
    return $true
}

# ============================================================
# PHP INSTALLATION
# ============================================================

function Install-PHP {
    Write-Step "Installing PHP (Portable)"

    $phpExe = $script:Files.PHPExe
    $phpPath = $script:Paths.PHP
    $phpZip = "$($script:Paths.Downloads)\php.zip"
    $minSize = 20MB

    # Check if already installed
    if (Test-Path $phpExe) {
        $result = Invoke-SafeCommand -Executable $phpExe -Arguments @("-v")
        $version = ($result.StdOut -split "`n")[0]
        Write-OK "PHP already installed: $version"
        return $true
    }

    Write-Info "PHP not found, downloading..."

    # Check for manually placed file
    $manualFiles = @(
        $phpZip,
        "$env:USERPROFILE\Downloads\php.zip",
        "$env:USERPROFILE\Downloads\php-8*.zip"
    )

    $foundFile = $null
    foreach ($pattern in $manualFiles) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue |
                 Where-Object { $_.Length -gt $minSize } |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
        if ($found) {
            $foundFile = $found.FullName
            break
        }
    }

    if ($foundFile -and $foundFile -ne $phpZip) {
        Copy-Item $foundFile $phpZip -Force
        Write-OK "Found PHP: $($found.Name)"
    } elseif (-not (Test-Path $phpZip) -or (Get-Item $phpZip -ErrorAction SilentlyContinue).Length -lt $minSize) {
        # Get dynamic URLs
        $phpUrls = Get-PHPDownloadUrls
        $downloaded = Download-WithFallback -Urls $phpUrls -OutputPath $phpZip -MinSize $minSize -Description "PHP 8.3"

        if (-not $downloaded) {
            Request-ManualDownload -Description "PHP 8.x (VS16 x64 Thread Safe ZIP)" `
                -Url "https://windows.php.net/download/" `
                -SavePath $phpZip `
                -SearchPattern "php*.zip" `
                -MinSizeMB 20
        }
    }

    # Verify download
    if (-not (Test-Path $phpZip) -or (Get-Item $phpZip).Length -lt $minSize) {
        Write-Err "PHP download not found or incomplete"
        return $false
    }

    # Clear existing and extract
    if (Test-Path $phpPath) {
        Remove-Item $phpPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $phpPath -Force | Out-Null

    if (-not (Extract-Archive -ArchivePath $phpZip -DestinationPath $phpPath)) {
        Write-Err "Failed to extract PHP"
        return $false
    }

    # Verify extraction
    if (-not (Test-Path $phpExe)) {
        Write-Err "PHP extraction failed - php.exe not found"
        return $false
    }

    Write-OK "PHP extracted successfully"
    return $true
}

function Configure-PHP {
    Write-Step "Configuring PHP"

    $phpPath = $script:Paths.PHP
    $phpIni = $script:Files.PHPIni
    $tempPath = $script:Paths.Temp

    # Find template
    $phpIniTemplate = "$phpPath\php.ini-production"
    if (-not (Test-Path $phpIniTemplate)) {
        $phpIniTemplate = "$phpPath\php.ini-development"
    }

    if (-not (Test-Path $phpIniTemplate)) {
        Write-Err "No php.ini template found"
        return $false
    }

    # Read template content
    $content = Get-Content $phpIniTemplate -Raw

    # Enable extensions
    $extensions = @(
        "curl", "fileinfo", "gd", "mbstring", "mysqli",
        "openssl", "pdo_mysql", "xml", "ldap", "zip",
        "exif", "intl", "sodium", "gettext"
    )

    foreach ($ext in $extensions) {
        $content = $content -replace ";extension=$ext", "extension=$ext"
    }

    # Set paths (using forward slashes)
    $extDir = "$phpPath\ext" -replace '\\', '/'
    $tempDir = $tempPath -replace '\\', '/'

    # Update extension directory
    $content = $content -replace ';?\s*extension_dir\s*=\s*"ext"', "extension_dir = `"$extDir`""
    $content = $content -replace ';?\s*extension_dir\s*=\s*"\./"', "extension_dir = `"$extDir`""

    # Set memory and upload limits
    $content = $content -replace 'memory_limit\s*=\s*\d+M', 'memory_limit = 256M'
    $content = $content -replace 'upload_max_filesize\s*=\s*\d+M', 'upload_max_filesize = 100M'
    $content = $content -replace 'post_max_size\s*=\s*\d+M', 'post_max_size = 100M'
    $content = $content -replace 'max_execution_time\s*=\s*\d+', 'max_execution_time = 300'
    $content = $content -replace 'max_input_time\s*=\s*\d+', 'max_input_time = 300'
    $content = $content -replace 'max_input_vars\s*=\s*\d+', 'max_input_vars = 5000'

    # Add portable configuration at the end (NO SSL cert references)
    $portableConfig = @"

; ================================================================
; PORTABLE BOOKSTACK CONFIGURATION
; ================================================================

; Temporary directory
sys_temp_dir = "$tempDir"
upload_tmp_dir = "$tempDir"

; Error logging
error_log = "$($script:Paths.Logs -replace '\\', '/')/php_errors.log"
log_errors = On

; Timezone (adjust as needed)
date.timezone = UTC

; Session settings
session.save_path = "$tempDir"
"@

    $content = $content.TrimEnd() + "`n" + $portableConfig

    # Write php.ini without BOM
    Write-FileNoBom -Path $phpIni -Content $content

    Write-Info "Created php.ini"

    # Verify PHP works
    $result = Invoke-SafeCommand -Executable $script:Files.PHPExe -Arguments @("-v")
    if ($result.Success) {
        $version = ($result.StdOut -split "`n")[0]
        Write-OK "PHP configured: $version"
        return $true
    } else {
        Write-Warn "PHP may have configuration issues: $($result.StdErr)"
        return $true
    }
}

# ============================================================
# COMPOSER INSTALLATION
# ============================================================

function Install-Composer {
    Write-Step "Installing Composer (Portable)"

    $composerPhar = $script:Files.ComposerPhar
    $composerPath = $script:Paths.Composer
    $minSize = 2MB

    if (-not (Test-Path $composerPath)) {
        New-Item -ItemType Directory -Path $composerPath -Force | Out-Null
    }

    # Check if already installed
    if ((Test-Path $composerPhar) -and (Get-Item $composerPhar).Length -ge $minSize) {
        Write-OK "Composer already installed"
        return $true
    }

    Write-Info "Looking for Composer..."

    # Check common locations
    $pharLocations = @(
        $composerPhar,
        "$env:USERPROFILE\Downloads\composer.phar",
        "C:\Downloads\composer.phar",
        "C:\composer\composer.phar",
        "C:\ProgramData\ComposerSetup\bin\composer.phar"
    )

    $foundPhar = $null
    foreach ($loc in $pharLocations) {
        if ((Test-Path $loc) -and (Get-Item $loc).Length -ge $minSize) {
            $foundPhar = $loc
            break
        }
    }

    if ($foundPhar -and $foundPhar -ne $composerPhar) {
        Copy-Item $foundPhar $composerPhar -Force
        Write-OK "Found existing Composer"
    } else {
        Write-Info "Downloading Composer..."

        $composerUrls = Get-ComposerDownloadUrls
        $downloaded = Download-WithFallback -Urls $composerUrls -OutputPath $composerPhar -MinSize $minSize -Description "Composer"

        if (-not $downloaded) {
            Request-ManualDownload -Description "Composer" `
                -Url "https://getcomposer.org/download/" `
                -SavePath $composerPhar `
                -SearchPattern "composer.phar" `
                -MinSizeMB 2
        }
    }

    # Verify
    if (-not (Test-Path $composerPhar) -or (Get-Item $composerPhar).Length -lt $minSize) {
        Write-Err "Composer installation failed"
        return $false
    }

    # Create composer.bat wrapper (use ASCII for batch files)
    $composerBat = $script:Files.ComposerBat
    $batContent = "@echo off`r`n`"%~dp0..\php\php.exe`" `"%~dp0composer.phar`" %*"
    Write-FileNoBom -Path $composerBat -Content $batContent -Ascii

    Write-OK "Composer installed"
    return $true
}

function Configure-Composer {
    Write-Info "Configuring Composer for portable use..."

    # Set environment for this session
    $env:COMPOSER_HOME = $script:Paths.Composer
    $env:COMPOSER_CACHE_DIR = "$($script:Paths.Temp)\composer-cache"
    $env:COMPOSER_ALLOW_SUPERUSER = "1"
    $env:COMPOSER_NO_INTERACTION = "1"
    $env:GIT_SSL_NO_VERIFY = "true"

    # Create cache directory
    if (-not (Test-Path $env:COMPOSER_CACHE_DIR)) {
        New-Item -ItemType Directory -Path $env:COMPOSER_CACHE_DIR -Force | Out-Null
    }

    # Configure Composer to handle SSL issues
    Invoke-Composer -Arguments @("config", "-g", "disable-tls", "true") | Out-Null
    Invoke-Composer -Arguments @("config", "-g", "secure-http", "false") | Out-Null
    Invoke-Composer -Arguments @("config", "-g", "process-timeout", "900") | Out-Null
    Invoke-Composer -Arguments @("config", "-g", "cache-dir", $env:COMPOSER_CACHE_DIR) | Out-Null

    Write-OK "Composer configured"
    return $true
}

# ============================================================
# GIT INSTALLATION
# ============================================================

function Install-Git {
    Write-Step "Installing Portable Git"

    $gitExe = $script:Files.GitExe
    $gitPath = $script:Paths.Git
    $gitArchive = "$($script:Paths.Downloads)\PortableGit.7z.exe"
    $minSize = 30MB

    # Check if already installed
    if (Test-Path $gitExe) {
        Write-OK "Portable Git already installed"

        # Configure Git
        Invoke-SafeCommand -Executable $gitExe -Arguments @("config", "--global", "http.sslVerify", "false") | Out-Null

        return $true
    }

    Write-Info "Git not found, downloading..."

    # Check for manually placed file
    $manualFiles = @(
        $gitArchive,
        "$env:USERPROFILE\Downloads\PortableGit*.exe",
        "$env:USERPROFILE\Downloads\PortableGit*.7z.exe"
    )

    $foundFile = $null
    foreach ($pattern in $manualFiles) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue |
                 Where-Object { $_.Length -gt $minSize } |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
        if ($found) {
            $foundFile = $found.FullName
            break
        }
    }

    if ($foundFile -and $foundFile -ne $gitArchive) {
        Copy-Item $foundFile $gitArchive -Force
        Write-OK "Found PortableGit"
    } elseif (-not (Test-Path $gitArchive) -or (Get-Item $gitArchive -ErrorAction SilentlyContinue).Length -lt $minSize) {
        $gitUrls = Get-GitDownloadUrls
        $downloaded = Download-WithFallback -Urls $gitUrls -OutputPath $gitArchive -MinSize $minSize -Description "Portable Git"

        if (-not $downloaded) {
            Write-Warn "Could not download Git automatically"
            Write-Host ""
            Write-Host "  Git is optional. BookStack will be downloaded as ZIP instead." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  To install Git manually later:" -ForegroundColor White
            Write-Host "  1. Go to: https://git-scm.com/download/win" -ForegroundColor Cyan
            Write-Host "  2. Download '64-bit Git for Windows Portable'" -ForegroundColor White
            Write-Host "  3. Save to: $gitArchive" -ForegroundColor Green
            Write-Host ""

            $response = Read-Host "Try to download manually now? (y/N)"
            if ($response -eq 'y') {
                Start-Process "https://github.com/git-for-windows/git/releases"
                Read-Host "Press Enter after downloading..."

                $found = Get-Item "$env:USERPROFILE\Downloads\PortableGit*.exe" -ErrorAction SilentlyContinue |
                         Where-Object { $_.Length -gt $minSize } | Select-Object -First 1
                if ($found) {
                    Copy-Item $found.FullName $gitArchive -Force
                }
            }
        }
    }

    # Extract if downloaded
    if ((Test-Path $gitArchive) -and (Get-Item $gitArchive).Length -gt $minSize) {
        Write-Info "Extracting Portable Git (this may take a minute)..."

        if (Test-Path $gitPath) {
            Remove-Item $gitPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $gitPath -Force | Out-Null

        $process = Start-Process -FilePath $gitArchive -ArgumentList "-o`"$gitPath`"", "-y" -Wait -PassThru -NoNewWindow

        if (Test-Path $gitExe) {
            # Configure Git
            Invoke-SafeCommand -Executable $gitExe -Arguments @("config", "--global", "http.sslVerify", "false") | Out-Null

            Write-OK "Portable Git installed"
            return $true
        } else {
            Write-Warn "Git extraction may have failed"
        }
    }

    Write-Warn "Git not installed - will use ZIP download for BookStack"
    return $true
}

# ============================================================
# MARIADB INSTALLATION (FIXED - NO BOM)
# ============================================================

function Install-MariaDB {
    Write-Step "Installing MariaDB (Portable)"

    $mariaPath = $script:Paths.MariaDB
    $mysqldExe = $script:Files.MySQLDExe
    $mariaZip = "$($script:Paths.Downloads)\mariadb.zip"
    $minSize = 50MB

    # Check if already installed
    if (Test-Path $mysqldExe) {
        Write-OK "MariaDB already installed"
        return $true
    }

    Write-Info "MariaDB not found, downloading..."

    # Check for manually placed file
    $manualFiles = @(
        $mariaZip,
        "$env:USERPROFILE\Downloads\mariadb*.zip"
    )

    $foundFile = $null
    foreach ($pattern in $manualFiles) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue |
                 Where-Object { $_.Length -gt $minSize } |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
        if ($found) {
            $foundFile = $found.FullName
            break
        }
    }

    if ($foundFile -and $foundFile -ne $mariaZip) {
        Copy-Item $foundFile $mariaZip -Force
        Write-OK "Found MariaDB: $($found.Name)"
    } elseif (-not (Test-Path $mariaZip) -or (Get-Item $mariaZip -ErrorAction SilentlyContinue).Length -lt $minSize) {
        $mariaUrls = Get-MariaDBDownloadUrls
        $downloaded = Download-WithFallback -Urls $mariaUrls -OutputPath $mariaZip -MinSize $minSize -Description "MariaDB 10.6"

        if (-not $downloaded) {
            Request-ManualDownload -Description "MariaDB (Windows x64 ZIP)" `
                -Url "https://mariadb.org/download/?t=mariadb&p=mariadb&r=10.6&os=windows&cpu=x86_64&pkg=zip" `
                -SavePath $mariaZip `
                -SearchPattern "mariadb*.zip" `
                -MinSizeMB 50
        }
    }

    # Verify download
    if (-not (Test-Path $mariaZip) -or (Get-Item $mariaZip).Length -lt $minSize) {
        Write-Err "MariaDB download not found or incomplete"
        return $false
    }

    # Extract MariaDB
    Write-Info "Extracting MariaDB..."

    $tempExtract = "$($script:Paths.Temp)\mariadb_extract_$(Get-Random)"
    if (Test-Path $tempExtract) {
        Remove-Item $tempExtract -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

    try {
        Expand-Archive -Path $mariaZip -DestinationPath $tempExtract -Force
    } catch {
        Write-Err "Failed to extract MariaDB: $_"
        return $false
    }

    # Find the extracted folder (mariadb-x.x.x-winx64)
    $extractedFolder = Get-ChildItem $tempExtract -Directory | Select-Object -First 1

    if ($extractedFolder) {
        if (Test-Path $mariaPath) {
            Remove-Item $mariaPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Move-Item $extractedFolder.FullName $mariaPath -Force
    } else {
        Write-Err "Could not find extracted MariaDB folder"
        return $false
    }

    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    # Verify
    if (-not (Test-Path $mysqldExe)) {
        Write-Err "MariaDB extraction failed - mysqld.exe not found"
        return $false
    }

    # Create data directory
    if (-not (Test-Path $script:Paths.DataDB)) {
        New-Item -ItemType Directory -Path $script:Paths.DataDB -Force | Out-Null
    }

    Write-OK "MariaDB extracted successfully"
    return $true
}

function Create-MariaDBConfig {
    Write-Info "Creating MariaDB configuration..."

    $mariaPath = $script:Paths.MariaDB
    $dataPath = $script:Paths.DataDB
    $logsPath = $script:Paths.Logs
    $myIni = $script:Files.MariaDBIni

    # Use forward slashes for MySQL config
    $dataDirForward = $dataPath -replace '\\', '/'
    $baseDirForward = $mariaPath -replace '\\', '/'
    $logDirForward = $logsPath -replace '\\', '/'

    # IMPORTANT: Config must start with [mysqld] - no BOM or blank lines before it
    $myIniContent = @"
[mysqld]
datadir=$dataDirForward
basedir=$baseDirForward
port=$DBPort
bind-address=127.0.0.1
skip-networking=0
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
character-set-client-handshake=FALSE
innodb_buffer_pool_size=128M
innodb_log_file_size=48M
innodb_file_per_table=1
innodb_flush_log_at_trx_commit=2
max_connections=50
table_open_cache=400
tmp_table_size=32M
max_heap_table_size=32M
skip-name-resolve
local-infile=0
log_error=$logDirForward/mariadb_error.log

[client]
port=$DBPort
default-character-set=utf8mb4

[mysql]
default-character-set=utf8mb4

[mysqld_safe]
log_error=$logDirForward/mariadb_error.log
"@

    # CRITICAL: Write without BOM using .NET method
    Write-FileNoBom -Path $myIni -Content $myIniContent

    Write-OK "MariaDB configuration created (without BOM)"
    return $true
}

function Initialize-MariaDB {
    Write-Step "Initializing MariaDB Database"

    $mariaPath = $script:Paths.MariaDB
    $dataPath = $script:Paths.DataDB
    $logsPath = $script:Paths.Logs
    $myIni = $script:Files.MariaDBIni
    $mysqldExe = $script:Files.MySQLDExe
    $mysqlInstallDb = $script:Files.MySQLInstallDb

    # Ensure directories exist
    foreach ($dir in @($dataPath, $logsPath)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Create configuration first (without BOM!)
    Create-MariaDBConfig

    # Check if already initialized
    if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
        Write-OK "MariaDB data directory already initialized"
        return $true
    }

    Write-Info "Initializing MariaDB data directory..."

    # Clear any partial data
    Get-ChildItem $dataPath -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # ================================================================
    # METHOD 1: Use mysql_install_db.exe (MariaDB's preferred method)
    # ================================================================
    if (Test-Path $mysqlInstallDb) {
        Write-SubStep "Using mysql_install_db.exe"

        $installArgs = @(
            "--datadir=`"$dataPath`"",
            "--password=`"`""
        )

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $mysqlInstallDb
        $pinfo.Arguments = $installArgs -join ' '
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $pinfo.WorkingDirectory = "$mariaPath\bin"

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $pinfo

        try {
            $process.Start() | Out-Null

            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()

            $process.WaitForExit(180000) # 3 minute timeout

            if ($stdout) {
                $stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
                    Write-Host "    $_" -ForegroundColor Gray
                }
            }

            if ($stderr -and $stderr -notmatch "Creation of the system tables|PLEASE REMEMBER") {
                Write-Host "    $stderr" -ForegroundColor Yellow
            }
        } catch {
            Write-Warn "mysql_install_db error: $_"
        } finally {
            if ($process) { $process.Dispose() }
        }

        # Check if it worked
        if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
            Write-OK "MariaDB initialized successfully"
            return $true
        }
    }

    # ================================================================
    # METHOD 2: Check for bundled data directory in MariaDB package
    # ================================================================
    Write-SubStep "Checking for bundled data template"

    $bundledDataPaths = @(
        "$mariaPath\data",
        "$mariaPath\var"
    )

    # Also search for data folder recursively
    $foundDataFolder = Get-ChildItem $mariaPath -Directory -Recurse -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -eq "data" -and (Test-Path "$($_.FullName)\mysql") } |
                       Select-Object -First 1

    if ($foundDataFolder) {
        $bundledDataPaths += $foundDataFolder.FullName
    }

    foreach ($bundledPath in $bundledDataPaths) {
        if ($bundledPath -and (Test-Path "$bundledPath\mysql")) {
            Write-Info "Found bundled data at: $bundledPath"

            # Clear destination
            Get-ChildItem $dataPath -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            # Copy bundled data
            Copy-Item "$bundledPath\*" $dataPath -Recurse -Force

            if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
                Write-OK "MariaDB initialized from bundled data"
                return $true
            }
        }
    }

    # ================================================================
    # METHOD 3: Use mysqld --initialize-insecure
    # ================================================================
    Write-SubStep "Trying mysqld --initialize-insecure"

    # Clear data directory
    Get-ChildItem $dataPath -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $initArgs = @(
        "--defaults-file=`"$myIni`"",
        "--initialize-insecure",
        "--datadir=`"$dataPath`"",
        "--basedir=`"$mariaPath`""
    )

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $mysqldExe
    $pinfo.Arguments = $initArgs -join ' '
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $pinfo.WorkingDirectory = "$mariaPath\bin"

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo

    try {
        $process.Start() | Out-Null
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit(180000)

        if ($stdout) { Write-Host "    $stdout" -ForegroundColor Gray }
    } catch {
        Write-Warn "mysqld --initialize error: $_"
    } finally {
        if ($process) { $process.Dispose() }
    }

    if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
        Write-OK "MariaDB initialized with mysqld --initialize"
        return $true
    }

    # ================================================================
    # METHOD 4: Start mysqld and let it self-initialize
    # ================================================================
    Write-SubStep "Trying mysqld self-initialization"

    # Clear data directory
    Get-ChildItem $dataPath -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Start mysqld with skip-grant-tables to allow self-initialization
    $startArgs = "--defaults-file=`"$myIni`" --skip-grant-tables --console"

    $process = Start-Process -FilePath $mysqldExe -ArgumentList $startArgs -PassThru -WindowStyle Hidden

    Write-Info "Waiting for MariaDB to initialize..."

    # Wait up to 30 seconds
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1

        if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
            Write-Info "Data directory populated, stopping initialization process..."
            break
        }

        if ($process.HasExited) {
            Write-Warn "mysqld process exited early"
            break
        }
    }

    # Stop the process
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3

    if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
        Write-OK "MariaDB self-initialized successfully"
        return $true
    }

    # ================================================================
    # FALLBACK: Manual instructions
    # ================================================================
    Write-Err "Automatic initialization failed"
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Yellow
    Write-Host "  MANUAL MARIADB INITIALIZATION REQUIRED" -ForegroundColor Yellow
    Write-Host "  ================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Please run these commands in a Command Prompt window:" -ForegroundColor White
    Write-Host ""
    Write-Host "    cd `"$mariaPath\bin`"" -ForegroundColor Cyan
    Write-Host "    mysql_install_db.exe --datadir=`"$dataPath`" --password=" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  If that doesn't work, try:" -ForegroundColor White
    Write-Host ""
    Write-Host "    mysqld.exe --initialize-insecure --datadir=`"$dataPath`"" -ForegroundColor Cyan
    Write-Host ""

    $response = Read-Host "Press Enter after running the command, or type 'skip' to continue anyway"

    if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
        Write-OK "MariaDB initialized manually"
        return $true
    }

    if ($response -eq 'skip') {
        Write-Warn "Continuing without MariaDB initialization - database may not work"
        return $true
    }

    return $false
}

function Start-MariaDBServer {
    param([switch]$Silent)

    if (-not $Silent) {
        Write-Info "Starting MariaDB server..."
    }

    $mysqldExe = $script:Files.MySQLDExe
    $mysqlExe = $script:Files.MySQLExe
    $myIni = $script:Files.MariaDBIni

    # Check if already running
    $existingProcess = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
    if ($existingProcess) {
        if (-not $Silent) {
            Write-OK "MariaDB is already running"
        }
        return $true
    }

    # Verify mysqld exists
    if (-not (Test-Path $mysqldExe)) {
        Write-Err "mysqld.exe not found at: $mysqldExe"
        return $false
    }

    # Start mysqld
    $process = Start-Process -FilePath $mysqldExe -ArgumentList "--defaults-file=`"$myIni`"" -PassThru -WindowStyle Hidden

    # Wait for it to start (up to 30 seconds)
    $maxWait = 30
    $waited = 0

    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds 1
        $waited++

        # Check if process exited
        if ($process.HasExited) {
            Write-Warn "MariaDB process exited unexpectedly"

            # Check error log
            $errorLog = "$($script:Paths.Logs)\mariadb_error.log"
            if (Test-Path $errorLog) {
                $lastLines = Get-Content $errorLog -Tail 10
                Write-Host "Last error log entries:" -ForegroundColor Yellow
                $lastLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
            }

            return $false
        }

        # Try to connect
        if (Test-Path $mysqlExe) {
            try {
                $testResult = & $mysqlExe -u root -P $DBPort -h 127.0.0.1 --skip-password -e "SELECT 1" 2>&1
                if ($LASTEXITCODE -eq 0 -or $testResult -match "1") {
                    if (-not $Silent) {
                        Write-OK "MariaDB started successfully (port $DBPort)"
                    }
                    return $true
                }
            } catch {}
        }

        if (-not $Silent) {
            Write-Host "." -NoNewline
        }
    }

    if (-not $Silent) {
        Write-Host ""
    }

    # Final check - is process running?
    $runningProcess = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
    if ($runningProcess) {
        if (-not $Silent) {
            Write-Warn "MariaDB is running but connection test failed. It may still work."
        }
        return $true
    }

    Write-Warn "MariaDB may not have started properly"
    return $false
}

function Stop-MariaDBServer {
    param([switch]$Silent)

    if (-not $Silent) {
        Write-Info "Stopping MariaDB server..."
    }

    $mysqladminExe = $script:Files.MySQLAdminExe

    # Try graceful shutdown first
    if (Test-Path $mysqladminExe) {
        try {
            $result = & $mysqladminExe -u root -P $DBPort -h 127.0.0.1 --skip-password shutdown 2>&1
            Start-Sleep -Seconds 2
        } catch {}
    }

    # Force kill if still running
    $process = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    if (-not $Silent) {
        Write-OK "MariaDB stopped"
    }
}

function Initialize-BookStackDatabase {
    Write-Step "Creating BookStack Database"

    # Ensure MariaDB is running
    if (-not (Start-MariaDBServer)) {
        Write-Err "Cannot create database - MariaDB is not running"
        return $false
    }

    Start-Sleep -Seconds 3

    $mysqlExe = $script:Files.MySQLExe

    $sql = @"
CREATE DATABASE IF NOT EXISTS $DBName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DBUser'@'localhost' IDENTIFIED BY '$DBPassword';
CREATE USER IF NOT EXISTS '$DBUser'@'127.0.0.1' IDENTIFIED BY '$DBPassword';
GRANT ALL PRIVILEGES ON $DBName.* TO '$DBUser'@'localhost';
GRANT ALL PRIVILEGES ON $DBName.* TO '$DBUser'@'127.0.0.1';
FLUSH PRIVILEGES;
SELECT 'Database created successfully' AS Status;
"@

    $sqlFile = "$($script:Paths.Temp)\create_bookstack_db.sql"
    Write-FileNoBom -Path $sqlFile -Content $sql

    Write-Info "Creating database and user..."

    try {
        $result = & $mysqlExe -u root -P $DBPort -h 127.0.0.1 --skip-password -e "source `"$sqlFile`"" 2>&1

        if ($result -match "successfully" -or $LASTEXITCODE -eq 0) {
            Write-OK "Database '$DBName' created successfully"
            Write-OK "User '$DBUser' created with password"
        } else {
            Write-Warn "Database creation output: $result"
        }
    } catch {
        Write-Warn "Database creation error: $_"
    }

    Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue

    return $true
}

# ============================================================
# BOOKSTACK INSTALLATION
# ============================================================

function Install-BookStack {
    Write-Step "Installing BookStack Application"

    $appPath = $script:Paths.App
    $gitExe = $script:Files.GitExe
    $bookstackZip = "$($script:Paths.Downloads)\bookstack.zip"
    $minSize = 5MB

    # Check if already installed
    if (Test-Path "$appPath\artisan") {
        Write-Warn "BookStack already exists at $appPath"
        $response = Read-Host "Reinstall? (y/N)"
        if ($response -ne 'y') {
            Write-Info "Keeping existing installation"
            return $true
        }

        Remove-FolderSafely $appPath | Out-Null
        New-Item -ItemType Directory -Path $appPath -Force | Out-Null
    }

    # Ensure directory exists
    if (-not (Test-Path $appPath)) {
        New-Item -ItemType Directory -Path $appPath -Force | Out-Null
    }

    # ================================================================
    # Try Git clone first (if Git is available)
    # ================================================================
    if (Test-Path $gitExe) {
        Write-Info "Cloning BookStack with Git..."

        $env:GIT_SSL_NO_VERIFY = "true"

        # Remove existing for fresh clone
        if (Test-Path $appPath) {
            Remove-Item $appPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        $result = Invoke-SafeCommand -Executable $gitExe -Arguments @(
            "clone",
            "https://github.com/BookStackApp/BookStack.git",
            "--branch", "release",
            "--single-branch",
            "--depth", "1",
            "`"$appPath`""
        ) -ShowOutput -TimeoutSeconds 300

        if (Test-Path "$appPath\artisan") {
            Write-OK "BookStack cloned successfully"
            return $true
        } else {
            Write-Warn "Git clone may have failed, trying ZIP download..."
        }
    }

    # ================================================================
    # Fallback to ZIP download
    # ================================================================
    Write-Info "Downloading BookStack as ZIP..."

    # Check for manually downloaded file
    $manualFiles = @(
        $bookstackZip,
        "$env:USERPROFILE\Downloads\BookStack*.zip",
        "$env:USERPROFILE\Downloads\bookstack*.zip",
        "$env:USERPROFILE\Downloads\release.zip"
    )

    $foundFile = $null
    foreach ($pattern in $manualFiles) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue |
                 Where-Object { $_.Length -gt $minSize } |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
        if ($found) {
            $foundFile = $found.FullName
            break
        }
    }

    if ($foundFile -and $foundFile -ne $bookstackZip) {
        Copy-Item $foundFile $bookstackZip -Force
        Write-OK "Found BookStack: $($found.Name)"
    } elseif (-not (Test-Path $bookstackZip) -or (Get-Item $bookstackZip -ErrorAction SilentlyContinue).Length -lt $minSize) {
        $bookstackUrls = @(
            "https://github.com/BookStackApp/BookStack/archive/refs/heads/release.zip"
        )
        
        $downloaded = Download-WithFallback -Urls $bookstackUrls -OutputPath $bookstackZip -MinSize $minSize -Description "BookStack"

        if (-not $downloaded) {
            Request-ManualDownload -Description "BookStack" `
                -Url "https://github.com/BookStackApp/BookStack/archive/refs/heads/release.zip" `
                -SavePath $bookstackZip `
                -SearchPattern "*.zip" `
                -MinSizeMB 5
        }
    }

    # Verify download
    if (-not (Test-Path $bookstackZip) -or (Get-Item $bookstackZip).Length -lt $minSize) {
        Write-Err "BookStack download not found or incomplete"
        return $false
    }

    # Extract
    Write-Info "Extracting BookStack..."

    if (-not (Extract-Archive -ArchivePath $bookstackZip -DestinationPath $appPath -StripFirstFolder)) {
        Write-Err "Failed to extract BookStack"
        return $false
    }

    # Verify
    if (Test-Path "$appPath\artisan") {
        Write-OK "BookStack installed successfully"
        return $true
    }

    Write-Err "BookStack installation failed - artisan file not found"
    return $false
}

function Initialize-BookStackDirectories {
    Write-Info "Creating BookStack storage directories..."

    $appPath = $script:Paths.App

    $directories = @(
        "bootstrap\cache",
        "storage\app",
        "storage\app\public",
        "storage\framework",
        "storage\framework\cache",
        "storage\framework\cache\data",
        "storage\framework\sessions",
        "storage\framework\testing",
        "storage\framework\views",
        "storage\logs",
        "public\uploads",
        "public\uploads\images"
    )

    foreach ($dir in $directories) {
        $fullPath = Join-Path $appPath $dir
        if (-not (Test-Path $fullPath)) {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        }
    }

    # Clear any cached files
    $cacheFiles = Get-Item "$appPath\bootstrap\cache\*.php" -ErrorAction SilentlyContinue
    if ($cacheFiles) {
        Remove-Item $cacheFiles -Force -ErrorAction SilentlyContinue
    }

    # Set permissions
    Set-FullPermissions -Path $appPath

    Write-OK "Storage directories created"
    return $true
}

function Install-BookStackDependencies {
    Write-Step "Installing BookStack Dependencies (Composer)"

    $appPath = $script:Paths.App

    # Setup environment
    $env:PATH = "$($script:Paths.PHP);$($script:Paths.Composer);$($script:Paths.Git)\cmd;$env:PATH"
    $env:COMPOSER_HOME = $script:Paths.Composer
    $env:COMPOSER_CACHE_DIR = "$($script:Paths.Temp)\composer-cache"
    $env:COMPOSER_ALLOW_SUPERUSER = "1"
    $env:COMPOSER_NO_INTERACTION = "1"
    $env:GIT_SSL_NO_VERIFY = "true"

    # Clear vendor folder for fresh install
    $vendorPath = "$appPath\vendor"
    if (Test-Path $vendorPath) {
        Write-Info "Clearing existing vendor folder..."
        Remove-Item $vendorPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Clear composer cache
    Write-Info "Clearing Composer cache..."
    Invoke-Composer -Arguments @("clear-cache") | Out-Null

    Write-Host ""
    Write-Host "  Installing PHP dependencies..." -ForegroundColor Yellow
    Write-Host "  This typically takes 5-15 minutes depending on your connection." -ForegroundColor Gray
    Write-Host ""

    # Run Composer install with prefer-dist (faster downloads)
    $composerArgs = @(
        "install",
        "--no-dev",
        "--no-scripts",
        "--prefer-dist",
        "--optimize-autoloader",
        "--no-interaction",
        "--working-dir=`"$appPath`""
    )

    $result = Invoke-Composer -Arguments $composerArgs -ShowOutput

    # Check if successful
    if (-not (Test-Path "$appPath\vendor\autoload.php")) {
        Write-Warn "First attempt had issues. Trying with prefer-source (uses Git)..."

        $composerArgs = @(
            "install",
            "--no-dev",
            "--no-scripts",
            "--prefer-source",
            "--no-interaction",
            "--working-dir=`"$appPath`""
        )

        $result = Invoke-Composer -Arguments $composerArgs -ShowOutput
    }

    # Verify installation
    if (Test-Path "$appPath\vendor\autoload.php") {
        $vendorCount = (Get-ChildItem "$appPath\vendor" -Directory -ErrorAction SilentlyContinue).Count
        Write-OK "Dependencies installed successfully ($vendorCount packages)"
        return $true
    }

    Write-Err "Dependencies installation failed"
    Write-Host ""
    Write-Host "  Try running manually in a Command Prompt:" -ForegroundColor Yellow
    Write-Host "    cd `"$appPath`"" -ForegroundColor Cyan
    Write-Host "    `"$($script:Files.PHPExe)`" `"$($script:Files.ComposerPhar)`" install --no-dev --no-scripts" -ForegroundColor Cyan
    Write-Host ""

    return $false
}

function Configure-BookStack {
    Write-Step "Configuring BookStack"

    $appPath = $script:Paths.App
    $envFile = "$appPath\.env"
    $envExample = "$appPath\.env.example"

    if (-not (Test-Path $envExample)) {
        Write-Err ".env.example not found!"
        return $false
    }

    Write-Info "Creating .env configuration file..."

    # Generate app key
    $randomBytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($randomBytes)
    $appKey = "base64:" + [Convert]::ToBase64String($randomBytes)
    $rng.Dispose()

    # Create .env content
    $envContent = @"
# BookStack Portable Configuration
# Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

APP_KEY=$appKey
APP_URL=http://localhost:$AppPort
APP_DEBUG=false
APP_ENV=production

# Database Configuration
DB_HOST=127.0.0.1
DB_PORT=$DBPort
DB_DATABASE=$DBName
DB_USERNAME=$DBUser
DB_PASSWORD=$DBPassword

# Mail Configuration (disabled by default)
MAIL_DRIVER=log

# Session Configuration
SESSION_DRIVER=file
SESSION_LIFETIME=120
CACHE_DRIVER=file

# File Storage
STORAGE_TYPE=local
"@

    # Write .env without BOM
    Write-FileNoBom -Path $envFile -Content $envContent

    Write-OK "BookStack configured"
    return $true
}

function Run-BookStackMigrations {
    Write-Step "Running Database Migrations"

    # Ensure database is running
    Start-MariaDBServer -Silent
    Start-Sleep -Seconds 2

    Write-Info "Running migrations..."
    $result = Invoke-Artisan -Arguments @("migrate", "--force") -ShowOutput

    Write-OK "Migrations complete"
    return $true
}

function Create-StartupScripts {
    Write-Step "Creating Startup Scripts"

    # START-BOOKSTACK.bat
    $startBat = @"
@echo off
title BookStack Portable Server
color 0A

echo.
echo ================================================================
echo            BOOKSTACK PORTABLE SERVER
echo ================================================================
echo.
echo   URL:       http://localhost:$AppPort
echo   Login:     admin@admin.com
echo   Password:  password
echo.
echo   Press Ctrl+C to stop the server
echo ================================================================
echo.

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

echo Starting database server...
tasklist /FI "IMAGENAME eq mysqld.exe" 2>NUL | find /I "mysqld.exe">NUL
if errorlevel 1 (
    start "" /B "%ROOT%\mariadb\bin\mysqld.exe" --defaults-file="%ROOT%\mariadb\my.ini"
    echo Waiting for database to start...
    timeout /t 5 /nobreak >nul
)

echo Starting web server on port $AppPort...
echo.
cd /d "%ROOT%\app"
"%ROOT%\php\php.exe" artisan serve --host=0.0.0.0 --port=$AppPort

pause
"@

    Write-FileNoBom -Path $script:Files.StartBat -Content $startBat -Ascii
    Write-OK "Created START-BOOKSTACK.bat"

    # STOP-BOOKSTACK.bat
    $stopBat = @"
@echo off
echo Stopping BookStack services...
taskkill /F /IM php.exe 2>nul
taskkill /F /IM mysqld.exe 2>nul
echo Done.
timeout /t 2 /nobreak >nul
"@

    Write-FileNoBom -Path $script:Files.StopBat -Content $stopBat -Ascii
    Write-OK "Created STOP-BOOKSTACK.bat"

    # START-DATABASE.bat (standalone database start)
    $startDBBat = @"
@echo off
echo Starting MariaDB database server...
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
start "" /B "%ROOT%\mariadb\bin\mysqld.exe" --defaults-file="%ROOT%\mariadb\my.ini"
echo Database server started.
timeout /t 3 /nobreak >nul
"@

    Write-FileNoBom -Path $script:Files.StartDBBat -Content $startDBBat -Ascii
    Write-OK "Created START-DATABASE.bat"

    # STOP-DATABASE.bat
    $stopDBBat = @"
@echo off
echo Stopping MariaDB database server...
taskkill /F /IM mysqld.exe 2>nul
echo Database server stopped.
timeout /t 2 /nobreak >nul
"@

    Write-FileNoBom -Path $script:Files.StopDBBat -Content $stopDBBat -Ascii
    Write-OK "Created STOP-DATABASE.bat"

    # README.txt
    $readme = @"
================================================================
BOOKSTACK PORTABLE
================================================================

Thank you for using BookStack Portable!

QUICK START
-----------
1. Double-click START-BOOKSTACK.bat
2. Open your browser to http://localhost:$AppPort
3. Login with:
   Email:    admin@admin.com
   Password: password

IMPORTANT: Change the default password immediately!

FILES AND FOLDERS
-----------------
app\        - BookStack application
php\        - PHP runtime
mariadb\    - MariaDB database server
data\       - Database files (your content is here!)
logs\       - Log files

PORTABLE
--------
You can copy this entire folder to another Windows PC.
Just run START-BOOKSTACK.bat on the new machine.

BACKUP
------
To backup your data, copy the following folders:
- data\mysql\  (database)
- app\public\uploads\  (uploaded files)
- app\storage\  (app data)

TROUBLESHOOTING
---------------
1. Port already in use:
   - Edit START-BOOKSTACK.bat and change the port number
   - Or stop the other application using port $AppPort

2. Database won't start:
   - Check logs\mariadb_error.log
   - Make sure no other MySQL/MariaDB is running

3. PHP errors:
   - Check logs\php_errors.log

SUPPORT
-------
BookStack Documentation: https://www.bookstackapp.com/docs/
BookStack GitHub: https://github.com/BookStackApp/BookStack

================================================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
================================================================
"@

    Write-FileNoBom -Path $script:Files.ReadMe -Content $readme -Ascii
    Write-OK "Created README.txt"

    # Desktop shortcut
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\BookStack Portable.lnk")
        $Shortcut.TargetPath = $script:Files.StartBat
        $Shortcut.WorkingDirectory = $RootPath
        $Shortcut.Description = "Start BookStack Portable Server"
        $Shortcut.Save()
        Write-OK "Created desktop shortcut"
    } catch {
        Write-Warn "Could not create desktop shortcut"
    }

    return $true
}

function Show-DownloadStats {
    Write-Host ""
    Write-Host "  Download Statistics:" -ForegroundColor Cyan
    Write-Host "    Attempted: $($script:DownloadStats.Attempted)" -ForegroundColor Gray
    Write-Host "    Succeeded: $($script:DownloadStats.Succeeded)" -ForegroundColor Green
    Write-Host "    Failed:    $($script:DownloadStats.Failed)" -ForegroundColor $(if ($script:DownloadStats.Failed -gt 0) { "Yellow" } else { "Gray" })
    Write-Host "    Total:     $(Format-FileSize $script:DownloadStats.TotalBytes)" -ForegroundColor Gray
    if ($script:DownloadStats.TotalTime.TotalSeconds -gt 0) {
        $avgSpeed = Format-FileSize ([long]($script:DownloadStats.TotalBytes / $script:DownloadStats.TotalTime.TotalSeconds))
        Write-Host "    Avg Speed: $avgSpeed/s" -ForegroundColor Gray
    }
}

function Show-CompletionMessage {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "                                                                " -ForegroundColor Green
    Write-Host "     PORTABLE BOOKSTACK INSTALLATION COMPLETE!                  " -ForegroundColor Green
    Write-Host "                                                                " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Location:    $RootPath" -ForegroundColor Cyan
    Write-Host "  URL:         http://localhost:$AppPort" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "  DEFAULT LOGIN:" -ForegroundColor Yellow
    Write-Host "    Email:     admin@admin.com" -ForegroundColor White
    Write-Host "    Password:  password" -ForegroundColor White
    Write-Host ""
    Write-Host "    !!! CHANGE THESE IMMEDIATELY !!!" -ForegroundColor Red
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  TO START:" -ForegroundColor Green
    Write-Host "    Double-click 'BookStack Portable' on your Desktop" -ForegroundColor White
    Write-Host "    Or run: $RootPath\START-BOOKSTACK.bat" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  PORTABLE:" -ForegroundColor Green
    Write-Host "    Copy the entire $RootPath folder to any Windows PC!" -ForegroundColor White
    Write-Host ""
    
    Show-DownloadStats
}

# ============================================================
# MAIN EXECUTION
# ============================================================

function Start-Installation {
    Write-Banner

    Write-Host "  This will create a FULLY PORTABLE BookStack installation." -ForegroundColor White
    Write-Host ""
    Write-Host "  Everything will be installed to:" -ForegroundColor Yellow
    Write-Host "    $RootPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Components:" -ForegroundColor White
    Write-Host "    - PHP 8.x" -ForegroundColor Gray
    Write-Host "    - Composer" -ForegroundColor Gray
    Write-Host "    - Portable Git" -ForegroundColor Gray
    Write-Host "    - MariaDB (database)" -ForegroundColor Gray
    Write-Host "    - BookStack application" -ForegroundColor Gray
    Write-Host ""
    
    if ($script:VerboseMode) {
        Write-Host "  [Verbose mode enabled]" -ForegroundColor Magenta
        Write-Host ""
    }

    $response = Read-Host "Continue with installation? (Y/n)"
    if ($response -eq 'n') {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        return
    }

    # Stop any existing processes
    Write-Info "Stopping any existing processes..."
    Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "php" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Run installation steps (NOTE: SSL Certificates step removed)
    $steps = @(
        @{ Name = "Create Directories"; Func = { Initialize-Directories } },
        @{ Name = "Install PHP"; Func = { Install-PHP } },
        @{ Name = "Configure PHP"; Func = { Configure-PHP } },
        @{ Name = "Install Composer"; Func = { Install-Composer } },
        @{ Name = "Configure Composer"; Func = { Configure-Composer } },
        @{ Name = "Install Git"; Func = { Install-Git } },
        @{ Name = "Install MariaDB"; Func = { Install-MariaDB } },
        @{ Name = "Initialize MariaDB"; Func = { Initialize-MariaDB } },
        @{ Name = "Create Database"; Func = { Initialize-BookStackDatabase } },
        @{ Name = "Install BookStack"; Func = { Install-BookStack } },
        @{ Name = "Create BookStack Directories"; Func = { Initialize-BookStackDirectories } },
        @{ Name = "Install Dependencies"; Func = { Install-BookStackDependencies } },
        @{ Name = "Configure BookStack"; Func = { Configure-BookStack } },
        @{ Name = "Run Migrations"; Func = { Run-BookStackMigrations } },
        @{ Name = "Create Startup Scripts"; Func = { Create-StartupScripts } }
    )

    $stepNumber = 0
    $totalSteps = $steps.Count
    
    foreach ($step in $steps) {
        $stepNumber++
        try {
            $result = & $step.Func
            if ($result -eq $false) {
                Write-Err "Step $stepNumber/$totalSteps - $($step.Name) failed!"
                $continue = Read-Host "Continue anyway? (y/N)"
                if ($continue -ne 'y') {
                    Write-Host "Installation aborted." -ForegroundColor Red
                    return
                }
            }
        } catch {
            Write-Err "Error in step $stepNumber/$totalSteps - $($step.Name): $_"
            $continue = Read-Host "Continue anyway? (y/N)"
            if ($continue -ne 'y') {
                Write-Host "Installation aborted." -ForegroundColor Red
                return
            }
        }
    }

    # Stop MariaDB after installation
    Stop-MariaDBServer -Silent

    # Show completion message
    Show-CompletionMessage

    # Offer to start
    $startNow = Read-Host "Start BookStack now? (Y/n)"
    if ($startNow -ne 'n') {
        Start-Process $script:Files.StartBat
        Start-Sleep -Seconds 5
        Start-Process "http://localhost:$AppPort"
    }
}

# ============================================================
# RUN THE INSTALLER
# ============================================================

Start-Installation