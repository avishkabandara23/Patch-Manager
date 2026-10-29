# =====================================================================
# 1. Self-Elevate to Run as Administrator Automatically
# =====================================================================
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }
    if ($scriptPath) {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" -Verb RunAs
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please save this script to a .ps1 file first before running so it can elevate to Administrator.", "Save Required", "OK", "Warning")
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Main Window ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Multi-Server Pre-Patching Manager"
$form.Size = New-Object System.Drawing.Size(1460, 800)
$form.MinimumSize = New-Object System.Drawing.Size(1160, 640)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 246, 248)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Global State
$script:DataTable     = $null
$script:CurrentFolder = ""
$script:AdminCred     = $null
$script:ThrottleLimit = 16
$script:ServerDetails = [ordered]@{}
$global:ServerDetails = $script:ServerDetails
$script:PrePatchServerDetails = [ordered]@{}
$global:PrePatchServerDetails = $script:PrePatchServerDetails

# --- Layout: 2-Column SplitContainer (Draggable Left / Right) ---
$mainLayout = New-Object System.Windows.Forms.SplitContainer
$mainLayout.Dock = "Fill"
$mainLayout.Orientation = [System.Windows.Forms.Orientation]::Vertical
$form.Controls.Add($mainLayout)
$mainLayout.Size = $form.ClientSize
$mainLayout.Panel1MinSize = 160
$mainLayout.Panel2MinSize = 450
$mainLayout.SplitterDistance = 320
$mainLayout.SplitterWidth = 6
$mainLayout.BackColor = [System.Drawing.Color]::FromArgb(215, 220, 228)
$mainLayout.Panel1.BackColor = [System.Drawing.SystemColors]::Control
$mainLayout.Panel2.BackColor = [System.Drawing.SystemColors]::Control
$mainLayout.Panel1.Padding = New-Object System.Windows.Forms.Padding(10, 10, 4, 10)
$mainLayout.Panel2.Padding = New-Object System.Windows.Forms.Padding(4, 10, 10, 10)

# ==========================================
# LEFT PANEL: Servers & Custom Scripts
# ==========================================
$leftLayout = New-Object System.Windows.Forms.TableLayoutPanel
$leftLayout.Dock = "Fill"
$leftLayout.ColumnCount = 1
$leftLayout.RowCount = 6
[void]$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 55)))
[void]$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 45)))
$mainLayout.Panel1.Controls.Add($leftLayout)

$lblServers = New-Object System.Windows.Forms.Label
$lblServers.Text = "Target Servers (One per line):"
$lblServers.AutoSize = $true
$lblServers.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
$lblServers.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$leftLayout.Controls.Add($lblServers, 0, 0)

$txtServers = New-Object System.Windows.Forms.TextBox
$txtServers.Multiline = $true
$txtServers.ScrollBars = "Vertical"
$txtServers.Dock = "Fill"
$txtServers.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$leftLayout.Controls.Add($txtServers, 0, 1)

$btnLoadTxt = New-Object System.Windows.Forms.Button
$btnLoadTxt.Text = "Load Server List (.txt)"
$btnLoadTxt.Dock = "Fill"
$btnLoadTxt.Height = 32
$btnLoadTxt.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 14)
$leftLayout.Controls.Add($btnLoadTxt, 0, 2)

$lblScripts = New-Object System.Windows.Forms.Label
$lblScripts.Text = "Custom Scripts Folder (Optional):"
$lblScripts.AutoSize = $true
$lblScripts.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
$lblScripts.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$leftLayout.Controls.Add($lblScripts, 0, 3)

$btnBrowseFolder = New-Object System.Windows.Forms.Button
$btnBrowseFolder.Text = "Browse Script Folder..."
$btnBrowseFolder.Dock = "Fill"
$btnBrowseFolder.Height = 32
$btnBrowseFolder.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
$leftLayout.Controls.Add($btnBrowseFolder, 0, 4)

$chkListScripts = New-Object System.Windows.Forms.CheckedListBox
$chkListScripts.Dock = "Fill"
$chkListScripts.CheckOnClick = $true
$leftLayout.Controls.Add($chkListScripts, 0, 5)

# ==========================================
# RIGHT PANEL: Top Bar, Grid & Output Log
# ==========================================
$rightLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rightLayout.Dock = "Fill"
$rightLayout.ColumnCount = 1
$rightLayout.RowCount = 4
$rightLayout.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
[void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 68)))
[void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 32)))
$mainLayout.Panel2.Controls.Add($rightLayout)

# --- Top Control Bar ---
$topBar = New-Object System.Windows.Forms.FlowLayoutPanel
$topBar.Dock = "Fill"
$topBar.AutoSize = $true
$topBar.WrapContents = $true
$topBar.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
$rightLayout.Controls.Add($topBar, 0, 0)

$chkAltCred = New-Object System.Windows.Forms.CheckBox
$chkAltCred.Text = "Prompt for Admin Credentials"
$chkAltCred.AutoSize = $true
$chkAltCred.Margin = New-Object System.Windows.Forms.Padding(0, 8, 14, 4)
$topBar.Controls.Add($chkAltCred)

$btnRunHealth = New-Object System.Windows.Forms.Button
$btnRunHealth.Text = "1. Run Built-in Pre-Patch Check"
$btnRunHealth.AutoSize = $true
$btnRunHealth.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$btnRunHealth.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnRunHealth.ForeColor = [System.Drawing.Color]::White
$btnRunHealth.FlatStyle = "Flat"
$btnRunHealth.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 4)
$topBar.Controls.Add($btnRunHealth)

$btnRunCustom = New-Object System.Windows.Forms.Button
$btnRunCustom.Text = "2. Run Checked Scripts"
$btnRunCustom.AutoSize = $true
$btnRunCustom.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$btnRunCustom.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 4)
$topBar.Controls.Add($btnRunCustom)

$btnRunPostPatch = New-Object System.Windows.Forms.Button
$btnRunPostPatch.Text = "3. Run Post-Patch Check"
$btnRunPostPatch.AutoSize = $true
$btnRunPostPatch.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$btnRunPostPatch.BackColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
$btnRunPostPatch.ForeColor = [System.Drawing.Color]::White
$btnRunPostPatch.FlatStyle = "Flat"
$btnRunPostPatch.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 4)
$topBar.Controls.Add($btnRunPostPatch)

$btnCompareServices = New-Object System.Windows.Forms.Button
$btnCompareServices.Text = "4. Compare Services (Pre vs Post)"
$btnCompareServices.AutoSize = $true
$btnCompareServices.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$btnCompareServices.BackColor = [System.Drawing.Color]::FromArgb(40, 96, 144)
$btnCompareServices.ForeColor = [System.Drawing.Color]::White
$btnCompareServices.FlatStyle = "Flat"
$btnCompareServices.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 4)
$topBar.Controls.Add($btnCompareServices)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export Report CSV"
$btnExport.AutoSize = $true
$btnExport.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$btnExport.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 4)
$topBar.Controls.Add($btnExport)

$btnViewDetails = New-Object System.Windows.Forms.Button
$btnViewDetails.Text = "View System Details"
$btnViewDetails.AutoSize = $true
$btnViewDetails.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$btnViewDetails.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 4)
$topBar.Controls.Add($btnViewDetails)

# --- Main Results Grid ---
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = "Fill"
$grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
$grid.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$grid.AllowUserToOrderColumns = $true
$grid.AllowUserToResizeColumns = $true
$grid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
$grid.ColumnHeadersHeight = 34
$grid.RowTemplate.MinimumHeight = 28
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = "FullRowSelect"
$grid.MultiSelect = $true
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.BorderStyle = "FixedSingle"
$grid.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$rightLayout.Controls.Add($grid, 0, 1)

# Context Menu on Main Grid for single PC actions (Domain Admin Tools)
$ctxGrid = New-Object System.Windows.Forms.ContextMenuStrip
$mnuRdp = $ctxGrid.Items.Add("Connect via Remote Desktop (RDP)")
$mnuRdpAdmin = $ctxGrid.Items.Add("Connect via RDP (Console / Admin Session: /admin)")
[void]$ctxGrid.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$mnuRestart = $ctxGrid.Items.Add("Remote Restart This Server...")
$mnuPostCheck = $ctxGrid.Items.Add("Run Post-Patch Check on This Server")
$mnuCompareServices = $ctxGrid.Items.Add("Compare Pre & Post Patch Services (Diff & Stopped)")
[void]$ctxGrid.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$mnuView = $ctxGrid.Items.Add("View System Details (New Window)")
$mnuCrosscheckServices = $ctxGrid.Items.Add("Crosscheck Services (Open in New Window)")
$mnuCopy = $ctxGrid.Items.Add("Copy Server Name")
$grid.ContextMenuStrip = $ctxGrid

# --- Bottom Log Header & Output Area ---
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Execution & Status Log:"
$lblLog.AutoSize = $true
$lblLog.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 4)
$lblLog.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$rightLayout.Controls.Add($lblLog, 0, 2)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Dock = "Fill"
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$rightLayout.Controls.Add($txtLog, 0, 3)

# --- Helper: Thread-Safe GUI Logging ---
function Write-GuiLog ($msg) {
    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $logLine = "[$timestamp] $msg`r`n"
    if ($form.InvokeRequired) {
        $form.Invoke([System.Action]{
            $txtLog.AppendText($logLine)
            $txtLog.SelectionStart = $txtLog.TextLength
            $txtLog.ScrollToCaret()
        })
    } else {
        $txtLog.AppendText($logLine)
        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.ScrollToCaret()
    }
}

# --- Helper: Extract Non-Empty Server Names ---
function Get-ServerList {
    return ($txtServers.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

# --- Helper: Test if Target is the Local Machine ---
function Test-IsLocalHost ($TargetName) {
    if ([string]::IsNullOrWhiteSpace($TargetName)) { return $false }
    $t = $TargetName.Trim().ToLower()
    $localNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$localNames.Add('localhost')
    [void]$localNames.Add('127.0.0.1')
    [void]$localNames.Add('::1')
    if ($env:COMPUTERNAME) { [void]$localNames.Add($env:COMPUTERNAME) }
    try {
        $dnsHost = [System.Net.Dns]::GetHostName()
        if ($dnsHost) { [void]$localNames.Add($dnsHost) }
    } catch {}
    if ($env:USERDNSDOMAIN) {
        if ($env:COMPUTERNAME) { [void]$localNames.Add("$($env:COMPUTERNAME).$($env:USERDNSDOMAIN)") }
        try {
            $dnsHost = [System.Net.Dns]::GetHostName()
            if ($dnsHost) { [void]$localNames.Add("$dnsHost.$($env:USERDNSDOMAIN)") }
        } catch {}
    }
    try {
        $localIPs = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | ForEach-Object { $_.IPAddressToString }
        foreach ($ip in $localIPs) { [void]$localNames.Add($ip) }
    } catch {}

    if ($localNames.Contains($t)) { return $true }
    if ($t.Contains('.')) {
        $short = $t.Split('.')[0]
        if ($localNames.Contains($short)) { return $true }
    }
    return $false
}

# --- Helper: Launch Remote Desktop (RDP) Client ---
function Connect-ServerRdp ($Target, $AdminSession = $false) {
    if ([string]::IsNullOrWhiteSpace($Target)) { return }
    $argList = "/v:$Target"
    if ($AdminSession) {
        $argList += " /admin"
    }
    Write-GuiLog "Launching Remote Desktop (RDP) session to [$Target]$(if ($AdminSession) { ' [/admin console mode]' })..."
    try {
        Start-Process -FilePath "mstsc.exe" -ArgumentList $argList
        Write-GuiLog "RDP client (mstsc.exe) launched for [$Target]."
    } catch {
        Write-GuiLog "[$Target ERROR] Failed to launch mstsc.exe: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Failed to launch Remote Desktop:`r`n`r`n$($_.Exception.Message)", "RDP Launch Error", "OK", "Error")
    }
}

# --- Helper: Highlight Grid Rows and Ensure Action Button Columns (RDP & Restart) Exist ---
function Style-GridRows {
    # Ensure RDP button column exists on the grid for quick Domain Admin access
    if (-not $grid.Columns.Contains("colRdpBtn")) {
        $rdpCol = New-Object System.Windows.Forms.DataGridViewButtonColumn
        $rdpCol.HeaderText = "RDP"
        $rdpCol.Name = "colRdpBtn"
        $rdpCol.Text = "Connect"
        $rdpCol.UseColumnTextForButtonValue = $true
        $rdpCol.Width = 75
        $rdpCol.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $grid.Columns.Add($rdpCol)
    }

    # Ensure individual Restart button column exists on the grid
    if (-not $grid.Columns.Contains("colRestartBtn")) {
        $btnCol = New-Object System.Windows.Forms.DataGridViewButtonColumn
        $btnCol.HeaderText = "Action"
        $btnCol.Name = "colRestartBtn"
        $btnCol.Text = "Restart"
        $btnCol.UseColumnTextForButtonValue = $true
        $btnCol.Width = 80
        $btnCol.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $grid.Columns.Add($btnCol)
    }

    # Apply optimal default column widths and enable drag/resize across all columns
    $colWidths = [ordered]@{
        "colRdpBtn"        = 75
        "colRestartBtn"    = 80
        "ServerName"       = 140
        "NIC_Details"      = 135
        "Status"           = 145
        "OSVersion"        = 180
        "UptimeDays"       = 90
        "PendingReboot"    = 110
        "Last_KBNumber"    = 115
        "KB_Description"   = 240
        "LastPatchDate"    = 115
    }

    foreach ($colName in $colWidths.Keys) {
        if ($grid.Columns.Contains($colName)) {
            $col = $grid.Columns[$colName]
            $col.MinimumWidth = 45
            if (-not $col.Tag) {
                $col.Width = $colWidths[$colName]
                $col.Tag = "Configured"
            }
            $col.Resizable = [System.Windows.Forms.DataGridViewTriState]::True
        }
    }

    foreach ($row in $grid.Rows) {
        $statusVal = [string]$row.Cells["Status"].Value
        if ($statusVal -eq "READY" -or $statusVal -like "*HEALTHY*") {
            $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(235, 255, 235)
        } elseif ($statusVal -like "*WARNING*" -or $statusVal -like "*REBOOT*" -or $statusVal -like "*STOPPED*") {
            $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 250, 205)
        } elseif ($statusVal -like "*OFFLINE*" -or $statusVal -like "*ERROR*") {
            $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 225, 225)
        }
    }
}

