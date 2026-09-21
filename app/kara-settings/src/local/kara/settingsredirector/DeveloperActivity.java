package local.kara.settingsredirector;

import android.content.Context;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.widget.ListView;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.Arrays;

public final class DeveloperActivity extends TvListActivity {
    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
    }

    @Override protected void onResume() {
        super.onResume();
        int adbEnabled;
        try { adbEnabled = Settings.Global.getInt(getContentResolver(), Settings.Global.ADB_ENABLED); }
        catch (Settings.SettingNotFoundException missing) { adbEnabled = -1; }
        String usbConfig = readProperty("sys.usb.config");
        String tcpPort = readProperty("service.adb.tcp.port");
        if (tcpPort.isEmpty()) tcpPort = readProperty("persist.adb.tcp.port");
        String address = wifiAddress();
        setRows("Developer & ADB", Arrays.asList(
                DeveloperFacts.adbLabel(adbEnabled),
                DeveloperFacts.usbLabel(usbConfig),
                DeveloperFacts.tcpLabel(tcpPort),
                DeveloperFacts.endpointLabel(address, tcpPort),
                "ADB controls are protected by Android"));
    }

    @Override protected void onListItemClick(ListView list, View view, int position, long id) {
        showMessage("Developer & ADB",
                "This screen reports the live debugging state without granting Kara Settings broad secure-settings privileges. "
                + "The installer preserves ADB access. Change or restart ADB from an authorized host connection.");
    }

    private String wifiAddress() {
        WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifi == null) return "";
        try {
            WifiInfo info = wifi.getConnectionInfo();
            return info == null ? "" : DeveloperFacts.ipv4(info.getIpAddress());
        } catch (SecurityException denied) { return ""; }
    }

    private static String readProperty(String name) {
        Process process = null;
        BufferedReader reader = null;
        try {
            process = new ProcessBuilder("/system/bin/getprop", name).start();
            reader = new BufferedReader(new InputStreamReader(process.getInputStream(), "UTF-8"));
            String value = reader.readLine();
            process.waitFor();
            return value == null ? "" : value.trim();
        } catch (IOException unavailable) {
            return "";
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            return "";
        } finally {
            if (reader != null) try { reader.close(); } catch (IOException ignored) { }
            if (process != null) process.destroy();
        }
    }
}
