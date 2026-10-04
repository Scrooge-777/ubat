<#
.SYNOPSIS
    Shared Console Helper Utilities for OMNI
.DESCRIPTION
    Common flicker-free cursor, terminal width, and line-rendering functions
    shared across ubat.ps1, LiveMonitor.ps1, and other OMNI modules.
    Dot-source this file instead of duplicating these functions.
#>

function Hide-Cursor {
    try { [Console]::CursorVisible = $false } catch {}
    try { [Console]::Write("`e[?25l") } catch {}
}

function Show-Cursor {
    try { [Console]::CursorVisible = $true } catch {}
    try { [Console]::Write("`e[?25h") } catch {}
}

function Reset-Cursor {
    try {
        [Console]::SetCursorPosition(0, 0)
    } catch {
        try { [Console]::Write("`e[H") } catch {}
    }
}

function Get-Width {
    $w = 88
    try {
        if ([Console]::WindowWidth -gt 1) {
            $w = [Console]::WindowWidth - 1
            if ($w -lt 35) { $w = 35 }
        }
    } catch { $w = 88 }
    return $w
}

# Alias for modules that use Get-TermWidth
function Get-TermWidth { return Get-Width }

function Write-LineClean {
    param(
        [string]$Text = "",
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    $termWidth = Get-Width
    $cleanText = if ($Text.Length -lt $termWidth) {
        $Text.PadRight($termWidth)
    } else {
        $Text.Substring(0, $termWidth)
    }
    Write-Host "$cleanText`e[K" -ForegroundColor $ForegroundColor
}

function Write-Border {
    param([string]$Char = "=", [ConsoleColor]$Color = [ConsoleColor]::Cyan)
    $w = Get-Width
    Write-Host ($Char * $w) -ForegroundColor $Color
}

function Write-Centered {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Yellow)
    $w = Get-Width
    $spaces = [math]::Max(0, [math]::Floor(($w - $Text.Length) / 2))
    $str = if ($Text.Length -gt $w) { $Text.Substring(0, $w) } else { (" " * $spaces) + $Text }
    Write-Host $str -ForegroundColor $Color
}

# ── Aliases for LiveMonitor.ps1 naming convention ──────────────────────────
Set-Alias -Name Hide-ConsoleCursor   -Value Hide-Cursor   -Scope Global -Force
Set-Alias -Name Show-ConsoleCursor   -Value Show-Cursor   -Scope Global -Force
Set-Alias -Name Reset-ConsoleCursor  -Value Reset-Cursor  -Scope Global -Force
