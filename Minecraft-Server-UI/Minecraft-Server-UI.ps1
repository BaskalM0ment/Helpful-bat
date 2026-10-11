# Minecraft Server UI
# Windows PowerShell 5.1, built-in Windows Forms only.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:ServerProcess = $null
$script:OutTask = $null
$script:ErrTask = $null
$script:ServerStartedAt = $null
$script:ServerReady = $false
$script:WaitingForChoice = $false
$script:RestartRequested = $false
$script:StopRequested = $false
$script:LastMetricsUpdate = [DateTime]::MinValue
$script:Players = @{}
$script:ServerDir = Join-Path $env:USERPROFILE 'Downloads\Minecraft server'
$script:PublicAddress = 'rails-wc.tun.ply.gg'

function Find-ManagerBat {
    param([string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $null
    }

    $names = @('start-server.bat', 'server-manager.bat', 'start.bat', 'run.bat', 'minecraft-server.bat')
    foreach ($name in $names) {
        $candidate = Join-Path $Directory $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

if (Find-ManagerBat -Directory $PSScriptRoot) {
    $script:ServerDir = $PSScriptRoot
}

function Set-Status {
    param([string]$Text, [System.Drawing.Color]$Color)
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = $Text
        $script:StatusLabel.BackColor = $Color
    }
}

function Add-LogLine {
    param([string]$Message)

    if (-not $script:LogBox -or [string]::IsNullOrEmpty($Message)) {
        return
    }

    $color = [System.Drawing.Color]::FromArgb(210, 220, 235)
    if ($Message -match '(?i)error|exception|failed|fatal') {
        $color = [System.Drawing.Color]::FromArgb(255, 110, 110)
    } elseif ($Message -match '(?i)joined the game|Done \(') {
        $color = [System.Drawing.Color]::FromArgb(100, 235, 170)
    } elseif ($Message -match '^\[UI\]') {
        $color = [System.Drawing.Color]::FromArgb(100, 190, 255)
    }

    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.SelectionLength = 0
    $script:LogBox.SelectionColor = $color
    $stamp = Get-Date -Format 'HH:mm:ss'
    $script:LogBox.AppendText(('[' + $stamp + '] ' + $Message + [Environment]::NewLine))
    $script:LogBox.SelectionColor = $script:LogBox.ForeColor
    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.ScrollToCaret()
}

function Refresh-PlayerList {
    if (-not $script:PlayerList) {
        return
    }

    $script:PlayerList.BeginUpdate()
    $script:PlayerList.Items.Clear()
    foreach ($player in ($script:Players.Values | Sort-Object)) {
        [void]$script:PlayerList.Items.Add($player)
    }
    $script:PlayerList.EndUpdate()
    $script:PlayerCountLabel.Text = 'Players online: ' + $script:Players.Count
}

function Reset-PlayerTracking {
    $script:Players = @{}
    Refresh-PlayerList
}

function Send-ManagerInput {
    param([string]$Text)

    if (-not $script:ServerProcess) {
        return
    }

    try {
        if (-not $script:ServerProcess.HasExited) {
            $script:ServerProcess.StandardInput.WriteLine($Text)
            $script:ServerProcess.StandardInput.Flush()
            Add-LogLine ('[UI] Sent input: ' + $Text)
        }
    } catch {
        Add-LogLine ('[UI] Could not send input: ' + $_.Exception.Message)
    }
}

function Process-LogLine {
    param([string]$Line)

    if ($Line -match ':\s*([A-Za-z0-9_]{1,16}) joined the game') {
        $name = $Matches[1]
        $script:Players[$name.ToLowerInvariant()] = $name
        Refresh-PlayerList
    } elseif ($Line -match ':\s*([A-Za-z0-9_]{1,16}) left the game') {
        [void]$script:Players.Remove($Matches[1].ToLowerInvariant())
        Refresh-PlayerList
    }

    if ($Line -match 'Done \(') {
        $script:ServerReady = $true
        if (-not $script:WaitingForChoice) {
            Set-Status 'ONLINE' ([System.Drawing.Color]::FromArgb(30, 115, 75))
        }
    }

    if ($Line -match '(?i)Type\s+R\s+to\s+restart.*X\s+to\s+exit') {
        $script:WaitingForChoice = $true
        Set-Status 'WAITING FOR INPUT' ([System.Drawing.Color]::FromArgb(135, 90, 25))

        if ($script:RestartRequested) {
            Send-ManagerInput 'R'
            $script:RestartRequested = $false
            $script:StopRequested = $false
            $script:WaitingForChoice = $false
            $script:ServerReady = $false
            $script:ServerStartedAt = Get-Date
            Reset-PlayerTracking
            Set-Status 'STARTING' ([System.Drawing.Color]::FromArgb(35, 85, 145))
        } elseif ($script:StopRequested) {
            Send-ManagerInput 'X'
            $script:StopRequested = $false
            $script:WaitingForChoice = $false
        }
    }
}

function Test-ServerJavaRunning {
    try {
        $javaProcesses = Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction Stop
        foreach ($javaProcess in $javaProcesses) {
            if ($javaProcess.CommandLine -match '(?i)fabric-server.*\.jar') {
                return $true
            }
        }
    } catch {
        Add-LogLine ('[UI] Could not inspect Java processes: ' + $_.Exception.Message)
    }
    return $false
}

function Start-ServerManager {
    if ($script:ServerProcess) {
        try {
            if (-not $script:ServerProcess.HasExited) {
                return
            }
        } catch {}
    }

    $directory = $script:PathBox.Text.Trim()
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'That server folder does not exist. Use Browse to select the correct folder.',
            'Server folder not found',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    $manager = Find-ManagerBat -Directory $directory
    if (-not $manager) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'I could not find start-server.bat, server-manager.bat, start.bat, run.bat, or minecraft-server.bat in that folder.',
            'Server manager not found',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    if (Test-ServerJavaRunning) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'A Java process using fabric-server.jar already appears to be running. Stop that server first, then start it from this UI so logs and player tracking work correctly.',
            'Server already running',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        Add-LogLine '[UI] Start blocked because a Fabric server process already appears to be running.'
        return
    }

    $script:ServerDir = $directory
    $script:ServerReady = $false
    $script:WaitingForChoice = $false
    $script:RestartRequested = $false
    $script:StopRequested = $false
    $script:ServerStartedAt = Get-Date
    $script:LastMetricsUpdate = [DateTime]::MinValue
    Reset-PlayerTracking

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /s /c ""' + $manager + '""'
    $startInfo.WorkingDirectory = $directory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw 'Windows could not start the server manager.'
        }

        $script:ServerProcess = $process
        $script:OutTask = $process.StandardOutput.ReadLineAsync()
        $script:ErrTask = $process.StandardError.ReadLineAsync()
        Set-Status 'STARTING' ([System.Drawing.Color]::FromArgb(35, 85, 145))
        Add-LogLine ('[UI] Launching ' + $manager)
        Add-LogLine '[UI] Live logs and player tracking are active.'
    } catch {
        $script:ServerProcess = $null
        Set-Status 'OFFLINE' ([System.Drawing.Color]::FromArgb(75, 45, 50))
        Add-LogLine ('[UI] Could not start server manager: ' + $_.Exception.Message)
        [void][System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Could not start server',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

function Stop-ServerManager {
    if (-not $script:ServerProcess) {
        return
    }

    try {
        if ($script:ServerProcess.HasExited) {
            return
        }
    } catch {
        return
    }

    if ($script:WaitingForChoice) {
        $script:RestartRequested = $false
        $script:StopRequested = $false
        Send-ManagerInput 'X'
        $script:WaitingForChoice = $false
        return
    }

    $script:StopRequested = $true
    $script:RestartRequested = $false
    Add-LogLine '[UI] Asking Minecraft to stop safely...'
    Send-ManagerInput 'stop'
}

function Restart-ServerManager {
    if (-not $script:ServerProcess) {
        Start-ServerManager
        return
    }

    try {
        if ($script:ServerProcess.HasExited) {
            Start-ServerManager
            return
        }
    } catch {
        Start-ServerManager
        return
    }

    if ($script:WaitingForChoice) {
        Send-ManagerInput 'R'
        $script:WaitingForChoice = $false
        $script:RestartRequested = $false
        $script:StopRequested = $false
        $script:ServerReady = $false
        $script:ServerStartedAt = Get-Date
        Reset-PlayerTracking
        Set-Status 'STARTING' ([System.Drawing.Color]::FromArgb(35, 85, 145))
        return
    }

    $script:RestartRequested = $true
    $script:StopRequested = $false
    Add-LogLine '[UI] Restart requested. Waiting for the server to shut down cleanly...'
    Send-ManagerInput 'stop'
}

function Poll-ServerOutput {
    if (-not $script:ServerProcess) {
        return
    }

    while ($script:OutTask -and $script:OutTask.IsCompleted) {
        try {
            $line = $script:OutTask.GetAwaiter().GetResult()
        } catch {
            $line = $null
        }

        if ($null -eq $line) {
            $script:OutTask = $null
            break
        }

        Add-LogLine $line
        Process-LogLine $line
        try {
            $script:OutTask = $script:ServerProcess.StandardOutput.ReadLineAsync()
        } catch {
            $script:OutTask = $null
        }
    }

    while ($script:ErrTask -and $script:ErrTask.IsCompleted) {
        try {
            $line = $script:ErrTask.GetAwaiter().GetResult()
        } catch {
            $line = $null
        }

        if ($null -eq $line) {
            $script:ErrTask = $null
            break
        }

        Add-LogLine ('[stderr] ' + $line)
        try {
            $script:ErrTask = $script:ServerProcess.StandardError.ReadLineAsync()
        } catch {
            $script:ErrTask = $null
        }
    }

    try {
        if ($script:ServerProcess.HasExited -and -not $script:OutTask -and -not $script:ErrTask) {
            $exitCode = $script:ServerProcess.ExitCode
            Add-LogLine ('[UI] Server manager exited with code ' + $exitCode)
            $script:ServerProcess.Dispose()
            $script:ServerProcess = $null
            $script:ServerStartedAt = $null
            $script:ServerReady = $false
            $script:WaitingForChoice = $false
            $script:RestartRequested = $false
            $script:StopRequested = $false
            Set-Status 'OFFLINE' ([System.Drawing.Color]::FromArgb(75, 45, 50))
        }
    } catch {}
}

function Update-Metrics {
    $active = $false
    if ($script:ServerProcess) {
        try {
            $active = -not $script:ServerProcess.HasExited
        } catch {}
    }

    if ($active) {
        if ($script:WaitingForChoice) {
            Set-Status 'WAITING FOR INPUT' ([System.Drawing.Color]::FromArgb(135, 90, 25))
        } elseif ($script:ServerReady) {
            Set-Status 'ONLINE' ([System.Drawing.Color]::FromArgb(30, 115, 75))
        } else {
            Set-Status 'STARTING' ([System.Drawing.Color]::FromArgb(35, 85, 145))
        }

        if ($script:ServerStartedAt) {
            $elapsed = (Get-Date) - $script:ServerStartedAt
            $script:UptimeLabel.Text = 'Session: ' + $elapsed.ToString('d\.hh\:mm\:ss')
        }
    } else {
        if (-not $script:ServerProcess) {
            Set-Status 'OFFLINE' ([System.Drawing.Color]::FromArgb(75, 45, 50))
        }
        $script:UptimeLabel.Text = 'Session: --'
    }

    try {
        $javaProcesses = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction Stop | Where-Object { $_.CommandLine -match '(?i)fabric-server.*\.jar' })
        $totalBytes = [long]0
        foreach ($javaProcess in $javaProcesses) {
            $p = Get-Process -Id $javaProcess.ProcessId -ErrorAction SilentlyContinue
            if ($p) {
                $totalBytes += $p.WorkingSet64
            }
        }

        if ($totalBytes -gt 0) {
            $script:RamLabel.Text = 'Java RAM: ' + [Math]::Round($totalBytes / 1MB) + ' MB'
        } else {
            $script:RamLabel.Text = 'Java RAM: --'
        }
    } catch {
        $script:RamLabel.Text = 'Java RAM: unavailable'
    }
}

function New-PanelButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [System.Drawing.Color]$Color
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = [System.Drawing.Point]::new($X, $Y)
    $button.Size = [System.Drawing.Size]::new($Width, 38)
    $button.BackColor = $Color
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

function New-TextLabel {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [float]$FontSize = 10,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Gainsboro
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = [System.Drawing.Point]::new($X, $Y)
    $label.Size = [System.Drawing.Size]::new($Width, $Height)
    $label.ForeColor = $Color
    $label.Font = [System.Drawing.Font]::new('Segoe UI', $FontSize, [System.Drawing.FontStyle]::Regular)
    return $label
}

$form = New-Object System.Windows.Forms.Form
$script:Form = $form
$form.Text = 'Minecraft Server Control Panel'
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MinimumSize = [System.Drawing.Size]::new(1000, 680)
$form.ClientSize = [System.Drawing.Size]::new(1160, 760)
$form.BackColor = [System.Drawing.Color]::FromArgb(13, 17, 27)
$form.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Font = [System.Drawing.Font]::new('Segoe UI', 9)

$header = New-Object System.Windows.Forms.Panel
$header.Location = [System.Drawing.Point]::new(0, 0)
$header.Size = [System.Drawing.Size]::new(1160, 80)
$header.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$header.BackColor = [System.Drawing.Color]::FromArgb(22, 29, 47)
$form.Controls.Add($header)

$title = New-TextLabel 'MINECRAFT SERVER' 20 10 500 32 18 ([System.Drawing.Color]::FromArgb(235, 242, 255))
$title.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 18, [System.Drawing.FontStyle]::Bold)
$header.Controls.Add($title)

