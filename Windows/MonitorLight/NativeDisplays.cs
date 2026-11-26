using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace MonitorLight;

internal sealed record Display(string Id, string Name, string Device)
{
    public override string ToString() => $"{Name} · {Device.Replace(@"\\.\DISPLAY", "屏幕 ")}";
}

internal static class NativeDisplays
{
    private const uint OnlyActivePaths = 2;
    private const int InsufficientBuffer = 122;

    public static Display[] Enumerate() => Routes().Select(route => route.Display).ToArray();

    public static DdcHandle Open(Display display)
    {
        foreach (var route in Routes())
        {
            if (!StringComparer.OrdinalIgnoreCase.Equals(route.Display.Id, display.Id))
                continue;

            // A single logical monitor must map to exactly one hardware handle.
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(route.Handle, out uint count))
                throw new InvalidOperationException($"无法枚举物理显示器（0x{Marshal.GetLastWin32Error():X8}）。");
            if (count != 1)
                throw new InvalidOperationException($"此屏幕对应 {count} 个物理显示器句柄，无法独立控制。");

            if (!GetPhysicalMonitorsFromHMONITOR(route.Handle, 1, out var physical))
                throw new InvalidOperationException($"无法打开物理显示器（0x{Marshal.GetLastWin32Error():X8}）。");
            if (physical.Handle == new IntPtr(-1))
                throw new InvalidOperationException($"无效的物理显示器句柄 {physical.Handle}（{physical.Description}）。");
            return new DdcHandle(physical.Handle);
        }

        throw new InvalidOperationException("无法连接该显示器，请确认 DDC/CI 已开启并重新检测。");
    }

    private static List<(Display Display, IntPtr Handle)> Routes()
    {
        var targets = new Dictionary<string, List<PathTarget>>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in ActivePaths())
        {
            var source = new SourceName { Header = Header<SourceName>(1, path.Source.Adapter, path.Source.Id) };
            if (GetSourceName(ref source) != 0 || string.IsNullOrWhiteSpace(source.Device))
                continue;

            if (!targets.TryGetValue(source.Device, out var list))
                targets[source.Device] = list = [];
            list.Add(path.Target);
        }

        var routes = new List<(Display Display, IntPtr Handle)>();
        MonitorCallback collect = (monitor, _, _, _) =>
        {
            var info = new MonitorInfo { Size = (uint)Marshal.SizeOf<MonitorInfo>() };
            if (!GetMonitorInfo(monitor, ref info) ||
                !targets.TryGetValue(info.Device, out var candidates) ||
                candidates.Count != 1)
                return true;

            var target = candidates[0];
            if (target.Available == 0 || !IsExternalConnector(target.Technology))
                return true;

            var name = new TargetName { Header = Header<TargetName>(2, target.Adapter, target.Id) };
            if (GetTargetName(ref name) != 0 || string.IsNullOrWhiteSpace(name.Path))
                return true;

            var display = new Display(name.Path, string.IsNullOrWhiteSpace(name.Name) ? "外接显示器" : name.Name,
                                      info.Device);
            routes.Add((display, monitor));
            return true;
        };

        if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, collect, IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法枚举显示器。");

        // An ambiguous device path cannot safely identify a write target.
        return routes.GroupBy(route => route.Display.Id, StringComparer.OrdinalIgnoreCase)
            .Where(group => group.Count() == 1)
            .Select(group => group.Single())
            .OrderBy(route => route.Display.Device, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    internal static bool IsExternalConnector(int technology) =>
        technology is >= 0 and <= 5 or 8 or 9 or 10 or 12 or 14 or 18;

    private static IEnumerable<PathInfo> ActivePaths()
    {
        // The required buffer can change between calls when a display is connected.
        for (int attempt = 0; attempt < 3; attempt++)
        {
            int result = GetDisplayConfigBufferSizes(OnlyActivePaths, out uint pathCount, out uint modeCount);
            if (result == InsufficientBuffer)
                continue;
            if (result != 0)
                throw new Win32Exception(result, "无法读取 Windows 显示配置。");
            if (pathCount == 0)
                return [];

            var paths = new PathInfo[pathCount];
            var modes = new ModeInfo[modeCount];
            result = QueryDisplayConfig(OnlyActivePaths, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
            if (result == 0)
                return paths.Take((int)pathCount);
            if (result != InsufficientBuffer)
                throw new Win32Exception(result, "无法读取 Windows 显示配置。");
        }

        throw new InvalidOperationException("显示配置正在变化，请重新检测。");
    }

    private static DeviceHeader Header<T>(uint type, Luid adapter, uint id) =>
        new() { Type = type, Size = (uint)Marshal.SizeOf<T>(), Adapter = adapter, Id = id };

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid { public uint Low; public int High; }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathSource { public Luid Adapter; public uint Id, Mode, Flags; }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathTarget
    {
        public Luid Adapter;
        public uint Id, Mode;
        public int Technology, Rotation, Scaling;
        public uint RefreshNumerator, RefreshDenominator;
        public int ScanLineOrdering, Available;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathInfo { public PathSource Source; public PathTarget Target; public uint Flags; }

    // DISPLAYCONFIG_MODE_INFO is a 16-byte header and 48-byte union. Only paths are read.
    [StructLayout(LayoutKind.Explicit, Size = 64)]
    private struct ModeInfo { [FieldOffset(0)] public ulong Alignment; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DeviceHeader { public uint Type, Size; public Luid Adapter; public uint Id; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SourceName
    {
        public DeviceHeader Header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct TargetName
    {
        public DeviceHeader Header;
        public uint Flags;
        public int Technology;
        public ushort Manufacturer, Product;
        public uint Connector;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Path;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfo
    {
        public uint Size;
        public Rect Bounds, WorkArea;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PhysicalMonitor
    {
        public IntPtr Handle;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
    }

    private delegate bool MonitorCallback(IntPtr monitor, IntPtr dc, IntPtr rect, IntPtr data);

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] paths,
                                                 ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topology);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int GetSourceName(ref SourceName name);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int GetTargetName(ref TargetName name);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorCallback callback, IntPtr data);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor, out uint count);

    [DllImport("dxva2.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor, uint count, out PhysicalMonitor physical);

    [DllImport("dxva2.dll")]
    private static extern bool DestroyPhysicalMonitor(IntPtr monitor);

    // Some drivers return 0 as a working physical-monitor handle.
    internal sealed class DdcHandle : SafeHandleMinusOneIsInvalid
    {
        public DdcHandle(IntPtr value) : base(true) => SetHandle(value);
        protected override bool ReleaseHandle() => DestroyPhysicalMonitor(handle);
    }
}
