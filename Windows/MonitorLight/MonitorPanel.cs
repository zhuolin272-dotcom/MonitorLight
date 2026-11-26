using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace MonitorLight;

internal sealed class MonitorPanel : Form
{
    private const int HotkeyUp = 1, HotkeyDown = 2;
    private const uint CtrlAltNoRepeat = 0x4003;
    private const int HotkeyMessage = 0x0312;

    private static readonly Color Paper = Color.FromArgb(247, 248, 245);
    private static readonly Color Ink = Color.FromArgb(23, 49, 44);
    private static readonly Color Muted = Color.FromArgb(73, 97, 88);

    private readonly ComboBox picker = new() { DropDownStyle = ComboBoxStyle.DropDownList, AccessibleName = "外接显示器" };
    private readonly TrackBar brightness = Slider("硬件亮度", 0, 100);
    private readonly TrackBar warmth = Slider("硬件冷暖", -100, 100);
    private readonly Label brightnessValue = Label("—", 10, true);
    private readonly Label warmthValue = Label("—", 10, true);
    private readonly Label displayStatus = Label("", 9);
    private readonly Label brightnessStatus = Label("", 9);
    private readonly Label colorStatus = Label("", 9);
    private readonly Label shortcutStatus = Label("", 9);
    private readonly Button refresh = Button("重新检测");
    private readonly Button[] brightnessPresets = [Button("低亮 15%"), Button("日常 45%"), Button("明亮 80%")];
    private readonly Button[] colorPresets = [Button("偏冷"), Button("标准"), Button("偏暖"), Button("恢复原色")];
    private readonly CheckBox colorOptIn = new() { Text = "启用蓝通道冷暖（未校准）", AutoSize = true };

