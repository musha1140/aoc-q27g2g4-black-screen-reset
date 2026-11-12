param(
    [ValidateSet('Show', 'Validate', 'Off', 'On', 'Cycle')] [string]$Action = 'Show',
    [int]$Seconds = 30,
    [string]$Match = 'AOC2702',
    [string]$StateFile = (Join-Path $PSScriptRoot 'q27-layout.bin'),
    [string]$Log = (Join-Path $PSScriptRoot 'q27-path.log')
)
# Software version of "Disconnect this display" / "Extend desktop to this display" for one monitor.
#   Show     : look only. Lists the active displays.
#   Validate : look only. Asks Windows whether Off and On WOULD be accepted. Changes nothing.
#   Off      : stop driving the matching monitor (like "Disconnect this display"). Not saved as the remembered layout.
#   On       : put back the exact layout saved by Off (like "Extend").
#   Cycle    : Off, wait -Seconds, On.
# The saved layout file is only valid until the next PC restart.
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Ccd {
    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] public struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint Numerator; public uint Denominator; }
    [StructLayout(LayoutKind.Sequential)] public struct PATH_TARGET {
        public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation; public uint scaling;
        public RATIONAL refreshRate; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags;
    }
    [StructLayout(LayoutKind.Sequential)] public struct PATH_INFO { public PATH_SOURCE sourceInfo; public PATH_TARGET targetInfo; public uint flags; }
    [StructLayout(LayoutKind.Sequential)] public struct MODE_INFO {
        public uint infoType; public uint id; public LUID adapterId;
        public ulong u0; public ulong u1; public ulong u2; public ulong u3; public ulong u4; public ulong u5;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct TARGET_DEVICE_NAME {
        public uint type; public uint size; public LUID adapterId; public uint id;
        public uint flags; public uint outputTechnology; public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
    }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint numPaths, [In, Out] PATH_INFO[] paths, ref uint numModes, [In, Out] MODE_INFO[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] static extern int SetDisplayConfig(uint numPaths, [In] PATH_INFO[] paths, uint numModes, [In] MODE_INFO[] modes, uint flags);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TARGET_DEVICE_NAME req);

    const uint QDC_ONLY_ACTIVE_PATHS = 2;
    const uint SDC_USE_SUPPLIED = 0x20, SDC_VALIDATE = 0x40, SDC_APPLY = 0x80, SDC_SAVE = 0x200, SDC_ALLOW_CHANGES = 0x400;

    public static string SizeCheck() {
        int p = Marshal.SizeOf(typeof(PATH_INFO)), m = Marshal.SizeOf(typeof(MODE_INFO)), n = Marshal.SizeOf(typeof(TARGET_DEVICE_NAME));
        return (p == 72 && m == 64 && n == 420) ? "ok" : ("BAD sizes path=" + p + " mode=" + m + " name=" + n);
    }
    public static void Query(out PATH_INFO[] paths, out MODE_INFO[] modes) {
        uint np, nm;
        int r = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out np, out nm);
        if (r != 0) throw new Exception("GetDisplayConfigBufferSizes failed, error " + r);
        paths = new PATH_INFO[np]; modes = new MODE_INFO[nm];
        r = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref np, paths, ref nm, modes, IntPtr.Zero);
        if (r != 0) throw new Exception("QueryDisplayConfig failed, error " + r);
        Array.Resize(ref paths, (int)np); Array.Resize(ref modes, (int)nm);
    }
    public static string TargetName(PATH_INFO p) {
        TARGET_DEVICE_NAME n = new TARGET_DEVICE_NAME();
        n.type = 2; n.size = (uint)Marshal.SizeOf(typeof(TARGET_DEVICE_NAME)); n.adapterId = p.targetInfo.adapterId; n.id = p.targetInfo.id;
        int r = DisplayConfigGetDeviceInfo(ref n);
        if (r != 0) return "(name unavailable, error " + r + ")";
        return n.monitorFriendlyDeviceName + " | " + n.monitorDevicePath;
    }
    public static string Describe(PATH_INFO p, MODE_INFO[] modes) {
        string s = TargetName(p);
        double hz = p.targetInfo.refreshRate.Denominator == 0 ? 0 : (double)p.targetInfo.refreshRate.Numerator / p.targetInfo.refreshRate.Denominator;
        string src = "";
        uint si = p.sourceInfo.modeInfoIdx;
        if (si < modes.Length && modes[si].infoType == 1) {
            MODE_INFO m = modes[si];
            uint w = (uint)(m.u0 & 0xFFFFFFFF), h = (uint)(m.u0 >> 32);
            int x = (int)(uint)(m.u1 >> 32), y = (int)(uint)(m.u2 & 0xFFFFFFFF);
            src = w + "x" + h + " at (" + x + "," + y + ")";
        }
        return s + " | " + src + " | " + hz.ToString("0.00") + " Hz | active=" + ((p.flags & 1) != 0) + " | connected=" + (p.targetInfo.targetAvailable != 0);
    }
    public static int Find(PATH_INFO[] paths, string match) {
        for (int i = 0; i < paths.Length; i++)
            if (TargetName(paths[i]).IndexOf(match, StringComparison.OrdinalIgnoreCase) >= 0) return i;
        return -1;
    }
    // method 1: same list, with the active flag cleared on one path
    public static int OffByFlag(PATH_INFO[] paths, MODE_INFO[] modes, int idx, bool validateOnly) {
        PATH_INFO[] p2 = (PATH_INFO[])paths.Clone();
        p2[idx].flags &= ~1u;
        uint f = SDC_USE_SUPPLIED | (validateOnly ? SDC_VALIDATE : (SDC_APPLY | SDC_ALLOW_CHANGES));
        return SetDisplayConfig((uint)p2.Length, p2, (uint)modes.Length, modes, f);
    }
    // method 2: the list without that path
    public static int OffBySubset(PATH_INFO[] paths, MODE_INFO[] modes, int idx, bool validateOnly) {
        PATH_INFO[] p2 = new PATH_INFO[paths.Length - 1];
        for (int i = 0, j = 0; i < paths.Length; i++) if (i != idx) p2[j++] = paths[i];
        uint f = SDC_USE_SUPPLIED | (validateOnly ? SDC_VALIDATE : (SDC_APPLY | SDC_ALLOW_CHANGES));
        return SetDisplayConfig((uint)p2.Length, p2, (uint)modes.Length, modes, f);
    }
    public static int Restore(PATH_INFO[] paths, MODE_INFO[] modes, bool validateOnly) {
        uint f = SDC_USE_SUPPLIED | (validateOnly ? SDC_VALIDATE : (SDC_APPLY | SDC_ALLOW_CHANGES | SDC_SAVE));
        return SetDisplayConfig((uint)paths.Length, paths, (uint)modes.Length, modes, f);
    }
    public static byte[] PathsToBytes(PATH_INFO[] a) { return ToBytes(a, Marshal.SizeOf(typeof(PATH_INFO))); }
    public static byte[] ModesToBytes(MODE_INFO[] a) { return ToBytes(a, Marshal.SizeOf(typeof(MODE_INFO))); }
    static byte[] ToBytes(Array a, int sz) {
        byte[] b = new byte[sz * a.Length];
        GCHandle h = GCHandle.Alloc(a, GCHandleType.Pinned);
        try { Marshal.Copy(h.AddrOfPinnedObject(), b, 0, b.Length); } finally { h.Free(); }
        return b;
    }
    public static PATH_INFO[] PathsFromBytes(byte[] b) {
        PATH_INFO[] a = new PATH_INFO[b.Length / Marshal.SizeOf(typeof(PATH_INFO))];
        GCHandle h = GCHandle.Alloc(a, GCHandleType.Pinned);
        try { Marshal.Copy(b, 0, h.AddrOfPinnedObject(), b.Length); } finally { h.Free(); }
        return a;
    }
    public static MODE_INFO[] ModesFromBytes(byte[] b) {
        MODE_INFO[] a = new MODE_INFO[b.Length / Marshal.SizeOf(typeof(MODE_INFO))];
        GCHandle h = GCHandle.Alloc(a, GCHandleType.Pinned);
        try { Marshal.Copy(b, 0, h.AddrOfPinnedObject(), b.Length); } finally { h.Free(); }
        return a;
    }
}
'@

