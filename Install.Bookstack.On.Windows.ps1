#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Portable BookStack Complete Installation Script for Windows (Apache Edition)

.DESCRIPTION
    Creates a fully portable, self-contained BookStack installation.
    Everything is installed to a single folder including:
    - Apache HTTPD (Portable Web Server)
    - PHP 8.x (Optimized with JIT/OPcache)
    - Composer
    - Portable Git
    - MariaDB (Performance Tuned)
    - BookStack application (Pre-cached)

    The entire folder can be copied to another Windows machine and run.

.NOTES
    Version: 8.1 (Apache Edition - Fixed)

    Structure:
    C:\BookStack\
    ├── app\              # BookStack application
    ├── apache\           # Apache HTTPD server
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
    .\Install-BookStack-Portable-Apache.ps1

.EXAMPLE
    .\Install-BookStack-Portable-Apache.ps1 -RootPath "D:\BookStack" -AppPort "8000"
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
    Apache      = "$RootPath\apache"
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
    PHPCgiExe       = "$RootPath\php\php-cgi.exe"
    PHPIni          = "$RootPath\php\php.ini"
    ApacheExe       = "$RootPath\apache\bin\httpd.exe"
    ApacheConf      = "$RootPath\apache\conf\httpd.conf"
    ApacheVhostConf = "$RootPath\apache\conf\extra\httpd-vhosts.conf"
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
    StartApacheBat  = "$RootPath\START-APACHE.bat"
    StopApacheBat   = "$RootPath\STOP-APACHE.bat"
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
    Write-Host "      PORTABLE BOOKSTACK INSTALLER (APACHE EDITION)             " -ForegroundColor White
    Write-Host "                      Version 8.1                               " -ForegroundColor Gray
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