    private readonly System.Windows.Forms.Timer writeTimer = new() { Interval = 220 };
    private readonly System.Windows.Forms.Timer topologyTimer = new() { Interval = 850 };
    private readonly MonitorSettings settings = new(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MonitorLight"));
    private readonly ContextMenuStrip trayMenu = new();
    private readonly NotifyIcon tray;
    private readonly Icon appIcon;

    private Level? currentBrightness;
    private Rgb? baseline;
    private Rgb? colorReading;
    private string? selectedId;
    private int? pendingBrightness;
    private int? pendingWarmth;
    private bool refreshingUi, busy, scanPending, exiting;
    private bool upRegistered, downRegistered;

    public MonitorPanel()
    {
        Text = "MonitorLight";
        appIcon = new Icon(typeof(MonitorPanel).Assembly.GetManifestResourceStream("MonitorLight.AppIcon.ico")!);
        Icon = appIcon;
        Font = new Font("Microsoft YaHei UI", 10);
        BackColor = Paper;
        ForeColor = Ink;
        AutoScaleDimensions = new SizeF(96, 96);
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MinimizeBox = MaximizeBox = false;
        ClientSize = new Size(436, 530);
        AutoScroll = true;

        var layout = new TableLayoutPanel
        {
            ColumnCount = 1, Dock = DockStyle.Top, AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink, Padding = new Padding(20, 12, 20, 14)
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        Controls.Add(layout);

        AddRow(layout, Label("MonitorLight", 20, true), 3);
        AddRow(layout, Label("外接显示器", 10, true), 5);
        AddRow(layout, Pair(picker, refresh), 4);
        AddRow(layout, displayStatus, 7);

        AddRow(layout, Section("硬件亮度", brightnessValue), 2);
        AddRow(layout, brightness, 2);
        AddRow(layout, Buttons(brightnessPresets), 4);
        AddRow(layout, brightnessStatus, 7);

        AddRow(layout, Section("硬件冷暖", warmthValue), 3);
        AddRow(layout, colorOptIn, 4);
        AddRow(layout, warmth, 2);
        AddRow(layout, Buttons(colorPresets), 4);
        AddRow(layout, colorStatus, 7);
        AddRow(layout, shortcutStatus, 0);

        trayMenu.Items.Add("打开面板", null, (_, _) => ShowPanel());
        trayMenu.Items.Add("重新检测", null, async (_, _) => await ScanAsync());
        trayMenu.Items.Add(new ToolStripSeparator());
        trayMenu.Items.Add("退出 MonitorLight", null, (_, _) => ExitApp());
        tray = new NotifyIcon { Text = "MonitorLight", Icon = appIcon, ContextMenuStrip = trayMenu, Visible = true };
        tray.MouseClick += (_, eventArgs) =>
        {
            if (eventArgs.Button != MouseButtons.Left)
                return;
            if (Visible)
                Hide();
            else
                ShowPanel();
        };

        refresh.Click += async (_, _) => await ScanAsync();
        picker.SelectedIndexChanged += async (_, _) =>
        {
            if (refreshingUi || picker.SelectedItem is not Display selected)
                return;
            CancelPendingWrites();
            selectedId = selected.Id;
            settings.SaveSelection(selected.Id);
            await RunAsync(ReloadReadingsAsync);
        };

        brightness.ValueChanged += (_, _) =>
        {
            if (!refreshingUi)
                QueueBrightness(brightness.Value);
        };
        warmth.ValueChanged += (_, _) =>
        {
            if (!refreshingUi)
                QueueWarmth(warmth.Value);
        };

        int[] brightnessValues = [15, 45, 80];
        int[] warmthValues = [-100, 0, 100, 0];
        for (int i = 0; i < brightnessPresets.Length; i++)
        {
            int value = brightnessValues[i];
            brightnessPresets[i].Click += (_, _) => QueueBrightness(value);
        }
        for (int i = 0; i < colorPresets.Length; i++)
        {
            int value = warmthValues[i];
            colorPresets[i].Click += (_, _) => QueueWarmth(value);
        }

        colorOptIn.CheckedChanged += (_, _) =>
        {
            if (!colorOptIn.Checked)
            {
                pendingWarmth = null;
                RenderReadings();
            }
            UpdateControls();
        };

        writeTimer.Tick += async (_, _) =>
        {
            writeTimer.Stop();
            await FlushWritesAsync();
        };
        topologyTimer.Tick += async (_, _) =>
        {
            topologyTimer.Stop();
            await ScanAsync();
        };

        statusLabels = [displayStatus, brightnessStatus, colorStatus, shortcutStatus];
        selectedId = settings.ReadSelection();
        UpdateControls();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        upRegistered = RegisterHotKey(Handle, HotkeyUp, CtrlAltNoRepeat, (uint)Keys.Up);
        downRegistered = RegisterHotKey(Handle, HotkeyDown, CtrlAltNoRepeat, (uint)Keys.Down);
        shortcutStatus.Text = upRegistered && downRegistered
            ? "Ctrl + Alt + ↑ / ↓  每次调节亮度 5%"
            : "快捷键注册不完整，仍可使用面板调节。";
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        if (upRegistered)
            UnregisterHotKey(Handle, HotkeyUp);
        if (downRegistered)
            UnregisterHotKey(Handle, HotkeyDown);
        base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == HotkeyMessage && !busy && !scanPending && currentBrightness is not null)
        {
            int id = message.WParam.ToInt32();
            if (id is HotkeyUp or HotkeyDown)
                QueueBrightness((pendingBrightness ?? currentBrightness.Value.Percent) + (id == HotkeyUp ? 5 : -5));
        }
        base.WndProc(ref message);
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!exiting && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnFormClosing(e);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            tray.Dispose();
            trayMenu.Dispose();
            writeTimer.Dispose();
            topologyTimer.Dispose();
            appIcon.Dispose();
        }
        base.Dispose(disposing);
    }

