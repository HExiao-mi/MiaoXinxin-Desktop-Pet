using System.IO;
using System.Windows;

namespace MiaoXinxin.Windows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var requestedPack = e.Args.FirstOrDefault();
        var defaultPack = Path.Combine(AppContext.BaseDirectory, "Resources", "DefaultPet");
        var packPath = Directory.Exists(requestedPack) ? requestedPack! : defaultPack;
        var window = new MainWindow(AssetPack.Load(packPath));
        MainWindow = window;
        window.Show();
    }
}
