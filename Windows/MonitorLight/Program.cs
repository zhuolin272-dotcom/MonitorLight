namespace MonitorLight;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var singleInstance = new Mutex(true, @"Local\MonitorLight.Windows", out bool first);
        if (!first)
        {
            MessageBox.Show("MonitorLight 已在运行，请点击任务栏通知区域的太阳图标。",
                "MonitorLight", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize();
        using var panel = new MonitorPanel();
        using var context = new ApplicationContext(panel);
        panel.ShowPanel();
        Application.Run(context);
    }
}