    public void ShowPanel()
    {
        if (Visible)
        {
            Activate();
            return;
        }

        var screen = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(screen.Right - Width - 16, screen.Bottom - Height - 12);
        Show();

        var bounds = Screen.FromHandle(Handle).WorkingArea;
        Size = new Size(Math.Min(LogicalToDeviceUnits(436), Math.Max(1, bounds.Width - 32)),
                        Math.Min(LogicalToDeviceUnits(385), Math.Max(1, bounds.Height - 24)));
        Location = new Point(bounds.Right - Width - 16, bounds.Bottom - Height - 12);
        Activate();
        _ = ScanAsync();
    }

    private void ExitApp()
    {
        exiting = true;
        Close();
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e) => ScheduleScan();
    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume)
            ScheduleScan();
    }

    private void ScheduleScan()
    {
        if (!IsHandleCreated || IsDisposed)
            return;
        try
        {
            BeginInvoke(() =>
            {
                CancelPendingWrites();
                topologyTimer.Stop();
                topologyTimer.Start();
                scanPending = true;
                UpdateControls();
            });
        }
        catch (InvalidOperationException) { }
    }

    private async Task ScanAsync()
    {
        scanPending = false;
        if (exiting)
            return;
        if (busy)
        {
            scanPending = true;
            return;
        }

        CancelPendingWrites();
        topologyTimer.Stop();
        await RunAsync(async () =>
        {
            Display[] displays;
            try { displays = await Task.Run(NativeDisplays.Enumerate); }
            catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                PopulatePicker([]);
                ResetReadings();
                displayStatus.Text = error.Message;
                return;
            }

            PopulatePicker(displays);
            displayStatus.Text = displays.Length == 0
                ? "未检测到可独立控制的外接屏。请检查连接，或将显示模式改为扩展。"
                : "";
            await ReloadReadingsAsync();
        });
    }

    private void PopulatePicker(Display[] displays)
    {
        refreshingUi = true;
        try
        {
            picker.Items.Clear();
            picker.Items.AddRange(displays);
            var preferred = displays.FirstOrDefault(d => StringComparer.OrdinalIgnoreCase.Equals(d.Id, selectedId));
            picker.SelectedItem = preferred ?? displays.FirstOrDefault();
        }
        finally { refreshingUi = false; }
    }

    private async Task ReloadReadingsAsync()
    {
        string? previouslyRead = readDisplayId;
        bool previousOptIn = colorOptIn.Checked;
        ResetReadings();
        if (picker.SelectedItem is not Display display)
            return;

        brightnessStatus.Text = "正在读取显示器…";
        var info = await Task.Run(() => Probe(display));
        if (exiting)
            return;
        readDisplayId = display.Id;
        currentBrightness = info.Brightness;
        colorReading = info.Color;
        baseline = info.Baseline;
        brightnessStatus.Text = info.BrightnessError ?? "";
        colorStatus.Text = info.ColorError ?? ColorDescription;
        colorOptIn.Checked = colorReading is not null &&
            (baseline is not null || (StringComparer.OrdinalIgnoreCase.Equals(previouslyRead, display.Id) && previousOptIn));
        RenderReadings();
    }

    private const string ColorDescription = "冷暖以原色为基准，只调蓝通道，幅度为蓝通道上限的 ±10%。";
    private string? readDisplayId;

    private (Level? Brightness, Rgb? Color, Rgb? Baseline, string? BrightnessError, string? ColorError)
        Probe(Display display)
    {
        try
        {
            using var handle = NativeDisplays.Open(display);
            var monitor = MonitorControl.ForHandle(handle);

            Level? light = null;
            string? lightError = null;
            try { light = monitor.ReadBrightness(); }
            catch (InvalidOperationException error) { lightError = error.Message; }

            try
            {
                var color = monitor.ReadColor();
                var saved = settings.ReadBaseline(display.Id);
                if (saved is not null && !saved.SameMode(color))
                    throw new InvalidOperationException("RGB 设置与原色记录不匹配，请切回保存原色时的显示器模式。");
                return (light, color, saved, lightError, null);
            }
            catch (InvalidOperationException error)
            {
                return (light, null, null, lightError, error.Message);
            }
        }
        catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return (null, null, null, error.Message, "当前无法读取 RGB。");
        }
    }

    private void ResetReadings()
    {
        currentBrightness = null;
        baseline = colorReading = null;
        readDisplayId = null;
        colorOptIn.Checked = false;
        brightnessStatus.Text = "";
        colorStatus.Text = "";
        RenderReadings();
    }

    private void QueueBrightness(int percent)
    {
        if (busy || scanPending || currentBrightness is null)
            return;
        pendingBrightness = Math.Clamp(percent, 0, 100);
        RenderReadings();
        RestartWriteTimer();
    }

    private void QueueWarmth(int value)
    {
        if (busy || scanPending || colorReading is null || !colorOptIn.Checked)
            return;
        pendingWarmth = Math.Clamp(value, -100, 100);
        RenderReadings();
        RestartWriteTimer();
    }

    private void RestartWriteTimer()
    {
        writeTimer.Stop();
        writeTimer.Start();
    }

    private void CancelPendingWrites()
    {
        writeTimer.Stop();
        pendingBrightness = pendingWarmth = null;
        RenderReadings();
    }

    private async Task FlushWritesAsync()
    {
        int? desiredBrightness = pendingBrightness;
        int? desiredWarmth = pendingWarmth;
        pendingBrightness = pendingWarmth = null;
        if (busy || scanPending || (desiredBrightness is null && desiredWarmth is null) ||
            picker.SelectedItem is not Display display)
            return;

        await RunAsync(async () =>
        {
            if (desiredBrightness is int pct)
            {
                brightnessStatus.Text = "正在写入并校验亮度…";
                try
                {
                    currentBrightness = await Task.Run(() =>
                    {
                        using var handle = NativeDisplays.Open(display);
                        return MonitorControl.ForHandle(handle).SetBrightness(pct);
                    });
                    brightnessStatus.Text = "";
                }
                catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
                {
                    brightnessStatus.Text = error.Message;
                    if (!Visible && !exiting)
                        tray.ShowBalloonTip(2500, "亮度调节失败", error.Message, ToolTipIcon.Warning);
                    await RefreshBrightnessAfterFailureAsync(display);
                }
            }

            if (desiredWarmth is int value && !scanPending && !exiting)
            {
                colorStatus.Text = "正在写入并校验冷暖…";
                try
                {
                    (colorReading, baseline) = await Task.Run(() => WriteWarmth(display, value));
                    colorStatus.Text = ColorDescription;
                }
                catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
                {
                    colorStatus.Text = error.Message;
                    var actual = await Task.Run(() => Probe(display));
                    colorReading = actual.Color;
                    baseline = actual.Baseline;
                }
            }

            RenderReadings();
        });
    }

    private async Task RefreshBrightnessAfterFailureAsync(Display display)
    {
        currentBrightness = await Task.Run<Level?>(() =>
        {
            try
            {
                using var handle = NativeDisplays.Open(display);
                return MonitorControl.ForHandle(handle).ReadBrightness();
            }
            catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                return null;
            }
        });
    }

    private (Rgb, Rgb?) WriteWarmth(Display display, int value)
    {
        using var handle = NativeDisplays.Open(display);
        var monitor = MonitorControl.ForHandle(handle);
        var before = monitor.ReadColor();
        var saved = settings.ReadBaseline(display.Id);
        if (saved is null)
        {
            if (value == 0 || before.BlueAt(value) == before.Blue.Current)
                return (before, null);

            settings.SaveBaseline(display.Id, before);
            saved = before;
        }

        return (monitor.SetWarmth(before, saved, value), saved);
    }

    private async Task RunAsync(Func<Task> action)
    {
        busy = true;
        UpdateControls();
        try { await action(); }
        finally
        {
            busy = false;
            if (!exiting)
            {
                UpdateControls();
                if (scanPending && !topologyTimer.Enabled)
                    await ScanAsync();
            }
        }
    }

    private void RenderReadings()
    {
        refreshingUi = true;
        try
        {
            int? pct = pendingBrightness ?? currentBrightness?.Percent;
            brightness.Value = pct ?? 0;
            brightnessValue.Text = pct is null ? "—" : $"{pct}%";
            int? temp = pendingWarmth ?? (colorReading is null ? null :
                baseline?.WarmthAt(colorReading.Blue.Current) ?? 0);
            warmth.Value = temp ?? 0;
            warmthValue.Text = temp switch
            {
                null => "—", 0 => "标准", < 0 => $"偏冷 {Math.Abs(temp.Value)}%", _ => $"偏暖 {temp}%"
            };
        }
        finally { refreshingUi = false; }
    }

    private void UpdateControls()
    {
        bool ready = !busy && !scanPending;
        picker.Enabled = ready && picker.Items.Count > 0;
        refresh.Enabled = !busy;
        brightness.Enabled = ready && currentBrightness is not null;
        foreach (var button in brightnessPresets)
            button.Enabled = brightness.Enabled;
        colorOptIn.Enabled = ready && colorReading is not null;
        warmth.Enabled = colorOptIn.Enabled && colorOptIn.Checked;
        foreach (var button in colorPresets)
            button.Enabled = warmth.Enabled;
        colorPresets[^1].Enabled = warmth.Enabled && baseline is not null;
    }

    private static Label Label(string text, float size, bool bold = false) => new()
    {
        Text = text, AutoSize = true, ForeColor = bold ? Ink : Muted,
        Font = new Font("Microsoft YaHei UI", size, bold ? FontStyle.Bold : FontStyle.Regular),
        Margin = Padding.Empty
    };

    private static Button Button(string text) => new()
    {
        Text = text, AutoSize = true, FlatStyle = FlatStyle.System,
        Padding = new Padding(4, 2, 4, 2), Margin = new Padding(0, 0, 6, 0)
    };

    private static TrackBar Slider(string label, int min, int max) => new()
    {
        Minimum = min, Maximum = max, TickStyle = TickStyle.None, AccessibleName = label,
        SmallChange = 1, LargeChange = 5, AutoSize = false, Height = 27, Margin = Padding.Empty
    };

    private readonly Label[] statusLabels;

    protected override void OnLayout(LayoutEventArgs levent)
    {
        if (statusLabels is not null)
        {
            int maxWidth = Math.Max(100, ClientSize.Width - LogicalToDeviceUnits(48));
            foreach (var status in statusLabels)
                status.MaximumSize = new Size(maxWidth, 0);
        }
        base.OnLayout(levent);
    }

    private static void AddRow(TableLayoutPanel layout, Control control, int gap)
    {
        control.Dock = DockStyle.Fill;
        control.Margin = new Padding(0, 0, 0, gap);
        layout.Controls.Add(control, 0, layout.RowCount++);
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
    }

    private static TableLayoutPanel Section(string title, Label value)
    {
        var titleLabel = Label(title, 11, true);
        value.Anchor = AnchorStyles.Right;
        return Pair(titleLabel, value);
    }

    private static TableLayoutPanel Pair(Control left, Control right)
    {
        var row = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Margin = Padding.Empty };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        left.Dock = DockStyle.Fill;
        left.Margin = new Padding(0, 0, 8, 0);
        right.Margin = Padding.Empty;
        row.Controls.Add(left, 0, 0);
        row.Controls.Add(right, 1, 0);
        return row;
    }

    private static FlowLayoutPanel Buttons(Button[] buttons)
    {
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = Padding.Empty };
        row.Controls.AddRange(buttons);
        return row;
    }

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr window, int id);
}