function Say([string]$m) {
    $line = '{0}  {1}' -f (Get-Date).ToString('HH:mm:ss.fff'), $m
    $line
    Add-Content -LiteralPath $Log -Value $line -Encoding utf8
}
function ShowAll($paths, $modes, [string]$title) {
    Say $title
    for ($i = 0; $i -lt $paths.Length; $i++) { Say ('   [{0}] {1}' -f $i, [Ccd]::Describe($paths[$i], $modes)) }
}
function SaveState($paths, $modes) {
    $pb = [Ccd]::PathsToBytes($paths); $mb = [Ccd]::ModesToBytes($modes)
    $all = [BitConverter]::GetBytes([int]$pb.Length) + $pb + $mb
    [IO.File]::WriteAllBytes($StateFile, [byte[]]$all)
}
function LoadState {
    $all = [IO.File]::ReadAllBytes($StateFile)
    $n = [BitConverter]::ToInt32($all, 0)
    $pb = New-Object byte[] $n; [Array]::Copy($all, 4, $pb, 0, $n)
    $mb = New-Object byte[] ($all.Length - 4 - $n); [Array]::Copy($all, 4 + $n, $mb, 0, $mb.Length)
    , @([Ccd]::PathsFromBytes($pb), [Ccd]::ModesFromBytes($mb))
}

