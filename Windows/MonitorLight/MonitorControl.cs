using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MonitorLight;

internal readonly record struct Level(uint Current, uint Maximum)
{
    public bool IsValid => Maximum > 0 && Current <= Maximum;
    public int Percent => (int)Math.Round(100.0 * Current / Maximum, MidpointRounding.AwayFromZero);
    public uint AtPercent(int percent) =>
        (uint)Math.Round(Maximum * (Math.Clamp(percent, 0, 100) / 100.0), MidpointRounding.AwayFromZero);
}

internal sealed record Rgb(Level Red, Level Green, Level Blue)
{
    public bool IsValid => Red.IsValid && Green.IsValid && Blue.IsValid;

    public bool SameMode(Rgb other) =>
        Red == other.Red && Green == other.Green && Blue.Maximum == other.Blue.Maximum;

    public uint BlueAt(int warmth)
    {
        double offset = Blue.Maximum * 0.10 * Math.Clamp(warmth, -100, 100) / 100;
        return (uint)Math.Clamp(Math.Round(Blue.Current - offset, MidpointRounding.AwayFromZero), 0, Blue.Maximum);
    }

    public int WarmthAt(uint blue) =>
        (int)Math.Clamp(Math.Round((Blue.Current - (double)blue) * 1000 / Blue.Maximum), -100, 100);
}

internal sealed class MonitorControl
{
    internal const byte Brightness = 0x10;
    internal const byte RedGain = 0x16;
    internal const byte GreenGain = 0x18;
    internal const byte BlueGain = 0x1A;

    private readonly Func<byte, Level> read;
    private readonly Action<byte, uint> write;

    internal MonitorControl(Func<byte, Level> read, Action<byte, uint> write)
    {
        this.read = read;
        this.write = write;
    }

    internal Level ReadBrightness() => read(Brightness);
    internal Rgb ReadColor() => new(read(RedGain), read(GreenGain), read(BlueGain));

    internal Level SetBrightness(int percent)
    {
        Level before = ReadBrightness();
        uint target = before.AtPercent(percent);
        if (before.Current == target)
            return before;

        write(Brightness, target);
        for (int attempt = 0; attempt < 3; attempt++)
        {
            Thread.Sleep(80);
            Level actual = ReadBrightness();
            if (actual.Current == target && actual.Maximum == before.Maximum)
                return actual;
        }

        throw new InvalidOperationException("亮度写入后，读回值与目标不一致。");
    }

    internal Rgb SetWarmth(Rgb before, Rgb baseline, int warmth)
    {
        if (!baseline.SameMode(before))
            throw new InvalidOperationException("当前 RGB 设置与已保存的原色不匹配，请切回保存原色时的显示器模式。");

        uint target = baseline.BlueAt(warmth);
        if (before.Blue.Current == target)
            return before;

        try
        {
            write(BlueGain, target);
            return VerifyColor(before with { Blue = before.Blue with { Current = target } });
        }
        catch (InvalidOperationException error)
        {
            bool restored;
            try
            {
                write(BlueGain, before.Blue.Current);
                VerifyColor(before);
                restored = true;
            }
            catch (InvalidOperationException)
            {
                restored = false;
            }

            string result = restored ? "已恢复调节前的蓝通道。" : "无法确认已恢复调节前的蓝通道。";
            throw new InvalidOperationException($"{error.Message} {result}", error);
        }
    }

    private Rgb VerifyColor(Rgb expected)
    {
        for (int attempt = 0; attempt < 3; attempt++)
        {
            Thread.Sleep(80);
            try
            {
                var actual = ReadColor();
                if (actual == expected)
                    return actual;
            }
            catch (InvalidOperationException) when (attempt < 2)
            {
                // A monitor can briefly refuse reads while it applies a gain change.
            }
        }

        throw new InvalidOperationException("冷暖写入后，RGB 读回值与目标不一致。");
    }

    internal static MonitorControl ForHandle(NativeDisplays.DdcHandle handle)
    {
        var sinceCommand = new Stopwatch();

        // Some displays need a pause between transactions, even after the Win32 call returns.
        void WaitForMonitor()
        {
            if (sinceCommand.IsRunning)
            {
                long remaining = 65 - sinceCommand.ElapsedMilliseconds;
                if (remaining > 0)
                    Thread.Sleep((int)remaining);
            }
        }

        Level Read(byte code)
        {
            int error = 0;
            for (int attempt = 0; attempt < 3; attempt++)
            {
                WaitForMonitor();
                bool ok = GetVCPFeatureAndVCPFeatureReply(handle, code, out _, out uint current, out uint maximum);
                error = Marshal.GetLastWin32Error();
                sinceCommand.Restart();
                if (!ok)
                    continue;

                var level = new Level(current, maximum);
                if (!level.IsValid)
                    throw new InvalidOperationException($"VCP 0x{code:X2} 返回的范围无效。");
                return level;
            }

            throw DdcError("读取", code, error);
        }

        void Write(byte code, uint value)
        {
            WaitForMonitor();
            bool ok = SetVCPFeature(handle, code, value);
            int error = Marshal.GetLastWin32Error();
            sinceCommand.Restart();
            if (!ok)
                throw DdcError("写入", code, error);
        }

        return new MonitorControl(Read, Write);
    }

    private static InvalidOperationException DdcError(string action, byte code, int error) =>
        new($"显示器拒绝{action} VCP 0x{code:X2}（0x{error:X8}）。");

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetVCPFeatureAndVCPFeatureReply(NativeDisplays.DdcHandle handle, byte code,
        out int type, out uint current, out uint maximum);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool SetVCPFeature(NativeDisplays.DdcHandle handle, byte code, uint value);
}
