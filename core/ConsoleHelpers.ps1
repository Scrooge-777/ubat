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
$global:G_RAIL    = [string][char]0x2502  # U+2502 vertical rail
$global:G_TOP     = [string][char]0x250C  # U+250C top-left corner
$global:G_BOT     = [string][char]0x2514  # U+2514 bottom-left corner
$global:G_TEE     = [string][char]0x251C  # U+251C tee-branch
$global:G_BAR     = [string][char]0x2500  # U+2500 horizontal bar
$global:G_TL      = [string][char]0x256D  # U+256D rounded top-left
$global:G_TR      = [string][char]0x256E  # U+256E rounded top-right
$global:G_BL      = [string][char]0x2570  # U+2570 rounded bottom-left
$global:G_BR      = [string][char]0x256F  # U+256F rounded bottom-right
$global:G_LT      = [string][char]0x251C  # U+251C left tee
$global:G_RT      = [string][char]0x2524  # U+2524 right tee
$global:G_DIAMOND = [string][char]0x25C7  # U+25C7 diamond
$global:G_ACTIVE  = [string][char]0x25CF  # U+25CF solid circle
$global:G_IDLE    = [string][char]0x25CB  # U+25CB empty circle
$global:G_CHECK   = [string][char]0x2713  # U+2713 checkmark

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
        [int]$TermWidth = 88
    )
    $bullet = if ($IsSelected) { $global:G_ACTIVE } else { $global:G_IDLE }
    $boxWidth = [math]::Min(102, [math]::Max(46, $TermWidth - 4))
    $innerWidth = $boxWidth - 2
    $colTitleWidth = [math]::Min([int]($innerWidth * 0.44), 36)
    $rawTitle = $Option.Title
    $titlePadded = if ($rawTitle.Length -gt $colTitleWidth) {
        $rawTitle.Substring(0, $colTitleWidth - 3) + "... "
    } else {
        $rawTitle.PadRight($colTitleWidth)
    }
    $availDesc = [math]::Max(0, $innerWidth - 5 - $colTitleWidth - 3 - 2)
    $rawDesc = if ($Option.Desc) { [string]$Option.Desc } else { "" }
    $desc = if ($rawDesc.Length -gt $availDesc) {
        if ($availDesc -gt 3) { $rawDesc.Substring(0, $availDesc - 3) + "..." } else { "" }
    } else {
        $rawDesc
    }
    $sepStr = if ($availDesc -ge 6 -and $desc.Length -gt 0) { " $global:G_BAR " } else { "   " }
    $innerRow = "  $bullet  $titlePadded$sepStr$desc"
    $trailSpaces = [math]::Max(0, $innerWidth - $innerRow.Length)
    return "$global:G_RAIL$innerRow" + (" " * $trailSpaces) + "$global:G_RAIL"
}