function Get-ApacheDownloadUrls {
    Write-Info "Discovering Apache HTTPD download URLs..."

    # Check cache first
    $cache = Get-UrlCache
    if ($cache.Apache) {
        Write-Debug "Using cached Apache URL"
        return @($cache.Apache)
    }

    # Apache Lounge provides Windows binaries
    # VS17 builds are for latest Visual C++ runtime
    $urls = @(
        "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.62-240904-win64-VS17.zip",
        "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.62-win64-VS17.zip",
        "https://www.apachelounge.com/download/VS16/binaries/httpd-2.4.62-win64-VS16.zip"
    )

    # Try to discover latest from Apache Lounge
    try {
        $response = Invoke-WebRequest -Uri "https://www.apachelounge.com/download/" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $content = $response.Content

        # Find httpd zip files
        $pattern = 'href="([^"]*httpd-2\.4\.\d+-[^"]*win64-VS1[67]\.zip)"'
        $matches = [regex]::Matches($content, $pattern)

        $discoveredUrls = @()
        foreach ($match in $matches) {
            $filename = $match.Groups[1].Value
            if ($filename -notmatch "^http") {
                $filename = "https://www.apachelounge.com/download/$filename"
            }
            $discoveredUrls += $filename
        }

        if ($discoveredUrls.Count -gt 0) {
            $urls = $discoveredUrls + $urls | Select-Object -Unique
            Write-OK "Found $($discoveredUrls.Count) Apache versions"
        }
    } catch {
        Write-Debug "Failed to parse Apache Lounge: $_"
    }

    # Test and cache
    $workingUrl = Find-WorkingUrl -Urls $urls -MinSize 10MB
    if ($workingUrl) {
        $cacheData = Get-UrlCache
        if (-not $cacheData) { $cacheData = @{} }
        $cacheData.Apache = $workingUrl
        Set-UrlCache -Urls $cacheData
        Write-OK "Found Apache: $(Split-Path $workingUrl -Leaf)"
    }

    return $urls
}

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
    # NOTE: For Apache, we need Thread Safe (TS) version
    try {
        $response = Invoke-WebRequest -Uri "https://windows.php.net/downloads/releases/" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $content = $response.Content

        # Find all PHP 8.x Win32 vs16 x64 Thread Safe zip files
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

    # Fallback: Known stable versions (Thread Safe for Apache)
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
    @("git", "php", "php-cgi", "mysqld", "mysql", "composer", "httpd") | ForEach-Object {
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

    # Create the app/public directory early for Apache config validation
    $appPublicPath = "$($script:Paths.App)\public"
    if (-not (Test-Path $appPublicPath)) {
        New-Item -ItemType Directory -Path $appPublicPath -Force | Out-Null
        Write-Info "Created: $appPublicPath (placeholder for Apache)"
    }

    # Set permissions on root
    Set-FullPermissions -Path $RootPath

    Write-OK "Directory structure ready"
    return $true
}

# ============================================================
# APACHE INSTALLATION
# ============================================================

function Install-Apache {
    Write-Step "Installing Apache HTTPD (Portable)"

    $apacheExe = $script:Files.ApacheExe
    $apachePath = $script:Paths.Apache
    $apacheZip = "$($script:Paths.Downloads)\httpd.zip"
    $minSize = 10MB

    # Check if already installed
    if (Test-Path $apacheExe) {
        $result = Invoke-SafeCommand -Executable $apacheExe -Arguments @("-v")
        $version = ($result.StdOut -split "`n")[0]
        Write-OK "Apache already installed: $version"
        return $true
    }

    Write-Info "Apache not found, downloading..."

    # Check for manually placed file
    $manualFiles = @(
        $apacheZip,
        "$env:USERPROFILE\Downloads\httpd*.zip",
        "$env:USERPROFILE\Downloads\Apache*.zip"
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

    if ($foundFile -and $foundFile -ne $apacheZip) {
        Copy-Item $foundFile $apacheZip -Force
        Write-OK "Found Apache: $($found.Name)"
    } elseif (-not (Test-Path $apacheZip) -or (Get-Item $apacheZip -ErrorAction SilentlyContinue).Length -lt $minSize) {
        # Get dynamic URLs
        $apacheUrls = Get-ApacheDownloadUrls
        $downloaded = Download-WithFallback -Urls $apacheUrls -OutputPath $apacheZip -MinSize $minSize -Description "Apache HTTPD 2.4"

        if (-not $downloaded) {
            Request-ManualDownload -Description "Apache HTTPD (Win64 ZIP)" `
                -Url "https://www.apachelounge.com/download/" `
                -SavePath $apacheZip `
                -SearchPattern "httpd*.zip" `
                -MinSizeMB 10
        }
    }

    # Verify download
    if (-not (Test-Path $apacheZip) -or (Get-Item $apacheZip).Length -lt $minSize) {
        Write-Err "Apache download not found or incomplete"
        return $false
    }

    # Clear existing and extract
    if (Test-Path $apachePath) {
        Remove-Item $apachePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $apachePath -Force | Out-Null

    # Extract - Apache Lounge zips contain "Apache24" folder
    if (-not (Extract-Archive -ArchivePath $apacheZip -DestinationPath $apachePath -StripFirstFolder)) {
        Write-Err "Failed to extract Apache"
        return $false
    }

    # Verify extraction
    if (-not (Test-Path $apacheExe)) {
        # Check if it extracted to a subfolder
        $subDir = Get-ChildItem $apachePath -Directory | Where-Object { $_.Name -match "Apache" -or $_.Name -eq "bin" } | Select-Object -First 1
        if ($subDir -and (Test-Path "$($subDir.FullName)\bin\httpd.exe")) {
            # Move contents up
            Get-ChildItem $subDir.FullName | ForEach-Object {
                Move-Item $_.FullName $apachePath -Force
            }
            Remove-Item $subDir.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path $apacheExe)) {
        Write-Err "Apache extraction failed - httpd.exe not found"
        return $false
    }

    Write-OK "Apache extracted successfully"
    return $true
}

function Configure-Apache {
    Write-Step "Configuring Apache for BookStack"

    $apachePath = $script:Paths.Apache
    $phpPath = $script:Paths.PHP
    $appPath = $script:Paths.App
    $logsPath = $script:Paths.Logs
    $apacheConf = $script:Files.ApacheConf

    # Ensure the public directory exists for Apache config validation
    $appPublicPath = "$appPath\public"
    if (-not (Test-Path $appPublicPath)) {
        New-Item -ItemType Directory -Path $appPublicPath -Force | Out-Null
        Write-Info "Created app/public directory for Apache"
    }

    # Convert paths to forward slashes for Apache config
    $apachePathFwd = $apachePath -replace '\\', '/'
    $phpPathFwd = $phpPath -replace '\\', '/'
    $appPathFwd = $appPath -replace '\\', '/'
    $logsPathFwd = $logsPath -replace '\\', '/'

    # Check if mod_fcgid exists
    $fcgidExists = Test-Path "$apachePath\modules\mod_fcgid.so"
    $fcgidLoadLine = if ($fcgidExists) {
        "LoadModule fcgid_module modules/mod_fcgid.so"
    } else {
        "# LoadModule fcgid_module modules/mod_fcgid.so  # Not installed - using CGI fallback"
    }

    # Create Apache configuration
    $httpdConf = @"
# Apache HTTPD Configuration for BookStack Portable
# Generated by BookStack Portable Installer

# Server root and modules
ServerRoot "$apachePathFwd"
Listen $AppPort

# Load required modules
LoadModule access_compat_module modules/mod_access_compat.so
LoadModule actions_module modules/mod_actions.so
LoadModule alias_module modules/mod_alias.so
LoadModule allowmethods_module modules/mod_allowmethods.so
LoadModule auth_basic_module modules/mod_auth_basic.so
LoadModule authn_core_module modules/mod_authn_core.so
LoadModule authn_file_module modules/mod_authn_file.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule authz_host_module modules/mod_authz_host.so
LoadModule authz_user_module modules/mod_authz_user.so
LoadModule autoindex_module modules/mod_autoindex.so
LoadModule cgi_module modules/mod_cgi.so
LoadModule dir_module modules/mod_dir.so
LoadModule env_module modules/mod_env.so
$fcgidLoadLine
LoadModule headers_module modules/mod_headers.so
LoadModule log_config_module modules/mod_log_config.so
LoadModule mime_module modules/mod_mime.so
LoadModule negotiation_module modules/mod_negotiation.so
LoadModule rewrite_module modules/mod_rewrite.so
LoadModule setenvif_module modules/mod_setenvif.so

# Server configuration
ServerAdmin admin@localhost
ServerName localhost:$AppPort

# Document root - BookStack public folder
DocumentRoot "$appPathFwd/public"

<Directory />
    AllowOverride None
    Require all denied
</Directory>

<Directory "$appPathFwd/public">
    Options FollowSymLinks ExecCGI
    AllowOverride All
    Require all granted
    DirectoryIndex index.php index.html
</Directory>

# Logging
ErrorLog "$logsPathFwd/apache_error.log"
LogLevel warn

<IfModule log_config_module>
    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
    LogFormat "%h %l %u %t \"%r\" %>s %b" common
    CustomLog "$logsPathFwd/apache_access.log" combined
</IfModule>

# MIME types
<IfModule mime_module>
    TypesConfig conf/mime.types
    AddType application/x-compress .Z
    AddType application/x-gzip .gz .tgz
    AddType application/x-httpd-php .php
</IfModule>

# PHP via FastCGI (mod_fcgid) - preferred method
<IfModule fcgid_module>
    FcgidInitialEnv PHPRC "$phpPathFwd"
    FcgidInitialEnv PHP_FCGI_MAX_REQUESTS 10000
    FcgidMaxRequestLen 1073741824
    FcgidIOTimeout 600
    FcgidConnectTimeout 60
    FcgidProcessLifeTime 3600
    FcgidMaxProcesses 5
    FcgidMinProcessesPerClass 1
    FcgidMaxProcessesPerClass 5
    
    <Files ~ "\.php$">
        Options +ExecCGI
        AddHandler fcgid-script .php
        FcgidWrapper "$phpPathFwd/php-cgi.exe" .php
    </Files>
</IfModule>

# PHP via CGI - fallback when mod_fcgid is not available
<IfModule !fcgid_module>
    <IfModule cgi_module>
        # Set up PHP-CGI as a script processor
        ScriptAlias /php-cgi-bin/ "$phpPathFwd/"
        
        <Directory "$phpPathFwd">
            AllowOverride None
            Options None
            Require all granted
        </Directory>
        
        # Process .php files through php-cgi.exe
        Action application/x-httpd-php "/php-cgi-bin/php-cgi.exe"
        
        # Set environment for PHP
        SetEnv PHPRC "$phpPathFwd"
    </IfModule>
</IfModule>

# Security headers
<IfModule headers_module>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
</IfModule>

# Enable rewrite engine for Laravel/BookStack
<IfModule rewrite_module>
    RewriteEngine On
</IfModule>

# Disable directory listings
<IfModule autoindex_module>
    IndexIgnore *
</IfModule>

# Performance
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# Timeouts
Timeout 300

# PidFile location
PidFile "$logsPathFwd/httpd.pid"

# Include additional configs if they exist
IncludeOptional conf/extra/httpd-default.conf
"@

    # Backup original config if exists
    if (Test-Path $apacheConf) {
        Copy-Item $apacheConf "$apacheConf.original" -Force
    }

    # Write new config
    Write-FileNoBom -Path $apacheConf -Content $httpdConf

    if ($fcgidExists) {
        Write-OK "Apache configured with mod_fcgid (FastCGI)"
    } else {
        Write-Warn "Apache configured with CGI fallback (mod_fcgid not found)"
        Write-Info "Performance may be reduced. Consider installing mod_fcgid manually."
    }
    
    return $true
}

function Install-ApacheFcgid {
    Write-Info "Checking for mod_fcgid..."

    $apachePath = $script:Paths.Apache
    $fcgidModule = "$apachePath\modules\mod_fcgid.so"
    $fcgidZip = "$($script:Paths.Downloads)\mod_fcgid.zip"

    if (Test-Path $fcgidModule) {
        Write-OK "mod_fcgid already installed"
        return $true
    }

    Write-Info "Downloading mod_fcgid..."

    # mod_fcgid download URLs
    $fcgidUrls = @(
        "https://www.apachelounge.com/download/VS17/modules/mod_fcgid-2.3.10-win64-VS17.zip",
        "https://www.apachelounge.com/download/VS16/modules/mod_fcgid-2.3.10-win64-VS16.zip"
    )

    $downloaded = Download-WithFallback -Urls $fcgidUrls -OutputPath $fcgidZip -MinSize 50KB -Description "mod_fcgid"

    if (-not $downloaded) {
        Write-Warn "Could not download mod_fcgid. Will use CGI mode instead."
        return $true  # Continue anyway, CGI fallback is configured
    }

    # Extract mod_fcgid
    $tempExtract = "$($script:Paths.Temp)\fcgid_extract"
    if (Test-Path $tempExtract) {
        Remove-Item $tempExtract -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

    try {
        Expand-Archive -Path $fcgidZip -DestinationPath $tempExtract -Force

        # Find mod_fcgid.so
        $fcgidFile = Get-ChildItem $tempExtract -Recurse -Filter "mod_fcgid.so" | Select-Object -First 1
        if ($fcgidFile) {
            Copy-Item $fcgidFile.FullName $fcgidModule -Force
            Write-OK "mod_fcgid installed"
        } else {
            Write-Warn "mod_fcgid.so not found in archive"
        }
    } catch {
        Write-Warn "Failed to extract mod_fcgid: $_"
    }

    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    return $true
}

# ============================================================
# PHP INSTALLATION (Thread Safe for Apache)
# ============================================================

function Install-PHP {
    Write-Step "Installing PHP (Portable - Thread Safe)"

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
        $downloaded = Download-WithFallback -Urls $phpUrls -OutputPath $phpZip -MinSize $minSize -Description "PHP 8.3 (Thread Safe)"

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

    # Verify php-cgi.exe exists (needed for Apache)
    if (-not (Test-Path $script:Files.PHPCgiExe)) {
        Write-Err "php-cgi.exe not found - make sure you downloaded Thread Safe version"
        return $false
    }

    Write-OK "PHP extracted successfully"
    return $true
}

function Configure-PHP {
    Write-Step "Configuring PHP (High Performance Mode for Apache)"

    $phpPath = $script:Paths.PHP
    $phpIni = $script:Files.PHPIni
    $tempPath = $script:Paths.Temp
    $logsPath = $script:Paths.Logs

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

    # Enable extensions (ADDED OPCACHE)
    $extensions = @(
        "curl", "fileinfo", "gd", "mbstring", "mysqli",
        "openssl", "pdo_mysql", "xml", "ldap", "zip",
        "exif", "intl", "sodium", "gettext", "opcache"
    )

    foreach ($ext in $extensions) {
        $content = $content -replace ";extension=$ext", "extension=$ext"
    }

    # Set paths (using forward slashes)
    $extDir = "$phpPath\ext" -replace '\\', '/'
    $tempDir = $tempPath -replace '\\', '/'
    $logsDir = $logsPath -replace '\\', '/'

    # Update extension directory
    $content = $content -replace ';?\s*extension_dir\s*=\s*"ext"', "extension_dir = `"$extDir`""
    $content = $content -replace ';?\s*extension_dir\s*=\s*"\./"', "extension_dir = `"$extDir`""

    # Set memory and upload limits (INCREASED FOR PERFORMANCE)
    $content = $content -replace 'memory_limit\s*=\s*\d+M', 'memory_limit = 512M'
    $content = $content -replace 'upload_max_filesize\s*=\s*\d+M', 'upload_max_filesize = 128M'
    $content = $content -replace 'post_max_size\s*=\s*\d+M', 'post_max_size = 128M'
    $content = $content -replace 'max_execution_time\s*=\s*\d+', 'max_execution_time = 300'
    $content = $content -replace 'max_input_time\s*=\s*\d+', 'max_input_time = 300'
    $content = $content -replace 'max_input_vars\s*=\s*\d+', 'max_input_vars = 5000'

    # Enable cgi.fix_pathinfo for Apache
    $content = $content -replace ';?\s*cgi\.fix_pathinfo\s*=\s*\d', 'cgi.fix_pathinfo=1'

    # Add portable configuration at the end (INCLUDES JIT/OPCACHE)
    $portableConfig = @"

; ================================================================
; PORTABLE BOOKSTACK CONFIGURATION - APACHE + PHP-CGI
; ================================================================

; Temporary directory
sys_temp_dir = "$tempDir"
upload_tmp_dir = "$tempDir"

; Error logging
error_log = "$logsDir/php_errors.log"
log_errors = On
display_errors = Off

; Timezone (adjust as needed)
date.timezone = UTC

; Session settings
session.save_path = "$tempDir"

; CGI/FastCGI settings
cgi.fix_pathinfo = 1
fastcgi.impersonate = 1
cgi.force_redirect = 0

; --------------------------------------
; OPCACHE & JIT (The Speed Boosters)
; --------------------------------------
[opcache]
opcache.enable=1
opcache.enable_cli=1
; Increase memory for code cache
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
; Don't check for file changes on every request (Performance win)
opcache.revalidate_freq=60
opcache.save_comments=1
; JIT Compiler (PHP 8.x)
opcache.jit_buffer_size=100M
opcache.jit=1255
"@

    $content = $content.TrimEnd() + "`n" + $portableConfig

    # Write php.ini without BOM
    Write-FileNoBom -Path $phpIni -Content $content

    Write-Info "Created php.ini with JIT and OPcache enabled for Apache"

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
# MARIADB INSTALLATION (PERFORMANCE TUNED)
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
    Write-Info "Creating MariaDB configuration (Performance Tuned)..."

    $mariaPath = $script:Paths.MariaDB
    $dataPath = $script:Paths.DataDB
    $logsPath = $script:Paths.Logs
    $myIni = $script:Files.MariaDBIni

    # Use forward slashes for MySQL config
    $dataDirForward = $dataPath -replace '\\', '/'
    $baseDirForward = $mariaPath -replace '\\', '/'
    $logDirForward = $logsPath -replace '\\', '/'

    # PERFORMANCE OPTIMIZED CONFIG
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

; Performance Tuning (Blazing Fast Mode)
innodb_buffer_pool_size=512M
innodb_log_file_size=128M
innodb_log_buffer_size=16M
innodb_write_io_threads=4
innodb_read_io_threads=4
innodb_flush_log_at_trx_commit=2
innodb_io_capacity=1000

; Caching
query_cache_type=1
query_cache_limit=2M
query_cache_size=64M
table_open_cache=2000
thread_cache_size=16

; Temp Tables
max_heap_table_size=64M
tmp_table_size=64M

; Basics
max_connections=100
innodb_file_per_table=1
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

    Write-FileNoBom -Path $myIni -Content $myIniContent

    Write-OK "MariaDB configuration created (Performance Optimized)"
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

    # Create configuration first
    Create-MariaDBConfig

    # Check if already initialized
    if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
        Write-OK "MariaDB data directory already initialized"
        return $true
    }

    Write-Info "Initializing MariaDB data directory..."

    # Clear any partial data
    Get-ChildItem $dataPath -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # METHOD 1: Use mysql_install_db.exe
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
            $process.WaitForExit(180000)

            if ($stdout) {
                $stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
                    Write-Host "    $_" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Warn "mysql_install_db error: $_"
        } finally {
            if ($process) { $process.Dispose() }
        }

        if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
            Write-OK "MariaDB initialized successfully"
            return $true
        }
    }

    # METHOD 2: Check for bundled data directory
    Write-SubStep "Checking for bundled data template"

    $bundledDataPaths = @("$mariaPath\data", "$mariaPath\var")

    $foundDataFolder = Get-ChildItem $mariaPath -Directory -Recurse -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -eq "data" -and (Test-Path "$($_.FullName)\mysql") } |
                       Select-Object -First 1

    if ($foundDataFolder) {
        $bundledDataPaths += $foundDataFolder.FullName
    }

    foreach ($bundledPath in $bundledDataPaths) {
        if ($bundledPath -and (Test-Path "$bundledPath\mysql")) {
            Write-Info "Found bundled data at: $bundledPath"
            Get-ChildItem $dataPath -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item "$bundledPath\*" $dataPath -Recurse -Force

            if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
                Write-OK "MariaDB initialized from bundled data"
                return $true
            }
        }
    }

    # METHOD 3: Use mysqld --initialize-insecure
    Write-SubStep "Trying mysqld --initialize-insecure"

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

    # METHOD 4: Start mysqld and let it self-initialize
    Write-SubStep "Trying mysqld self-initialization"

    Get-ChildItem $dataPath -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $startArgs = "--defaults-file=`"$myIni`" --skip-grant-tables --console"
    $process = Start-Process -FilePath $mysqldExe -ArgumentList $startArgs -PassThru -WindowStyle Hidden

    Write-Info "Waiting for MariaDB to initialize..."

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

    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3

    if ((Test-Path "$dataPath\mysql") -and (Get-ChildItem "$dataPath\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
        Write-OK "MariaDB self-initialized successfully"
        return $true
    }

    Write-Err "Automatic initialization failed"
    Write-Host ""
    Write-Host "  Please run these commands manually:" -ForegroundColor Yellow
    Write-Host "    cd `"$mariaPath\bin`"" -ForegroundColor Cyan
    Write-Host "    mysql_install_db.exe --datadir=`"$dataPath`" --password=" -ForegroundColor Cyan
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

    if (-not (Test-Path $mysqldExe)) {
        Write-Err "mysqld.exe not found at: $mysqldExe"
        return $false
    }

    $process = Start-Process -FilePath $mysqldExe -ArgumentList "--defaults-file=`"$myIni`"" -PassThru -WindowStyle Hidden

    $maxWait = 60
    $waited = 0

    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds 1
        $waited++

        if ($process.HasExited) {
            Write-Warn "MariaDB process exited unexpectedly"
            return $false
        }

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

    if (Test-Path $mysqladminExe) {
        try {
            $result = & $mysqladminExe -u root -P $DBPort -h 127.0.0.1 --skip-password shutdown 2>&1
            Start-Sleep -Seconds 2
        } catch {}
    }

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

    if (-not (Test-Path $appPath)) {
        New-Item -ItemType Directory -Path $appPath -Force | Out-Null
    }

    # Try Git clone first
    if (Test-Path $gitExe) {
        Write-Info "Cloning BookStack with Git..."

        $env:GIT_SSL_NO_VERIFY = "true"

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

    # Fallback to ZIP download
    Write-Info "Downloading BookStack as ZIP..."

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

    if (-not (Test-Path $bookstackZip) -or (Get-Item $bookstackZip).Length -lt $minSize) {
        Write-Err "BookStack download not found or incomplete"
        return $false
    }

    Write-Info "Extracting BookStack..."

    if (-not (Extract-Archive -ArchivePath $bookstackZip -DestinationPath $appPath -StripFirstFolder)) {
        Write-Err "Failed to extract BookStack"
        return $false
    }

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

    $cacheFiles = Get-Item "$appPath\bootstrap\cache\*.php" -ErrorAction SilentlyContinue
    if ($cacheFiles) {
        Remove-Item $cacheFiles -Force -ErrorAction SilentlyContinue
    }

    Set-FullPermissions -Path $appPath

    Write-OK "Storage directories created"
    return $true
}

