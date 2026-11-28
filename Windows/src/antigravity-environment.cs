// Reads only Antigravity's per-launch CSRF token from a same-user process.
// It does not expose or persist the rest of the process environment.
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PulseAntigravityEnvironment {
    [StructLayout(LayoutKind.Sequential)] struct Pbi { public IntPtr Reserved1, Peb, Reserved2a, Reserved2b, Pid, Reserved3; }
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int c, ref Pbi p, int length, out int returned);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr address, byte[] buffer, UIntPtr length, out UIntPtr read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    static byte[] Read(IntPtr h, long address, int size) { var b=new byte[size]; UIntPtr n; if(!ReadProcessMemory(h,new IntPtr(address),b,(UIntPtr)(uint)size,out n) || n.ToUInt64()!=(ulong)size) return null; return b; }
    static long Pointer(IntPtr h,long address) { var b=Read(h,address,8); return b==null?0:BitConverter.ToInt64(b,0); }
    public static string ReadToken(int pid) {
        if(IntPtr.Size!=8) return null;
        IntPtr h=OpenProcess(0x1010,false,pid); if(h==IntPtr.Zero) return null;
        try {
            var p=new Pbi(); int n; if(NtQueryInformationProcess(h,0,ref p,Marshal.SizeOf(typeof(Pbi)),out n)!=0) return null;
            long parameters=Pointer(h,p.Peb.ToInt64()+0x20); if(parameters==0) return null;
            long env=Pointer(h,parameters+0x80); if(env==0) return null;
            var text=new StringBuilder(); const string key="ANTIGRAVITY_SERVER_CSRF_TOKEN=";
            for(int offset=0;offset<1048576;) {
                int count=(int)Math.Min(4096-((env+offset)&4095),1048576-offset); if((count&1)!=0) return null;
                var bytes=Read(h,env+offset,count); if(bytes==null) return null; offset+=count;
                for(int i=0;i<bytes.Length;i+=2) { char ch=(char)(bytes[i]|bytes[i+1]<<8); if(ch=='\0') { if(text.Length==0) return null; string item=text.ToString(); if(item.StartsWith(key,StringComparison.OrdinalIgnoreCase)) return item.Substring(key.Length); text.Clear(); } else { text.Append(ch); if(text.Length>32767) return null; } }
            }
            return null;
        } finally { CloseHandle(h); }
    }
}