$subtitle = New-TextLabel 'CONTROL PANEL  /  FABRIC + PLAYIT' 23 45 500 20 9 ([System.Drawing.Color]::FromArgb(135, 157, 190))
$header.Controls.Add($subtitle)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = 'OFFLINE'
$script:StatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$script:StatusLabel.Location = [System.Drawing.Point]::new(950, 21)
$script:StatusLabel.Size = [System.Drawing.Size]::new(185, 36)
$script:StatusLabel.BackColor = [System.Drawing.Color]::FromArgb(75, 45, 50)
$script:StatusLabel.ForeColor = [System.Drawing.Color]::White
$script:StatusLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$header.Controls.Add($script:StatusLabel)

$script:StartButton = New-PanelButton 'START SERVER' 16 92 145 ([System.Drawing.Color]::FromArgb(30, 125, 82))
$script:StopButton = New-PanelButton 'STOP SERVER' 170 92 135 ([System.Drawing.Color]::FromArgb(150, 55, 62))
$script:RestartButton = New-PanelButton 'RESTART' 314 92 115 ([System.Drawing.Color]::FromArgb(48, 90, 155))
$script:ClearButton = New-PanelButton 'CLEAR LOGS' 438 92 115 ([System.Drawing.Color]::FromArgb(48, 57, 77))
$script:OpenFolderButton = New-PanelButton 'OPEN FOLDER' 562 92 125 ([System.Drawing.Color]::FromArgb(48, 57, 77))
$form.Controls.Add($script:StartButton)
$form.Controls.Add($script:StopButton)
$form.Controls.Add($script:RestartButton)
$form.Controls.Add($script:ClearButton)
$form.Controls.Add($script:OpenFolderButton)

