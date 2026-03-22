param(
    [string]$Title = 'ntfy forwarder test',
    [string]$Message = 'If this toast is forwarded to your phone, the Windows notification listener is working.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] > $null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] > $null

$appId = 'E.ntfy.TestNotifier'
$shortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\ntfy Test Notifier.lnk'
$powershellPath = (Get-Command powershell.exe).Source

$shortcutInterop = @"
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

[ComImport]
[Guid("00021401-0000-0000-C000-000000000046")]
internal class CShellLink
{
}

[ComImport]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[Guid("000214F9-0000-0000-C000-000000000046")]
internal interface IShellLinkW
{
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszFile, int cch, IntPtr pfd, int fFlags);
    void GetIDList(out IntPtr ppidl);
    void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszName, int cch);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszDir, int cch);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszArgs, int cch);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
    void GetHotkey(out short pwHotkey);
    void SetHotkey(short wHotkey);
    void GetShowCmd(out int piShowCmd);
    void SetShowCmd(int iShowCmd);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszIconPath, int cch, out int piIcon);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, int dwReserved);
    void Resolve(IntPtr hwnd, int fFlags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
}

[ComImport]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
internal interface IPropertyStore
{
    uint GetCount(out uint cProps);
    uint GetAt(uint iProp, out PROPERTYKEY pkey);
    uint GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
    uint SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
    uint Commit();
}

[StructLayout(LayoutKind.Sequential, Pack = 4)]
internal struct PROPERTYKEY
{
    public Guid fmtid;
    public uint pid;
}

[StructLayout(LayoutKind.Explicit)]
internal struct PROPVARIANT
{
    [FieldOffset(0)]
    public ushort vt;
    [FieldOffset(8)]
    public IntPtr pointerValue;

    public static PROPVARIANT FromString(string value)
    {
        var pv = new PROPVARIANT();
        pv.vt = 31;
        pv.pointerValue = Marshal.StringToCoTaskMemUni(value);
        return pv;
    }
}

[ComImport]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
[Guid("0000010b-0000-0000-C000-000000000046")]
internal interface IPersistFile
{
    void GetClassID(out Guid pClassID);
    void IsDirty();
    void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
    void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, bool fRemember);
    void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
    void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
}

public static class ToastShortcutManager
{
    public static void EnsureShortcut(string shortcutPath, string exePath, string arguments, string appId)
    {
        var link = (IShellLinkW)new CShellLink();
        link.SetPath(exePath);
        link.SetArguments(arguments);
        link.SetWorkingDirectory(System.IO.Path.GetDirectoryName(exePath));
        link.SetDescription("ntfy toast test notifier");

        var propertyStore = (IPropertyStore)link;
        var appIdKey = new PROPERTYKEY
        {
            fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
            pid = 5
        };
        var pv = PROPVARIANT.FromString(appId);
        propertyStore.SetValue(ref appIdKey, ref pv);
        propertyStore.Commit();

        var persistFile = (IPersistFile)link;
        persistFile.Save(shortcutPath, true);
    }
}
"@

if (-not ('ToastShortcutManager' -as [type])) {
    Add-Type -TypeDefinition $shortcutInterop -Language CSharp
}

function Ensure-ToastShortcut {
    if (Test-Path -LiteralPath $shortcutPath) {
        return
    }

    $arguments = '-NoProfile'
    [ToastShortcutManager]::EnsureShortcut($shortcutPath, $powershellPath, $arguments, $appId)
}

function New-ToastXml {
    param(
        [string]$ToastTitle,
        [string]$ToastMessage
    )

    $escapedTitle = [System.Security.SecurityElement]::Escape($ToastTitle)
    $escapedMessage = [System.Security.SecurityElement]::Escape($ToastMessage)

    return @"
<toast activationType="protocol" launch="https://ntfy.sh/">
  <visual>
    <binding template="ToastGeneric">
      <text>$escapedTitle</text>
      <text>$escapedMessage</text>
    </binding>
  </visual>
</toast>
"@
}

Ensure-ToastShortcut

$xml = New-ToastXml -ToastTitle $Title -ToastMessage $Message
$xmlDocument = New-Object Windows.Data.Xml.Dom.XmlDocument
$xmlDocument.LoadXml($xml)

$toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDocument)
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)
$notifier.Show($toast)

Write-Host "Test toast sent."
Write-Host "Title: $Title"
Write-Host "Message: $Message"