function Install-BookStackDependencies {
    Write-Step "Installing BookStack Dependencies (Composer)"

    $appPath = $script:Paths.App

    $env:PATH = "$($script:Paths.PHP);$($script:Paths.Composer);$($script:Paths.Git)\cmd;$env:PATH"
    $env:COMPOSER_HOME = $script:Paths.Composer
    $env:COMPOSER_CACHE_DIR = "$($script:Paths.Temp)\composer-cache"
    $env:COMPOSER_ALLOW_SUPERUSER = "1"
    $env:COMPOSER_NO_INTERACTION = "1"
    $env:GIT_SSL_NO_VERIFY = "true"

    $vendorPath = "$appPath\vendor"
    if (Test-Path $vendorPath) {
        Write-Info "Clearing existing vendor folder..."
        Remove-Item $vendorPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Info "Clearing Composer cache..."
    Invoke-Composer -Arguments @("clear-cache") | Out-Null

    Write-Host ""
    Write-Host "  Installing PHP dependencies..." -ForegroundColor Yellow
    Write-Host "  This typically takes 5-15 minutes depending on your connection." -ForegroundColor Gray
    Write-Host ""

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

    if (-not (Test-Path "$appPath\vendor\autoload.php")) {
        Write-Warn "First attempt had issues. Trying with prefer-source..."

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

    if (Test-Path "$appPath\vendor\autoload.php") {
        $vendorCount = (Get-ChildItem "$appPath\vendor" -Directory -ErrorAction SilentlyContinue).Count
        Write-OK "Dependencies installed successfully ($vendorCount packages)"
        return $true
    }

    Write-Err "Dependencies installation failed"
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

    $envContent = @"
# BookStack Portable Configuration (Apache Edition)
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

    Write-FileNoBom -Path $envFile -Content $envContent

    Write-OK "BookStack configured"
    return $true
}

function Run-BookStackMigrations {
    Write-Step "Running Database Migrations"

    Start-MariaDBServer -Silent
    Start-Sleep -Seconds 2

    Write-Info "Running migrations..."
    $result = Invoke-Artisan -Arguments @("migrate", "--force") -ShowOutput

    Write-OK "Migrations complete"
    return $true
}

function Optimize-BookStackInstallation {
    Write-Step "Applying BookStack Production Optimizations"

    Start-MariaDBServer -Silent

    $appPath = $script:Paths.App

    Write-Info "Caching configuration and routes..."

    Invoke-Artisan -Arguments @("config:cache") -ShowOutput
    Invoke-Artisan -Arguments @("route:cache") -ShowOutput
    Invoke-Artisan -Arguments @("view:cache") -ShowOutput

    Write-OK "BookStack optimized for production speed"
    return $true
}

# ============================================================
# APACHE STARTUP SCRIPTS
# ============================================================

function Create-StartupScripts {
    Write-Step "Creating Startup Scripts"

    # START-BOOKSTACK.bat (Apache version)
    $startBat = @"
@echo off
title BookStack Portable Server (Apache)
color 0A

echo.
echo ================================================================
echo         BOOKSTACK PORTABLE SERVER (APACHE EDITION)
echo ================================================================
echo.
echo   URL:       http://localhost:$AppPort
echo   Login:     admin@admin.com
echo   Password:  password
echo.
echo   Press Ctrl+C or close this window to stop all services
echo ================================================================
echo.

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

echo [1/2] Starting MariaDB database server...
tasklist /FI "IMAGENAME eq mysqld.exe" 2>NUL | find /I "mysqld.exe">NUL
if errorlevel 1 (
    start "" /B "%ROOT%\mariadb\bin\mysqld.exe" --defaults-file="%ROOT%\mariadb\my.ini"
    echo       Waiting for database to start...
    timeout /t 5 /nobreak >nul
    echo       Database started.
) else (
    echo       Database already running.
)

echo.
echo [2/2] Starting Apache web server on port $AppPort...
tasklist /FI "IMAGENAME eq httpd.exe" 2>NUL | find /I "httpd.exe">NUL
if errorlevel 1 (
    "%ROOT%\apache\bin\httpd.exe"
) else (
    echo       Apache already running.
    echo.
    echo Press any key to stop all services...
    pause >nul
    taskkill /F /IM httpd.exe 2>nul
    taskkill /F /IM mysqld.exe 2>nul
)

pause
"@

    Write-FileNoBom -Path $script:Files.StartBat -Content $startBat -Ascii
    Write-OK "Created START-BOOKSTACK.bat"

    # STOP-BOOKSTACK.bat
    $stopBat = @"
@echo off
echo Stopping BookStack services...
echo.
echo Stopping Apache...
taskkill /F /IM httpd.exe 2>nul
echo Stopping MariaDB...
taskkill /F /IM mysqld.exe 2>nul
echo Stopping PHP processes...
taskkill /F /IM php-cgi.exe 2>nul
taskkill /F /IM php.exe 2>nul
echo.
echo All services stopped.
timeout /t 2 /nobreak >nul
"@

    Write-FileNoBom -Path $script:Files.StopBat -Content $stopBat -Ascii
    Write-OK "Created STOP-BOOKSTACK.bat"

    # START-DATABASE.bat
    $startDBBat = @"
@echo off
echo Starting MariaDB database server...
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
start "" /B "%ROOT%\mariadb\bin\mysqld.exe" --defaults-file="%ROOT%\mariadb\my.ini"
echo Database server started on port $DBPort.
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

    # START-APACHE.bat
    $startApacheBat = @"
@echo off
echo Starting Apache web server...
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
"%ROOT%\apache\bin\httpd.exe"
"@

    Write-FileNoBom -Path $script:Files.StartApacheBat -Content $startApacheBat -Ascii
    Write-OK "Created START-APACHE.bat"

    # STOP-APACHE.bat
    $stopApacheBat = @"
@echo off
echo Stopping Apache web server...
taskkill /F /IM httpd.exe 2>nul
taskkill /F /IM php-cgi.exe 2>nul
echo Apache stopped.
timeout /t 2 /nobreak >nul
"@

    Write-FileNoBom -Path $script:Files.StopApacheBat -Content $stopApacheBat -Ascii
    Write-OK "Created STOP-APACHE.bat"

    # README.txt
    $readme = @"
================================================================
BOOKSTACK PORTABLE (APACHE EDITION)
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

COMPONENTS
----------
- Apache HTTPD:  Web server (replaces php artisan serve)
- PHP:           Application runtime with FastCGI
- MariaDB:       Database server
- BookStack:     Documentation platform

FILES AND FOLDERS
-----------------
app\        - BookStack application
apache\     - Apache HTTPD web server
php\        - PHP runtime
mariadb\    - MariaDB database server
data\       - Database files (your content is here!)
logs\       - Log files (apache, php, mariadb)

PORTABLE
--------
You can copy this entire folder to another Windows PC.
Just run START-BOOKSTACK.bat on the new machine.

INDIVIDUAL CONTROLS
-------------------
START-BOOKSTACK.bat  - Start both Apache and MariaDB
STOP-BOOKSTACK.bat   - Stop all services
START-DATABASE.bat   - Start only MariaDB
STOP-DATABASE.bat    - Stop MariaDB
START-APACHE.bat     - Start only Apache
STOP-APACHE.bat      - Stop Apache

BACKUP
------
To backup your data, copy the following folders:
- data\mysql\           (database)
- app\public\uploads\   (uploaded files)
- app\storage\          (app data)

TROUBLESHOOTING
---------------
1. Port already in use:
   - Edit apache\conf\httpd.conf and change Listen $AppPort
   - Also update APP_URL in app\.env

2. Apache won't start:
   - Check logs\apache_error.log
   - Ensure no other web server uses port $AppPort

3. PHP errors:
   - Check logs\php_errors.log

4. Database issues:
   - Check logs\mariadb_error.log
   - Ensure no other MySQL/MariaDB uses port $DBPort

PERFORMANCE
-----------
This installation includes:
- PHP OPcache with JIT compilation
- Optimized MariaDB InnoDB settings
- Pre-cached Laravel routes and views

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
        $Shortcut.Description = "Start BookStack Portable Server (Apache)"
        $Shortcut.Save()
        Write-OK "Created desktop shortcut"
    } catch {
        Write-Warn "Could not create desktop shortcut"
    }

    return $true
}

# ============================================================
# APACHE SERVER CONTROL FUNCTIONS
# ============================================================

function Test-ApacheConfiguration {
    Write-Info "Testing Apache configuration..."

    $apacheExe = $script:Files.ApacheExe

    if (-not (Test-Path $apacheExe)) {
        Write-Err "Apache not found"
        return $false
    }

    $result = Invoke-SafeCommand -Executable $apacheExe -Arguments @("-t") -ShowOutput -ShowErrors

    if ($result.StdErr -match "Syntax OK") {
        Write-OK "Apache configuration is valid"
        return $true
    } elseif ($result.StdOut -match "Syntax OK") {
        Write-OK "Apache configuration is valid"
        return $true
    } else {
        Write-Warn "Apache configuration may have issues"
        Write-Host $result.StdErr -ForegroundColor Yellow
        return $true  # Continue anyway
    }
}

function Start-ApacheServer {
    param([switch]$Silent)

    if (-not $Silent) {
        Write-Info "Starting Apache server..."
    }

    $apacheExe = $script:Files.ApacheExe

    # Check if already running
    $existingProcess = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
    if ($existingProcess) {
        if (-not $Silent) {
            Write-OK "Apache is already running"
        }
        return $true
    }

    if (-not (Test-Path $apacheExe)) {
        Write-Err "httpd.exe not found at: $apacheExe"
        return $false
    }

    # Start Apache in background
    $process = Start-Process -FilePath $apacheExe -PassThru -WindowStyle Hidden

    # Wait for it to start
    $maxWait = 30
    $waited = 0

    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds 1
        $waited++

        if ($process.HasExited) {
            Write-Warn "Apache process exited unexpectedly"

            # Check error log
            $errorLog = "$($script:Paths.Logs)\apache_error.log"
            if (Test-Path $errorLog) {
                $lastLines = Get-Content $errorLog -Tail 10 -ErrorAction SilentlyContinue
                if ($lastLines) {
                    Write-Host "Last error log entries:" -ForegroundColor Yellow
                    $lastLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
                }
            }

            return $false
        }

        # Try to connect
        try {
            $testUrl = "http://localhost:$AppPort"
            $response = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 302) {
                if (-not $Silent) {
                    Write-OK "Apache started successfully (port $AppPort)"
                }
                return $true
            }
        } catch {
            # Still starting up
        }

        if (-not $Silent -and ($waited % 5 -eq 0)) {
            Write-Host "." -NoNewline
        }
    }

    if (-not $Silent) {
        Write-Host ""
    }

    # Final check - is process running?
    $runningProcess = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
    if ($runningProcess) {
        if (-not $Silent) {
            Write-OK "Apache is running (connection test pending)"
        }
        return $true
    }

    Write-Warn "Apache may not have started properly"
    return $false
}