$sidePanel = New-Object System.Windows.Forms.Panel
$sidePanel.Location = [System.Drawing.Point]::new(16, 142)
$sidePanel.Size = [System.Drawing.Size]::new(330, 600)
$sidePanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$sidePanel.BackColor = [System.Drawing.Color]::FromArgb(22, 27, 41)
$form.Controls.Add($sidePanel)

$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Location = [System.Drawing.Point]::new(362, 142)
$logPanel.Size = [System.Drawing.Size]::new(782, 600)
$logPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$logPanel.BackColor = [System.Drawing.Color]::FromArgb(22, 27, 41)
$form.Controls.Add($logPanel)

$sidePanel.Controls.Add((New-TextLabel 'SERVER FOLDER' 12 12 290 20 9 ([System.Drawing.Color]::FromArgb(135, 157, 190))))
$script:PathBox = New-Object System.Windows.Forms.TextBox
$script:PathBox.Location = [System.Drawing.Point]::new(12, 36)
$script:PathBox.Size = [System.Drawing.Size]::new(306, 28)
$script:PathBox.Text = $script:ServerDir
$script:PathBox.BackColor = [System.Drawing.Color]::FromArgb(12, 16, 25)
$script:PathBox.ForeColor = [System.Drawing.Color]::FromArgb(220, 230, 245)
$script:PathBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$sidePanel.Controls.Add($script:PathBox)