# =====================================================================
# HELPER: Compare Pre-Patch and Post-Patch Services
# =====================================================================
function Compare-PrePostServices ($preServices, $postServices) {
    $preMap = @{}
    if ($preServices) {
        foreach ($s in $preServices) {
            $preMap[$s.Name] = $s
        }
    }

    $compared = @()
    $postMap = @{}

    if ($postServices) {
        foreach ($postSvc in $postServices) {
            $sName = $postSvc.Name
            $postMap[$sName] = $true
            $preSvc = if ($preMap.ContainsKey($sName)) { $preMap[$sName] } else { $null }
            $preStatus = if ($preSvc) { $preSvc.Status } else { "Not Present (Pre)" }
            $postStatus = $postSvc.Status

            $isSame = ($preStatus -eq $postStatus)
            $diffState = if ($isSame) {
                "Same State"
            } elseif ($preStatus -eq "Running" -and $postStatus -ne "Running") {
                "STOPPED AFTER RESTART"
            } elseif ($preStatus -ne "Running" -and $postStatus -eq "Running") {
                "Started After Restart"
            } else {
                "Status Changed ($preStatus -> $postStatus)"
            }

            $compared += [PSCustomObject]@{
                Name                  = $sName
                DisplayName           = $postSvc.DisplayName
                StartType             = $postSvc.StartType
                PrePatchStatus        = $preStatus
                PostPatchStatus       = $postStatus
                DiffState             = $diffState
                IsSameState           = $isSame
                IsStoppedAfterRestart = ($diffState -eq "STOPPED AFTER RESTART")
            }
        }
    }

    # Catch any service that was present in pre-patch but missing in post-patch
    if ($preServices) {
        foreach ($preSvc in $preServices) {
            if (-not $postMap.ContainsKey($preSvc.Name)) {
                $isStopped = ($preSvc.Status -eq "Running")
                $compared += [PSCustomObject]@{
                    Name                  = $preSvc.Name
                    DisplayName           = $preSvc.DisplayName
                    StartType             = $preSvc.StartType
                    PrePatchStatus        = $preSvc.Status
                    PostPatchStatus       = "Missing / Removed"
                    DiffState             = if ($isStopped) { "STOPPED AFTER RESTART" } else { "Service Missing After Restart" }
                    IsSameState           = $false
                    IsStoppedAfterRestart = $isStopped
                }
            }
        }
    }

    return $compared
}

# =====================================================================
# CORE ENGINE: Run Post-Patch Verification Check for a Single Server
# =====================================================================
function Run-SinglePostPatchCheck ($Target) {
    if ([string]::IsNullOrWhiteSpace($Target)) { return }

    Write-GuiLog "=========================================================="
    Write-GuiLog "RUNNING POST-PATCH CHECK: [$Target]"
    Write-GuiLog "=========================================================="

    $isLocal = Test-IsLocalHost $Target
    $credParam = @{}
    if ($chkAltCred.Checked -and $null -ne $script:AdminCred) {
        $credParam["Credential"] = $script:AdminCred
    }

    try {
        $r = $null
        if ($isLocal) {
            Write-GuiLog "[$Target] Querying local computer for post-patch metrics..."
            $r = & $healthBlock
        } else {
            Write-GuiLog "[$Target] Connecting via WinRM to query post-patch health..."
            $attempts = 0
            while ($attempts -lt 4 -and $null -eq $r) {
                $attempts++
                try {
                    $r = Invoke-Command -ComputerName $Target -ScriptBlock $healthBlock @credParam -ErrorAction Stop
                } catch {
                    if ($attempts -lt 4) {
                        Write-GuiLog "[$Target] WinRM not ready yet ($($_.Exception.Message)). Retrying in 6s (attempt $attempts of 4)..."
                        Start-Sleep -Seconds 6
                    } else {
                        throw
                    }
                }
            }
        }

        if ($r) {
            $sName = if ($r.PSComputerName) { $r.PSComputerName } else { $Target }

            # Retrieve Pre-Patch services baseline for comparison
            $preDetails = if ($script:PrePatchServerDetails -and $script:PrePatchServerDetails.Contains($sName)) {
                $script:PrePatchServerDetails[$sName]
            } elseif ($global:PrePatchServerDetails -and $global:PrePatchServerDetails.Contains($sName)) {
                $global:PrePatchServerDetails[$sName]
            } elseif ($script:ServerDetails -and $script:ServerDetails.Contains($sName)) {
                $script:ServerDetails[$sName]
            } elseif ($global:ServerDetails -and $global:ServerDetails.Contains($sName)) {
                $global:ServerDetails[$sName]
            } else {
                $null
            }

            $preServices = if ($preDetails -and $preDetails.PrePatchServicesList) {
                $preDetails.PrePatchServicesList
            } elseif ($preDetails -and $preDetails.ServicesList) {
                $preDetails.ServicesList
            } else {
                $null
            }

            # Compare Pre vs Post Services
            $comparedServices = Compare-PrePostServices -preServices $preServices -postServices $r.ServicesList
            $stoppedAfterRestart = @($comparedServices | Where-Object { $_.IsStoppedAfterRestart })
            $changedServices = @($comparedServices | Where-Object { -not $_.IsSameState })
            $sameServices = @($comparedServices | Where-Object { $_.IsSameState })

            $stoppedAfterRestartCount = $stoppedAfterRestart.Count
            $stoppedAfterRestartList = ($stoppedAfterRestart | ForEach-Object { $_.Name }) -join ", "
            $changedCount = $changedServices.Count
            $sameCount = $sameServices.Count

            # Evaluate Post-Patch Status
            $postStatus = if ($r.PendingReboot) {
                "WARNING (Reboot Still Pending)"
            } elseif ($stoppedAfterRestartCount -gt 0) {
                "WARNING ($stoppedAfterRestartCount Services Stopped After Restart)"
            } elseif ($r.StoppedCount -gt 0) {
                "WARNING ($($r.StoppedCount) Auto Services Stopped)"
            } elseif ($r.UptimeDays -ge 1) {
                "WARNING (Uptime $($r.UptimeDays)d - Not Rebooted)"
            } elseif ($r.C_FreeSpaceGB -lt 10) {
                "WARNING (Low Disk)"
            } else {
                "POST-PATCH: HEALTHY"
            }

            if ($null -eq $script:DataTable) {
                $script:DataTable = New-Object System.Data.DataTable
                @("ServerName", "NIC_Details", "Status", "OSVersion", "UptimeDays", "PendingReboot", "Last_KBNumber", "KB_Description", "LastPatchDate") | ForEach-Object {
                    [void]$script:DataTable.Columns.Add($_)
                }
            }

            # Update row in $script:DataTable
            $existingRow = $null
            foreach ($row in $script:DataTable.Rows) {
                if ($row["ServerName"] -eq $sName) {
                    $existingRow = $row
                    break
                }
            }
            if ($existingRow) {
                $existingRow["NIC_Details"]    = $r.NIC_Compact
                $existingRow["Status"]         = $postStatus
                $existingRow["OSVersion"]      = $r.OSVersion
                $existingRow["UptimeDays"]     = $r.UptimeDays
                $existingRow["PendingReboot"]  = $r.PendingReboot
                $existingRow["Last_KBNumber"]  = $r.LastKB
                $existingRow["KB_Description"] = $r.LastKBDescription
                $existingRow["LastPatchDate"]  = $r.LastPatchDate
            } else {
                [void]$script:DataTable.Rows.Add($sName, $r.NIC_Compact, $postStatus, $r.OSVersion, $r.UptimeDays, $r.PendingReboot, $r.LastKB, $r.LastKBDescription, $r.LastPatchDate)
            }

            # Update $script:ServerDetails
            $script:ServerDetails[$sName] = @{
                IsOffline                  = $false
                ServerName                 = $sName
                Domain                     = $r.Domain
                Model                      = $r.Model
                Status                     = $postStatus
                OSVersion                  = $r.OSVersion
                OSBuild                    = $r.OSBuild
                CPULoad                    = $r.CPULoad
                RAMInfo                    = $r.RAMInfo
                UptimeDays                 = $r.UptimeDays
                LastBoot                   = $r.LastBoot
                C_FreeSpaceGB              = $r.C_FreeSpaceGB
                AllDisks                   = $r.AllDisks
                NIC_Compact                = $r.NIC_Compact
                NIC_Expanded               = $r.NIC_Expanded
                PendingReboot              = $r.PendingReboot
                RebootDetail               = $r.RebootDetail
                StoppedCount               = $r.StoppedCount
                StoppedList                = $r.StoppedList
                LastKB                     = $r.LastKB
                LastKBDescription          = $r.LastKBDescription
                LastPatchBy                = $r.LastPatchBy
                LastPatchDate              = $r.LastPatchDate
                DaysSincePatch             = $r.DaysSincePatch
                TotalPatchesCount          = $r.TotalPatchesCount
                WuauservStatus             = $r.WuauservStatus
                PatchServices              = $r.PatchServices
                WsusServer                 = $r.WsusServer
                AuOptionDesc               = $r.AuOptionDesc
                PatchList                  = $r.PatchList
                ServicesList               = $r.ServicesList
                PrePatchServicesList       = $preServices
                PostPatchServicesList      = $r.ServicesList
                ComparedServicesList       = $comparedServices
                StoppedAfterRestartCount   = $stoppedAfterRestartCount
                StoppedAfterRestartList    = $stoppedAfterRestartList
                ChangedServicesCount       = $changedCount
                SameServicesCount          = $sameCount
                HasPostPatch               = $true
                TotalServicesCount         = $r.TotalServicesCount
                RunningServicesCount       = $r.RunningServicesCount
                StoppedServicesCount       = $r.StoppedServicesCount
                ErrorMessage               = ""
            }
            $global:ServerDetails = $script:ServerDetails

            if ($null -eq $grid.DataSource) {
                $grid.DataSource = $script:DataTable
                $grid.BindingContext = New-Object System.Windows.Forms.BindingContext
            }
            Style-GridRows

            Write-GuiLog "[$sName POST-PATCH] Status: $postStatus | Uptime: $($r.UptimeDays) d | Reboot Pending: $($r.PendingReboot) | Latest KB: $($r.LastKB) ($($r.LastPatchDate))"
            if ($stoppedAfterRestartCount -gt 0) {
                Write-GuiLog "[$sName CRITICAL] $stoppedAfterRestartCount service(s) STOPPED after restart: $stoppedAfterRestartList"
            } elseif ($r.StoppedCount -gt 0) {
                Write-GuiLog "[$sName WARNING] Stopped Auto Services: $($r.StoppedList)"
            }

            $serviceDiffNote = if ($stoppedAfterRestartCount -gt 0) {
                "`r`n`r`n[!] SERVICES STOPPED AFTER RESTART: $stoppedAfterRestartCount service(s)!`r`n$stoppedAfterRestartList`r`n`r`n(Check the Services tab in System Details for full Red/Green diff table)"
            } elseif ($preServices) {
                "`r`n`r`n[OK] Pre vs Post Services Check: All $sameCount services remain in the same state!"
            } else {
                ""
            }

            $iconType = if ($postStatus -eq "POST-PATCH: HEALTHY") { "Information" } else { "Warning" }
            [System.Windows.Forms.MessageBox]::Show(
                "Post-Patch Check completed for '$sName'! `r`n`r`nStatus: $postStatus`r`nSystem Uptime: $($r.UptimeDays) days`r`nPending Reboot: $($r.PendingReboot)`r`nLatest Patch: $($r.LastKB) - $($r.LastKBDescription)`r`nInstalled Date: $($r.LastPatchDate)`r`nStopped Auto Services: $($r.StoppedCount)$serviceDiffNote",
                "Post-Patch Verification - $sName",
                "OK",
                $iconType
            )
        }
    } catch {
        Write-GuiLog "[$Target ERROR] Post-patch check failed: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Failed to query '$Target' for post-patch check:`r`n`r`n$($_.Exception.Message)", "Post-Patch Check Error", "OK", "Error")
    }
}

# =====================================================================
# CORE ENGINE: Restart a SINGLE Server Individually
# =====================================================================
function Restart-SingleServer ($Target) {
    if ([string]::IsNullOrWhiteSpace($Target)) { return }

    $isLocal = Test-IsLocalHost $Target
    $serverMap = if ($script:ServerDetails -and $script:ServerDetails.Count -gt 0) {
        $script:ServerDetails
    } elseif ($global:ServerDetails -and $global:ServerDetails.Count -gt 0) {
        $global:ServerDetails
    } else {
        $null
    }
    $d = if ($serverMap -and $serverMap.Contains($Target)) { $serverMap[$Target] } else { $null }
    $rebootInfo = if ($d -and $d.PendingReboot -eq $true) { " [Pending Reboot: YES - Required before patching]" } else { "" }

    $msg = "Are you sure you want to remotely restart this single server?`r`n`r`nTarget PC: $Target$rebootInfo"
    if ($isLocal) {
        $msg += "`r`n`r`nWARNING: This is your local machine ($env:COMPUTERNAME)! Restarting will reboot your current Windows session!"
    }
    $msg += "`r`n`r`nChoose an action:`r`n  [ Yes ]    Restart AND automatically run Post-Patch Check once online`r`n  [ No ]     Restart only (without Post-Patch Check)`r`n  [ Cancel ] Abort restart"

    $res = [System.Windows.Forms.MessageBox]::Show(
        $msg,
        "Confirm Remote Restart - $Target",
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($res -eq [System.Windows.Forms.DialogResult]::Cancel) { return }

    $autoPostCheck = ($res -eq [System.Windows.Forms.DialogResult]::Yes)

    $credParam = @{}
    if ($chkAltCred.Checked -and $null -ne $script:AdminCred) {
        $credParam["Credential"] = $script:AdminCred
    }

    Write-GuiLog "=========================================================="
    Write-GuiLog "RESTARTING SINGLE SERVER: [$Target]"
    Write-GuiLog "=========================================================="

    try {
        if ($isLocal) {
            Write-GuiLog "[$Target] Restarting local computer ($env:COMPUTERNAME)..."
            Restart-Computer -Force -ErrorAction Stop
        } else {
            try {
                Restart-Computer -ComputerName $Target @credParam -Force -ErrorAction Stop
                Write-GuiLog "[$Target] Restart command delivered via RPC."
            } catch {
                Write-GuiLog "[$Target] RPC restart notice ($($_.Exception.Message)). Attempting WinRM fallback..."
                Invoke-Command -ComputerName $Target -ScriptBlock { Restart-Computer -Force } @credParam -ErrorAction Stop
                Write-GuiLog "[$Target] Restart command delivered via WinRM."
            }

            Write-GuiLog "[$Target] Waiting for reboot to complete (ping verification)..."
            Start-Sleep -Seconds 8
            $sw = [System.Diagnostics.Stopwatch]::StartNew()

            # 1. Wait for host to go offline
            while ($sw.Elapsed.TotalSeconds -lt 40) {
                $isUp = Test-Connection -ComputerName $Target -Count 1 -Quiet -ErrorAction SilentlyContinue
                if (-not $isUp) {
                    Write-GuiLog "[$Target] Server is offline (rebooting)..."
                    break
                }
                Start-Sleep -Seconds 2
            }

            # 2. Wait for host to come back online
            $backOnline = $false
            while ($sw.Elapsed.TotalSeconds -lt 180) {
                $isUp = Test-Connection -ComputerName $Target -Count 1 -Quiet -ErrorAction SilentlyContinue
                if ($isUp) {
                    $backOnline = $true
                    Write-GuiLog "[$Target] SUCCESS: Server is back online! (Elapsed: $([math]::Round($sw.Elapsed.TotalSeconds, 0))s)"
                    break
                }
                Start-Sleep -Seconds 3
            }

            if (-not $backOnline) {
                Write-GuiLog "[$Target WARNING] Ping timeout reached (180s). Server may still be applying updates or rebooting."
                [System.Windows.Forms.MessageBox]::Show("Restart command delivered to '$Target', but the server has not responded to ping within 180s.`r`n`r`nIt may still be configuring updates.", "Restart In Progress", "OK", "Warning")
                return
            }

            if ($autoPostCheck) {
                Write-GuiLog "[$Target] Server is back online. Waiting 10s for Windows services to stabilize before running Post-Patch Check..."
                Start-Sleep -Seconds 10
                Run-SinglePostPatchCheck -Target $Target
            } else {
                Write-GuiLog "Single server restart for [$Target] completed."
                [System.Windows.Forms.MessageBox]::Show("Restart completed successfully for '$Target'.`r`n`r`nThe server is back online.", "Restart Complete", "OK", "Information")
            }
        }
    } catch {
        Write-GuiLog "[$Target ERROR] Failed to restart: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Failed to restart '$Target':`r`n`r`n$($_.Exception.Message)", "Restart Error", "OK", "Error")
    }
}

