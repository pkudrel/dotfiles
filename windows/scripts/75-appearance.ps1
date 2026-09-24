# Windows appearance: all animations on (window minimize / maximize, menus, lists, tooltips, taskbar), Windows dark
# and apps light, taskbar aligned left with search as an icon. Applied at once, no sign-out.
# Animation switches: SystemParametersInfo below; the other values: config\appearance.txt.
# Transparency, accent colour and the rest of the taskbar stay as they are.
. (Join-Path $PSScriptRoot 'lib.ps1')

# user32 calls. Created only when missing, so tests can supply a fake DlabUser32.
if (-not ('DlabUser32' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class DlabUser32 {
    [StructLayout(LayoutKind.Sequential)]
    struct AnimationInfo { public uint Size; public int MinAnimate; }

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool SystemParametersInfo(uint action, uint param, ref int value, uint flags);
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool SystemParametersInfo(uint action, uint param, IntPtr value, uint flags);
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool SystemParametersInfo(uint action, uint param, ref AnimationInfo value, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, string lParam,
        uint flags, uint timeout, out UIntPtr result);

    const uint SaveAndNotify = 0x01 | 0x02;  // SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
    const uint GetAnimation = 0x0048, SetAnimation = 0x0049;

    public static bool GetBool(uint action) {
        int value = 0;
        if (!SystemParametersInfo(action, 0, ref value, 0)) throw new Win32Exception();
        return value != 0;
    }

    public static void SetBool(uint action, bool on) {
        if (!SystemParametersInfo(action, 0, new IntPtr(on ? 1 : 0), SaveAndNotify)) throw new Win32Exception();
    }

    // "Animate windows when minimizing and maximizing" (also written to WindowMetrics\MinAnimate).
    public static bool GetMinAnimate() {
        var info = new AnimationInfo { Size = 8 };
        if (!SystemParametersInfo(GetAnimation, 8, ref info, 0)) throw new Win32Exception();
        return info.MinAnimate != 0;
    }

    public static void SetMinAnimate(bool on) {
        var info = new AnimationInfo { Size = 8, MinAnimate = on ? 1 : 0 };
        if (!SystemParametersInfo(SetAnimation, 8, ref info, SaveAndNotify)) throw new Win32Exception();
    }

    // WM_SETTINGCHANGE to all windows (what Settings sends), 1 s per window, skipping hung ones.
    public static void BroadcastSettingChange(string area) {
        UIntPtr result;
        SendMessageTimeout(new IntPtr(0xffff), 0x001A, UIntPtr.Zero, area, 0x0002, 1000, out result);
    }
}
'@
}

# SystemParametersInfo GET / SET pairs; the master switch first (with it off, Windows skips most other animations).
$switches = @(
    @{ Name = 'animation effects (Settings > Accessibility > Visual effects)'; Get = 0x1042; Set = 0x1043 }
    @{ Name = 'menus fade or slide into view';                               Get = 0x1002; Set = 0x1003 }
    @{ Name = 'combo boxes slide open';                                      Get = 0x1004; Set = 0x1005 }
    @{ Name = 'list boxes scroll smoothly';                                  Get = 0x1006; Set = 0x1007 }
    @{ Name = 'menu items fade out after clicking';                          Get = 0x1014; Set = 0x1015 }
    @{ Name = 'tooltips fade or slide into view';                            Get = 0x1016; Set = 0x1017 }
)

$changed = 0
$failed = 0

function Set-Switch([string] $Name, [scriptblock] $Get, [scriptblock] $Set) {
    if (& $Get) { return }
    if ($DotfilesDryRun) {
        Write-Would "turn on: $Name"
        return
    }
    try {
        & $Set
        Write-Ok "${Name}: on (was off)"
        $script:changed++
    }
    catch {
        Write-Warn "${Name}: not changed ($($_.Exception.Message))"
        $script:failed++
    }
}

$first = $switches[0]
Set-Switch $first.Name { [DlabUser32]::GetBool($first.Get) } { [DlabUser32]::SetBool($first.Set, $true) }
Set-Switch 'windows animate when minimizing and maximizing' { [DlabUser32]::GetMinAnimate() } { [DlabUser32]::SetMinAnimate($true) }
foreach ($switch in $switches | Select-Object -Skip 1) {
    Set-Switch $switch.Name { [DlabUser32]::GetBool($switch.Get) } { [DlabUser32]::SetBool($switch.Set, $true) }
}

$lines = @(Read-ListFile (Join-Path $WindowsDir 'config\appearance.txt'))
$changedValues = @()
foreach ($line in $lines) {
    $path, $name, $value = ($line -split '\|', 3).ForEach({ $_.Trim() })
    $value = [int] $value
    $current = (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
    if ($current -eq $value) { continue }
    $now = if ($null -ne $current) { " (was $current)" } else { '' }
    if ($DotfilesDryRun) {
        Write-Would "set $path\$name = $value$now"
        continue
    }
    try {
        if (-not (Test-Path -Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name $name -Value $value -Type DWord
        Write-Ok "$path\$name = $value$now"
        $changedValues += $name
        $changed++
    }
    catch {
        Write-Warn "$path\$name not set ($($_.Exception.Message))"
        $failed++
    }
}

if ($changedValues) {
    # Colours and taskbar pick the new values up without a sign-out.
    [DlabUser32]::BroadcastSettingChange('ImmersiveColorSet')
    [DlabUser32]::BroadcastSettingChange('TraySettings')
    if ('SearchboxTaskbarMode' -in $changedValues) {
        Write-Warn 'taskbar search button: if it did not change yet, sign out, or restart Explorer (Task Manager)'
    }
}

if ($env:SESSIONNAME -like 'RDP-*') {
    Write-Warn 'Remote Desktop session: Windows turns animations off here by itself; they are on at the console'
}
if (-not $changed -and -not $failed -and -not $DotfilesDryRun) {
    Write-Ok "appearance in place ($($switches.Count + 1) animation switches, $($lines.Count) registry values)"
}