function Show-SubMenu {
    param(
        [string]$HubTitle,
        [array]$Options,
        [string]$PromptText = "Choose an operation to execute:",
        [string]$Subtitle = "",
        [int]$DefaultIndex = 0
    )

    $subIndex = $DefaultIndex
    if ($subIndex -lt 0 -or $subIndex -ge $Options.Count) { $subIndex = 0 }
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

            # Card Container Dimensions
            $boxWidth = [math]::Min(102, [math]::Max(46, $termWidth - 4))
            $innerWidth = $boxWidth - 2

            # 1. Header with Title Badge
            $maxTitleChars = [math]::Max(4, $boxWidth - 12)
            $cleanTitle = if ($HubTitle.Length -gt $maxTitleChars) { $HubTitle.Substring(0, $maxTitleChars - 3) + "..." } else { $HubTitle }
            $titleBadge = " [ $cleanTitle ] "
            $dashesNeeded = [math]::Max(1, $boxWidth - 4 - $titleBadge.Length)
            $topLine = "$global:G_TL$global:G_BAR$global:G_BAR$titleBadge" + ($global:G_BAR * $dashesNeeded) + "$global:G_TR"
            if ($topLine.Length -gt $boxWidth) { $topLine = $topLine.Substring(0, $boxWidth - 1) + $global:G_TR }
            Write-Host "$topLine`e[K" -ForegroundColor Cyan

            # 2. Blank Spacer
            Write-Host ("$global:G_RAIL" + (" " * $innerWidth) + "$global:G_RAIL`e[K") -ForegroundColor DarkGray

            # 3. Optional Subtitle (e.g. Platform / CPU metadata)
            if ($Subtitle) {
                $subClean = if ($Subtitle.Length -gt ($innerWidth - 6)) { $Subtitle.Substring(0, $innerWidth - 9) + "..." } else { $Subtitle }
                $subPad = [math]::Max(0, $innerWidth - 5 - $subClean.Length)
                Write-Host "$global:G_RAIL  " -NoNewline -ForegroundColor DarkGray
                Write-Host "$global:G_DIAMOND  " -NoNewline -ForegroundColor Cyan
                Write-Host $subClean -NoNewline -ForegroundColor DarkGray
                Write-Host (" " * $subPad) -NoNewline
                Write-Host "$global:G_RAIL`e[K" -ForegroundColor DarkGray
            }

            # 4. Prompt Text
            $promptClean = if ($PromptText.Length -gt ($innerWidth - 6)) { $PromptText.Substring(0, $innerWidth - 9) + "..." } else { $PromptText }
            $promptPad = [math]::Max(0, $innerWidth - 5 - $promptClean.Length)
            Write-Host "$global:G_RAIL  " -NoNewline -ForegroundColor DarkGray
            Write-Host "$global:G_DIAMOND  " -NoNewline -ForegroundColor Cyan
            Write-Host $promptClean -NoNewline -ForegroundColor White
            Write-Host (" " * $promptPad) -NoNewline
            Write-Host "$global:G_RAIL`e[K" -ForegroundColor DarkGray

            # 5. Blank Spacer
            Write-Host ("$global:G_RAIL" + (" " * $innerWidth) + "$global:G_RAIL`e[K") -ForegroundColor DarkGray

            # 6. Options with Aligned Columns
            $maxT = 0
            foreach ($o in $Options) { if ($o.Title.Length -gt $maxT) { $maxT = $o.Title.Length } }
            $maxColAllowed = [math]::Max(20, [int]($innerWidth * 0.48))
            $colTitleWidth = [math]::Min($maxColAllowed, [math]::Max(20, $maxT))

            for ($i = 0; $i -lt $Options.Count; $i++) {
                $opt = $Options[$i]
                $isSel = ($i -eq $subIndex)
                $bullet = if ($isSel) { $global:G_ACTIVE } else { $global:G_IDLE }
                $rawTitle = $opt.Title
                $titlePadded = if ($rawTitle.Length -gt $colTitleWidth) {
                    $rawTitle.Substring(0, $colTitleWidth - 3) + "..."
                } else {
                    $rawTitle.PadRight($colTitleWidth)
                }

                $availDesc = [math]::Max(0, $innerWidth - 5 - $colTitleWidth - 3 - 2)
                $rawDesc = if ($opt.Desc) { [string]$opt.Desc } else { "" }
                $desc = if ($rawDesc.Length -gt $availDesc) {
                    if ($availDesc -gt 3) { $rawDesc.Substring(0, $availDesc - 3) + "..." } else { "" }
                } else {
                    $rawDesc
                }

                $sepStr = if ($availDesc -ge 6 -and $desc.Length -gt 0) { " $global:G_BAR " } else { "   " }
                $innerRow = "  $bullet  $titlePadded$sepStr$desc"
                $trailSpaces = [math]::Max(0, $innerWidth - $innerRow.Length)

                if ($isSel) {
                    Write-Host "$global:G_RAIL" -NoNewline -ForegroundColor Cyan
                    Write-Host "  $bullet  " -NoNewline -ForegroundColor Cyan
                    Write-Host "$titlePadded" -NoNewline -ForegroundColor White
                    Write-Host "$sepStr" -NoNewline -ForegroundColor Cyan
                    Write-Host "$desc" -NoNewline -ForegroundColor Cyan
                    Write-Host (" " * $trailSpaces) -NoNewline
                    Write-Host "$global:G_RAIL`e[K" -ForegroundColor Cyan
                } else {
                    Write-Host "$global:G_RAIL" -NoNewline -ForegroundColor DarkGray
                    Write-Host "  $bullet  " -NoNewline -ForegroundColor DarkGray
                    Write-Host "$titlePadded" -NoNewline -ForegroundColor Gray
                    Write-Host "$sepStr" -NoNewline -ForegroundColor DarkGray
                    Write-Host "$desc" -NoNewline -ForegroundColor DarkGray
                    Write-Host (" " * $trailSpaces) -NoNewline
                    Write-Host "$global:G_RAIL`e[K" -ForegroundColor DarkGray
                }
            }

            # 7. Blank Spacer
            Write-Host ("$global:G_RAIL" + (" " * $innerWidth) + "$global:G_RAIL`e[K") -ForegroundColor DarkGray

            # 8. Divider Line
            $divLine = "$global:G_LT" + ($global:G_BAR * $innerWidth) + "$global:G_RT"
            Write-Host "$divLine`e[K" -ForegroundColor DarkGray

            # 9. Controls Footer
            $arrowNav = "$([char]0x2191)/$([char]0x2193)"
            $actionLabel = if ($HubTitle -match "MAIN|TELEMETRY") { "Exit" } else { "Back" }
            $ctrlVisual = "  [$arrowNav] Navigate    [Enter] Select    [Esc/Q] $actionLabel"
            if ($ctrlVisual.Length -gt $innerWidth) {
                $ctrlVisual = "  [$arrowNav] Nav  [Enter] Select  [Esc] $actionLabel"
            }
            $ctrlPad = [math]::Max(0, $innerWidth - $ctrlVisual.Length)
            Write-Host "$global:G_RAIL  " -NoNewline -ForegroundColor DarkGray
            Write-Host "[$arrowNav] " -NoNewline -ForegroundColor White
            Write-Host "Navigate    " -NoNewline -ForegroundColor DarkGray
            Write-Host "[Enter] " -NoNewline -ForegroundColor White
            Write-Host "Select    " -NoNewline -ForegroundColor DarkGray
            Write-Host "[Esc/Q] " -NoNewline -ForegroundColor White
            Write-Host $actionLabel -NoNewline -ForegroundColor DarkGray
            Write-Host (" " * $ctrlPad) -NoNewline
            Write-Host "$global:G_RAIL`e[K" -ForegroundColor DarkGray

            # 10. Footer with Ready Badge
            $footerBadge = " [ Ready ] "
            $botDashes = [math]::Max(1, $boxWidth - 4 - $footerBadge.Length)
            $botLine = "$global:G_BL$global:G_BAR$global:G_BAR$footerBadge" + ($global:G_BAR * $botDashes) + "$global:G_BR"
            if ($botLine.Length -gt $boxWidth) { $botLine = $botLine.Substring(0, $boxWidth - 1) + $global:G_BR }
            Write-Host "$botLine`e[K" -ForegroundColor Cyan

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
                'Home' {
                    $subIndex = 0
                }
                'End' {
                    $subIndex = $Options.Count - 1
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
