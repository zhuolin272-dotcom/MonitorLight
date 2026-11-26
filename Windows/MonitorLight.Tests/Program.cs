using MonitorLight;

if (args is ["--probe"])
{
    Display[] displays = NativeDisplays.Enumerate();
    Console.WriteLine($"Independent external displays: {displays.Length}");
    foreach (Display display in displays)
    {
        Console.WriteLine(display);
        try
        {
            using var handle = NativeDisplays.Open(display);
            var monitor = MonitorControl.ForHandle(handle);
            Console.WriteLine($"Brightness: {monitor.ReadBrightness().Percent}%");
            Console.WriteLine($"RGB: {monitor.ReadColor()}");
        }
        catch (InvalidOperationException error)
        {
            Console.WriteLine(error.Message);
        }
    }
    return;
}

const byte light = MonitorControl.Brightness, red = MonitorControl.RedGain,
    green = MonitorControl.GreenGain, blue = MonitorControl.BlueGain;
var testLevels = new Dictionary<byte, Level>
{
    [light] = new(120, 200), [red] = new(44, 100), [green] = new(44, 100), [blue] = new(50, 100)
};
var writes = new List<(byte, uint)>();
void Set(byte channel, uint value)
{
    writes.Add((channel, value));
    testLevels[channel] = testLevels[channel] with { Current = value };
}

var control = new MonitorControl(code => testLevels[code], Set);
var baseline = control.ReadColor();
Require(writes.Count == 0, "Reading controls never writes");
Require(control.ReadBrightness().Percent == 60, "Brightness uses the monitor maximum");
Require(control.SetBrightness(45).Current == 90 && writes.SequenceEqual(new[] { (light, 90u) }),
    "Brightness presets map to the hardware range");
writes.Clear();
Require(control.SetWarmth(baseline, baseline, 100).Blue.Current == 40, "Warm endpoint");
Require(control.SetWarmth(control.ReadColor(), baseline, -50).Blue.Current == 55, "Cold midpoint");
Require(control.SetWarmth(control.ReadColor(), baseline, 0) == baseline, "Restore exact original blue");
Require(writes.SequenceEqual(new[] { (blue, 40u), (blue, 55u), (blue, 50u) }), "Never write red or green");
Require((baseline with { Blue = new(99, 100) }).BlueAt(-100) == 100, "Clamp the cold endpoint");
Require((baseline with { Blue = new(3, 100) }).BlueAt(100) == 0, "Clamp the warm endpoint");

writes.Clear();
testLevels[green] = new(45, 100);
ExpectFailure(() => control.SetWarmth(control.ReadColor(), baseline, 100), "不匹配");
Require(writes.Count == 0, "Different RGB mode must cause zero writes");
testLevels[green] = baseline.Green;

var mismatch = new MonitorControl(code => testLevels[code], (channel, value) =>
{
    Set(channel, value == 40 ? 41u : value);
});
ExpectFailure(() => mismatch.SetWarmth(baseline, baseline, 100), "已恢复");
Require(mismatch.ReadColor() == baseline && writes.SequenceEqual(new[] { (blue, 41u), (blue, 50u) }),
    "Rollback restores the preceding blue value");

string temporary = Path.Combine(Path.GetTempPath(), "MonitorLight.Tests", Guid.NewGuid().ToString("N"));
try
{
    var settings = new MonitorSettings(temporary);
    Require(settings.ReadBaseline("DISPLAY-A") is null, "Missing original is detected");
    settings.SaveBaseline("Display-A", baseline);
    Require(new MonitorSettings(temporary).ReadBaseline("display-a") == baseline, "Original survives restart");
    Require(settings.ReadBaseline("DISPLAY-B") is null, "Display IDs isolate originals");
    ExpectFailure(() => settings.SaveBaseline("display-a", baseline with { Blue = new(40, 100) }), "无法保存");
    Require(settings.ReadBaseline("DISPLAY-A") == baseline, "An existing original is never overwritten");
    File.WriteAllText(Directory.GetFiles(temporary, "*.json").Single(), "{}");
    ExpectFailure(() => settings.ReadBaseline("DISPLAY-A"), "已停用");
}
finally
{
    if (Directory.Exists(temporary))
        Directory.Delete(temporary, recursive: true);
}

Require(NativeDisplays.IsExternalConnector(5) && NativeDisplays.IsExternalConnector(10)
    && NativeDisplays.IsExternalConnector(18), "Allow HDMI, DisplayPort and tunneled DisplayPort");
Require(new[] { -1, 6, 11, 13, 15, 16, 17, int.MinValue }.All(x => !NativeDisplays.IsExternalConnector(x)),
    "Exclude unknown, embedded, network and virtual routes");

Console.WriteLine("MonitorLight: all Windows checks passed.");

static void Require(bool condition, string message)
{
    if (!condition)
        throw new Exception(message);
}

static void ExpectFailure(Action operation, string expectedMessage)
{
    try { operation(); }
    catch (InvalidOperationException error) when (error.Message.Contains(expectedMessage)) { return; }
    throw new Exception($"Expected failure containing: {expectedMessage}");
}