# =====================================================================
# POPUP WINDOW: Comprehensive System & Hardware Details Dialog
# =====================================================================
function Show-ServerDetailsDialog ($defaultServer, [string]$InitialTab = "System") {
    $srvDetails = if ($script:ServerDetails -and $script:ServerDetails.Count -gt 0) {
        $script:ServerDetails
    } elseif ($global:ServerDetails -and $global:ServerDetails.Count -gt 0) {
        $global:ServerDetails
    } else {
        $null
    }

    if ($null -eq $srvDetails -or $srvDetails.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No server details available yet. Please run the Pre-Patch Check first.", "No Data", "OK", "Information")
        return
    }

    $detailForm = New-Object System.Windows.Forms.Form
    $detailForm.Text = "System Details - $defaultServer"
    $detailForm.Size = New-Object System.Drawing.Size(1060, 720)
    $detailForm.MinimumSize = New-Object System.Drawing.Size(880, 580)
    
    # Calculate cascade location so multiple windows appear nicely staggered
    if ($null -eq $global:WindowCascadeCount) { $global:WindowCascadeCount = 0 }
    $offset = ($global:WindowCascadeCount * 32) % 192
    $global:WindowCascadeCount++

    $detailForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $targetX = [math]::Max(20, $form.Location.X + 40 + $offset)
    $targetY = [math]::Max(20, $form.Location.Y + 30 + $offset)
    $detailForm.Location = New-Object System.Drawing.Point($targetX, $targetY)
    $detailForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Top Bar: Server Dropdown & Status Badge
    $dlgTop = New-Object System.Windows.Forms.Panel
    $dlgTop.Dock = [System.Windows.Forms.DockStyle]::Top
    $dlgTop.Height = 52
    $dlgTop.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
    $dlgTop.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

    $lblSelect = New-Object System.Windows.Forms.Label
    $lblSelect.Text = "Target PC:"
    $lblSelect.Location = New-Object System.Drawing.Point(14, 14)
    $lblSelect.AutoSize = $true
    $lblSelect.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $dlgTop.Controls.Add($lblSelect)

    $cmbServers = New-Object System.Windows.Forms.ComboBox
    $cmbServers.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbServers.Location = New-Object System.Drawing.Point(95, 12)
    $cmbServers.Width = 230
    $cmbServers.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    foreach ($k in $srvDetails.Keys) {
        [void]$cmbServers.Items.Add($k)
    }
    if ($defaultServer -and $srvDetails.Contains($defaultServer)) {
        $cmbServers.SelectedItem = $defaultServer
    } elseif ($cmbServers.Items.Count -gt 0) {
        $cmbServers.SelectedIndex = 0
    }
    $dlgTop.Controls.Add($cmbServers)

    $btnNewWindow = New-Object System.Windows.Forms.Button
    $btnNewWindow.Text = "+ Open in New Window"
    $btnNewWindow.Location = New-Object System.Drawing.Point(335, 11)
    $btnNewWindow.Width = 160
    $btnNewWindow.Height = 28
    $btnNewWindow.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnNewWindow.ForeColor = [System.Drawing.Color]::White
    $btnNewWindow.FlatStyle = "Flat"
    $btnNewWindow.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $dlgTop.Controls.Add($btnNewWindow)

    $lblStatusBadge = New-Object System.Windows.Forms.Label
    $lblStatusBadge.Location = New-Object System.Drawing.Point(510, 12)
    $lblStatusBadge.Size = New-Object System.Drawing.Size(250, 26)
    $lblStatusBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblStatusBadge.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $dlgTop.Controls.Add($lblStatusBadge)

    $detailForm.Controls.Add($dlgTop)

    # Bottom Bar: Buttons (Copy, RDP, Restart PC, Close)
    $dlgBottom = New-Object System.Windows.Forms.Panel
    $dlgBottom.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $dlgBottom.Height = 48
    $dlgBottom.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)
    $dlgBottom.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text = "Copy PC Info to Clipboard"
    $btnCopy.Dock = [System.Windows.Forms.DockStyle]::Left
    $btnCopy.Width = 185
    $dlgBottom.Controls.Add($btnCopy)

    $btnRdpThisPc = New-Object System.Windows.Forms.Button
    $btnRdpThisPc.Text = "Connect RDP"
    $btnRdpThisPc.Dock = [System.Windows.Forms.DockStyle]::Left
    $btnRdpThisPc.Width = 125
    $btnRdpThisPc.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
    $btnRdpThisPc.ForeColor = [System.Drawing.Color]::White
    $btnRdpThisPc.FlatStyle = "Flat"
    $btnRdpThisPc.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnRdpThisPc.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $dlgBottom.Controls.Add($btnRdpThisPc)

    $btnRestartThisPc = New-Object System.Windows.Forms.Button
    $btnRestartThisPc.Text = "Restart This Single PC"
    $btnRestartThisPc.Dock = [System.Windows.Forms.DockStyle]::Left
    $btnRestartThisPc.Width = 175
    $btnRestartThisPc.BackColor = [System.Drawing.Color]::FromArgb(217, 83, 79)
    $btnRestartThisPc.ForeColor = [System.Drawing.Color]::White
    $btnRestartThisPc.FlatStyle = "Flat"
    $btnRestartThisPc.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $dlgBottom.Controls.Add($btnRestartThisPc)

    $btnPostCheckThisPc = New-Object System.Windows.Forms.Button
    $btnPostCheckThisPc.Text = "Run Post-Patch Check"
    $btnPostCheckThisPc.Dock = [System.Windows.Forms.DockStyle]::Left
    $btnPostCheckThisPc.Width = 175
    $btnPostCheckThisPc.BackColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
    $btnPostCheckThisPc.ForeColor = [System.Drawing.Color]::White
    $btnPostCheckThisPc.FlatStyle = "Flat"
    $btnPostCheckThisPc.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $dlgBottom.Controls.Add($btnPostCheckThisPc)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Dock = [System.Windows.Forms.DockStyle]::Right
    $btnClose.Width = 100
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlgBottom.Controls.Add($btnClose)

    $detailForm.Controls.Add($dlgBottom)

    # Center Tabs: General & Hardware, Network (NICs), Disks & Storage, Patch Details Grid, Windows Services
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
    $tabControl.Padding = New-Object System.Drawing.Point(14, 6)

    # Tab 1: System Summary & Detailed Patches List
    $tabSys = New-Object System.Windows.Forms.TabPage
    $tabSys.Text = "System Summary & Patches"
    $txtSys = New-Object System.Windows.Forms.TextBox
    $txtSys.Multiline = $true
    $txtSys.ReadOnly = $true
    $txtSys.Dock = [System.Windows.Forms.DockStyle]::Fill
    $txtSys.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtSys.Font = New-Object System.Drawing.Font("Consolas", 10)
    $txtSys.BackColor = [System.Drawing.Color]::White
    $tabSys.Controls.Add($txtSys)
    $tabControl.TabPages.Add($tabSys)

    # Tab 2: Interactive Patches Table (Search & CSV Export)
    $tabPatchGrid = New-Object System.Windows.Forms.TabPage
    $tabPatchGrid.Text = "Interactive Patches Grid"

    # Top Status Panel for Patching
    $pnlPatchTop = New-Object System.Windows.Forms.Panel
    $pnlPatchTop.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlPatchTop.Height = 90
    $pnlPatchTop.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 6)
    $pnlPatchTop.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

    $lblPatchSummary = New-Object System.Windows.Forms.Label
    $lblPatchSummary.Dock = [System.Windows.Forms.DockStyle]::Fill
    $lblPatchSummary.Font = New-Object System.Drawing.Font("Consolas", 9)
    $pnlPatchTop.Controls.Add($lblPatchSummary)
    $tabPatchGrid.Controls.Add($pnlPatchTop)

    # Filter & Export Bar for Patches
    $pnlPatchFilter = New-Object System.Windows.Forms.Panel
    $pnlPatchFilter.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlPatchFilter.Height = 38
    $pnlPatchFilter.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 4)
    $pnlPatchFilter.BackColor = [System.Drawing.Color]::FromArgb(240, 242, 245)

    $lblFilter = New-Object System.Windows.Forms.Label
    $lblFilter.Text = "Search Patches:"
    $lblFilter.AutoSize = $true
    $lblFilter.Location = New-Object System.Drawing.Point(10, 9)
    $lblFilter.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $pnlPatchFilter.Controls.Add($lblFilter)

    $txtPatchFilter = New-Object System.Windows.Forms.TextBox
    $txtPatchFilter.Location = New-Object System.Drawing.Point(115, 6)
    $txtPatchFilter.Width = 260
    $pnlPatchFilter.Controls.Add($txtPatchFilter)

    $btnExportPatches = New-Object System.Windows.Forms.Button
    $btnExportPatches.Text = "Export Patch List to CSV"
    $btnExportPatches.Location = New-Object System.Drawing.Point(390, 5)
    $btnExportPatches.Width = 170
    $btnExportPatches.Height = 26
    $pnlPatchFilter.Controls.Add($btnExportPatches)

    $lblPatchCount = New-Object System.Windows.Forms.Label
    $lblPatchCount.Location = New-Object System.Drawing.Point(580, 8)
    $lblPatchCount.AutoSize = $true
    $lblPatchCount.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $pnlPatchFilter.Controls.Add($lblPatchCount)

    $tabPatchGrid.Controls.Add($pnlPatchFilter)

    # Patches DataGridView
    $gridPatches = New-Object System.Windows.Forms.DataGridView
    $gridPatches.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridPatches.ReadOnly = $true
    $gridPatches.AllowUserToAddRows = $false
    $gridPatches.RowHeadersVisible = $false
    $gridPatches.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $gridPatches.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $gridPatches.BackgroundColor = [System.Drawing.Color]::White
    $gridPatches.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $tabPatchGrid.Controls.Add($gridPatches)
    $gridPatches.BringToFront()

    $tabControl.TabPages.Add($tabPatchGrid)

    # Tab 3: Windows Services (Full List & Search)
    $tabServices = New-Object System.Windows.Forms.TabPage
    $tabServices.Text = "Windows Services"

    $pnlSvcFilter = New-Object System.Windows.Forms.Panel
    $pnlSvcFilter.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlSvcFilter.Height = 42
    $pnlSvcFilter.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 6)
    $pnlSvcFilter.BackColor = [System.Drawing.Color]::FromArgb(240, 242, 245)

    $lblSvcSearch = New-Object System.Windows.Forms.Label
    $lblSvcSearch.Text = "Search Services:"
    $lblSvcSearch.AutoSize = $true
    $lblSvcSearch.Location = New-Object System.Drawing.Point(10, 11)
    $lblSvcSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $pnlSvcFilter.Controls.Add($lblSvcSearch)

    $txtSvcSearch = New-Object System.Windows.Forms.TextBox
    $txtSvcSearch.Location = New-Object System.Drawing.Point(125, 8)
    $txtSvcSearch.Width = 170
    $pnlSvcFilter.Controls.Add($txtSvcSearch)

    $lblSvcStatus = New-Object System.Windows.Forms.Label
    $lblSvcStatus.Text = "Filter:"
    $lblSvcStatus.AutoSize = $true
    $lblSvcStatus.Location = New-Object System.Drawing.Point(305, 11)
    $lblSvcStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $pnlSvcFilter.Controls.Add($lblSvcStatus)

    $cmbSvcStatus = New-Object System.Windows.Forms.ComboBox
    $cmbSvcStatus.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbSvcStatus.Location = New-Object System.Drawing.Point(350, 8)
    $cmbSvcStatus.Width = 205
    $cmbSvcStatus.Items.AddRange(@("All Services", "Stopped After Restart (Red)", "Changed Status (Red)", "Same State as Pre-Patch (Green)", "Post-Patch Running", "Post-Patch Stopped"))
    $cmbSvcStatus.SelectedIndex = 0
    $pnlSvcFilter.Controls.Add($cmbSvcStatus)

    $chkOnlyStoppedAuto = New-Object System.Windows.Forms.CheckBox
    $chkOnlyStoppedAuto.Text = "Issues Only (Red)"
    $chkOnlyStoppedAuto.AutoSize = $true
    $chkOnlyStoppedAuto.Location = New-Object System.Drawing.Point(565, 10)
    $chkOnlyStoppedAuto.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $chkOnlyStoppedAuto.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
    $pnlSvcFilter.Controls.Add($chkOnlyStoppedAuto)

    $btnExportThisPcSvcs = New-Object System.Windows.Forms.Button
    $btnExportThisPcSvcs.Text = "Export Comparison CSV"
    $btnExportThisPcSvcs.Location = New-Object System.Drawing.Point(695, 7)
    $btnExportThisPcSvcs.Width = 165
    $btnExportThisPcSvcs.Height = 26
    $pnlSvcFilter.Controls.Add($btnExportThisPcSvcs)

    $lblSvcCount = New-Object System.Windows.Forms.Label
    $lblSvcCount.Location = New-Object System.Drawing.Point(870, 11)
    $lblSvcCount.AutoSize = $true
    $lblSvcCount.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $pnlSvcFilter.Controls.Add($lblSvcCount)

    $tabServices.Controls.Add($pnlSvcFilter)

    $gridServices = New-Object System.Windows.Forms.DataGridView
    $gridServices.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridServices.ReadOnly = $true
    $gridServices.AllowUserToAddRows = $false
    $gridServices.RowHeadersVisible = $false
    $gridServices.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $gridServices.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $gridServices.BackgroundColor = [System.Drawing.Color]::White
    $gridServices.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $tabServices.Controls.Add($gridServices)
    $gridServices.BringToFront()

    $tabControl.TabPages.Add($tabServices)

    # Tab 4: Network Adapters (NICs)
    $tabNic = New-Object System.Windows.Forms.TabPage
    $tabNic.Text = "Network Adapters (NICs)"
    $txtNic = New-Object System.Windows.Forms.TextBox
    $txtNic.Multiline = $true
    $txtNic.ReadOnly = $true
    $txtNic.Dock = [System.Windows.Forms.DockStyle]::Fill
    $txtNic.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtNic.Font = New-Object System.Drawing.Font("Consolas", 10)
    $txtNic.BackColor = [System.Drawing.Color]::White
    $tabNic.Controls.Add($txtNic)
    $tabControl.TabPages.Add($tabNic)

    # Tab 5: Disks & Storage
    $tabDisk = New-Object System.Windows.Forms.TabPage
    $tabDisk.Text = "Disks & Storage"
    $txtDisk = New-Object System.Windows.Forms.TextBox
    $txtDisk.Multiline = $true
    $txtDisk.ReadOnly = $true
    $txtDisk.Dock = [System.Windows.Forms.DockStyle]::Fill
    $txtDisk.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtDisk.Font = New-Object System.Drawing.Font("Consolas", 10)
    $txtDisk.BackColor = [System.Drawing.Color]::White
    $tabDisk.Controls.Add($txtDisk)
    $tabControl.TabPages.Add($tabDisk)

    $detailForm.Controls.Add($tabControl)
    $tabControl.BringToFront()

    # Styling logic: Green for Same State, Red for Stopped / Changed
    $fnStyleServiceRows = {
        if ($null -eq $gridServices.DataSource) { return }
        $hasDiff = $gridServices.Columns.Contains("Comparison State")
        foreach ($sRow in $gridServices.Rows) {
            if ($hasDiff) {
                $diff = [string]$sRow.Cells["Comparison State"].Value
                if ($diff -eq "STOPPED AFTER RESTART") {
                    # RED for services stopped after restart
                    $sRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220)
                    $sRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
                    $sRow.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
                    $sRow.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(235, 170, 170)
                    $sRow.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::FromArgb(120, 0, 0)
                } elseif ($diff -ne "Same State") {
                    # RED for any service whose status changed
                    $sRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 238, 238)
                    $sRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(160, 20, 20)
                    $sRow.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(240, 190, 190)
                    $sRow.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::FromArgb(100, 0, 0)
                } else {
                    # GREEN for all services in same state as pre-patch
                    $sRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(235, 252, 235)
                    $sRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(20, 100, 30)
                    $sRow.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(200, 240, 200)
                    $sRow.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::FromArgb(10, 70, 20)
                }
            } else {
                $st = [string]$sRow.Cells["Status (Pre-Patch)"].Value
                $start = [string]$sRow.Cells["StartType"].Value
                if ($start -eq "Automatic" -and $st -ne "Running") {
                    $sRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 235, 235)
                    $sRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(160, 0, 0)
                } elseif ($st -eq "Running") {
                    $sRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(240, 255, 240)
                    $sRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(20, 100, 30)
                }
            }
        }
    }

    # Function to render details of selected server
    $fnUpdateDisplay = {
        $curServer = [string]$cmbServers.SelectedItem
        $sourceDetails = if ($srvDetails -and $srvDetails.Count -gt 0) {
            $srvDetails
        } elseif ($global:ServerDetails -and $global:ServerDetails.Count -gt 0) {
            $global:ServerDetails
        } elseif ($script:ServerDetails -and $script:ServerDetails.Count -gt 0) {
            $script:ServerDetails
        } else {
            $null
        }

        if ([string]::IsNullOrWhiteSpace($curServer) -or ($null -eq $sourceDetails) -or (-not $sourceDetails.Contains($curServer))) {
            return
        }
        $d = $sourceDetails[$curServer]
        if ($null -eq $d) {
            return
        }
        $detailForm.Text = "System Details - $curServer"

        # Update Top Badge
        $lblStatusBadge.Text = "Status: $($d.Status)"
        if ($d.Status -eq "READY" -or $d.Status -like "*HEALTHY*") {
            $lblStatusBadge.BackColor = [System.Drawing.Color]::FromArgb(212, 237, 218)
            $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(21, 87, 36)
        } elseif ($d.Status -like "*WARNING*") {
            $lblStatusBadge.BackColor = [System.Drawing.Color]::FromArgb(255, 243, 205)
            $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(133, 100, 4)
        } else {
            $lblStatusBadge.BackColor = [System.Drawing.Color]::FromArgb(248, 215, 218)
            $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(114, 28, 36)
        }

        # If offline/error
        if ($d.IsOffline) {
            $txtSys.Text = "COMPUTER NAME: $curServer`r`nSTATUS: OFFLINE / WINRM ERROR`r`n`r`nERROR DETAILS:`r`n$($d.ErrorMessage)`r`n`r`nTROUBLESHOOTING TIPS:`r`n1. Check if the PC is powered on and connected to the network.`r`n2. Ensure WinRM service (wsman) is running on the target PC: Get-Service WinRM`r`n3. Check Windows Firewall: allow port 5985 (HTTP) or 5986 (HTTPS).`r`n4. If targeting the local machine, ensure you run PowerShell as Administrator and leave 'Prompt for Admin Credentials' unchecked."
            $txtNic.Text = "Network data unavailable because connection failed."
            $txtDisk.Text = "Storage data unavailable because connection failed."
            $lblPatchSummary.Text = "Connection to $curServer failed. Unable to query patch information."
            $gridPatches.DataSource = $null
            $lblPatchCount.Text = "0 patches detected"
            $gridServices.DataSource = $null
            $lblSvcCount.Text = "Services unavailable because connection failed."
            return
        }

        # Tab 1: System & Hardware + Full Detailed Patches List on this window!
        $sbSys = New-Object System.Text.StringBuilder
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine(" COMPUTER & HARDWARE IDENTIFICATION")
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine("Computer Name     : $($d.ServerName)")
        [void]$sbSys.AppendLine("IP Address(es)    : $($d.NIC_Compact)")
        [void]$sbSys.AppendLine("Domain / Workgroup: $($d.Domain)")
        [void]$sbSys.AppendLine("Manufacturer/Model: $($d.Model)")
        [void]$sbSys.AppendLine("")
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine(" OPERATING SYSTEM & RESOURCE UTILIZATION")
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine("OS Caption        : $($d.OSVersion)")
        [void]$sbSys.AppendLine("Build Number      : $($d.OSBuild)")
        [void]$sbSys.AppendLine("CPU Load Average  : $($d.CPULoad)%")
        [void]$sbSys.AppendLine("RAM Available     : $($d.RAMInfo)")
        [void]$sbSys.AppendLine("System Uptime     : $($d.UptimeDays) days")
        [void]$sbSys.AppendLine("Last Bootup Time  : $($d.LastBoot)")
        [void]$sbSys.AppendLine("")
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine(" PATCH READINESS SUMMARY")
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine("Patch Readiness   : $($d.Status)")
        [void]$sbSys.AppendLine("Pending Reboot    : $(if ($d.PendingReboot -eq $true) { 'YES (Reboot required before patching)' } else { 'NO (Clean)' })")
        [void]$sbSys.AppendLine("Latest KB Number  : $($d.LastKB)")
        [void]$sbSys.AppendLine("KB Description    : $($d.LastKBDescription)")
        [void]$sbSys.AppendLine("Installed Date    : $($d.LastPatchDate) ($($d.DaysSincePatch) days ago)")
        [void]$sbSys.AppendLine("Total Patches     : $($d.TotalPatchesCount) installed updates detected")
        [void]$sbSys.AppendLine("Windows Update Svc: $($d.WuauservStatus)")
        [void]$sbSys.AppendLine("")

        # DIRECTLY ON THIS WINDOW: Table of each KB
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine(" INSTALLED PATCHES & HOTFIXES (ALL DETECTED)")
        [void]$sbSys.AppendLine("=================================================================")
        $hdr = "{0,-14} | {1,-26} | {2,-26} | {3}" -f "KB Number", "Description", "Released / Installed Date", "Installation Status"
        $div = "-" * 86
        [void]$sbSys.AppendLine($hdr)
        [void]$sbSys.AppendLine($div)
        if ($d.PatchList -and $d.PatchList.Count -gt 0) {
            foreach ($p in $d.PatchList) {
                [void]$sbSys.AppendLine(("{0,-14} | {1,-26} | {2,-26} | {3}" -f $p.KBNumber, $p.Description, $p.InstalledDate, $p.InstallStatus))
            }
        } else {
            [void]$sbSys.AppendLine("No patch records found on this system.")
        }
        [void]$sbSys.AppendLine("")

        # DIRECTLY ON THIS WINDOW: Itemized Breakdown of each KB
        [void]$sbSys.AppendLine("-----------------------------------------------------------------")
        [void]$sbSys.AppendLine(" DETAILED BREAKDOWN OF EACH KB:")
        [void]$sbSys.AppendLine("-----------------------------------------------------------------")
        if ($d.PatchList -and $d.PatchList.Count -gt 0) {
            $idx = 1
            foreach ($p in $d.PatchList) {
                [void]$sbSys.AppendLine("[$idx] KB Number   : $($p.KBNumber)")
                [void]$sbSys.AppendLine("    Description : $($p.Description)")
                [void]$sbSys.AppendLine("    Date        : $($p.InstalledDate)")
                [void]$sbSys.AppendLine("    Status      : $($p.InstallStatus)")
                [void]$sbSys.AppendLine("    Installed By: $($p.InstalledBy)")
                [void]$sbSys.AppendLine("    Support Link: $($p.SupportUrl)")
                [void]$sbSys.AppendLine("")
                $idx++
            }
        }

        # DIRECTLY ON THIS WINDOW: Windows Services Summary
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine(" WINDOWS SERVICES SUMMARY")
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine("Total Services Detected : $($d.TotalServicesCount)")
        [void]$sbSys.AppendLine("Running Services        : $($d.RunningServicesCount)")
        [void]$sbSys.AppendLine("Stopped Services        : $($d.StoppedServicesCount)")
        [void]$sbSys.AppendLine("Stopped Automatic (Alert): $($d.StoppedList)")
        [void]$sbSys.AppendLine("(Search and inspect all $($d.TotalServicesCount) services under the 'Windows Services' tab)")
        [void]$sbSys.AppendLine("")

        # DIRECTLY ON THIS WINDOW: Storage
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine(" STORAGE & LOCAL DISK STATUS")
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine("System Drive (C:) : $($d.C_FreeSpaceGB) GB Free")
        [void]$sbSys.AppendLine("")
        [void]$sbSys.AppendLine("All Fixed Drives  :")
        [void]$sbSys.AppendLine($d.AllDisks)
        [void]$sbSys.AppendLine("")

        # DIRECTLY ON THIS WINDOW: Network Interfaces
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine(" ACTIVE NETWORK INTERFACES & IP CONFIGURATION")
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine($d.NIC_Expanded)
        [void]$sbSys.AppendLine("")

        # DIRECTLY ON THIS WINDOW: Windows Update Services & Policies
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine(" WINDOWS UPDATE & SERVICING SERVICES")
        [void]$sbSys.AppendLine("=================================================================")
        [void]$sbSys.AppendLine($d.PatchServices)
        [void]$sbSys.AppendLine("WSUS Server       : $($d.WsusServer)")
        [void]$sbSys.AppendLine("Update Policy     : $($d.AuOptionDesc)")

        $txtSys.Text = $sbSys.ToString()
        $txtSys.SelectionStart = 0; $txtSys.ScrollToCaret()

        # Tab 2: Interactive Grid Patches
        $sbTop = New-Object System.Text.StringBuilder
        [void]$sbTop.AppendLine("REBOOT STATUS   : $($d.RebootDetail -replace '`r`n', ' ')")
        [void]$sbTop.AppendLine("UPDATE SERVICES : $($d.PatchServices -replace '`r`n', ' | ')")
        [void]$sbTop.AppendLine("WSUS / POLICY   : WSUS: $($d.WsusServer) | AU Policy: $($d.AuOptionDesc)")
        [void]$sbTop.AppendLine("LATEST PATCH    : $($d.LastKB) - $($d.LastKBDescription) (Installed on $($d.LastPatchDate), $($d.DaysSincePatch) days ago)")
        $lblPatchSummary.Text = $sbTop.ToString().Trim()

        # Populate Patches DataGridView
        $dtPatches = New-Object System.Data.DataTable
        @("PSComputerName", "Title", "Date", "Result", "Description") | ForEach-Object {
            [void]$dtPatches.Columns.Add($_)
        }

        if ($d.PatchList -and $d.PatchList.Count -gt 0) {
            foreach ($p in $d.PatchList) {
                    $comp = if ($p.PSComputerName) { $p.PSComputerName } else { $curServer }
                    [void]$dtPatches.Rows.Add(
                        [string]$comp,
                        [string]$p.Title,
                        [string]$p.Date,
                        [string]$p.Result,
                        [string]$p.Description
                    )
            }
        }

        $gridPatches.DataSource = $dtPatches
        $lblPatchCount.Text = "Total: $($dtPatches.Rows.Count) updates"

        if ($gridPatches.Columns.Contains("PSComputerName")) { $gridPatches.Columns["PSComputerName"].FillWeight = 85 }
        if ($gridPatches.Columns.Contains("Title")) { $gridPatches.Columns["Title"].FillWeight = 160 }
        if ($gridPatches.Columns.Contains("Date")) { $gridPatches.Columns["Date"].FillWeight = 95 }
        if ($gridPatches.Columns.Contains("Result")) { $gridPatches.Columns["Result"].FillWeight = 65 }
        if ($gridPatches.Columns.Contains("Description")) { $gridPatches.Columns["Description"].FillWeight = 110 }

        foreach ($pRow in $gridPatches.Rows) {
            $st = [string]$pRow.Cells["Result"].Value
            if ($st -eq "Succeeded" -or $st -like "*Installed*") {
                $pRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(235, 255, 235)
                $pRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(20, 100, 30)
            } elseif ($st -eq "Failed") {
                $pRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 230, 230)
                $pRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
            }
        }

        # Tab 3: Windows Services DataGridView (Pre vs Post Patch Comparison)
        $dtServices = New-Object System.Data.DataTable
        $isComparing = ($d.ComparedServicesList -and $d.ComparedServicesList.Count -gt 0)

        if ($isComparing) {
            @("Name", "DisplayName", "StartType", "Pre-Patch Status", "Post-Patch Status", "Comparison State") | ForEach-Object {
                [void]$dtServices.Columns.Add($_)
            }
            foreach ($s in $d.ComparedServicesList) {
                [void]$dtServices.Rows.Add(
                    [string]$s.Name,
                    [string]$s.DisplayName,
                    [string]$s.StartType,
                    [string]$s.PrePatchStatus,
                    [string]$s.PostPatchStatus,
                    [string]$s.DiffState
                )
            }
            $tabServices.Text = "Windows Services (Pre vs Post Compare)"
            $stoppedCount = if ($d.StoppedAfterRestartCount) { $d.StoppedAfterRestartCount } else { 0 }
            $changedCount = if ($d.ChangedServicesCount) { $d.ChangedServicesCount } else { 0 }
            $sameCount = if ($d.SameServicesCount) { $d.SameServicesCount } else { 0 }
            $lblSvcCount.Text = "Pre vs Post: $sameCount Same (Green) | $changedCount Changed (Red) | $stoppedCount Stopped Post-Restart"
        } else {
            @("Name", "DisplayName", "Status (Pre-Patch)", "StartType") | ForEach-Object {
                [void]$dtServices.Columns.Add($_)
            }
            if ($d.ServicesList -and $d.ServicesList.Count -gt 0) {
                foreach ($s in $d.ServicesList) {
                    [void]$dtServices.Rows.Add([string]$s.Name, [string]$s.DisplayName, [string]$s.Status, [string]$s.StartType)
                }
            }
            $tabServices.Text = "Windows Services (Pre-Patch Baseline)"
            $lblSvcCount.Text = "Pre-Patch Baseline: $($dtServices.Rows.Count) services (Run Post-Patch Check after restart to compare)"
        }

        $gridServices.DataSource = $dtServices

        if ($isComparing) {
            if ($gridServices.Columns.Contains("Name")) { $gridServices.Columns["Name"].FillWeight = 85 }
            if ($gridServices.Columns.Contains("DisplayName")) { $gridServices.Columns["DisplayName"].FillWeight = 140 }
            if ($gridServices.Columns.Contains("StartType")) { $gridServices.Columns["StartType"].FillWeight = 55 }
            if ($gridServices.Columns.Contains("Pre-Patch Status")) { $gridServices.Columns["Pre-Patch Status"].FillWeight = 75 }
            if ($gridServices.Columns.Contains("Post-Patch Status")) { $gridServices.Columns["Post-Patch Status"].FillWeight = 75 }
            if ($gridServices.Columns.Contains("Comparison State")) { $gridServices.Columns["Comparison State"].FillWeight = 100 }
        } else {
            if ($gridServices.Columns.Contains("Name")) { $gridServices.Columns["Name"].FillWeight = 95 }
            if ($gridServices.Columns.Contains("DisplayName")) { $gridServices.Columns["DisplayName"].FillWeight = 160 }
            if ($gridServices.Columns.Contains("Status (Pre-Patch)")) { $gridServices.Columns["Status (Pre-Patch)"].FillWeight = 65 }
            if ($gridServices.Columns.Contains("StartType")) { $gridServices.Columns["StartType"].FillWeight = 65 }
        }

        & $fnStyleServiceRows

        # Tab 4: Network Adapters
        $sbNic = New-Object System.Text.StringBuilder
        [void]$sbNic.AppendLine("=================================================================")
        [void]$sbNic.AppendLine(" ACTIVE NETWORK INTERFACES & IP CONFIGURATION")
        [void]$sbNic.AppendLine("=================================================================")
        [void]$sbNic.AppendLine($d.NIC_Expanded)
        $txtNic.Text = $sbNic.ToString()
        $txtNic.SelectionStart = 0; $txtNic.ScrollToCaret()

        # Tab 5: Storage
        $sbDisk = New-Object System.Text.StringBuilder
        [void]$sbDisk.AppendLine("=================================================================")
        [void]$sbDisk.AppendLine(" STORAGE & LOCAL FIXED DRIVES")
        [void]$sbDisk.AppendLine("=================================================================")
        [void]$sbDisk.AppendLine("System Drive (C:) Free: $($d.C_FreeSpaceGB) GB")
        [void]$sbDisk.AppendLine("")
        [void]$sbDisk.AppendLine("All Fixed Volumes Detail:")
        [void]$sbDisk.AppendLine($d.AllDisks)
        $txtDisk.Text = $sbDisk.ToString()
        $txtDisk.SelectionStart = 0; $txtDisk.ScrollToCaret()
    }.GetNewClosure()

    # Search filter for Patches
    $txtPatchFilter.Add_TextChanged({
        if ($null -ne $gridPatches.DataSource -and ($gridPatches.DataSource -is [System.Data.DataTable])) {
            $kw = $txtPatchFilter.Text.Trim().Replace("'", "''")
            if ([string]::IsNullOrWhiteSpace($kw)) {
                $gridPatches.DataSource.DefaultView.RowFilter = ""
            } else {
            $gridPatches.DataSource.DefaultView.RowFilter = "[PSComputerName] LIKE '%$kw%' OR [Title] LIKE '%$kw%' OR [Result] LIKE '%$kw%' OR [Description] LIKE '%$kw%'"
            }
        }
    }.GetNewClosure())

    # Export Patches for this Server
    $btnExportPatches.Add_Click({
        if ($null -eq $gridPatches.DataSource -or $gridPatches.Rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No update history to export for this server.", "Empty Table", "OK", "Information")
            return
        }
        $curServer = [string]$cmbServers.SelectedItem
        $saveFile = New-Object System.Windows.Forms.SaveFileDialog
        $saveFile.Filter = "CSV File (*.csv)|*.csv"
        $saveFile.FileName = "Patches_${curServer}_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
        if ($saveFile.ShowDialog() -eq "OK") {
            $dt = $gridPatches.DataSource
            $dt | Export-Csv -Path $saveFile.FileName -NoTypeInformation
            [System.Windows.Forms.MessageBox]::Show("Exported $($dt.Rows.Count) update records for $curServer to $($saveFile.FileName)", "Exported", "OK", "Information")
        }
    }.GetNewClosure())


    $gridServices.Add_DataBindingComplete({ & $fnStyleServiceRows }.GetNewClosure())

    # Filter logic for Services tab (handles both baseline and comparison modes)
    $fnFilterServices = {
        if ($null -ne $gridServices.DataSource -and ($gridServices.DataSource -is [System.Data.DataTable])) {
            $filterParts = @()
            $kw = $txtSvcSearch.Text.Trim().Replace("'", "''")
            $hasDiff = $gridServices.Columns.Contains("Comparison State")

            if (-not [string]::IsNullOrWhiteSpace($kw)) {
                if ($hasDiff) {
                    $filterParts += "([Name] LIKE '%$kw%' OR [DisplayName] LIKE '%$kw%' OR [Comparison State] LIKE '%$kw%')"
                } else {
                    $filterParts += "([Name] LIKE '%$kw%' OR [DisplayName] LIKE '%$kw%')"
                }
            }

            if ($hasDiff) {
                if ($cmbSvcStatus.SelectedIndex -eq 1) {
                    $filterParts += "[Comparison State] = 'STOPPED AFTER RESTART'"
                } elseif ($cmbSvcStatus.SelectedIndex -eq 2) {
                    $filterParts += "[Comparison State] <> 'Same State'"
                } elseif ($cmbSvcStatus.SelectedIndex -eq 3) {
                    $filterParts += "[Comparison State] = 'Same State'"
                } elseif ($cmbSvcStatus.SelectedIndex -eq 4) {
                    $filterParts += "[Post-Patch Status] = 'Running'"
                } elseif ($cmbSvcStatus.SelectedIndex -eq 5) {
                    $filterParts += "[Post-Patch Status] <> 'Running'"
                }

                if ($chkOnlyStoppedAuto.Checked) {
                    $filterParts += "[Comparison State] <> 'Same State'"
                }
            } else {
                if ($cmbSvcStatus.SelectedIndex -eq 4 -or $cmbSvcStatus.Text -like "*Running*") {
                    $filterParts += "[Status (Pre-Patch)] = 'Running'"
                } elseif ($cmbSvcStatus.SelectedIndex -eq 5 -or $cmbSvcStatus.Text -like "*Stopped*") {
                    $filterParts += "[Status (Pre-Patch)] <> 'Running'"
                }
                if ($chkOnlyStoppedAuto.Checked) {
                    $filterParts += "[StartType] = 'Automatic' AND [Status (Pre-Patch)] <> 'Running'"
                }
            }

            $gridServices.DataSource.DefaultView.RowFilter = ($filterParts -join " AND ")
            $lblSvcCount.Text = "Showing: $($gridServices.Rows.Count) of $($gridServices.DataSource.Rows.Count) services"
            & $fnStyleServiceRows
        }
    }.GetNewClosure()

    $txtSvcSearch.Add_TextChanged({ & $fnFilterServices }.GetNewClosure())
    $cmbSvcStatus.Add_SelectedIndexChanged({ & $fnFilterServices }.GetNewClosure())
    $chkOnlyStoppedAuto.Add_CheckedChanged({ & $fnFilterServices }.GetNewClosure())

    # Export Services for this single Server
    $btnExportThisPcSvcs.Add_Click({
        if ($null -eq $gridServices.DataSource -or $gridServices.Rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No services to export for this server.", "Empty Table", "OK", "Information")
            return
        }
        $curServer = [string]$cmbServers.SelectedItem
        $sourceDetails = if ($srvDetails -and $srvDetails.Count -gt 0) { $srvDetails } elseif ($global:ServerDetails) { $global:ServerDetails } else { $script:ServerDetails }
        if ($null -eq $sourceDetails -or [string]::IsNullOrWhiteSpace($curServer) -or (-not $sourceDetails.Contains($curServer))) {
            [System.Windows.Forms.MessageBox]::Show("Server details unavailable for '$curServer'.", "Error", "OK", "Error")
            return
        }
        $saveFile = New-Object System.Windows.Forms.SaveFileDialog
        $saveFile.Filter = "CSV File (*.csv)|*.csv"
        $saveFile.FileName = "Windows_Services_${curServer}_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
        if ($saveFile.ShowDialog() -eq "OK") {
            $d = $sourceDetails[$curServer]
            if ($d.ComparedServicesList -and $d.ComparedServicesList.Count -gt 0) {
                $exportList = $d.ComparedServicesList | Select-Object `
                    @{Name="ServerName"; Expression={$curServer}},
                    Name,
                    DisplayName,
                    StartType,
                    PrePatchStatus,
                    PostPatchStatus,
                    DiffState,
                    IsSameState,
                    IsStoppedAfterRestart
                $exportList | Export-Csv -Path $saveFile.FileName -NoTypeInformation
                [System.Windows.Forms.MessageBox]::Show("Exported $($exportList.Count) services comparison records for $curServer to $($saveFile.FileName)", "Exported", "OK", "Information")
            } else {
                $exportList = $d.ServicesList | Select-Object `
                    @{Name="ServerName"; Expression={$curServer}},
                    Name,
                    DisplayName,
                    Status,
                    StartType
                $exportList | Export-Csv -Path $saveFile.FileName -NoTypeInformation
                [System.Windows.Forms.MessageBox]::Show("Exported $($exportList.Count) services for $curServer to $($saveFile.FileName)", "Exported", "OK", "Information")
            }
        }
    }.GetNewClosure())

    # RDP Button Handler in Details Window
    $btnRdpThisPc.Add_Click({
        $curServer = [string]$cmbServers.SelectedItem
        if ([string]::IsNullOrWhiteSpace($curServer)) { return }
        Connect-ServerRdp -Target $curServer
    }.GetNewClosure())

    # Restart This Single PC Button Handler
    $btnRestartThisPc.Add_Click({
        $curServer = [string]$cmbServers.SelectedItem
        if ([string]::IsNullOrWhiteSpace($curServer)) { return }
        Restart-SingleServer -Target $curServer
    }.GetNewClosure())

    $btnPostCheckThisPc.Add_Click({
        $curServer = [string]$cmbServers.SelectedItem
        if ([string]::IsNullOrWhiteSpace($curServer)) { return }
        Run-SinglePostPatchCheck -Target $curServer
        & $fnUpdateDisplay
    }.GetNewClosure())

    $cmbServers.Add_SelectedIndexChanged({
        $txtPatchFilter.Text = ""
        $txtSvcSearch.Text = ""
        $cmbSvcStatus.SelectedIndex = 0
        $chkOnlyStoppedAuto.Checked = $false
        & $fnUpdateDisplay
    }.GetNewClosure())

    $btnCopy.Add_Click({
        $curServer = [string]$cmbServers.SelectedItem
        $fullText = "SYSTEM REPORT FOR: $curServer`r`n`r`n" + $txtSys.Text
        [System.Windows.Forms.Clipboard]::SetText($fullText)
        [System.Windows.Forms.MessageBox]::Show("Full system & patch report for '$curServer' copied to clipboard!", "Copied", "OK", "Information")
    }.GetNewClosure())

    # Allow opening currently selected server in an additional new window to crosscheck
    $btnNewWindow.Add_Click({
        $selectedServer = [string]$cmbServers.SelectedItem
        if ($selectedServer) {
            $curTab = if ($tabControl.SelectedTab -eq $tabServices) { "Services" } elseif ($tabControl.SelectedTab -eq $tabPatchGrid) { "Patches" } else { "System" }
            Show-ServerDetailsDialog -defaultServer $selectedServer -InitialTab $curTab
        }
    }.GetNewClosure())

    # Select initial tab (e.g. Services if requested for crosscheck)
    if ($InitialTab -eq "Services") {
        $tabControl.SelectedTab = $tabServices
    } elseif ($InitialTab -eq "Patches") {
        $tabControl.SelectedTab = $tabPatchGrid
    }

    & $fnUpdateDisplay

    # Wire Close button explicitly for modeless window support
    $btnClose.Add_Click({
        $detailForm.Close()
    })

    # Track open modeless windows so they can be managed and cleanly disposed on exit
    if ($null -eq $global:OpenDetailWindows) { $global:OpenDetailWindows = [System.Collections.ArrayList]::new() }
    [void]$global:OpenDetailWindows.Add($detailForm)
    $detailForm.Add_FormClosed({
        if ($global:OpenDetailWindows) { [void]$global:OpenDetailWindows.Remove($detailForm) }
    })

    # Show modelessly so multiple windows can be open simultaneously for crosschecking
    $detailForm.Show()
}

