// Copyright (c) 2026 Zahid Hussain / Scopewise Consulting.
// Native, windowless shell for the existing PowerShell/WPF control center.
// No Tor networking, firewall changes or configuration is implemented here.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class VeylRouteLauncher
{
    [STAThread]
    private static int Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        string gui = Path.Combine(root, "ui", "TorTunnel.ModernGui.ps1");
        if (!File.Exists(gui))
        {
            MessageBox.Show("VeylRoute interface files are missing. Please repair the installation.",
                "VeylRoute", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
        string powerShell = Path.Combine(Environment.SystemDirectory,
            "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powerShell))
        {
            MessageBox.Show("Windows PowerShell 5.1 could not be found.",
                "VeylRoute", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 3;
        }
        var p = new ProcessStartInfo
        {
            FileName = powerShell,
            Arguments = "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass " +
                        "-WindowStyle Hidden -File \"" + gui + "\"",
            WorkingDirectory = root,
            UseShellExecute = true,
            Verb = "runas",
            WindowStyle = ProcessWindowStyle.Hidden
        };
        try { Process.Start(p); return 0; }
        catch (Win32Exception ex)
        {
            // A cancelled elevation dialog is not a startup crash.
            if (ex.NativeErrorCode == 1223) return 1;
            MessageBox.Show("Could not launch VeylRoute: " + ex.Message,
                "VeylRoute", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 4;
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not launch VeylRoute: " + ex.Message,
                "VeylRoute", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 5;
        }
    }
}
