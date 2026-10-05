<#
.SYNOPSIS
    Shared Console Helper Utilities for OMNI
.DESCRIPTION
    Common flicker-free cursor, terminal width, and line-rendering functions
    shared across ubat.ps1, LiveMonitor.ps1, and other OMNI modules.
    Dot-source this file instead of duplicating these functions.
#>

# Ensure UTF-8 console output encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}

# Unicode Box Drawing & Clack Timeline Glyphs (String typed for multiplication and formatting)
$global:G_RAIL    = [string][char]0x2502  # │
$global:G_TOP     = [string][char]0x250C  # ┌
$global:G_BOT     = [string][char]0x2514  # └
$global:G_TEE     = [string][char]0x251C  # ├
$global:G_BAR     = [string][char]0x2500  # ─
$global:G_TR      = [string][char]0x256E  # ╮
$global:G_BR      = [string][char]0x256F  # ╯
$global:G_DIAMOND = [string][char]0x25C7  # ◇
$global:G_ACTIVE  = [string][char]0x25CF  # ●
$global:G_IDLE    = [string][char]0x25CB  # ○
$global:G_CHECK   = [string][char]0x2713  # ✓

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

# -- Aliases for LiveMonitor.ps1 naming convention --------------------------
Set-Alias -Name Hide-ConsoleCursor   -Value Hide-Cursor   -Scope Global -Force
Set-Alias -Name Show-ConsoleCursor   -Value Show-Cursor   -Scope Global -Force
Set-Alias -Name Reset-ConsoleCursor  -Value Reset-Cursor  -Scope Global -Force

# -- Modern Clack / Vercel-style UI Rendering Utilities --------------------
function Write-ClackStart {
    param([string]$Title = "")
    Write-Host "$($global:G_TOP)   $Title" -ForegroundColor Cyan
    Write-Host "$($global:G_RAIL)" -ForegroundColor DarkGray
}

function Write-ClackStep {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::White)
    Write-Host "$($global:G_DIAMOND)  " -NoNewline -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor $Color
    Write-Host "$($global:G_RAIL)" -ForegroundColor DarkGray
}

function Write-ClackSuccess {
    param([string]$Message)
    Write-Host "$($global:G_CHECK)  " -NoNewline -ForegroundColor Green
    Write-Host $Message -ForegroundColor White
    Write-Host "$($global:G_RAIL)" -ForegroundColor DarkGray
}

function Write-ClackCard {
    param(
        [string]$Title,
        [array]$Lines,
        [int]$Width = 54
    )
    $pad = [math]::Max(2, ($Width - $Title.Length - 4))
    Write-Host "$($global:G_DIAMOND)  " -NoNewline -ForegroundColor Cyan
    Write-Host "$Title " -NoNewline -ForegroundColor White
    Write-Host ($global:G_BAR * $pad) -NoNewline -ForegroundColor DarkGray
    Write-Host "$($global:G_TR)" -ForegroundColor DarkGray

    Write-Host "$($global:G_RAIL)  " -NoNewline -ForegroundColor DarkGray
    Write-Host (" " * ($Width - 1)) -NoNewline
    Write-Host "$($global:G_RAIL)" -ForegroundColor DarkGray

    foreach ($l in $Lines) {
        $clean = $l -replace '\x1b\[[0-9;]*m', ''
        $spaces = [math]::Max(0, ($Width - $clean.Length - 1))
        Write-Host "$($global:G_RAIL)  $l" -NoNewline
        Write-Host (" " * $spaces) -NoNewline
        Write-Host "$($global:G_RAIL)" -ForegroundColor DarkGray
    }

    Write-Host "$($global:G_RAIL)  " -NoNewline -ForegroundColor DarkGray
    Write-Host (" " * ($Width - 1)) -NoNewline
    Write-Host "$($global:G_RAIL)" -ForegroundColor DarkGray

    Write-Host "$($global:G_TEE)" -NoNewline -ForegroundColor DarkGray
    Write-Host ($global:G_BAR * ($Width + 1)) -NoNewline -ForegroundColor DarkGray
    Write-Host "$($global:G_BR)" -ForegroundColor DarkGray
    Write-Host "$($global:G_RAIL)" -ForegroundColor DarkGray
}

function Write-ClackEnd {
    param([string]$Message = "Done!")
    Write-Host "$($global:G_BOT)  " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor Green
    Write-Host ""
}

function Format-MenuOptionLine {
    param(
        [object]$Option,
        [bool]$IsSelected,
        [int]$TermWidth
    )
    $bullet = if ($IsSelected) { $global:G_ACTIVE } else { $global:G_IDLE }
    $prefix = "$($global:G_RAIL)  $bullet  "
    $avail = $TermWidth - $prefix.Length
    if ($avail -le 24) {
        return "$prefix$($Option.Title)"
    }
    if ($avail -lt 60) {
        $title = $Option.Title
        $rem = $avail - $title.Length - 4
        if ($rem -gt 8) {
            $desc = if ($Option.Desc.Length -gt $rem) { $Option.Desc.Substring(0, $rem - 3) + "..." } else { $Option.Desc }
            return "$prefix$title $($global:G_BAR) $desc"
        } else {
            return "$prefix$title"
        }
    } else {
        $pad = [math]::Min(36, [math]::Max(24, [int]($avail * 0.36)))
        $rem = $avail - $pad - 4
        $desc = if ($Option.Desc.Length -gt $rem) { $Option.Desc.Substring(0, [math]::Max(0, $rem - 3)) + "..." } else { $Option.Desc }
        return "$prefix$($Option.Title.PadRight($pad)) $($global:G_BAR) $desc"
    }
}