$browseButton = New-PanelButton 'BROWSE...' 12 69 100 ([System.Drawing.Color]::FromArgb(48, 57, 77))
$browseButton.Size = [System.Drawing.Size]::new(100, 32)
$sidePanel.Controls.Add($browseButton)

$sidePanel.Controls.Add((New-TextLabel 'PLAYIT ADDRESS' 12 112 290 20 9 ([System.Drawing.Color]::FromArgb(135, 157, 190))))
$script:AddressBox = New-Object System.Windows.Forms.TextBox
$script:AddressBox.Location = [System.Drawing.Point]::new(12, 136)
$script:AddressBox.Size = [System.Drawing.Size]::new(306, 28)
$script:AddressBox.Text = $script:PublicAddress
$script:AddressBox.BackColor = [System.Drawing.Color]::FromArgb(12, 16, 25)
$script:AddressBox.ForeColor = [System.Drawing.Color]::FromArgb(100, 235, 170)
$script:AddressBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$sidePanel.Controls.Add($script:AddressBox)

$copyButton = New-PanelButton 'COPY ADDRESS' 12 169 120 ([System.Drawing.Color]::FromArgb(48, 57, 77))
$copyButton.Size = [System.Drawing.Size]::new(120, 32)
$sidePanel.Controls.Add($copyButton)

