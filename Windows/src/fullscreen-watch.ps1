param([int]$OwnerProcessId)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PulseFullScreen {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int left, top, right, bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct MonitorInfo { public int size; public Rect monitor, work; public uint flags; }
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
 [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder name, int max);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out Rect r);
 [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
 [DllImport("user32.dll", CharSet=CharSet.Auto)] static extern bool GetMonitorInfo(IntPtr h, ref MonitorInfo m);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll", EntryPoint="GetWindowLongW")] static extern int GetWindowLong(IntPtr h, int index);
 public static string Current(int owner) {
  IntPtr h=GetForegroundWindow(); uint pid; if(h==IntPtr.Zero || h==GetShellWindow() || h==GetDesktopWindow() || !IsWindowVisible(h)) return "null";
  var name=new StringBuilder(128); GetClassName(h,name,name.Capacity);
  if(name.ToString()=="Progman" || name.ToString()=="WorkerW" || name.ToString()=="Shell_TrayWnd") return "null";
  GetWindowThreadProcessId(h,out pid); if(pid==(uint)owner) return "null";
  const int WS_CAPTION=0x00C00000; if((GetWindowLong(h,-16)&WS_CAPTION)!=0) return "null";
  Rect r; var m=new MonitorInfo(); m.size=Marshal.SizeOf(typeof(MonitorInfo));
  if(!GetWindowRect(h,out r)||!GetMonitorInfo(MonitorFromWindow(h,2),ref m)) return "null";
  if(r.left>m.monitor.left+2||r.top>m.monitor.top+2||r.right<m.monitor.right-2||r.bottom<m.monitor.bottom-2) return "null";
  long cx=((long)m.monitor.left+m.monitor.right)/2, cy=((long)m.monitor.top+m.monitor.bottom)/2;
  return "{\"x\":"+cx+",\"y\":"+cy+"}";
 }
}
'@
$ownerProcess = [System.Diagnostics.Process]::GetProcessById($OwnerProcessId)
$lastValue = ''
while (-not $ownerProcess.HasExited) {
    $value = [PulseFullScreen]::Current($OwnerProcessId)
    if ($value -ne $lastValue) { [Console]::Out.WriteLine($value); [Console]::Out.Flush(); $lastValue = $value }
    Start-Sleep -Milliseconds 750
}
