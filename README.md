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
- Works behind corporate proxies
- Cleans up after itself