# --- Event: Double-Click Row to Open Separate Details Window ---
$grid.Add_CellDoubleClick({
    param($s, $e)
    if ($e.RowIndex -ge 0) {
        $colName = $grid.Columns[$e.ColumnIndex].Name
        # If user double-clicked an action button column, cell click handler takes care of it
        if ($colName -eq "colRdpBtn" -or $colName -eq "colRestartBtn") { return }

        $selectedServer = [string]$grid.Rows[$e.RowIndex].Cells["ServerName"].Value
        if (-not [string]::IsNullOrWhiteSpace($selectedServer)) {
            Show-ServerDetailsDialog $selectedServer
        }
    }
})

# --- Event: Single-Click Action Buttons Directly in Grid Row (RDP or Restart) ---
$grid.Add_CellContentClick({
    param($s, $e)
    if ($e.RowIndex -ge 0) {
        $colName = $grid.Columns[$e.ColumnIndex].Name
        $selectedServer = [string]$grid.Rows[$e.RowIndex].Cells["ServerName"].Value
        if ([string]::IsNullOrWhiteSpace($selectedServer)) { return }

        if ($colName -eq "colRdpBtn") {
            Connect-ServerRdp -Target $selectedServer
        } elseif ($colName -eq "colRestartBtn") {
            Restart-SingleServer -Target $selectedServer
        }
    }
})