$sidePanel.Controls.Add((New-TextLabel 'SERVER STATS' 12 216 290 20 9 ([System.Drawing.Color]::FromArgb(135, 157, 190))))
$script:UptimeLabel = New-TextLabel 'Session: --' 12 242 300 22 10 ([System.Drawing.Color]::FromArgb(220, 230, 245))
$script:RamLabel = New-TextLabel 'Java RAM: --' 12 268 300 22 10 ([System.Drawing.Color]::FromArgb(220, 230, 245))
$script:PlayerCountLabel = New-TextLabel 'Players online: 0' 12 294 300 22 10 ([System.Drawing.Color]::FromArgb(100, 235, 170))
$sidePanel.Controls.Add($script:UptimeLabel)
$sidePanel.Controls.Add($script:RamLabel)
$sidePanel.Controls.Add($script:PlayerCountLabel)

$sidePanel.Controls.Add((New-TextLabel 'CONNECTED PLAYERS' 12 331 290 20 9 ([System.Drawing.Color]::FromArgb(135, 157, 190))))
$script:PlayerList = New-Object System.Windows.Forms.ListBox
$script:PlayerList.Location = [System.Drawing.Point]::new(12, 355)
$script:PlayerList.Size = [System.Drawing.Size]::new(306, 225)
$script:PlayerList.BackColor = [System.Drawing.Color]::FromArgb(12, 16, 25)
$script:PlayerList.ForeColor = [System.Drawing.Color]::FromArgb(100, 235, 170)
$script:PlayerList.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:PlayerList.Font = [System.Drawing.Font]::new('Consolas', 10)
$sidePanel.Controls.Add($script:PlayerList)