function Show-SubMenu {
    param(
        [string]$HubTitle,
        [array]$Options,
        [string]$PromptText = "Choose an operation to execute:"
    )

    $subIndex = 0
    $lastWidth = 0
    $lastHeight = 0

    while ($true) {
        Hide-Cursor
        $termWidth = Get-Width
        $termHeight = try { [Console]::WindowHeight } catch { 25 }
        $lastWidth = $termWidth
        $lastHeight = $termHeight
        try { Clear-Host } catch {}

        $exitSub = $false
        $chosenSubKey = $null

        while (-not $exitSub) {
            $curW = Get-Width
            $curH = try { [Console]::WindowHeight } catch { 25 }
            if ($curW -ne $lastWidth -or $curH -ne $lastHeight) {
                $termWidth = $curW
                $termHeight = $curH
                $lastWidth = $curW
                $lastHeight = $curH
                try { Clear-Host } catch {}
            }

            Reset-Cursor
            Write-LineClean "$($global:G_TOP)   $HubTitle" Cyan
            Write-LineClean "$($global:G_RAIL)" DarkGray
            Write-LineClean "$($global:G_DIAMOND)  $PromptText" White
            Write-LineClean "$($global:G_RAIL)" DarkGray

            for ($i = 0; $i -lt $Options.Count; $i++) {
                $opt = $Options[$i]
                $line = Format-MenuOptionLine -Option $opt -IsSelected ($i -eq $subIndex) -TermWidth $termWidth
                if ($i -eq $subIndex) {
                    Write-LineClean $line Cyan
                } else {
                    Write-LineClean $line DarkGray
                }
            }

            Write-LineClean "$($global:G_RAIL)" DarkGray
            $cardWidth = [math]::Min(58, [math]::Max(42, $termWidth - 6))
            $padLen = [math]::Max(2, ($cardWidth - 14))
            Write-LineClean ("$($global:G_DIAMOND)  Controls " + ($global:G_BAR * $padLen) + $global:G_TR) DarkGray
            Write-LineClean ("$($global:G_RAIL)" + (" " * ($cardWidth + 1)) + "$($global:G_RAIL)") DarkGray
            $arrowNav = "$([char]0x2191)/$([char]0x2193)"
            $contentStr = "  [$arrowNav] Navigate   [Enter] Select   [Esc/Q] Back"
            $contentPad = [math]::Max(1, ($cardWidth - $contentStr.Length + 1))
            Write-LineClean ("$($global:G_RAIL)" + $contentStr + (" " * $contentPad) + "$($global:G_RAIL)") DarkGray
            Write-LineClean ("$($global:G_RAIL)" + (" " * ($cardWidth + 1)) + "$($global:G_RAIL)") DarkGray
            Write-LineClean ("$($global:G_TEE)" + ($global:G_BAR * ($cardWidth + 1)) + $global:G_BR) DarkGray
            Write-LineClean "$($global:G_RAIL)" DarkGray
            Write-LineClean "$($global:G_BOT)  Ready. Use arrow keys to navigate." DarkGray
            try { [Console]::Write("`e[J") } catch {}

            try {
                if ([Console]::IsInputRedirected) { return $null }
            } catch { return $null }

            # Live responsive polling (detects zoom in / zoom out while sitting on menu)
            while (-not [Console]::KeyAvailable) {
                $checkW = Get-Width
                $checkH = try { [Console]::WindowHeight } catch { 25 }
                if ($checkW -ne $lastWidth -or $checkH -ne $lastHeight) {
                    break
                }
                Start-Sleep -Milliseconds 50
            }

            if (-not [Console]::KeyAvailable) {
                continue
            }

            $kInfo = [Console]::ReadKey($true)
            switch ($kInfo.Key) {
                'UpArrow' {
                    $subIndex--
                    if ($subIndex -lt 0) { $subIndex = $Options.Count - 1 }
                }
                'DownArrow' {
                    $subIndex++
                    if ($subIndex -ge $Options.Count) { $subIndex = 0 }
                }
                'Enter' {
                    $chosenSubKey = $Options[$subIndex].Key
                    $exitSub = $true
                }
                'Spacebar' {
                    $chosenSubKey = $Options[$subIndex].Key
                    $exitSub = $true
                }
                'Escape' {
                    return "0"
                }
                Default {
                    $ch = $kInfo.KeyChar
                    if ($ch -eq '0' -or $ch -eq 'q' -or $ch -eq 'Q') {
                        return "0"
                    }
                }
            }
        }

        Show-Cursor
        return $chosenSubKey
    }
}