# --- Event: Right-Click Row Selection for Context Menu ---
$grid.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $hti = $grid.HitTest($e.X, $e.Y)
        if ($hti.RowIndex -ge 0) {
            # Only change selection if right-clicked row is not already part of multi-selection
            if (-not $grid.Rows[$hti.RowIndex].Selected) {
                $grid.ClearSelection()
                $grid.Rows[$hti.RowIndex].Selected = $true
            }
        }
    }
})

# --- Event: Context Menu Items for Single PC (Domain Admin Tools) ---
$mnuRdp.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        $selectedServer = [string]$grid.SelectedRows[0].Cells["ServerName"].Value
        if ($selectedServer) { Connect-ServerRdp -Target $selectedServer }
    }
})

$mnuRdpAdmin.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        $selectedServer = [string]$grid.SelectedRows[0].Cells["ServerName"].Value
        if ($selectedServer) { Connect-ServerRdp -Target $selectedServer -AdminSession $true }
    }
})

$mnuRestart.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        $selectedServer = [string]$grid.SelectedRows[0].Cells["ServerName"].Value
        if ($selectedServer) {
            Restart-SingleServer -Target $selectedServer
        }
    }
})

$mnuPostCheck.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        $selectedServer = [string]$grid.SelectedRows[0].Cells["ServerName"].Value
        if ($selectedServer) {
            Run-SinglePostPatchCheck -Target $selectedServer
        }
    }
})

