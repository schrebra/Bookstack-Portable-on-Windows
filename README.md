# 📖 Portable BookStack Installer for Windows

**A fully automated PowerShell script that sets up a totally self-contained, portable installation of [BookStack](https://www.bookstackapp.com/), a simple, self-hosted wiki and knowledge base, on Windows.**

Tired of complicated software installs? This script takes care of absolutely everything, from downloading all the necessary dependencies to fine-tuning the performance. The result is a complete, ready-to-run environment packed neatly into a single folder.

  * The `BookStack Control Center` PowerShell script for super easy management of your portable instances.
  * The `Bookstack Migration Tool` Powershell script to make migrations from old Bookstacks to new Bookstack Editions
<div align="center">
  <img src="https://github.com/user-attachments/assets/51c96459-b2d3-429d-aed2-7d0b94ef91f2" 
       alt="Bookstack Control Center" 
       width="250" 
       height="200" />
  &nbsp; &nbsp; 
  <img src="https://github.com/user-attachments/assets/907e9790-dbad-406c-bf15-c4dcaa82ea40" 
       alt="Bookstack Migration Tool" 
       width="250" 
       height="150" />
  &nbsp; &nbsp; 
  <img src="https://github.com/user-attachments/assets/3ba0a687-5645-4166-ace7-dff020f091f5"
       alt="Bookstack Installer" 
       width="180" 
       height="150" />
</div>

## ✨ Why Go Portable?

| Feature | Description | Benefit |
| :--- | :--- | :--- |
| **100% Portable** | The entire application lives inside just one folder (`C:\BookStack` is the default location). | Move it, copy it, or run it straight from a USB drive without reinstalling anything. |
| **Zero Dependencies** | Everything you need is configured and included: **Apache 2.4, PHP 8.x, MariaDB, Composer, and Portable Git.** | You don't need any pre-existing software. No messy registry changes or system clutter. |
| **Performance Tuned** | It comes pre-configured for maximum speed with **JIT Compiler, OPcache,** and database optimizations already set up. | You get a fast, responsive knowledge base right from the start. |
| **Automated Setup** | The script handles all the downloading, configuration, database creation, and shortcut generation. | Go from hitting "Run" on the script to having a working wiki in just a few minutes. |

-----

## 📋 What You Need

  * **OS:** Windows 10, Windows 11, or Windows Server.
  * **PowerShell:** Version 5.1 or newer (it's pre-installed on all modern Windows versions).
  * **Internet Connection:** Only needed during the initial installation to grab the components.

## 🚀 Installation: Let's Get Running

### 1\. Download

Grab the installation script right here from this repository.

### 2\. Execute

Open **PowerShell as Administrator** (you need this for file permissions and network settings) and run the script:

```powershell
.\Install.Bookstack.On.Windows.ps1
```

### 3\. Script Parameters (Customize It)

You can easily change the installation defaults using these parameters.

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `-RootPath` | `C:\BookStack` | The exact folder where everything will be installed. |
| `-AppPort` | `8080` | The port for the Apache web server (e.g., `80` if you want a standard URL). |
| `-DBPort` | `3366` | The port for the MariaDB database. |
| `-DBPassword` | `bookstack123` | The initial database root password. **Seriously, change this right away\!** |

> **Example:** To install the app inside your user profile folder and use port 80:
> `.\Install.Bookstack.On.Windows.ps1 -RootPath "$env:USERPROFILE\BookStack" -AppPort 80`

-----

## 🖥️ How to Use It

The installation folder has easy batch files for managing the whole setup.

### The Quick Way (Primary Controls)

| Command | Description |
| :--- | :--- |
| **`START-BOOKSTACK.bat`** | **The main command.** Kicks off both Apache (the Web Server) and MariaDB (the Database) in the background. |
| **`STOP-BOOKSTACK.bat`** | Shuts down everything running (Apache, all PHP-CGI processes, and MariaDB). |

### Controlling Things Separately

| Command | Description |
| :--- | :--- |
| `START-DATABASE.bat` / `STOP-DATABASE.bat` | Just controls the MariaDB server. |
| `START-APACHE.bat` / `STOP-APACHE.bat` | Just controls the Apache web server. |

### Default Login Info

Here's how to access your BookStack:

| Detail | Value |
| :--- | :--- |
| **URL** | `http://localhost:<AppPort>` (e.g., `http://localhost:8080`) |
| **Email** | `admin@admin.com` |
| **Password** | `password` |

> ⚠️ **Important:** Please change these default credentials immediately after you log in for the first time\!

-----

## 📂 What the Folder Looks Like

The installation creates a tidy, self-contained structure:

```
C:\BookStack\
├── app\             # The main BookStack code (this is where you'd put updates)
├── apache\          # Apache HTTPD Web Server files
├── php\             # The PHP Runtime optimized for this setup
├── mariadb\         # Database Server files
├── data\            # **THIS IS WHERE YOUR CONTENT IS SAVED!** (Database files, uploads, and config)
├── logs\            # Access, Error, and PHP logs (handy for debugging)
├── downloads\       # A cache of the installers it downloaded (you can safely delete this later)
├── temp\            # Temporary session files
└── START-BOOKSTACK.bat # The main launcher
```

-----

## 🔄 Backup & Moving

The best part about being portable: backing up or moving your entire BookStack instance is incredibly easy.

1.  Run **`STOP-BOOKSTACK.bat`** to make sure all services are safely closed.
2.  **Copy the whole `C:\BookStack` folder** to your backup drive or your new machine.
3.  On the new computer, just run **`START-BOOKSTACK.bat`**. That's it\!

-----

## 🔧 Need Help? (Troubleshooting)

### Port 8080 is already busy

  * **Option 1 (Easiest):** Just run the installer again with a different port number:
    `.\Install.Bookstack.On.Windows.ps1 -AppPort 8088`
  * **Option 2 (Manual Fix):**
    1.  Edit `apache\conf\httpd.conf` and change `Listen 8080` to your preferred port.
    2.  Then, update the `APP_URL` variable inside `app\.env` to match the new port.

### Missing Visual C++ Redistributable Errors

If Apache or PHP fails to load, you might be missing a necessary system library.

  * **Solution:** Download and install the latest [Visual C++ Redistributable (vc\_redist.x64.exe)](https://www.google.com/search?q=https://aka.ms/vs/17/release/vc_redist.x64.exe) from Microsoft.

### Services won't start at all

Your first stop should always be the log files in the `logs\` folder.

| Log File | Component | What to look for |
| :--- | :--- | :--- |
| `logs\apache_error.log` | Apache Web Server | Permissions issues or configuration mistakes. |
| `logs\mariadb_error.log` | MariaDB Database | Port conflicts or database startup failures. |
| `logs\php_errors.log` | PHP Runtime | Any fatal PHP errors or missing extensions. |

-----

## 📜 License

This installation script is open-source.

  * BookStack itself is licensed under the **MIT license**.
  * The other components it downloads (Apache, PHP, MariaDB) follow their own respective open-source licenses.
-----

## ⚖️ Project Status and Transparency

This code is provided to the community **"as is"** (as you see it) with the goal of being helpful and functional.

### Our Commitment

While we strive to provide high-quality and reliable code, please note:

* We cannot offer any express or implied **guarantees or warranties** regarding its performance, suitability for a specific purpose, or lack of defects.
* The author(s) and contributors are not liable for any issues or damage that may arise from using this software.

### 🛡️ Best Practices for Use

We encourage responsible testing and deployment, especially in critical environments. Before running this code on a production server, we strongly recommend that you:

1.  **Always test first** in a staging or development environment.
2.  **Verify your backups** are complete and working, ensuring you have a safe restore point.
3.  Understand that using the code means you are accepting responsibility for assessing its suitability for your specific needs.
