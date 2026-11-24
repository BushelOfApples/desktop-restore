using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace DesktopRestore {
    public sealed class WindowInfo {
        public long Handle;
        public int ProcessId;
        public string Path;
        public string Class;
        public string Title;
    }

    public static class Native {
        private delegate bool EnumProc(IntPtr hwnd, IntPtr data);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr data);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
        [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder name, ref int size);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);

        public static WindowInfo[] ListWindows() {
            var windows = new List<WindowInfo>();
            int ownPid = Process.GetCurrentProcess().Id;
            bool ok = EnumWindows(delegate(IntPtr hwnd, IntPtr unused) {
                // Other virtual desktops use DWM shell cloaking. Keep those windows.
                if (!IsWindowVisible(hwnd)) return true;
                int style = GetWindowLong(hwnd, -20);
                if ((style & 0x80) != 0) return true; // WS_EX_TOOLWINDOW
                if (GetWindow(hwnd, 4) != IntPtr.Zero && (style & 0x40000) == 0) return true;
                int cloaked;
                if (DwmGetWindowAttribute(hwnd, 14, out cloaked, 4) == 0 && (cloaked & 1) != 0) return true;
                var title = new StringBuilder(32768);
                if (GetWindowText(hwnd, title, title.Capacity) == 0) return true;
                var cls = new StringBuilder(512);
                GetClassName(hwnd, cls, cls.Capacity);
                string className = cls.ToString();
                if (className == "Progman" || className == "WorkerW" || className == "Shell_TrayWnd" || className == "Shell_SecondaryTrayWnd") return true;
                uint pid;
                GetWindowThreadProcessId(hwnd, out pid);
                if (pid == ownPid) return true;
                IntPtr process = OpenProcess(0x1000, false, pid);
                if (process == IntPtr.Zero) return true;
                string path;
                try {
                    var buffer = new StringBuilder(32768);
                    int size = buffer.Capacity;
                    if (!QueryFullProcessImageName(process, 0, buffer, ref size)) return true;
                    path = buffer.ToString();
                } finally { CloseHandle(process); }
                windows.Add(new WindowInfo { Handle = hwnd.ToInt64(), ProcessId = (int)pid, Path = path, Class = className, Title = title.ToString() });
                return true;
            }, IntPtr.Zero);
            if (!ok) throw new InvalidOperationException("Windows could not enumerate application windows.");
            return windows.ToArray();
        }
    }
}
