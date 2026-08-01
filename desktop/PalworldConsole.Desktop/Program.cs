using System.Diagnostics;
using System.Net;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace PalworldServerConsole;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new ConsoleHostForm(args));
    }
}

internal sealed class ConsoleHostForm : Form
{
    private const int StartupTimeoutSeconds = 30;
    private static readonly TimeSpan ProbeTimeout = TimeSpan.FromSeconds(2);

    private readonly string[] _arguments;
    private readonly HttpClient _httpClient = new() { Timeout = ProbeTimeout };
    private readonly WebView2 _webView = new() { Dock = DockStyle.Fill, Visible = false };
    private readonly Label _message = new()
    {
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleCenter,
        Padding = new Padding(28),
    };
    private readonly StatusStrip _status = new();
    private readonly ToolStripStatusLabel _statusLabel = new("正在准备本地控制台…");
    private string? _projectRoot;
    private Uri? _consoleUri;

    public ConsoleHostForm(string[] arguments)
    {
        _arguments = arguments;
        Text = "Palworld Server Console";
        MinimumSize = new Size(980, 700);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = SystemIcons.Application;

        var menu = new ToolStrip { GripStyle = ToolStripGripStyle.Hidden };
        var chooseProject = new ToolStripButton("选择服务器目录…");
        chooseProject.Click += async (_, _) => await ChooseProjectAsync();
        var reload = new ToolStripButton("重新加载面板");
        reload.Click += async (_, _) => await LoadConsoleAsync(requireSelection: false);
        var openBrowser = new ToolStripButton("在浏览器中打开");
        openBrowser.Click += (_, _) => OpenInBrowser(_consoleUri);
        menu.Items.AddRange([chooseProject, reload, new ToolStripSeparator(), openBrowser]);

        _status.Items.Add(_statusLabel);
        Controls.Add(_webView);
        Controls.Add(_message);
        Controls.Add(_status);
        Controls.Add(menu);

        _webView.CreationProperties = new CoreWebView2CreationProperties
        {
            UserDataFolder = Path.Combine(AppDataDirectory, "WebView2"),
        };
        Shown += async (_, _) => await LoadConsoleAsync(requireSelection: false);
        FormClosed += (_, _) => _httpClient.Dispose();
    }