$mnuView.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        foreach ($row in $grid.SelectedRows) {
            $selectedServer = [string]$row.Cells["ServerName"].Value
            if ($selectedServer) { Show-ServerDetailsDialog -defaultServer $selectedServer }
        }
    }
})

$mnuCrosscheckServices.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        foreach ($row in $grid.SelectedRows) {
            $selectedServer = [string]$row.Cells["ServerName"].Value
            if ($selectedServer) { Show-ServerDetailsDialog -defaultServer $selectedServer -InitialTab "Services" }
        }
    }
})

$mnuCompareServices.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        $selectedServer = [string]$grid.SelectedRows[0].Cells["ServerName"].Value
        if ($selectedServer) {
            Show-ServerDetailsDialog -defaultServer $selectedServer -InitialTab "Services"
        }
    }
})

$mnuCopy.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        $selectedServer = [string]$grid.SelectedRows[0].Cells["ServerName"].Value
        if ($selectedServer) {
            [System.Windows.Forms.Clipboard]::SetText($selectedServer)
        }
    }
})


# --- Event: 4. Compare Services Button ---
$btnCompareServices.Add_Click({
    $serverMap = if ($script:ServerDetails -and $script:ServerDetails.Count -gt 0) {
        $script:ServerDetails
    } elseif ($global:ServerDetails -and $global:ServerDetails.Count -gt 0) {
        $global:ServerDetails
    } else {
        $null
    }

    if ($null -eq $serverMap -or $serverMap.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No server check data available yet. Please run '1. Run Built-in Pre-Patch Check' first.", "No Data", "OK", "Information")
        return
    }

    $selectedServer = $null
    if ($grid.SelectedRows.Count -gt 0) {
        $selectedServer = [string]$grid.SelectedRows[0].Cells["ServerName"].Value
    }

    if ($selectedServer) {
        Show-ServerDetailsDialog -defaultServer $selectedServer -InitialTab "Services"
    } else {
        $res = [System.Windows.Forms.MessageBox]::Show(
            "Would you like to open the Services Comparison dialog for the first server, or export comparison report for ALL servers?`r`n`r`nClick [ Yes ]    Open System Details on Services Comparison`r`nClick [ No ]     Export Pre vs Post Services Comparison CSV for ALL servers`r`nClick [ Cancel ] Abort",
            "Compare Pre vs Post Services",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
            foreach ($k in $serverMap.Keys) {
                Show-ServerDetailsDialog -defaultServer $k -InitialTab "Services"
                break
            }
        } elseif ($res -eq [System.Windows.Forms.DialogResult]::No) {
            $saveFile = New-Object System.Windows.Forms.SaveFileDialog
            $saveFile.Filter = "CSV File (*.csv)|*.csv"
            $saveFile.FileName = "Pre_vs_Post_Services_Comparison_All_Servers_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
            if ($saveFile.ShowDialog() -eq "OK") {
                $allRecords = @()
                foreach ($k in $serverMap.Keys) {
                    $entry = $serverMap[$k]
                    if ($entry.ComparedServicesList) {
                        foreach ($c in $entry.ComparedServicesList) {
                            $allRecords += [PSCustomObject]@{
                                ServerName            = $k
                                Name                  = $c.Name
                                DisplayName           = $c.DisplayName
                                StartType             = $c.StartType
                                PrePatchStatus        = $c.PrePatchStatus
                                PostPatchStatus       = $c.PostPatchStatus
                                DiffState             = $c.DiffState
                                IsSameState           = $c.IsSameState
                                IsStoppedAfterRestart = $c.IsStoppedAfterRestart
                            }
                        }
                    } elseif ($entry.ServicesList) {
                        foreach ($s in $entry.ServicesList) {
                            $allRecords += [PSCustomObject]@{
                                ServerName            = $k
                                Name                  = $s.Name
                                DisplayName           = $s.DisplayName
                                StartType             = $s.StartType
                                PrePatchStatus        = $s.Status
                                PostPatchStatus       = "Post-Patch Not Run"
                                DiffState             = "Baseline Only"
                                IsSameState           = $null
                                IsStoppedAfterRestart = $null
                            }
                        }
                    }
                }

                if ($allRecords.Count -gt 0) {
                    $allRecords | Export-Csv -Path $saveFile.FileName -NoTypeInformation
                    Write-GuiLog "Exported $($allRecords.Count) services comparison records to $($saveFile.FileName)"
                    [System.Windows.Forms.MessageBox]::Show("Exported $($allRecords.Count) services comparison records across all servers to:`r`n$($saveFile.FileName)", "Export Completed", "OK", "Information")
                } else {
                    [System.Windows.Forms.MessageBox]::Show("No services data found to export.", "Empty Table", "OK", "Information")
                }
            }
        }
    }
})

# --- Event: View System Details Button ---
$btnViewDetails.Add_Click({
    $serverMap = if ($script:ServerDetails -and $script:ServerDetails.Count -gt 0) {
        $script:ServerDetails
    } elseif ($global:ServerDetails -and $global:ServerDetails.Count -gt 0) {
        $global:ServerDetails
    } else {
        $null
    }
    if ($grid.SelectedRows.Count -gt 0) {
        foreach ($row in $grid.SelectedRows) {
            $selectedServer = [string]$row.Cells["ServerName"].Value
            if ($selectedServer) { Show-ServerDetailsDialog -defaultServer $selectedServer }
        }
    } elseif ($serverMap -and $serverMap.Count -gt 0) {
        foreach ($k in $serverMap.Keys) {
            Show-ServerDetailsDialog -defaultServer $k
            break
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please select a server row from the grid first, or run Pre-Patch Check.", "No Server Selected", "OK", "Information")
    }
})


# --- Event: Load Server List (.txt) ---
$btnLoadTxt.Add_Click({
    $openFile = New-Object System.Windows.Forms.OpenFileDialog
    $openFile.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
    if ($openFile.ShowDialog() -eq "OK") {
        $txtServers.Text = [System.IO.File]::ReadAllText($openFile.FileName)
        Write-GuiLog "Loaded server list from $($openFile.FileName)"
    }
})

# --- Event: Browse Custom Scripts Folder ---
$btnBrowseFolder.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select Folder Containing Custom Scripts (.ps1)"
    if ($folderBrowser.ShowDialog() -eq "OK") {
        $script:CurrentFolder = $folderBrowser.SelectedPath
        $chkListScripts.Items.Clear()
        $found = Get-ChildItem -Path $script:CurrentFolder -Filter *.ps1
        foreach ($file in $found) {
            [void]$chkListScripts.Items.Add($file.Name, $true)
        }
        Write-GuiLog "Found $($found.Count) script(s) in $($script:CurrentFolder)"
    }
})