$logTitle = New-TextLabel 'LIVE CONSOLE LOG' 12 12 400 22 10 ([System.Drawing.Color]::FromArgb(220, 230, 245))
$logTitle.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)
$logPanel.Controls.Add($logTitle)

$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Location = [System.Drawing.Point]::new(12, 40)
$script:LogBox.Size = [System.Drawing.Size]::new(758, 530)
$script:LogBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$script:LogBox.ReadOnly = $true
$script:LogBox.DetectUrls = $false
$script:LogBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(8, 11, 18)
$script:LogBox.ForeColor = [System.Drawing.Color]::FromArgb(210, 220, 235)
$script:LogBox.Font = [System.Drawing.Font]::new('Consolas', 9)
$logPanel.Controls.Add($script:LogBox)

$hint = New-TextLabel 'Start the server from this panel to capture live logs and player joins.' 12 577 755 18 8 ([System.Drawing.Color]::FromArgb(115, 132, 158))
$logPanel.Controls.Add($hint)

$script:StartButton.Add_Click({ Start-ServerManager })
$script:StopButton.Add_Click({ Stop-ServerManager })
$script:RestartButton.Add_Click({ Restart-ServerManager })
$script:ClearButton.Add_Click({ $script:LogBox.Clear() })
$script:OpenFolderButton.Add_Click({
    $directory = $script:PathBox.Text.Trim()
    if (Test-Path -LiteralPath $directory -PathType Container) {
        try {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $directory + '"')
        } catch {
            Add-LogLine ('[UI] Could not open folder: ' + $_.Exception.Message)
        }
    } else {
        [void][System.Windows.Forms.MessageBox]::Show('Select a valid server folder first.', 'Folder not found')
    }
})
$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select your Minecraft server folder'
    $dialog.ShowNewFolderButton = $false
    if (Test-Path -LiteralPath $script:PathBox.Text -PathType Container) {
        $dialog.SelectedPath = $script:PathBox.Text
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:PathBox.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})
$copyButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($script:AddressBox.Text)) {
        try {
            [System.Windows.Forms.Clipboard]::SetText($script:AddressBox.Text.Trim())
            Add-LogLine '[UI] Playit address copied to clipboard.'
        } catch {
            Add-LogLine ('[UI] Could not copy address: ' + $_.Exception.Message)
        }
    }
})

$script:Timer = New-Object System.Windows.Forms.Timer
$script:Timer.Interval = 150
$script:Timer.Add_Tick({
    Poll-ServerOutput

    if (((Get-Date) - $script:LastMetricsUpdate).TotalSeconds -ge 1) {
        $script:LastMetricsUpdate = Get-Date
        Update-Metrics
    }
})

$form.Add_FormClosing({
    param($sender, $eventArgs)

    if ($script:ServerProcess) {
        try {
            if (-not $script:ServerProcess.HasExited) {
                [void][System.Windows.Forms.MessageBox]::Show(
                    'Stop the server with the Stop Server button before closing this panel. This keeps the live console pipe from being left unattended.',
                    'Server is still running',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                $eventArgs.Cancel = $true
                return
            }
        } catch {}
    }

    $script:Timer.Stop()
})

Add-LogLine '[UI] Control panel ready.'
Add-LogLine ('[UI] Default server folder: ' + $script:ServerDir)
Add-LogLine '[UI] Use Browse if your server is stored somewhere else.'
$script:Timer.Start()
[void]$form.ShowDialog()
$script:Timer.Stop()