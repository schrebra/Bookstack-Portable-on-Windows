# Portable BookStack Installer for Windows

A fully automated PowerShell script that creates a self-contained, portable installation of [BookStack](https://www.bookstackapp.com/) on Windows. 


## 🚀 Features

*   **100% Portable:** The entire installation lives in a single folder (`C:\BookStack` by default). You can copy this folder to a USB drive or another computer, and it will just work.
*   **Zero Dependencies:** The script automatically downloads and configures:
    *   **Apache HTTPD 2.4:** Configured with `mod_fcgid` for FastCGI performance.
    *   **PHP 8.x:** Optimized with JIT Compiler and OPcache enabled.
    *   **MariaDB:** Performance-tuned portable database instance.
    *   **Composer:** For dependency management.
    *   **Portable Git:** For application updates.
*   **Performance Tuned:** Pre-configured with caching (Route, View, Config) and database optimizations.
*   **Automated:** Handles downloading, extraction, configuration, database creation, migrations, and shortcut creation.

## 📋 Prerequisites

*   **OS:** Windows.
*   **PowerShell:** Version 5.1 or newer (pre-installed on Windows).
*   **Internet Connection:** Required during installation to download components.

## 🛠️ Installation

1.  Download the script from this repository.
2.  Open **PowerShell as Administrator**.
3.  Run the script:


Script Parameters
Parameter	Default	Description
-RootPath	C:\BookStack	The folder where everything will be installed.
-AppPort	8080	The port for the Apache web server.
-DBPort	3366	The port for the MariaDB database.
-DBPassword	bookstack123	The initial database password.
🖥️ Usage

Once installed, you will find the following batch files in your installation folder:

    START-BOOKSTACK.bat
    Starts both Apache and MariaDB in the background. This is the main launcher.
    STOP-BOOKSTACK.bat
    Stops all running services (Apache, PHP-CGI, MariaDB).
    START-DATABASE.bat / STOP-DATABASE.bat
    Controls only the database server.
    START-APACHE.bat / STOP-APACHE.bat
    Controls only the web server.

Default Login Credentials

    URL: http://localhost:8080
    Email: admin@admin.com
    Password: password

    ⚠️ Important: Change these credentials immediately after your first login!

📂 Directory Structure

The installation creates a self-contained environment:
text

C:\BookStack\
├── app\              # The BookStack application code
├── apache\           # Apache HTTPD Web Server
├── php\              # PHP Runtime (Thread Safe)
├── mariadb\          # Database Server
├── data\             # Database files (Your content lives here!)
├── logs\             # Access and Error logs
├── downloads\        # Cache of downloaded installers
├── temp\             # Temporary session files
└── START-BOOKSTACK.bat

🔄 How to Backup / Move

Because this is a portable installation, backing up or moving to a new machine is incredibly simple:

    Run STOP-BOOKSTACK.bat to ensure all services are closed.
    Copy the entire C:\BookStack folder to your backup location or new computer.
    On the new computer, simply run START-BOOKSTACK.bat.

🔧 Troubleshooting

Port 8080 is already in use
Edit apache\conf\httpd.conf and change Listen 8080 to a different port. Also update APP_URL in app\.env.

Visual C++ Redistributable Errors
If Apache or PHP fails to start, you may need to install the latest Visual C++ Redistributable (vc_redist.x64.exe).

Services won't start
Check the logs\ folder. Specifically:

    logs\apache_error.log
    logs\mariadb_error.log
    logs\php_errors.log

📜 License

This script is open-source. BookStack itself is licensed under the MIT license. All downloaded components (Apache, PHP, MariaDB) are subject to their respective licenses.
