namespace Metra.Host;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        try
        {
            var app = TrayApp.Start(args);
            Application.Run(app);
        }
        catch (InvalidOperationException ex) when (
            ex.Message.Contains("already running", StringComparison.OrdinalIgnoreCase))
        {
            // Second Start Menu click opens browser via bridge; exit quietly.
            Environment.ExitCode = 0;
        }
        catch (Exception ex)
        {
            HostLog.Write($"MetraHost failed to start - {ex}", "error");
            MessageBox.Show(
                ex.Message,
                "Metra Ops Host",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            Environment.ExitCode = 1;
        }
    }
}