# =====================================================================
# SCRIPTBLOCK: Built-in Pre-Patch & System Health Collection
# =====================================================================
$healthBlock = {
    $ErrorActionPreference = "SilentlyContinue"

    $OS = Get-CimInstance Win32_OperatingSystem
    $CS = Get-CimInstance Win32_ComputerSystem

    # Disks Info
    $Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    $C = $Disks | Where-Object { $_.DeviceID -eq 'C:' }
    $FreeGB = if ($C -and $C.FreeSpace) { [math]::Round($C.FreeSpace / 1GB, 1) } else { 0 }
    $AllDisksSummary = ($Disks | ForEach-Object {
        $f = [math]::Round($_.FreeSpace / 1GB, 1)
        $s = [math]::Round($_.Size / 1GB, 1)
        "$($_.DeviceID) $f GB free of $s GB"
    }) -join "`r`n"

    # CPU & RAM Info
    $Proc = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
    $CPULoad = if ($Proc.Average) { [math]::Round($Proc.Average, 0) } else { 0 }
    $TotalRAM = if ($OS.TotalVisibleMemorySize) { [math]::Round($OS.TotalVisibleMemorySize / 1MB, 1) } else { 0 }
    $FreeRAM  = if ($OS.FreePhysicalMemory) { [math]::Round($OS.FreePhysicalMemory / 1MB, 1) } else { 0 }

    # Uptime & Last Boot
    $LastBoot = $OS.LastBootUpTime
    $UptimeDays = if ($LastBoot) { [math]::Round(((Get-Date) - $LastBoot).TotalDays, 1) } else { 0 }
    $LastBootStr = if ($LastBoot) { $LastBoot.ToString("yyyy-MM-dd HH:mm") } else { "Unknown" }

    # Network Adapters (Active IPv4 - IP Address Only for Grid View)
    $ActiveNICs = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True")
    $NICSummaryList = @()
    $AllIPList = @()
    foreach ($nic in $ActiveNICs) {
        $ipv4s = @($nic.IPAddress | Where-Object { $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and $_ -ne '127.0.0.1' })
        foreach ($ip in $ipv4s) {
            if ($ip -and $AllIPList -notcontains $ip) {
                $AllIPList += $ip
            }
        }
        $ipStr = if ($ipv4s.Count -gt 0) { $ipv4s -join ", " } else { "No IPv4" }
        $NICSummaryList += "Adapter: $($nic.Description)`r`n  IP(s): $ipStr`r`n  MAC  : $($nic.MACAddress)`r`n  GW   : $(if ($nic.DefaultIPGateway) { $nic.DefaultIPGateway -join ', ' } else { 'None' })`r`n  DNS  : $(if ($nic.DNSServerSearchOrder) { $nic.DNSServerSearchOrder -join ', ' } else { 'None' })"
    }
    $validIPs = @($AllIPList | Where-Object { $_ -notlike '169.254.*' })
    $NICCompactStr  = if ($validIPs.Count -gt 0) { $validIPs -join ", " } elseif ($AllIPList.Count -gt 0) { $AllIPList -join ", " } else { "No IPv4" }
    $NICExpandedStr = if ($NICSummaryList.Count -gt 0) { $NICSummaryList -join "`r`n`r`n" } else { "No active IP-enabled network adapters found." }

    # Reboot Pending Status
    $RebootSources = @()
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $RebootSources += "CBS (Component-Based Servicing)" }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $RebootSources += "Windows Update (RebootRequired)" }
    $pfro = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($pfro -and $pfro.PendingFileRenameOperations) { $RebootSources += "Pending File Rename Operations" }
    $PendingReboot = ($RebootSources.Count -gt 0)
    $RebootDetail = if ($PendingReboot) { "True`r`n(" + ($RebootSources -join ", ") + ")" } else { "False`r`n(Clean)" }

    # Stopped Automatic Services
    $StoppedAuto = @(Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' })
    $StoppedNames = if ($StoppedAuto.Count -gt 0) { ($StoppedAuto.Name | Select-Object -First 5) -join ", " } else { "None" }

    # All Windows Services (Comprehensive Collection for Services Integration)
    $AllServicesList = @(Get-Service -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType | ForEach-Object {
        [PSCustomObject]@{
            Name        = [string]$_.Name
            DisplayName = [string]$_.DisplayName
            Status      = [string]$_.Status
            StartType   = [string]$_.StartType
        }
    })
    $TotalServicesCount   = $AllServicesList.Count
    $RunningServicesCount = @($AllServicesList | Where-Object { $_.Status -eq 'Running' }).Count
    $StoppedServicesCount = @($AllServicesList | Where-Object { $_.Status -ne 'Running' }).Count

    # Core Windows Update Services
    $wuSvc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $WuauservStatus = if ($wuSvc) { "$($wuSvc.Status) ($($wuSvc.StartType))" } else { "Service not found" }

    $PatchServicesList = @(Get-Service -Name wuauserv, bits, trustedinstaller -ErrorAction SilentlyContinue)
    $PatchServicesSummary = ($PatchServicesList | ForEach-Object {
        "$($_.Name.PadRight(18)) : $($_.Status) ($($_.StartType))"
    }) -join "`r`n"
    if (-not $PatchServicesSummary) { $PatchServicesSummary = "Unable to query Windows Update services." }

    # WSUS & Windows Update Policy
    $wuPolicy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    $auPolicy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
    $wsusServer = if ($wuPolicy -and $wuPolicy.WUServer) { $wuPolicy.WUServer } else { "None (Using Microsoft Update directly)" }
    $auOptionDesc = if ($auPolicy) {
        switch ($auPolicy.AUOptions) {
            1 { "Keep computer up to date is disabled" }
            2 { "Notify for download and notify for install" }
            3 { "Auto download and notify for install" }
            4 { "Auto download and schedule the install" }
            5 { "Allow local admin to select setting" }
            default { if ($auPolicy.NoAutoUpdate -eq 1) { "Automatic Updates Disabled by Policy" } else { "Default Windows AU Setting" } }
        }
    } else {
        "Default Windows AU Setting (No Group Policy Override)"
    }

    # Windows Update History - using WU COM API for Title/Date/Result, fallback to Get-HotFix
    $computerName    = $env:COMPUTERNAME
    $PatchDetailsList = @()

    # 1. Try Windows Update Session COM API (richest data: Title, Date, Result)
    try {
        $wuSession  = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $wuSearcher = $wuSession.CreateUpdateSearcher()
        $totalCount = $wuSearcher.GetTotalHistoryCount()
        if ($totalCount -gt 0) {
            $fetchCount = [math]::Min($totalCount, 200)
            $wuHistory  = $wuSearcher.QueryHistory(0, $fetchCount)
            foreach ($item in $wuHistory) {
                $resStr = switch ($item.ResultCode) {
                    1 { "In Progress" }
                    2 { "Succeeded" }
                    3 { "Succeeded With Errors" }
                    4 { "Failed" }
                    5 { "Aborted" }
                    default { "Unknown Status" }
                }
                $cleanTitle = if ($item.Title) { $item.Title } else { "Update" }
                $cleanDesc  = if ($item.Description) { $item.Description } else {
                    if ($cleanTitle -match '\((KB\d+)\)') { "Fix for $($matches[1])" } else { "Windows Update" }
                }
                $dateStr = if ($item.Date) {
                    if ($item.Date -is [DateTime]) { $item.Date.ToString("M/d/yyyy h:mm:ss tt") } else { [string]$item.Date }
                } else { "-" }
                $kbNum = if ($cleanTitle -match '\((KB\d+)\)') { $matches[1] } elseif ($cleanTitle -match '(KB\d+)') { $matches[1] } else { "" }

                $PatchDetailsList += [PSCustomObject]@{
                    PSComputerName = $computerName
                    Title          = $cleanTitle
                    Date           = $dateStr
                    Result         = $resStr
                    Description    = $cleanDesc
                    # Compatibility aliases
                    KBNumber       = $kbNum
                    InstalledDate  = $dateStr
                    InstallStatus  = $resStr
                    InstalledBy    = "SYSTEM / Windows Update"
                    SupportUrl     = if ($kbNum) { "https://support.microsoft.com/help/$($kbNum -replace '\D')" } else { "" }
                }
            }
        }
    } catch {}

    # 2. Fallback: Get-HotFix (if COM returned nothing)
    if ($PatchDetailsList.Count -eq 0) {
        $AllHotFixes = @(Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending)
        foreach ($h in $AllHotFixes) {
            $hId      = if ($h.HotFixID) { $h.HotFixID } else { "Update" }
            $titleStr = if ($hId -match '^KB') { "Update for Windows ($hId)" } else { "Update ($hId)" }
            $descStr  = if ($h.Description) { $h.Description } else { "Fix for $hId" }
            $dateStr  = if ($h.InstalledOn) { $h.InstalledOn.ToString("M/d/yyyy h:mm:ss tt") } else { "Installed with OS / Baseline" }
            $resStr   = "Succeeded"
            $PatchDetailsList += [PSCustomObject]@{
                PSComputerName = $computerName
                Title          = $titleStr
                Date           = $dateStr
                Result         = $resStr
                Description    = $descStr
                KBNumber       = $hId
                InstalledDate  = $dateStr
                InstallStatus  = $resStr
                InstalledBy    = if ($h.InstalledBy) { $h.InstalledBy } else { "SYSTEM" }
                SupportUrl     = if ($h.Caption -match 'http') { $h.Caption } else { "https://support.microsoft.com/help/$($hId -replace '\D')" }
            }
        }
    } else {
        # Also build AllHotFixes for summary counts (even if COM worked)
        $AllHotFixes = @(Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending)
    }

    $LastPatch = $PatchDetailsList | Select-Object -First 1
    $AllHotFixes = if ($AllHotFixes) { $AllHotFixes } else { @() }
    $LastKBId   = if ($LastPatch -and $LastPatch.KBNumber) { $LastPatch.KBNumber } else { "N/A" }
    $LastKBDesc = if ($LastPatch -and $LastPatch.Title) { $LastPatch.Title } else { "Update" }
    $LastKBBy   = if ($LastPatch -and $LastPatch.InstalledBy) { $LastPatch.InstalledBy } else { "SYSTEM" }
    $LastPatchDateStr = if ($LastPatch -and $LastPatch.Date) { $LastPatch.Date } else { "N/A" }
    $DaysSincePatch = if ($AllHotFixes.Count -gt 0 -and $AllHotFixes[0].InstalledOn) {
        [math]::Round(((Get-Date) - $AllHotFixes[0].InstalledOn).TotalDays, 0)
    } else { "N/A" }

    [PSCustomObject]@{
        ServerName         = $env:COMPUTERNAME
        NIC_Compact        = $NICCompactStr
        NIC_Expanded       = $NICExpandedStr
        Status             = if ($FreeGB -lt 10) { "WARNING (Low Disk)" } elseif ($PendingReboot) { "WARNING (Reboot Pending)" } else { "READY" }
        OSVersion          = $OS.Caption
        UptimeDays         = $UptimeDays
        C_FreeSpaceGB      = $FreeGB
        PendingReboot      = $PendingReboot
        LastKB             = $LastKBId
        LastKBDescription  = $LastKBDesc
        LastPatchBy        = $LastKBBy
        LastPatchDate      = $LastPatchDateStr
        DaysSincePatch     = $DaysSincePatch
        TotalPatchesCount  = $PatchDetailsList.Count
        WuauservStatus     = $WuauservStatus
        PatchServices      = $PatchServicesSummary
        WsusServer         = $wsusServer
        AuOptionDesc       = $auOptionDesc
        PatchList          = $PatchDetailsList
        # Services collection
        ServicesList       = $AllServicesList
        TotalServicesCount = $TotalServicesCount
        RunningServicesCount = $RunningServicesCount
        StoppedServicesCount = $StoppedServicesCount
        # Hardware & general properties
        Model              = "$($CS.Manufacturer) $($CS.Model)"
        Domain             = $CS.Domain
        OSBuild            = $OS.BuildNumber
        CPULoad            = $CPULoad
        RAMInfo            = "$FreeRAM / $TotalRAM GB free"
        LastBoot           = $LastBootStr
        AllDisks           = $AllDisksSummary
        RebootDetail       = $RebootDetail
        StoppedCount       = $StoppedAuto.Count
        StoppedList        = $StoppedNames
    }
}

# =====================================================================
# EVENT: 1. Run Built-in Pre-Patch Check
# =====================================================================
$btnRunHealth.Add_Click({
    $servers = @(Get-ServerList)
    if ($servers.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please enter or load at least one server name in the Target Servers list.", "No Servers", "OK", "Warning")
        return
    }

    $btnRunHealth.Enabled = $false
    Write-GuiLog "Starting parallel pre-patch check across $($servers.Count) servers..."

    $credParam = @{}
    if ($chkAltCred.Checked) {
        if ($null -eq $script:AdminCred) {
            $script:AdminCred = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message "Enter Admin Credentials for Remoting"
            if ($null -eq $script:AdminCred) {
                Write-GuiLog "Credential prompt cancelled. Aborting pre-patch check."
                $btnRunHealth.Enabled = $true
                return
            }
            Write-GuiLog "Admin credentials cached for $($script:AdminCred.UserName)"
        }
        $credParam["Credential"] = $script:AdminCred
    }

    $script:DataTable = New-Object System.Data.DataTable
    $script:ServerDetails = [ordered]@{}
    $global:ServerDetails = $script:ServerDetails
    @("ServerName", "NIC_Details", "Status", "OSVersion", "UptimeDays", "PendingReboot", "Last_KBNumber", "KB_Description", "LastPatchDate") | ForEach-Object {
        [void]$script:DataTable.Columns.Add($_)
    }

    # Separate local machine from remote servers
    $localServers = @()
    $remoteServers = @()
    foreach ($s in $servers) {
        if (Test-IsLocalHost $s) {
            $localServers += $s
        } else {
            $remoteServers += $s
        }
    }

    $results = @()
    $errVar = @()

    # 1. Run local targets directly (instant, reliable, no WinRM loopback credential errors)
    foreach ($localTarget in $localServers) {
        try {
            Write-GuiLog "Querying local host [$localTarget] directly..."
            $localRes = & $healthBlock
            $localRes.ServerName = $localTarget
            $results += $localRes
        } catch {
            $errObj = [PSCustomObject]@{
                TargetObject = $localTarget
                Exception    = $_.Exception
            }
            $errVar += $errObj
        }
    }

    # 2. Run remote targets via Invoke-Command in parallel
    if ($remoteServers.Count -gt 0) {
        Write-GuiLog "Connecting in parallel to $($remoteServers.Count) remote server(s)..."
        $results += Invoke-Command -ComputerName $remoteServers -ScriptBlock $healthBlock -ThrottleLimit $script:ThrottleLimit @credParam -ErrorAction SilentlyContinue -ErrorVariable +errVar
    }

    foreach ($r in $results) {
        $sName = if ($r.PSComputerName) { $r.PSComputerName } else { $r.ServerName }
        [void]$script:DataTable.Rows.Add($sName, $r.NIC_Compact, $r.Status, $r.OSVersion, $r.UptimeDays, $r.PendingReboot, $r.LastKB, $r.LastKBDescription, $r.LastPatchDate)
        $script:ServerDetails[$sName] = @{
            IsOffline          = $false
            ServerName         = $sName
            Domain             = $r.Domain
            Model              = $r.Model
            Status             = $r.Status
            OSVersion          = $r.OSVersion
            OSBuild            = $r.OSBuild
            CPULoad            = $r.CPULoad
            RAMInfo            = $r.RAMInfo
            UptimeDays         = $r.UptimeDays
            LastBoot           = $r.LastBoot
            C_FreeSpaceGB      = $r.C_FreeSpaceGB
            AllDisks           = $r.AllDisks
            NIC_Compact        = $r.NIC_Compact
            NIC_Expanded       = $r.NIC_Expanded
            PendingReboot      = $r.PendingReboot
            RebootDetail       = $r.RebootDetail
            StoppedCount       = $r.StoppedCount
            StoppedList        = $r.StoppedList
            LastKB             = $r.LastKB
            LastKBDescription  = $r.LastKBDescription
            LastPatchBy        = $r.LastPatchBy
            LastPatchDate      = $r.LastPatchDate
            DaysSincePatch     = $r.DaysSincePatch
            TotalPatchesCount  = $r.TotalPatchesCount
            WuauservStatus     = $r.WuauservStatus
            PatchServices      = $r.PatchServices
            WsusServer         = $r.WsusServer
            AuOptionDesc       = $r.AuOptionDesc
            PatchList          = $r.PatchList
            # Services
            ServicesList              = $r.ServicesList
            PrePatchServicesList      = $r.ServicesList
            TotalServicesCount        = $r.TotalServicesCount
            RunningServicesCount      = $r.RunningServicesCount
            StoppedServicesCount      = $r.StoppedServicesCount
            HasPostPatch              = $false
            ComparedServicesList      = @()
            StoppedAfterRestartCount  = 0
            ErrorMessage              = ""
        }
    }

    foreach ($err in $errVar) {
        $failedTarget = if ($err.TargetObject) { $err.TargetObject.ToString() } else { "Unknown" }
        [void]$script:DataTable.Rows.Add($failedTarget, "-", "OFFLINE / WINRM ERROR", "Double-click to view error", "-", "-", "-", "-", "-")
        $script:ServerDetails[$failedTarget] = @{
            IsOffline          = $true
            ServerName         = $failedTarget
            Domain             = "-"
            Model              = "-"
            Status             = "OFFLINE / WINRM ERROR"
            OSVersion          = "Unreachable"
            OSBuild            = "-"
            CPULoad            = "-"
            RAMInfo            = "-"
            UptimeDays         = "-"
            LastBoot           = "-"
            C_FreeSpaceGB      = "-"
            AllDisks           = "Drive information unavailable."
            NIC_Compact        = "-"
            NIC_Expanded       = "Network adapter details unavailable."
            PendingReboot      = "-"
            RebootDetail       = "-"
            StoppedCount       = 0
            StoppedList        = "None"
            LastKB             = "-"
            LastKBDescription  = "-"
            LastPatchBy        = "-"
            LastPatchDate      = "-"
            DaysSincePatch     = "-"
            TotalPatchesCount  = 0
            WuauservStatus     = "Unknown"
            PatchServices      = "Unavailable"
            WsusServer         = "-"
            AuOptionDesc       = "-"
            PatchList          = @()
            ServicesList       = @()
            TotalServicesCount = 0
            RunningServicesCount = 0
            StoppedServicesCount = 0
            ErrorMessage       = $err.Exception.Message
        }
        Write-GuiLog "ERROR on ${failedTarget}: $($err.Exception.Message)"
    }
    $global:ServerDetails = $script:ServerDetails
    $script:PrePatchServerDetails = [ordered]@{}
    foreach ($k in $script:ServerDetails.Keys) {
        $script:PrePatchServerDetails[$k] = $script:ServerDetails[$k]
    }
    $global:PrePatchServerDetails = $script:PrePatchServerDetails

    $grid.DataSource = $script:DataTable
    $grid.BindingContext = New-Object System.Windows.Forms.BindingContext
    Style-GridRows

    $btnRunHealth.Enabled = $true
    Write-GuiLog "Pre-patch check completed. Online: $(@($results).Count) | Failed: $($errVar.Count)"
})

