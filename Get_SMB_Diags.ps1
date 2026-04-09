# ============================================================
#  Get-TlogSMBDiagnostics.ps1
#  Superior Grocers - Control-M TLOG Transfer Diagnostic
#
#  Purpose : Captures SMB session state, port 445 connections,
#            DNS registration status, and Security log auth
#            events around the 1:00 AM TLOG transfer window.
#
#  Schedule: Run as a Scheduled Task at 1:00 AM nightly.
#  Run As  : Local Administrator (required for Security log
#            and SMB session access).
#
#  Output  : C:\Logs\TLOG_SMB_Diagnostics\
#            One timestamped .txt file per run.
# ============================================================

# --- CONFIGURATION ------------------------------------------
$LogDir       = "C:\PCMaster\BAK\TLOG_SMB_Diagnostics"
$TlogPath     = "C:\PCMaster\BAK"   # <-- Update this to the actual TLOG share path
$LookbackMins = 15                          # How many minutes back to search the Security log
$ControlMUser = "controlmadmin"             # <-- Update to your Control-M service account name (partial match ok)
# ------------------------------------------------------------

# Create log directory if it doesn't exist
If (-Not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

$Timestamp  = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$OutputFile = "$LogDir\SMB_Diag_$Timestamp.txt"
$Since      = (Get-Date).AddMinutes(-$LookbackMins)

Function Write-Section {
    Param([string]$Title)
    $Line = "=" * 60
    "$Line`r`n  $Title`r`n$Line"
}

$Report = @()

# ============================================================
$Report += Write-Section "RUN TIMESTAMP"
$Report += "Script executed : $(Get-Date)"
$Report += "Lookback window : Last $LookbackMins minutes (since $Since)"
$Report += ""

# ============================================================
$Report += Write-Section "1. PORT 445 - TCP CONNECTION STATE"
Try {
    $Connections = Get-NetTCPConnection -LocalPort 445 -ErrorAction Stop |
        Select-Object LocalAddress, RemoteAddress, State, OwningProcess,
            @{N="ProcessName"; E={ (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name }}
    If ($Connections) {
        $Report += $Connections | Format-Table -AutoSize | Out-String
    } Else {
        $Report += "  No connections found on port 445."
        $Report += ""
    }
} Catch {
    $Report += "  ERROR querying port 445: $_"
    $Report += ""
}

# ============================================================
$Report += Write-Section "2. ACTIVE SMB SESSIONS (Get-SmbSession)"
Try {
    $Sessions = Get-SmbSession -ErrorAction Stop
    If ($Sessions) {
        $Report += $Sessions | Format-Table -AutoSize | Out-String
    } Else {
        $Report += "  No active SMB sessions at time of capture."
        $Report += "  NOTE: If Control-M should have connected by now, this"
        $Report += "  confirms the session never established."
        $Report += ""
    }
} Catch {
    $Report += "  ERROR querying SMB sessions: $_"
    $Report += ""
}

# ============================================================
$Report += Write-Section "3. OPEN SMB FILES (Get-SmbOpenFile)"
Try {
    $OpenFiles = Get-SmbOpenFile -ErrorAction Stop
    If ($OpenFiles) {
        $Report += $OpenFiles | Format-Table -AutoSize | Out-String
    } Else {
        $Report += "  No files currently open over SMB."
        $Report += ""
    }
} Catch {
    $Report += "  ERROR querying open SMB files: $_"
    $Report += ""
}

# ============================================================
$Report += Write-Section "4. TLOG FILE PRESENCE CHECK"
Try {
    If (Test-Path $TlogPath) {
        $TlogFiles = Get-ChildItem -Path $TlogPath -ErrorAction Stop |
            Select-Object Name, Length, LastWriteTime, CreationTime
        If ($TlogFiles) {
            $Report += "  TLOG directory exists. Contents:"
            $Report += $TlogFiles | Format-Table -AutoSize | Out-String
        } Else {
            $Report += "  WARNING: TLOG directory exists but is EMPTY at capture time."
            $Report += ""
        }
    } Else {
        $Report += "  ERROR: TLOG path not found: $TlogPath"
        $Report += "  This path may be incorrect or the share may be unavailable."
        $Report += ""
    }
} Catch {
    $Report += "  ERROR checking TLOG path: $_"
    $Report += ""
}

# ============================================================
$Report += Write-Section "5. DNS REGISTRATION STATUS"
Try {
    $Adapters = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -ne $null }
    ForEach ($Adapter in $Adapters) {
        $Report += "  Adapter  : $($Adapter.InterfaceAlias)"
        $Report += "  IPv4     : $($Adapter.IPv4Address.IPAddress)"
        $Report += "  DNS Svrs : $($Adapter.DNSServer.ServerAddresses -join ', ')"
        $Report += ""
    }

    # Attempt to force DNS registration and capture result
    $Report += "  Attempting ipconfig /registerdns ..."
    $RegResult = & ipconfig /registerdns 2>&1
    $Report += "  Result: $RegResult"
    $Report += ""

    # Check DNS Client event log for registration failures
    $Report += "  DNS Client Event Log - Recent Errors (last $LookbackMins min):"
    Try {
        $DnsEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            StartTime = $Since
        } -ErrorAction Stop |
        Where-Object { $_.Message -like "*failed to register*" -or $_.Message -like "*DNS*" }

        If ($DnsEvents) {
            ForEach ($Evt in $DnsEvents) {
                $Report += "  [$($Evt.TimeCreated)] ID $($Evt.Id): $($Evt.Message.Split("`n")[0])"
            }
        } Else {
            $Report += "  No DNS registration errors found in System log for this window."
        }
    } Catch {
        $Report += "  Could not read System event log: $_"
    }
    $Report += ""
} Catch {
    $Report += "  ERROR checking DNS status: $_"
    $Report += ""
}

# ============================================================
$Report += Write-Section "6. SECURITY LOG - NETWORK LOGON EVENTS (Type 3)"
$Report += "  Filtering Event IDs 4624 (Success) and 4625 (Failure)"
$Report += "  for the last $LookbackMins minutes ..."
$Report += ""
Try {
    $AuthEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = @(4624, 4625)
        StartTime = $Since
    } -ErrorAction Stop

    $NetworkLogons = $AuthEvents | Where-Object {
        $_.Message -like "*Logon Type:*3*"
    }

    If ($NetworkLogons) {
        ForEach ($Evt in $NetworkLogons) {
            $EventType = If ($Evt.Id -eq 4624) { "SUCCESS" } Else { "FAILURE" }
            # Extract key fields from message
            $MsgLines  = $Evt.Message -split "`n"
            $AcctLine  = ($MsgLines | Where-Object { $_ -like "*Account Name*" }     | Select-Object -First 1).Trim()
            $DomLine   = ($MsgLines | Where-Object { $_ -like "*Account Domain*" }   | Select-Object -First 1).Trim()
            $AuthLine  = ($MsgLines | Where-Object { $_ -like "*Authentication*" }   | Select-Object -First 1).Trim()
            $FailLine  = ($MsgLines | Where-Object { $_ -like "*Failure Reason*" }   | Select-Object -First 1).Trim()
            $SrcLine   = ($MsgLines | Where-Object { $_ -like "*Source Network*" }   | Select-Object -First 1).Trim()

            $Report += "  [$($Evt.TimeCreated)] *** $EventType (Event $($Evt.Id)) ***"
            $Report += "    $AcctLine"
            $Report += "    $DomLine"
            $Report += "    $AuthLine"
            If ($FailLine) { $Report += "    $FailLine" }
            If ($SrcLine)  { $Report += "    $SrcLine"  }
            $Report += ""
        }

        # Highlight any Control-M service account hits
        $CMEvents = $NetworkLogons | Where-Object { $_.Message -like "*$ControlMUser*" }
        If ($CMEvents) {
            $Report += "  >>> Control-M service account '$ControlMUser' was found in $($CMEvents.Count) logon event(s) above."
        } Else {
            $Report += "  >>> WARNING: Control-M service account '$ControlMUser' was NOT found"
            $Report += "      in any network logon events during this window."
            $Report += "      This suggests Control-M did not successfully authenticate."
        }
    } Else {
        $Report += "  No network logon events (Type 3) found in the last $LookbackMins minutes."
        $Report += "  This likely means no SMB authentication attempts occurred."
    }
} Catch {
    If ($_.Exception.Message -like "*No events*") {
        $Report += "  No matching Security log events found for this time window."
    } Else {
        $Report += "  ERROR reading Security log: $_"
        $Report += "  Ensure script is running as Administrator."
    }
}
$Report += ""

# ============================================================
$Report += Write-Section "7. SMB SERVER CONFIGURATION SNAPSHOT"
Try {
    $SmbConfig = Get-SmbServerConfiguration | Select-Object `
        EnableSMB1Protocol, EnableSMB2Protocol, RequireSecuritySignature,
        EnableSecuritySignature, AutoDisconnectTimeout, MaxThreadsPerQueue
    $Report += $SmbConfig | Format-List | Out-String
} Catch {
    $Report += "  ERROR retrieving SMB server config: $_"
    $Report += ""
}

# ============================================================
$Report += Write-Section "8. NETSTAT - ALL PORT 445 CONNECTIONS (raw)"
Try {
    $NetstatRaw = & netstat -ano | findstr ":445"
    If ($NetstatRaw) {
        $Report += $NetstatRaw
    } Else {
        $Report += "  No output from netstat for port 445."
    }
} Catch {
    $Report += "  ERROR running netstat: $_"
}
$Report += ""

# ============================================================
$Report += Write-Section "END OF REPORT"
$Report += "Output saved to: $OutputFile"

# Write report to file
$Report | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host "Diagnostic complete. Report saved to: $OutputFile"