import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import local.kara.settingsredirector.AppEntry;
import local.kara.settingsredirector.DeveloperFacts;

public final class TestKaraSettingsModels {
    public static void main(String[] args) {
        AppEntry userZulu = new AppEntry("Zulu", "org.example.zulu", "1.0", false, true);
        AppEntry userAlpha = new AppEntry("alpha", "org.example.alpha", "2.0", false, false);
        AppEntry systemAlpha = new AppEntry("Alpha", "com.android.alpha", "3.0", true, true);
        List<AppEntry> entries = new ArrayList<AppEntry>();
        entries.add(systemAlpha);
        entries.add(userZulu);
        entries.add(userAlpha);
        Collections.sort(entries, AppEntry.ORDER);
        assert entries.get(0) == userAlpha : "user apps sort before system apps";
        assert entries.get(1) == userZulu : "user apps sort by label";
        assert entries.get(2) == systemAlpha : "system app sorts last";
        assert userZulu.canUninstall("local.kara.settingsredirector") : "third-party app can uninstall";
        assert !systemAlpha.canUninstall("local.kara.settingsredirector") : "system app cannot uninstall";
        assert !new AppEntry("Kara", "local.kara.settingsredirector", "6.0", false, true)
                .canUninstall("local.kara.settingsredirector") : "hub cannot uninstall itself";
        assert "alpha — 2.0".equals(userAlpha.rowLabel()) : "version is visible";

        assert "ADB debugging: Enabled".equals(DeveloperFacts.adbLabel(1));
        assert "ADB debugging: Disabled".equals(DeveloperFacts.adbLabel(0));
        assert "ADB debugging: Unknown".equals(DeveloperFacts.adbLabel(-1));
        assert "USB configuration: adb".equals(DeveloperFacts.usbLabel("adb\n"));
        assert "TCP ADB port: 5555".equals(DeveloperFacts.tcpLabel("5555"));
        assert "TCP ADB port: Not active".equals(DeveloperFacts.tcpLabel("-1"));
        assert "Wi-Fi ADB endpoint: 192.0.2.65:5555".equals(
                DeveloperFacts.endpointLabel("192.0.2.65", "5555"));
        assert "Wi-Fi ADB endpoint: Unavailable".equals(DeveloperFacts.endpointLabel("", "5555"));
        System.out.println("KARA_SETTINGS_MODEL_GATE=PASS");
    }
}