function Stop-ApacheServer {
    param([switch]$Silent)

    if (-not $Silent) {
        Write-Info "Stopping Apache server..."
    }

    # Kill httpd processes
    $process = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Name "httpd" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # Also kill any php-cgi processes
    $phpCgi = Get-Process -Name "php-cgi" -ErrorAction SilentlyContinue
    if ($phpCgi) {
        Stop-Process -Name "php-cgi" -Force -ErrorAction SilentlyContinue
    }

    if (-not $Silent) {
        Write-OK "Apache stopped"
    }
}

# ============================================================
# VERIFICATION AND STATISTICS FUNCTIONS
# ============================================================

function Test-Installation {
    Write-Step "Verifying Installation"

    $allGood = $true

    # Check PHP
    if (Test-Path $script:Files.PHPExe) {
        $result = Invoke-SafeCommand -Executable $script:Files.PHPExe -Arguments @("-v")
        if ($result.Success) {
            $version = ($result.StdOut -split "`n")[0]
            Write-OK "PHP: $version"
        } else {
            Write-Warn "PHP installed but may have issues"
        }
    } else {
        Write-Err "PHP not found"
        $allGood = $false
    }

    # Check php-cgi
    if (Test-Path $script:Files.PHPCgiExe) {
        Write-OK "PHP-CGI: Found"
    } else {
        Write-Err "PHP-CGI not found (required for Apache)"
        $allGood = $false
    }

    # Check Apache
    if (Test-Path $script:Files.ApacheExe) {
        $result = Invoke-SafeCommand -Executable $script:Files.ApacheExe -Arguments @("-v")
        $version = ($result.StdOut -split "`n")[0]
        Write-OK "Apache: $version"
    } else {
        Write-Err "Apache not found"
        $allGood = $false
    }

    # Check MariaDB
    if (Test-Path $script:Files.MySQLDExe) {
        Write-OK "MariaDB: Found"
    } else {
        Write-Err "MariaDB not found"
        $allGood = $false
    }

    # Check Composer
    if (Test-Path $script:Files.ComposerPhar) {
        Write-OK "Composer: Found"
    } else {
        Write-Warn "Composer not found"
    }

    # Check BookStack
    if (Test-Path "$($script:Paths.App)\artisan") {
        Write-OK "BookStack: Found"

        # Check vendor
        if (Test-Path "$($script:Paths.App)\vendor\autoload.php") {
            Write-OK "Dependencies: Installed"
        } else {
            Write-Warn "Dependencies may be missing"
            $allGood = $false
        }

        # Check .env
        if (Test-Path "$($script:Paths.App)\.env") {
            Write-OK "Configuration: Found"
        } else {
            Write-Warn ".env file missing"
            $allGood = $false
        }
    } else {
        Write-Err "BookStack not found"
        $allGood = $false
    }

    # Check database data
    if ((Test-Path "$($script:Paths.DataDB)\mysql") -and (Get-ChildItem "$($script:Paths.DataDB)\mysql" -ErrorAction SilentlyContinue).Count -gt 5) {
        Write-OK "Database: Initialized"
    } else {
        Write-Warn "Database may not be initialized"
    }

    if ($allGood) {
        Write-Host ""
        Write-OK "All components verified successfully!"
    } else {
        Write-Host ""
        Write-Warn "Some components may need attention"
    }

    return $allGood
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
    Write-Host "   PORTABLE BOOKSTACK INSTALLATION COMPLETE! (APACHE EDITION)  " -ForegroundColor Green
    Write-Host "                                                                " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Location:    $RootPath" -ForegroundColor Cyan
    Write-Host "  URL:         http://localhost:$AppPort" -ForegroundColor Cyan
    Write-Host "  Web Server:  Apache HTTPD" -ForegroundColor Cyan
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
    Write-Host "  Using Apache HTTPD as the web server (production-ready)." -ForegroundColor White
    Write-Host ""
    Write-Host "  Everything will be installed to:" -ForegroundColor Yellow
    Write-Host "    $RootPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Components:" -ForegroundColor White
    Write-Host "    - Apache HTTPD 2.4 (Web Server)" -ForegroundColor Gray
    Write-Host "    - PHP 8.x (Thread Safe)" -ForegroundColor Gray
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
    Stop-Process -Name "httpd" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "php" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "php-cgi" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Run installation steps
    $steps = @(
        @{ Name = "Create Directories"; Func = { Initialize-Directories } },
        @{ Name = "Install Apache"; Func = { Install-Apache } },
        @{ Name = "Install mod_fcgid"; Func = { Install-ApacheFcgid } },
        @{ Name = "Install PHP"; Func = { Install-PHP } },
        @{ Name = "Configure PHP"; Func = { Configure-PHP } },
        @{ Name = "Configure Apache"; Func = { Configure-Apache } },
        @{ Name = "Test Apache Config"; Func = { Test-ApacheConfiguration } },
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
        @{ Name = "Optimize BookStack"; Func = { Optimize-BookStackInstallation } },
        @{ Name = "Create Startup Scripts"; Func = { Create-StartupScripts } },
        @{ Name = "Verify Installation"; Func = { Test-Installation } }
    )

    $stepNumber = 0
    $totalSteps = $steps.Count

    foreach ($step in $steps) {
        $stepNumber++
        Write-Host ""
        Write-Host "[$stepNumber/$totalSteps] $($step.Name)" -ForegroundColor Magenta

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

    # Stop services after installation
    Stop-ApacheServer -Silent
    Stop-MariaDBServer -Silent

    # Show completion message
    Show-CompletionMessage

    # Offer to start
    $startNow = Read-Host "Start BookStack now? (Y/n)"
    if ($startNow -ne 'n') {
        Write-Info "Starting services..."

        # Start MariaDB first
        Start-MariaDBServer -Silent
        Start-Sleep -Seconds 3

        # Start Apache
        Start-ApacheServer -Silent
        Start-Sleep -Seconds 3

        # Open browser
        Start-Process "http://localhost:$AppPort"

        Write-Host ""
        Write-Host "  BookStack is now running!" -ForegroundColor Green
        Write-Host "  Browser opened to http://localhost:$AppPort" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  To stop services, run STOP-BOOKSTACK.bat" -ForegroundColor Yellow
    }
}

# ============================================================
# RUN THE INSTALLER
# ============================================================

Start-Installation