# =====================================================================
# EVENT: 2. Run Checked Custom Scripts
# =====================================================================
$btnRunCustom.Add_Click({
    $servers = @(Get-ServerList)
    if ($servers.Count -eq 0 -or $chkListScripts.CheckedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Ensure servers are listed and at least one custom script is checked.", "Missing Selection", "OK", "Warning")
        return
    }

    $credParam = @{}
    if ($chkAltCred.Checked -and $null -ne $script:AdminCred) {
        $credParam["Credential"] = $script:AdminCred
    }

    $localServers = @()
    $remoteServers = @()
    foreach ($s in $servers) {
        if (Test-IsLocalHost $s) { $localServers += $s } else { $remoteServers += $s }
    }

    $sessions = @()
    if ($remoteServers.Count -gt 0) {
        Write-GuiLog "Opening persistent sessions to $($remoteServers.Count) remote servers..."
        $sessionErr = @()
        $sessions = @(New-PSSession -ComputerName $remoteServers @credParam -ErrorAction SilentlyContinue -ErrorVariable +sessionErr)
        foreach ($err in $sessionErr) {
            Write-GuiLog "SESSION FAILED [$($err.TargetObject)]: $($err.Exception.Message)"
        }
    }

    if ($localServers.Count -eq 0 -and $sessions.Count -eq 0) {
        Write-GuiLog "No sessions could be established. Check credentials or WinRM status."
        return
    }

    foreach ($scriptName in $chkListScripts.CheckedItems) {
        $fullPath = Join-Path $script:CurrentFolder $scriptName
        Write-GuiLog ">>> Executing $scriptName..."

        # Run locally if local targets exist
        foreach ($loc in $localServers) {
            try {
                $outLoc = & $fullPath
                foreach ($line in $outLoc) {
                    Write-GuiLog "[$loc] $($line | Out-String)".Trim()
                }
            } catch {
                Write-GuiLog "[$loc ERROR] $($_.Exception.Message)"
            }
        }

        # Run remotely across sessions
        if ($sessions.Count -gt 0) {
            $out = Invoke-Command -Session $sessions -FilePath $fullPath -ThrottleLimit $script:ThrottleLimit -ErrorAction SilentlyContinue
            foreach ($line in $out) {
                $comp = if ($line.PSComputerName) { $line.PSComputerName } else { "Remote" }
                Write-GuiLog "[$comp] $($line | Out-String)".Trim()
            }
        }
    }

    if ($sessions.Count -gt 0) {
        Remove-PSSession -Session $sessions
    }
    Write-GuiLog "All selected custom scripts finished."
})

# =====================================================================
# EVENT: Export Pre-Patch Summary DataTable to CSV
# =====================================================================
$btnExport.Add_Click({
    if ($null -eq $script:DataTable -or $script:DataTable.Rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No grid data to export yet. Please run the Pre-Patch Check first.", "Empty Table", "OK", "Information")
        return
    }
    $saveFile = New-Object System.Windows.Forms.SaveFileDialog
    $saveFile.Filter = "CSV File (*.csv)|*.csv"
    $saveFile.FileName = "PrePatch_Report_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
    if ($saveFile.ShowDialog() -eq "OK") {
        $script:DataTable | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors | Export-Csv -Path $saveFile.FileName -NoTypeInformation
        Write-GuiLog "Exported pre-patch report to $($saveFile.FileName)"
        [System.Windows.Forms.MessageBox]::Show("Pre-patch report exported successfully to:`r`n$($saveFile.FileName)", "Export Completed", "OK", "Information")
    }
})


# =====================================================================
# EVENT: 3. Run Post-Patch Verification Check (All Servers)
# =====================================================================
$btnRunPostPatch.Add_Click({
    $servers = @(Get-ServerList)
    if ($servers.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please enter or load target servers in the left panel first.", "No Servers", "OK", "Warning")
        return
    }

    $btnRunPostPatch.Enabled = $false
    Write-GuiLog "=========================================================="
    Write-GuiLog "STARTING POST-PATCH CHECK FOR $($servers.Count) SERVER(S)"
    Write-GuiLog "=========================================================="

    $credParam = @{}
    if ($chkAltCred.Checked -and $null -ne $script:AdminCred) {
        $credParam["Credential"] = $script:AdminCred
    }

    $localServers = @()
    $remoteServers = @()
    foreach ($s in $servers) {
        if (Test-IsLocalHost $s) { $localServers += $s } else { $remoteServers += $s }
    }

    $results = @()
    $errVar = @()

    # 1. Local execution
    if ($localServers.Count -gt 0) {
        foreach ($loc in $localServers) {
            Write-GuiLog "Running post-patch check on local computer ($loc)..."
            $locRes = & $healthBlock
            if ($locRes) { $results += $locRes }
        }
    }

    # 2. Remote execution
    if ($remoteServers.Count -gt 0) {
        Write-GuiLog "Connecting in parallel to $($remoteServers.Count) remote server(s) for Post-Patch Verification..."
        $results += Invoke-Command -ComputerName $remoteServers -ScriptBlock $healthBlock -ThrottleLimit $script:ThrottleLimit @credParam -ErrorAction SilentlyContinue -ErrorVariable +errVar
    }

    if ($null -eq $script:DataTable) {
        $script:DataTable = New-Object System.Data.DataTable
        @("ServerName", "NIC_Details", "Status", "OSVersion", "UptimeDays", "PendingReboot", "Last_KBNumber", "KB_Description", "LastPatchDate") | ForEach-Object {
            [void]$script:DataTable.Columns.Add($_)
        }
    }

    $healthyCount = 0
    $warnCount = 0
    $totalStoppedServers = 0
    $stoppedServersSummary = @()

    foreach ($r in $results) {
        $sName = if ($r.PSComputerName) { $r.PSComputerName } else { $r.ServerName }

        # Retrieve Pre-Patch services baseline for comparison
        $preDetails = if ($script:PrePatchServerDetails -and $script:PrePatchServerDetails.Contains($sName)) {
            $script:PrePatchServerDetails[$sName]
        } elseif ($global:PrePatchServerDetails -and $global:PrePatchServerDetails.Contains($sName)) {
            $global:PrePatchServerDetails[$sName]
        } elseif ($script:ServerDetails -and $script:ServerDetails.Contains($sName)) {
            $script:ServerDetails[$sName]
        } elseif ($global:ServerDetails -and $global:ServerDetails.Contains($sName)) {
            $global:ServerDetails[$sName]
        } else {
            $null
        }

        $preServices = if ($preDetails -and $preDetails.PrePatchServicesList) {
            $preDetails.PrePatchServicesList
        } elseif ($preDetails -and $preDetails.ServicesList) {
            $preDetails.ServicesList
        } else {
            $null
        }

        # Compare Pre vs Post Services
        $comparedServices = Compare-PrePostServices -preServices $preServices -postServices $r.ServicesList
        $stoppedAfterRestart = @($comparedServices | Where-Object { $_.IsStoppedAfterRestart })
        $changedServices = @($comparedServices | Where-Object { -not $_.IsSameState })
        $sameServices = @($comparedServices | Where-Object { $_.IsSameState })

        $stoppedAfterRestartCount = $stoppedAfterRestart.Count
        $stoppedAfterRestartList = ($stoppedAfterRestart | ForEach-Object { $_.Name }) -join ", "
        $changedCount = $changedServices.Count
        $sameCount = $sameServices.Count

        if ($stoppedAfterRestartCount -gt 0) {
            $totalStoppedServers++
            $stoppedServersSummary += "$sName ($stoppedAfterRestartCount stopped: $stoppedAfterRestartList)"
        }

        $postStatus = if ($r.PendingReboot) {
            $warnCount++
            "WARNING (Reboot Still Pending)"
        } elseif ($stoppedAfterRestartCount -gt 0) {
            $warnCount++
            "WARNING ($stoppedAfterRestartCount Services Stopped After Restart)"
        } elseif ($r.StoppedCount -gt 0) {
            $warnCount++
            "WARNING ($($r.StoppedCount) Auto Services Stopped)"
        } elseif ($r.UptimeDays -ge 1) {
            $warnCount++
            "WARNING (Uptime $($r.UptimeDays)d - Not Rebooted)"
        } elseif ($r.C_FreeSpaceGB -lt 10) {
            $warnCount++
            "WARNING (Low Disk)"
        } else {
            $healthyCount++
            "POST-PATCH: HEALTHY"
        }

        # Update existing row or add new
        $existingRow = $null
        foreach ($row in $script:DataTable.Rows) {
            if ($row["ServerName"] -eq $sName) {
                $existingRow = $row
                break
            }
        }
        if ($existingRow) {
            $existingRow["NIC_Details"]    = $r.NIC_Compact
            $existingRow["Status"]         = $postStatus
            $existingRow["OSVersion"]      = $r.OSVersion
            $existingRow["UptimeDays"]     = $r.UptimeDays
            $existingRow["PendingReboot"]  = $r.PendingReboot
            $existingRow["Last_KBNumber"]  = $r.LastKB
            $existingRow["KB_Description"] = $r.LastKBDescription
            $existingRow["LastPatchDate"]  = $r.LastPatchDate
        } else {
            [void]$script:DataTable.Rows.Add($sName, $r.NIC_Compact, $postStatus, $r.OSVersion, $r.UptimeDays, $r.PendingReboot, $r.LastKB, $r.LastKBDescription, $r.LastPatchDate)
        }

        $script:ServerDetails[$sName] = @{
            IsOffline                  = $false
            ServerName                 = $sName
            Domain                     = $r.Domain
            Model                      = $r.Model
            Status                     = $postStatus
            OSVersion                  = $r.OSVersion
            OSBuild                    = $r.OSBuild
            CPULoad                    = $r.CPULoad
            RAMInfo                    = $r.RAMInfo
            UptimeDays                 = $r.UptimeDays
            LastBoot                   = $r.LastBoot
            C_FreeSpaceGB              = $r.C_FreeSpaceGB
            AllDisks                   = $r.AllDisks
            NIC_Compact                = $r.NIC_Compact
            NIC_Expanded               = $r.NIC_Expanded
            PendingReboot              = $r.PendingReboot
            RebootDetail               = $r.RebootDetail
            StoppedCount               = $r.StoppedCount
            StoppedList                = $r.StoppedList
            LastKB                     = $r.LastKB
            LastKBDescription          = $r.LastKBDescription
            LastPatchBy                = $r.LastPatchBy
            LastPatchDate              = $r.LastPatchDate
            DaysSincePatch             = $r.DaysSincePatch
            TotalPatchesCount          = $r.TotalPatchesCount
            WuauservStatus             = $r.WuauservStatus
            PatchServices              = $r.PatchServices
            WsusServer                 = $r.WsusServer
            AuOptionDesc               = $r.AuOptionDesc
            PatchList                  = $r.PatchList
            ServicesList               = $r.ServicesList
            PrePatchServicesList       = $preServices
            PostPatchServicesList      = $r.ServicesList
            ComparedServicesList       = $comparedServices
            StoppedAfterRestartCount   = $stoppedAfterRestartCount
            StoppedAfterRestartList    = $stoppedAfterRestartList
            ChangedServicesCount       = $changedCount
            SameServicesCount          = $sameCount
            HasPostPatch               = $true
            TotalServicesCount         = $r.TotalServicesCount
            RunningServicesCount       = $r.RunningServicesCount
            StoppedServicesCount       = $r.StoppedServicesCount
            ErrorMessage               = ""
        }

        Write-GuiLog "[$sName POST-PATCH] Status: $postStatus | Uptime: $($r.UptimeDays) d | Reboot Pending: $($r.PendingReboot) | Latest KB: $($r.LastKB) ($($r.LastPatchDate))"
        if ($stoppedAfterRestartCount -gt 0) {
            Write-GuiLog "[$sName CRITICAL] $stoppedAfterRestartCount service(s) STOPPED after restart: $stoppedAfterRestartList"
        }
    }

    foreach ($err in $errVar) {
        $failedTarget = if ($err.TargetObject) { $err.TargetObject.ToString() } else { "Unknown" }
        $existingRow = $null
        foreach ($row in $script:DataTable.Rows) {
            if ($row["ServerName"] -eq $failedTarget) {
                $existingRow = $row
                break
            }
        }
        if ($existingRow) {
            $existingRow["Status"] = "OFFLINE / WINRM ERROR"
        } else {
            [void]$script:DataTable.Rows.Add($failedTarget, "-", "OFFLINE / WINRM ERROR", "Double-click to view error", "-", "-", "-", "-", "-")
        }
        Write-GuiLog "ERROR on ${failedTarget}: $($err.Exception.Message)"
    }
    $global:ServerDetails = $script:ServerDetails

    $grid.DataSource = $script:DataTable
    $grid.BindingContext = New-Object System.Windows.Forms.BindingContext
    Style-GridRows

    $btnRunPostPatch.Enabled = $true
    Write-GuiLog "Post-patch check completed. Healthy: $healthyCount | Warnings: $warnCount | Failed: $($errVar.Count)"
    $stoppedReportMsg = if ($totalStoppedServers -gt 0) {
        "`r`n`r`n[!] Services Stopped After Restart on $totalStoppedServers server(s):`r`n" + ($stoppedServersSummary -join "`r`n") + "`r`n`r`nClick '4. Compare Services' or open System Details to view side-by-side Red/Green comparison."
    } elseif ($script:PrePatchServerDetails.Count -gt 0) {
        "`r`n`r`n[OK] Services Comparison: All services maintained their pre-patch state across all checked servers!"
    } else {
        ""
    }
    [System.Windows.Forms.MessageBox]::Show(
        "Post-Patch Check completed for $($servers.Count) server(s)!`r`n`r`nHealthy & Ready: $healthyCount`r`nWarnings (Reboot Pending / Services): $warnCount`r`nOffline / Errors: $($errVar.Count)$stoppedReportMsg",
        "Post-Patch Summary & Service Comparison",
        "OK",
        "Information"
    )
})

# Ensure all open detail windows close when the main application closes
$form.Add_FormClosing({
    $openWins = if ($global:OpenDetailWindows) { $global:OpenDetailWindows } else { $script:OpenDetailWindows }
    if ($openWins) {
        foreach ($w in @($openWins)) {
            if ($w -and -not $w.IsDisposed) {
                $w.Close()
            }
        }
    }
})

[void]$form.ShowDialog()