    private static string AppDataDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "PalworldServerConsole");

    private static string SavedRootPath => Path.Combine(AppDataDirectory, "settings.json");

    private async Task ChooseProjectAsync()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "选择包含 settings-panel.ps1 与 docker-compose.yml 的 PalworldServer 目录",
            UseDescriptionForTitle = true,
            InitialDirectory = _projectRoot ?? Environment.CurrentDirectory,
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        if (!IsProjectRoot(dialog.SelectedPath))
        {
            ShowMessage("所选目录不是 PalworldServer 项目目录。需要 settings-panel.ps1、docker-compose.yml、web/index.html 与 .env。", error: true);
            return;
        }
        _projectRoot = Path.GetFullPath(dialog.SelectedPath);
        SaveProjectRoot(_projectRoot);
        await LoadConsoleAsync(requireSelection: false);
    }

    private async Task LoadConsoleAsync(bool requireSelection)
    {
        _webView.Visible = false;
        _message.Visible = true;
        _projectRoot = ResolveProjectRoot(_arguments) ?? LoadSavedProjectRoot() ?? _projectRoot;
        if (!IsProjectRoot(_projectRoot))
        {
            ShowMessage("请选择 PalworldServer 项目目录，然后桌面应用会启动或连接本地 Web Console。", error: false);
            if (requireSelection) await ChooseProjectAsync();
            return;
        }

        try
        {
            ShowMessage("正在连接本地 Web Console…", error: false);
            _consoleUri = await EnsureConsoleAsync(_projectRoot!);
            await EnsureWebViewAsync();
            _webView.Source = _consoleUri;
            _webView.Visible = true;
            _message.Visible = false;
            _statusLabel.Text = $"已连接本地控制台：{_consoleUri.Host}:{_consoleUri.Port}。Docker 与 Windows 运行时均由同一受保护后端管理。";
        }
        catch (WebView2RuntimeNotFoundException)
        {
            ShowWebViewRuntimeHelp();
        }
        catch (Exception error)
        {
            ShowMessage($"无法打开本地 Web Console。{Environment.NewLine}{Environment.NewLine}{error.Message}{Environment.NewLine}{Environment.NewLine}请确认项目目录和 .env 有效；此应用不会绕过运行时切换、保存或权限检查。", error: true);
        }
    }

    private async Task<Uri> EnsureConsoleAsync(string projectRoot)
    {
        var existing = await FindReachableConsoleAsync(projectRoot);
        if (existing is not null) return existing;

        var scriptPath = Path.Combine(projectRoot, "settings-panel.ps1");
        var start = new ProcessStartInfo("powershell.exe")
        {
            WorkingDirectory = projectRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-ExecutionPolicy");
        start.ArgumentList.Add("Bypass");
        start.ArgumentList.Add("-File");
        start.ArgumentList.Add(scriptPath);
        if (Process.Start(start) is null)
        {
            throw new InvalidOperationException("settings-panel.ps1 无法启动。");
        }

        var deadline = DateTimeOffset.UtcNow.AddSeconds(StartupTimeoutSeconds);
        while (DateTimeOffset.UtcNow < deadline)
        {
            await Task.Delay(500);
            var endpoint = await FindReachableConsoleAsync(projectRoot);
            if (endpoint is not null) return endpoint;
        }
        throw new TimeoutException($"Web Console 未在 {StartupTimeoutSeconds} 秒内就绪。请检查 data\\log-sources\\panel 下的本地日志。");
    }

    private async Task<Uri?> FindReachableConsoleAsync(string projectRoot)
    {
        var portPath = Path.Combine(projectRoot, ".settings-panel.port");
        var candidates = new List<int>();
        if (File.Exists(portPath) && int.TryParse((await File.ReadAllTextAsync(portPath)).Trim(), out var storedPort))
        {
            candidates.Add(storedPort);
        }
        candidates.AddRange([8213, 8214, 18213]);

        foreach (var port in candidates.Distinct())
        {
            if (port is < 1 or > 65535) continue;
            var candidate = new UriBuilder(Uri.UriSchemeHttp, "localhost", port, "/").Uri;
            try
            {
                // Dashboard construction may wait on Docker, REST, and tunnel
                // telemetry. The runtime endpoint is a bounded, read-only
                // readiness probe and is the same endpoint used by the local
                // launcher.
                using var response = await _httpClient.GetAsync(new Uri(candidate, "api/runtime"));
                if (response.StatusCode == HttpStatusCode.OK) return candidate;
            }
            catch (HttpRequestException) { }
            catch (TaskCanceledException) { }
        }
        return null;
    }

    private async Task EnsureWebViewAsync()
    {
        if (_webView.CoreWebView2 is null)
        {
            await _webView.EnsureCoreWebView2Async();
            var core = _webView.CoreWebView2 ?? throw new InvalidOperationException("WebView2 初始化未返回浏览器实例。");
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.AreDefaultContextMenusEnabled = true;
            core.NavigationStarting += (_, args) =>
            {
                if (IsLocalConsoleUri(args.Uri)) return;
                args.Cancel = true;
                OpenInBrowser(new Uri(args.Uri));
            };
            core.NewWindowRequested += (_, args) =>
            {
                args.Handled = true;
                OpenInBrowser(new Uri(args.Uri));
            };
        }
    }

    private bool IsLocalConsoleUri(string address)
    {
        if (!Uri.TryCreate(address, UriKind.Absolute, out var uri)) return false;
        return uri.Scheme == Uri.UriSchemeHttp && uri.IsLoopback && _consoleUri is not null && uri.Port == _consoleUri.Port;
    }

    private void OpenInBrowser(Uri? address)
    {
        if (address is null) return;
        try
        {
            Process.Start(new ProcessStartInfo(address.ToString()) { UseShellExecute = true });
        }
        catch (Exception error)
        {
            ShowMessage($"无法打开浏览器：{error.Message}", error: true);
        }
    }

    private void ShowWebViewRuntimeHelp()
    {
        const string runtimeUrl = "https://developer.microsoft.com/microsoft-edge/webview2/";
        ShowMessage("未检测到 Microsoft Edge WebView2 Runtime。请安装 Evergreen Runtime 后重新打开此应用。应用和服务器均未被修改。", error: true);
        _statusLabel.Text = "需要 Microsoft Edge WebView2 Runtime。";
        var result = MessageBox.Show(this,
            "需要 Microsoft Edge WebView2 Runtime 才能嵌入本地控制台。是否在默认浏览器中打开官方安装页？",
            "缺少 WebView2 Runtime", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
        if (result == DialogResult.Yes) OpenInBrowser(new Uri(runtimeUrl));
    }

    private void ShowMessage(string message, bool error)
    {
        _message.Text = message;
        _message.ForeColor = error ? Color.Firebrick : SystemColors.ControlText;
        _statusLabel.Text = error ? "桌面宿主未连接；服务器状态没有被此操作改变。" : "正在准备本地控制台…";
    }

    private static bool IsProjectRoot(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path)) return false;
        return File.Exists(Path.Combine(path, "settings-panel.ps1")) &&
               File.Exists(Path.Combine(path, "docker-compose.yml")) &&
               File.Exists(Path.Combine(path, ".env")) &&
               File.Exists(Path.Combine(path, "web", "index.html"));
    }

    private static string? ResolveProjectRoot(IEnumerable<string> arguments)
    {
        var values = arguments.ToArray();
        for (var index = 0; index < values.Length - 1; index += 1)
        {
            if (string.Equals(values[index], "--project-root", StringComparison.OrdinalIgnoreCase) && IsProjectRoot(values[index + 1]))
            {
                return Path.GetFullPath(values[index + 1]);
            }
        }
        foreach (var start in new[] { Environment.CurrentDirectory, AppContext.BaseDirectory })
        {
            var directory = new DirectoryInfo(start);
            for (var level = 0; directory is not null && level < 8; level += 1, directory = directory.Parent)
            {
                if (IsProjectRoot(directory.FullName)) return directory.FullName;
            }
        }
        return null;
    }

    private static string? LoadSavedProjectRoot()
    {
        try
        {
            if (!File.Exists(SavedRootPath)) return null;
            var saved = JsonSerializer.Deserialize<SavedSettings>(File.ReadAllText(SavedRootPath));
            var savedRoot = saved?.ProjectRoot;
            return IsProjectRoot(savedRoot) ? savedRoot : null;
        }
        catch (JsonException) { return null; }
        catch (IOException) { return null; }
    }

    private static void SaveProjectRoot(string projectRoot)
    {
        Directory.CreateDirectory(AppDataDirectory);
        var json = JsonSerializer.Serialize(new SavedSettings(projectRoot));
        File.WriteAllText(SavedRootPath, json);
    }

    private sealed record SavedSettings(string ProjectRoot);
}
