# TorTunnel.AppBypass.ps1
# Per-application DIRECT and TOR routing using Windows Filtering Platform (WFP)
# connection-routing policies. Windows PowerShell 5.1+.

Set-StrictMode -Version 2.0

$script:TTAppBypassNativeLoaded = $false

function Initialize-TTAppBypassNative {
    if ($script:TTAppBypassNativeLoaded) { return }
    if ('TorTunnelNative.WfpRoutePolicy' -as [type]) {
        $script:TTAppBypassNativeLoaded = $true
        return
    }

    $source = @'
using System;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;

namespace TorTunnelNative
{
    public static class WfpRoutePolicy
    {
        private const uint RPC_C_AUTHN_WINNT = 10;
        private const int FWP_IP_VERSION_V4 = 0;
        private const int FWP_MATCH_EQUAL = 0;
        private const int FWP_UINT32 = 3;
        private const int FWP_UINT64 = 4;
        private const int FWP_BYTE_BLOB_TYPE = 12;
        private const int FWPM_NETWORK_CONNECTION_POLICY_CONTEXT = 13;
        private const int FWP_NETWORK_CONNECTION_POLICY_SOURCE_ADDRESS = 0;
        private const int FWP_NETWORK_CONNECTION_POLICY_NEXT_HOP_INTERFACE = 1;
        private const int FWP_NETWORK_CONNECTION_POLICY_NEXT_HOP = 2;
        private const uint FWP_E_PROVIDER_CONTEXT_NOT_FOUND = 0x80320006;
        private const uint FWP_E_NOT_FOUND = 0x80320008;

        private static readonly Guid FWPM_CONDITION_ALE_APP_ID =
            new Guid("D78E1E87-8644-4EA5-9437-D809ECEFC971");

        [StructLayout(LayoutKind.Sequential)]
        private struct FWP_BYTE_BLOB
        {
            public uint size;
            public IntPtr data;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct FWP_VALUE_UNION
        {
            [FieldOffset(0)] public byte uint8;
            [FieldOffset(0)] public ushort uint16;
            [FieldOffset(0)] public uint uint32;
            [FieldOffset(0)] public IntPtr uint64;
            [FieldOffset(0)] public IntPtr ptr;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FWP_VALUE0
        {
            public int type;
            public FWP_VALUE_UNION value;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct FWP_CONDITION_VALUE_UNION
        {
            [FieldOffset(0)] public uint uint32;
            [FieldOffset(0)] public IntPtr byteBlob;
            [FieldOffset(0)] public IntPtr ptr;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FWP_CONDITION_VALUE0
        {
            public int type;
            public FWP_CONDITION_VALUE_UNION value;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FWPM_FILTER_CONDITION0
        {
            public Guid fieldKey;
            public int matchType;
            public FWP_CONDITION_VALUE0 conditionValue;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FWPM_DISPLAY_DATA0
        {
            public IntPtr name;
            public IntPtr description;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FWPM_NETWORK_CONNECTION_POLICY_SETTING0
        {
            public int type;
            public FWP_VALUE0 value;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0
        {
            public uint numSettings;
            public IntPtr settings;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FWPM_PROVIDER_CONTEXT3
        {
            public Guid providerContextKey;
            public FWPM_DISPLAY_DATA0 displayData;
            public uint flags;
            public IntPtr providerKey;
            public FWP_BYTE_BLOB providerData;
            public int type;
            public IntPtr networkConnectionPolicy;
            public ulong providerContextId;
        }

        [DllImport("fwpuclnt.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
        private static extern uint FwpmEngineOpen0(
            string serverName,
            uint authnService,
            IntPtr authIdentity,
            IntPtr session,
            out IntPtr engineHandle);

        [DllImport("fwpuclnt.dll", ExactSpelling = true)]
        private static extern uint FwpmEngineClose0(IntPtr engineHandle);

        [DllImport("fwpuclnt.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
        private static extern uint FwpmGetAppIdFromFileName0(string fileName, out IntPtr appId);

        [DllImport("fwpuclnt.dll", ExactSpelling = true)]
        private static extern void FwpmFreeMemory0(ref IntPtr p);

        [DllImport("fwpuclnt.dll", ExactSpelling = true)]
        private static extern uint FwpmConnectionPolicyAdd0(
            IntPtr engineHandle,
            ref FWPM_PROVIDER_CONTEXT3 connectionPolicy,
            int ipVersion,
            ulong weight,
            uint numFilterConditions,
            ref FWPM_FILTER_CONDITION0 filterConditions,
            IntPtr sd);

        [DllImport("fwpuclnt.dll", ExactSpelling = true)]
        private static extern uint FwpmConnectionPolicyDeleteByKey0(
            IntPtr engineHandle,
            ref Guid key);

        [DllImport("fwpuclnt.dll", ExactSpelling = true)]
        private static extern uint FwpmProviderContextGetByKey3(
            IntPtr engineHandle,
            ref Guid key,
            out IntPtr providerContext);

        [DllImport("iphlpapi.dll", ExactSpelling = true)]
        private static extern uint ConvertInterfaceIndexToLuid(uint interfaceIndex, out ulong interfaceLuid);

        [DllImport("kernel32.dll", EntryPoint = "LoadLibraryW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibrary(string fileName);

        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr GetProcAddress(IntPtr module, string procName);

        [DllImport("kernel32.dll", ExactSpelling = true)]
        private static extern bool FreeLibrary(IntPtr module);

        private static void ThrowIfError(uint result, string operation)
        {
            if (result != 0)
                throw new InvalidOperationException(operation + " failed with 0x" + result.ToString("X8") + ".");
        }

        private static void EnsureConnectionPolicyExports()
        {
            IntPtr module = LoadLibrary("fwpuclnt.dll");
            if (module == IntPtr.Zero)
                throw new InvalidOperationException("Could not load fwpuclnt.dll.");
            try
            {
                string[] names = new string[] {
                    "FwpmConnectionPolicyAdd0",
                    "FwpmConnectionPolicyDeleteByKey0",
                    "FwpmProviderContextGetByKey3"
                };
                foreach (string name in names)
                {
                    if (GetProcAddress(module, name) == IntPtr.Zero)
                        throw new PlatformNotSupportedException(name + " is not available on this Windows build.");
                }
            }
            finally
            {
                FreeLibrary(module);
            }
        }

        private static uint IPv4ToNetworkUInt32(string address)
        {
            IPAddress ip;
            if (!IPAddress.TryParse(address, out ip))
                throw new ArgumentException("Invalid IPv4 address: " + address);
            byte[] bytes = ip.GetAddressBytes();
            if (bytes.Length != 4)
                throw new ArgumentException("IPv4 address required: " + address);
            return BitConverter.ToUInt32(bytes, 0);
        }

        public static string AddDirectBypass(
            string executablePath,
            uint interfaceIndex,
            string sourceIPv4,
            string nextHopIPv4,
            ulong weight)
        {
            EnsureConnectionPolicyExports();
            if (String.IsNullOrWhiteSpace(executablePath))
                throw new ArgumentException("Executable path is empty.");
            executablePath = Path.GetFullPath(executablePath);
            if (!File.Exists(executablePath))
                throw new FileNotFoundException("Excluded application was not found.", executablePath);

            IntPtr engine = IntPtr.Zero;
            IntPtr appId = IntPtr.Zero;
            IntPtr luidPtr = IntPtr.Zero;
            IntPtr settingsArrayPtr = IntPtr.Zero;
            IntPtr settingsHeaderPtr = IntPtr.Zero;
            IntPtr displayNamePtr = IntPtr.Zero;
            IntPtr displayDescriptionPtr = IntPtr.Zero;

            try
            {
                uint rc = FwpmEngineOpen0(null, RPC_C_AUTHN_WINNT, IntPtr.Zero, IntPtr.Zero, out engine);
                ThrowIfError(rc, "FwpmEngineOpen0");

                rc = FwpmGetAppIdFromFileName0(executablePath, out appId);
                ThrowIfError(rc, "FwpmGetAppIdFromFileName0");

                ulong luid;
                rc = ConvertInterfaceIndexToLuid(interfaceIndex, out luid);
                ThrowIfError(rc, "ConvertInterfaceIndexToLuid");

                uint source = IPv4ToNetworkUInt32(sourceIPv4);
                uint nextHop = IPv4ToNetworkUInt32(nextHopIPv4);

                luidPtr = Marshal.AllocHGlobal(8);
                Marshal.WriteInt64(luidPtr, unchecked((long)luid));

                FWPM_NETWORK_CONNECTION_POLICY_SETTING0[] settings =
                    new FWPM_NETWORK_CONNECTION_POLICY_SETTING0[3];

                settings[0].type = FWP_NETWORK_CONNECTION_POLICY_SOURCE_ADDRESS;
                settings[0].value.type = FWP_UINT32;
                settings[0].value.value.uint32 = source;

                settings[1].type = FWP_NETWORK_CONNECTION_POLICY_NEXT_HOP_INTERFACE;
                settings[1].value.type = FWP_UINT64;
                settings[1].value.value.uint64 = luidPtr;

                settings[2].type = FWP_NETWORK_CONNECTION_POLICY_NEXT_HOP;
                settings[2].value.type = FWP_UINT32;
                settings[2].value.value.uint32 = nextHop;

                int settingSize = Marshal.SizeOf(typeof(FWPM_NETWORK_CONNECTION_POLICY_SETTING0));
                settingsArrayPtr = Marshal.AllocHGlobal(settingSize * settings.Length);
                for (int i = 0; i < settings.Length; i++)
                {
                    IntPtr dest = IntPtr.Add(settingsArrayPtr, settingSize * i);
                    Marshal.StructureToPtr(settings[i], dest, false);
                }

                FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0 header =
                    new FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0();
                header.numSettings = (uint)settings.Length;
                header.settings = settingsArrayPtr;
                settingsHeaderPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0)));
                Marshal.StructureToPtr(header, settingsHeaderPtr, false);

                Guid key = Guid.NewGuid();
                displayNamePtr = Marshal.StringToHGlobalUni("TorTunnel direct bypass: " + Path.GetFileName(executablePath));
                displayDescriptionPtr = Marshal.StringToHGlobalUni("Temporary per-application direct IPv4 route created by TorTunnel.");

                FWPM_PROVIDER_CONTEXT3 policy = new FWPM_PROVIDER_CONTEXT3();
                policy.providerContextKey = key;
                policy.displayData.name = displayNamePtr;
                policy.displayData.description = displayDescriptionPtr;
                policy.flags = 0;
                policy.providerKey = IntPtr.Zero;
                policy.providerData.size = 0;
                policy.providerData.data = IntPtr.Zero;
                policy.type = FWPM_NETWORK_CONNECTION_POLICY_CONTEXT;
                policy.networkConnectionPolicy = settingsHeaderPtr;
                policy.providerContextId = 0;

                FWPM_FILTER_CONDITION0 condition = new FWPM_FILTER_CONDITION0();
                condition.fieldKey = FWPM_CONDITION_ALE_APP_ID;
                condition.matchType = FWP_MATCH_EQUAL;
                condition.conditionValue.type = FWP_BYTE_BLOB_TYPE;
                condition.conditionValue.value.byteBlob = appId;

                rc = FwpmConnectionPolicyAdd0(
                    engine,
                    ref policy,
                    FWP_IP_VERSION_V4,
                    weight,
                    1,
                    ref condition,
                    IntPtr.Zero);
                ThrowIfError(rc, "FwpmConnectionPolicyAdd0");

                return key.ToString("D");
            }
            finally
            {
                if (displayDescriptionPtr != IntPtr.Zero) Marshal.FreeHGlobal(displayDescriptionPtr);
                if (displayNamePtr != IntPtr.Zero) Marshal.FreeHGlobal(displayNamePtr);
                if (settingsHeaderPtr != IntPtr.Zero) Marshal.FreeHGlobal(settingsHeaderPtr);
                if (settingsArrayPtr != IntPtr.Zero) Marshal.FreeHGlobal(settingsArrayPtr);
                if (luidPtr != IntPtr.Zero) Marshal.FreeHGlobal(luidPtr);
                if (appId != IntPtr.Zero) FwpmFreeMemory0(ref appId);
                if (engine != IntPtr.Zero) FwpmEngineClose0(engine);
            }
        }

        public static void ValidateSupport(string executablePath, uint interfaceIndex)
        {
            EnsureConnectionPolicyExports();
            if (String.IsNullOrWhiteSpace(executablePath))
                throw new ArgumentException("Executable path is empty.");
            executablePath = Path.GetFullPath(executablePath);
            if (!File.Exists(executablePath))
                throw new FileNotFoundException("Application was not found.", executablePath);

            IntPtr engine = IntPtr.Zero;
            IntPtr appId = IntPtr.Zero;
            try
            {
                uint rc = FwpmEngineOpen0(null, RPC_C_AUTHN_WINNT, IntPtr.Zero, IntPtr.Zero, out engine);
                ThrowIfError(rc, "FwpmEngineOpen0");

                rc = FwpmGetAppIdFromFileName0(executablePath, out appId);
                ThrowIfError(rc, "FwpmGetAppIdFromFileName0");

                ulong luid;
                rc = ConvertInterfaceIndexToLuid(interfaceIndex, out luid);
                ThrowIfError(rc, "ConvertInterfaceIndexToLuid");

                // Probe that the newer provider-context API used to inspect the
                // temporary connection policy is exported. A random key should
                // simply report not-found; no policy is created by this probe.
                Guid randomKey = Guid.NewGuid();
                IntPtr providerContext = IntPtr.Zero;
                rc = FwpmProviderContextGetByKey3(engine, ref randomKey, out providerContext);
                if (providerContext != IntPtr.Zero) FwpmFreeMemory0(ref providerContext);
                if (rc != 0 && rc != FWP_E_PROVIDER_CONTEXT_NOT_FOUND && rc != FWP_E_NOT_FOUND)
                    ThrowIfError(rc, "FwpmProviderContextGetByKey3");
            }
            finally
            {
                if (appId != IntPtr.Zero) FwpmFreeMemory0(ref appId);
                if (engine != IntPtr.Zero) FwpmEngineClose0(engine);
            }
        }

        public static bool PolicyExists(string keyText)
        {
            Guid key;
            if (!Guid.TryParse(keyText, out key))
                throw new ArgumentException("Invalid WFP policy GUID: " + keyText);

            IntPtr engine = IntPtr.Zero;
            IntPtr providerContext = IntPtr.Zero;
            try
            {
                uint rc = FwpmEngineOpen0(null, RPC_C_AUTHN_WINNT, IntPtr.Zero, IntPtr.Zero, out engine);
                ThrowIfError(rc, "FwpmEngineOpen0");
                rc = FwpmProviderContextGetByKey3(engine, ref key, out providerContext);
                if (rc == 0) return true;
                if (rc == FWP_E_PROVIDER_CONTEXT_NOT_FOUND || rc == FWP_E_NOT_FOUND) return false;
                ThrowIfError(rc, "FwpmProviderContextGetByKey3");
                return false;
            }
            finally
            {
                if (providerContext != IntPtr.Zero) FwpmFreeMemory0(ref providerContext);
                if (engine != IntPtr.Zero) FwpmEngineClose0(engine);
            }
        }

        public static uint DeleteDirectBypass(string keyText)
        {
            Guid key;
            if (!Guid.TryParse(keyText, out key))
                throw new ArgumentException("Invalid WFP policy GUID: " + keyText);

            IntPtr engine = IntPtr.Zero;
            try
            {
                uint rc = FwpmEngineOpen0(null, RPC_C_AUTHN_WINNT, IntPtr.Zero, IntPtr.Zero, out engine);
                ThrowIfError(rc, "FwpmEngineOpen0");
                return FwpmConnectionPolicyDeleteByKey0(engine, ref key);
            }
            finally
            {
                if (engine != IntPtr.Zero) FwpmEngineClose0(engine);
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
    $script:TTAppBypassNativeLoaded = $true
}

function Get-TTExcludedApps {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)]$Settings
    )

    if (-not $Settings.EnableAppExclusions) { return @() }

    $path = Join-Path $Root 'config\excluded-apps.txt'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-TTUtf8NoBom -Path $path -Text "# One executable path per line. Lines starting with # are comments.`r`n"
        return @()
    }

    $items = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($raw in @(Get-Content -LiteralPath $path -ErrorAction Stop)) {
        if ($null -eq $raw) { continue }
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $line = $line.Trim('"')
        $line = [Environment]::ExpandEnvironmentVariables($line)

        if (-not [IO.Path]::IsPathRooted($line)) {
            $line = Join-Path $Root $line
        }
        $full = [IO.Path]::GetFullPath($line)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Excluded application does not exist: $full"
        }
        if ([IO.Path]::GetExtension($full) -ne '.exe') {
            throw "Excluded application must be an .exe file: $full"
        }
        if ($seen.Add($full)) {
            $items.Add([pscustomobject]@{
                Path = $full
                Name = [IO.Path]::GetFileName($full)
            })
        }
    }

    # Windows PowerShell 5.1 can throw "Argument types do not match" when
    # an array-subexpression directly wraps a generic List[object]. ToArray()
    # avoids that PowerShell 5.1 binder bug while preserving normal pipeline output.
    return $items.ToArray()
}


function Get-TTTorApps {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)]$Settings
    )

    if (-not $Settings.EnableSelectedTorApps) { return @() }

    $path = Join-Path $Root 'config\tor-apps.txt'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-TTUtf8NoBom -Path $path -Text "# One executable path per line. These apps use Tor when SelectedAppsOnly is chosen at Start.`r`n"
        return @()
    }

    $items = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($raw in @(Get-Content -LiteralPath $path -ErrorAction Stop)) {
        if ($null -eq $raw) { continue }
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $line = $line.Trim('"')
        $line = [Environment]::ExpandEnvironmentVariables($line)

        if (-not [IO.Path]::IsPathRooted($line)) { $line = Join-Path $Root $line }
        $full = [IO.Path]::GetFullPath($line)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Selected Tor application does not exist: $full"
        }
        if ([IO.Path]::GetExtension($full) -ne '.exe') {
            throw "Selected Tor application must be an .exe file: $full"
        }
        if ($seen.Add($full)) {
            $items.Add([pscustomobject]@{ Path=$full; Name=[IO.Path]::GetFileName($full) })
        }
    }
    return $items.ToArray()
}

function Get-TTPrimarySourceIPv4 {
    param([Parameter(Mandatory=$true)][int]$InterfaceIndex)

    $ips = @(Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object {
            $_.IPAddress -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.IPAddress -ne '0.0.0.0' -and
            $_.PrefixOrigin -ne 'WellKnown' -and
            $_.AddressState -ne 'Duplicate' -and
            $_.AddressState -ne 'Invalid'
        } |
        Sort-Object @{Expression={ if ($_.SkipAsSource) { 1 } else { 0 } }}, @{Expression={ if ($_.AddressState -eq 'Preferred') { 0 } else { 1 } }})

    $best = $ips | Select-Object -First 1
    if (-not $best) { throw "No usable IPv4 source address was found on interface $InterfaceIndex." }
    return [string]$best.IPAddress
}

function Get-TTIPv4RoutePoliciesState {
    $text = (& netsh.exe interface ipv4 dump 2>$null) -join "`n"
    $match = [regex]::Match($text, '(?im)\broutepolicies\s*=\s*(enabled|disabled)\b')
    if ($match.Success) { return $match.Groups[1].Value.ToLowerInvariant() }
    return 'unknown'
}

function Set-TTIPv4RoutePoliciesState {
    param([Parameter(Mandatory=$true)][ValidateSet('enabled','disabled')][string]$State)
    & netsh.exe interface ipv4 set global "routepolicies=$State" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not set Windows IPv4 route policies to $State."
    }
}

function Add-TTDirectAppPolicy {
    param(
        [Parameter(Mandatory=$true)][string]$ExecutablePath,
        [Parameter(Mandatory=$true)][int]$InterfaceIndex,
        [Parameter(Mandatory=$true)][string]$SourceIPv4,
        [Parameter(Mandatory=$true)][string]$GatewayIPv4
    )
    Initialize-TTAppBypassNative
    $weight = [UInt64]::Parse('F000000000000000', [System.Globalization.NumberStyles]::HexNumber, [System.Globalization.CultureInfo]::InvariantCulture)
    $key = [TorTunnelNative.WfpRoutePolicy]::AddDirectBypass(
        $ExecutablePath,
        [uint32]$InterfaceIndex,
        $SourceIPv4,
        $GatewayIPv4,
        $weight)
    return [string]$key
}


function Add-TTTorAppPolicy {
    param(
        [Parameter(Mandatory=$true)][string]$ExecutablePath,
        [Parameter(Mandatory=$true)][int]$InterfaceIndex,
        [Parameter(Mandatory=$true)][string]$TunIPv4
    )
    # Reuse the same Windows connection-routing primitive. For a TOR app the
    # selected outgoing interface/source are Wintun rather than the physical NIC.
    # The Wintun interface address is also used as the on-link next hop, matching
    # the route form used by the working system-wide mode.
    return Add-TTDirectAppPolicy -ExecutablePath $ExecutablePath -InterfaceIndex $InterfaceIndex -SourceIPv4 $TunIPv4 -GatewayIPv4 $TunIPv4
}

function Test-TTAppRoutePolicy {
    param([Parameter(Mandatory=$true)][string]$PolicyKey)
    return Test-TTDirectAppPolicy -PolicyKey $PolicyKey
}

function Remove-TTAppRoutePolicy {
    param([Parameter(Mandatory=$true)][string]$PolicyKey)
    return Remove-TTDirectAppPolicy -PolicyKey $PolicyKey
}

function Test-TTAppBypassSupport {
    param(
        [Parameter(Mandatory=$true)][string]$ExecutablePath,
        [Parameter(Mandatory=$true)][int]$InterfaceIndex
    )
    Initialize-TTAppBypassNative
    [TorTunnelNative.WfpRoutePolicy]::ValidateSupport($ExecutablePath, [uint32]$InterfaceIndex)
}

function Test-TTDirectAppPolicy {
    param([Parameter(Mandatory=$true)][string]$PolicyKey)
    Initialize-TTAppBypassNative
    return [bool][TorTunnelNative.WfpRoutePolicy]::PolicyExists($PolicyKey)
}

function Remove-TTDirectAppPolicy {
    param([Parameter(Mandatory=$true)][string]$PolicyKey)
    Initialize-TTAppBypassNative
    return [uint32][TorTunnelNative.WfpRoutePolicy]::DeleteDirectBypass($PolicyKey)
}
