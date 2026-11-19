Option Explicit
Dim fso, sh, shell, root, exe, gui, args
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
Set shell = CreateObject("Shell.Application")
root = fso.GetParentFolderName(WScript.ScriptFullName)
gui = fso.BuildPath(fso.BuildPath(root, "ui"), "TorTunnel.ModernGui.ps1")
exe = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
If Not fso.FileExists(gui) Then
    MsgBox "Missing the VeylRoute interface script. Restore the complete extracted package.", vbCritical, "VeylRoute"
    WScript.Quit 1
End If
args = "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & gui & Chr(34)
On Error Resume Next
shell.ShellExecute exe, args, root, "runas", 0
If Err.Number <> 0 Then MsgBox "Could not open VeylRoute: " & Err.Description, vbExclamation, "VeylRoute"
On Error GoTo 0
