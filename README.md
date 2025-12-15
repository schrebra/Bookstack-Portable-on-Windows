

# 📖 Portable BookStack Installer for Windows

**A fully automated PowerShell script that creates a self-contained, portable installation of [BookStack](https://www.bookstackapp.com/) (a simple, self-hosted wiki/knowledge base) on Windows.**

Tired of complex installations? This script handles everything—from downloading dependencies to performance tuning—creating a complete, ready-to-run environment in a single folder.

  * **Included:** The `BookStack Control Center` PowerShell script for easy management of your portable instances.

<img src="https://github.com/user-attachments/assets/b2257ec9-bc21-4fdb-8d5c-ac0b084ae8f1" alt="BookStack Control Center Screenshot" width="75%"/>

## ✨ Why Go Portable?

| Feature | Description | Benefit |
| :--- | :--- | :--- |
| **100% Portable** | The entire application lives in a single folder (`C:\BookStack` by default). | Easily move, copy, or run from a USB drive without re-installation. |
| **Zero Dependencies** | Everything is included and configured: **Apache 2.4, PHP 8.x, MariaDB, Composer, Portable Git.** | No pre-existing software required. No registry changes or system clutter. |
| **Performance Tuned** | Pre-configured for speed with **JIT Compiler, OPcache,** and database optimizations. | Get a fast knowledge base right out of the box. |
| **Automated Setup** | Handles downloading, configuration, database creation, and shortcut generation. | Go from script download to running wiki in minutes. |

-----

## 📋 Prerequisites

  * **OS:** Windows 10 / Windows 11 / Windows Server.
  * **PowerShell:** Version 5.1 or newer (pre-installed on all modern Windows versions).
  * **Internet Connection:** Required only during the initial installation to download components.

## 🚀 Installation & First Run

### 1\. Download

Download the installation script from this repository.

### 2\. Execute

Open **PowerShell as Administrator** (this is necessary for network configuration and file permissions) and run the script:

```powershell
.\Install.Bookstack.On.Windows.ps1
```

### 3\. Script Parameters (Optional)

You can customize the installation using parameters.

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `-RootPath` | `C:\BookStack` | The target folder for the entire installation. |
| `-AppPort` | `8080` | The port for the Apache web server (e.g., `80`). |
| `-DBPort` | `3366` | The port for the MariaDB database. |
| `-DBPassword` | `bookstack123` | The initial database root password. **Change this immediately\!** |

> **Example:** To install to your user profile on port 80:
> `.\Install.Bookstack.On.Windows.ps1 -RootPath "$env:USERPROFILE\BookStack" -AppPort 80`

-----

## 🖥️ Usage & Control

Your installation folder contains simple batch files to manage the service.

### Primary Controls

| Command | Description |
| :--- | :--- |
| **`START-BOOKSTACK.bat`** | **The main launcher.** Starts both Apache (Web Server) and MariaDB (Database) in the background. |
| **`STOP-BOOKSTACK.bat`** | Stops all running services (Apache, PHP-CGI processes, MariaDB). |

### Granular Controls

| Command | Description |
| :--- | :--- |
| `START-DATABASE.bat` / `STOP-DATABASE.bat` | Controls only the MariaDB database server. |
| `START-APACHE.bat` / `STOP-APACHE.bat` | Controls only the Apache web server. |

### Default Login Credentials

Access your BookStack instance:

| Detail | Value |
| :--- | :--- |
| **URL** | `http://localhost:<AppPort>` (e.g., `http://localhost:8080`) |
| **Email** | `admin@admin.com` |
| **Password** | `password` |

> ⚠️ **Important:** Change these default credentials immediately after your first login\!

-----

## 📂 Directory Structure

The installation creates a fully self-contained, logical structure:

```
C:\BookStack\
├── app\             # The main BookStack application code (where updates go)
├── apache\          # Apache HTTPD Web Server configuration and binaries
├── php\             # PHP Runtime (Optimized for FastCGI)
├── mariadb\         # Database Server binaries
├── data\            # **YOUR CONTENT LIVES HERE!** (Database files, uploads, config)
├── logs\            # Access, Error, and PHP logs for troubleshooting
├── downloads\       # Cache of downloaded installers (can be safely deleted after setup)
├── temp\            # Temporary session files
└── START-BOOKSTACK.bat # Primary Launcher
```

-----

## 🔄 Backup & Migration (The Portable Advantage)

Backing up or moving your entire BookStack instance is as simple as copying a folder.

1.  Run **`STOP-BOOKSTACK.bat`** to safely close all services and flush data buffers.
2.  **Copy the entire `C:\BookStack` folder** to your backup location or new computer.
3.  On the new computer, simply run **`START-BOOKSTACK.bat`**. Done\!

-----

## 🔧 Troubleshooting

### Port 8080 is already in use

  * **Solution 1 (Recommended):** Re-run the installer with a different port:
    `.\Install.Bookstack.On.Windows.ps1 -AppPort 8088`
  * **Solution 2 (Manual):**
    1.  Edit `apache\conf\httpd.conf` and change `Listen 8080` to your desired port.
    2.  Update the `APP_URL` variable in `app\.env` to reflect the new port.

### Visual C++ Redistributable Errors

If Apache or PHP fails to start, you may be missing a required system library.

  * **Solution:** Download and install the latest [Visual C++ Redistributable (vc\_redist.x64.exe)](https://www.google.com/search?q=https://aka.ms/vs/17/release/vc_redist.x64.exe) from Microsoft.

### Services won't start

Always check the log files first.

| Log File | Component | What to look for |
| :--- | :--- | :--- |
| `logs\apache_error.log` | Apache Web Server | Configuration errors, permissions issues. |
| `logs\mariadb_error.log` | MariaDB Database | Database startup failures, port conflicts. |
| `logs\php_errors.log` | PHP Runtime | Fatal PHP errors, missing extensions. |

-----

## 📜 License

This installation script is open-source.

  * BookStack itself is licensed under the **MIT license**.
  * All downloaded components (Apache, PHP, MariaDB) are subject to their respective open-source licenses.
