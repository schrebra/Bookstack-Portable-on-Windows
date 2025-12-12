
# BookStack Portable Installer for Windows

A single PowerShell script that creates a fully portable, self-contained BookStack installation on Windows. No Docker. No WSL. No XAMPP. Just double-click and go.

## Why This Exists

Installing BookStack on Windows is traditionally a nightmare. The official docs point you toward Docker or Linux, and the community solutions involve cobbling together XAMPP, manually configuring Apache, wrestling with PHP extensions, and sacrificing hours to cryptic error messages.

This script exists because **nobody should need a computer science degree to run a wiki.**

One command. Ten minutes. Done.

## Who This Is For

- **Small teams and home users** who want a private knowledge base without renting a server
- **IT professionals** who need to deploy BookStack on Windows infrastructure
- **Self-hosters** who are tired of Docker container sprawl
- **Anyone** who just wants the damn thing to work

## What Makes It Great

### Truly Portable

The entire installation lives in a single folder. Want to move it to another PC? Copy the folder. Want to run it from a USB drive? Copy the folder. Want to back it up? You get the idea.

### Zero Prerequisites

The script downloads and configures everything automatically:

- PHP 8.x (thread-safe build with all required extensions)
- Composer (PHP package manager)
- Portable Git
- MariaDB (lightweight MySQL-compatible database)
- BookStack application and all dependencies

Your system stays clean. No global installations. No PATH pollution. No registry entries.

### Batteries Included

After installation, you get simple batch files:

- `START-BOOKSTACK.bat` — Launches everything and opens your browser
- `STOP-BOOKSTACK.bat` — Gracefully shuts it all down
- `START-DATABASE.bat` / `STOP-DATABASE.bat` — Manual database control if needed

A desktop shortcut is created automatically.

### Smart and Resilient

- Detects already-downloaded components and skips them
- Validates downloads with SHA256 checksums
- Handles network failures gracefully
- Cleans up after itself

## Quick Start

### Download and Run

1. Download the powershell script
2. Right-click → "Run with PowerShell" (as Administrator)
3. Follow the prompts

### After Installation

1. Run `START-BOOKSTACK.bat` or use the desktop shortcut
2. Open `http://localhost:8080` in your browser
3. Log in with the default credentials:
   - **Email:** `admin@admin.com`
   - **Password:** `password`
4. **Change the default password immediately**

## System Requirements

- Windows 10 or later (64-bit)
- PowerShell 5.1 or later (included with Windows)
- Administrator privileges (for initial setup only)
- ~2 GB disk space
- Internet connection (for initial download only)

## Installation Directory Structure

```
C:\BookStack\
├── php\                    # PHP runtime
├── composer\               # Composer package manager
├── git\                    # Portable Git
├── mariadb\                # MariaDB database server
├── app\                    # BookStack application
├── data\
│   └── mysql\              # Database files (your content lives here)
├── temp\                   # Temporary files
├── START-BOOKSTACK.bat     # Start everything
├── STOP-BOOKSTACK.bat      # Stop everything
├── START-DATABASE.bat      # Start database only
├── STOP-DATABASE.bat       # Stop database only
└── README.txt              # Quick reference
```

## Configuration

### Changing the Port

By default, BookStack runs on port `8080` and MariaDB on port `3366`. To change these, edit the batch files and the `.env` file in the `app` folder.

### Accessing from Other Devices

To access BookStack from other computers on your network:

1. Open the `.env` file in `C:\BookStack\app\`
2. Change `APP_URL=http://localhost:8080` to `APP_URL=http://YOUR_IP:8080`
3. Ensure Windows Firewall allows inbound connections on port 8080

### Backup

Your data lives in two places:

- `C:\BookStack\data\mysql\` — The database (users, pages, settings)
- `C:\BookStack\app\storage\` — Uploaded files and images

Copy these folders to back up everything.

## Troubleshooting

### "Port 8080 is already in use"

Another application is using the port. Either close that application or edit the batch files to use a different port.

### "MariaDB won't start"

Check if another MySQL/MariaDB instance is running on port 3366. You can change the port in `C:\BookStack\mariadb\my.ini`.

### "PHP errors in the browser"

Run `STOP-BOOKSTACK.bat`, wait a few seconds, then run `START-BOOKSTACK.bat` again. If issues persist, check that antivirus software isn't blocking PHP.

### "Can't access from another computer"

Ensure Windows Firewall isn't blocking the connection. You may need to add an inbound rule for port 8080.


## Uninstalling

1. Run `STOP-BOOKSTACK.bat`
2. Delete the `C:\BookStack` folder
3. Delete the desktop shortcut

That's it. Nothing else to clean up.

## License

This installer script is released under the MIT License.

BookStack itself is licensed under the MIT License. See the [BookStack repository](https://github.com/BookStackApp/BookStack) for details.

## Acknowledgments

- [BookStack](https://www.bookstackapp.com/) — The excellent open-source wiki platform
- [MariaDB](https://mariadb.org/) — The database that makes it all work
- [PHP](https://www.php.net/) — Still powering the web after all these years

---

**Made with frustration, then determination, then satisfaction.**

*If this saved you time, consider [supporting BookStack development](https://www.bookstackapp.com/donate/).*