$chk = [Ccd]::SizeCheck()
if ($chk -ne 'ok') { Say "ABORT: internal layout check failed ($chk). Nothing was changed."; exit 2 }

$paths = $null; $modes = $null
[Ccd]::Query([ref]$paths, [ref]$modes)
Say "---- q27-path: action=$Action match=$Match ----"
ShowAll $paths $modes 'active displays now:'
$idx = [Ccd]::Find($paths, $Match)

switch ($Action) {
    'Show' {
        if ($idx -lt 0) { Say "no active display matches '$Match'" } else { Say "the display matching '$Match' is entry [$idx]" }
    }
    'Validate' {
        if ($idx -lt 0) { Say "no active display matches '$Match'; nothing to validate"; break }
        Say ('would Windows accept OFF, method 1 (flag)?   result code {0} (0 = yes)' -f [Ccd]::OffByFlag($paths, $modes, $idx, $true))
        Say ('would Windows accept OFF, method 2 (subset)? result code {0} (0 = yes)' -f [Ccd]::OffBySubset($paths, $modes, $idx, $true))
        Say ('would Windows accept putting back the current layout? result code {0} (0 = yes)' -f [Ccd]::Restore($paths, $modes, $true))
        Say 'validate only: nothing was changed'
    }
    { $_ -in 'Off', 'Cycle' } {
        if ($idx -lt 0) { Say "no active display matches '$Match'; nothing done"; break }
        SaveState $paths $modes
        Say "layout saved to $StateFile"
        $r = [Ccd]::OffByFlag($paths, $modes, $idx, $false)
        Say "OFF (method 1) result code $r (0 = done)"
        if ($r -ne 0) { $r = [Ccd]::OffBySubset($paths, $modes, $idx, $false); Say "OFF (method 2) result code $r (0 = done)" }
        if ($r -ne 0) { Say 'OFF was refused by Windows. Nothing was changed.'; break }
        $p2 = $null; $m2 = $null; [Ccd]::Query([ref]$p2, [ref]$m2); ShowAll $p2 $m2 'active displays after OFF:'
        if ($Action -eq 'Cycle') {
            for ($s = $Seconds; $s -gt 0; $s -= 5) { Say "waiting, $s s left"; Start-Sleep -Seconds ([Math]::Min(5, $s)) }
            $r = [Ccd]::Restore($paths, $modes, $false)
            Say "ON (put back saved layout) result code $r (0 = done)"
            Start-Sleep -Seconds 3
            $p3 = $null; $m3 = $null; [Ccd]::Query([ref]$p3, [ref]$m3); ShowAll $p3 $m3 'active displays after ON:'
        }
    }
    'On' {
        $st = LoadState
        $r = [Ccd]::Restore($st[0], $st[1], $false)
        Say "ON (put back saved layout) result code $r (0 = done)"
        Start-Sleep -Seconds 3
        $p3 = $null; $m3 = $null; [Ccd]::Query([ref]$p3, [ref]$m3); ShowAll $p3 $m3 'active displays after ON:'
    }
}
