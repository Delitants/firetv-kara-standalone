package local.kara.settingsredirector;

import android.Manifest;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.net.wifi.ScanResult;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.widget.EditText;
import android.widget.ListView;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@SuppressWarnings("deprecation") // These configuration APIs are public on the pinned API 28.
public final class NetworkActivity extends TvListActivity {
    private static final int LOCATION_REQUEST = 31;
    private WifiManager wifi;
    private boolean receiverRegistered;
    private boolean permissionRequested;
    private boolean permissionDenied;
    private List<WifiEntry> entries = new ArrayList<WifiEntry>();
    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            if (WifiManager.SCAN_RESULTS_AVAILABLE_ACTION.equals(action)
                    || WifiManager.NETWORK_STATE_CHANGED_ACTION.equals(action)) refreshRows();
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (state != null) {
            permissionRequested = state.getBoolean("permissionRequested");
            permissionDenied = state.getBoolean("permissionDenied");
        }
    }

    @Override protected void onSaveInstanceState(Bundle state) {
        state.putBoolean("permissionRequested", permissionRequested);
        state.putBoolean("permissionDenied", permissionDenied);
        super.onSaveInstanceState(state);
    }

    @Override protected void onResume() {
        super.onResume();
        if (!receiverRegistered) {
            IntentFilter filter = new IntentFilter();
            filter.addAction(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION);
            filter.addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION);
            registerReceiver(receiver, filter);
            receiverRegistered = true;
        }
        refreshRows();
        if (hasLocationPermission()) scanWithPermission();
        else if (!permissionRequested) requestScan();
    }

    @Override protected void onPause() {
        if (receiverRegistered) {
            unregisterReceiver(receiver);
            receiverRegistered = false;
        }
        super.onPause();
    }

    private boolean hasLocationPermission() {
        return checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestScan() {
        if (hasLocationPermission()) {
            permissionDenied = false;
            scanWithPermission();
        } else if (permissionDenied) {
            showMessage("Scan unavailable", "Location permission is required to scan for Wi-Fi networks on Android 9. Permission was denied. Wi-Fi status remains available; grant Location permission in the app permissions before scanning again.");
        } else if (!permissionRequested) {
            permissionRequested = true;
            requestPermissions(new String[] {Manifest.permission.ACCESS_COARSE_LOCATION}, LOCATION_REQUEST);
        } else {
            showMessage("Scan unavailable", "Location permission is required. Complete the pending permission request before scanning again.");
        }
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != LOCATION_REQUEST) return;
        boolean granted = permissions.length == 1 && grantResults.length == 1
                && Manifest.permission.ACCESS_COARSE_LOCATION.equals(permissions[0])
                && grantResults[0] == PackageManager.PERMISSION_GRANTED && hasLocationPermission();
        permissionDenied = !granted;
        refreshRows();
        if (granted) scanWithPermission();
    }

    private void scanWithPermission() {
        if (!hasLocationPermission()) return;
        if (wifi == null) {
            showMessage("Wi-Fi unavailable", "Wi-Fi service is unavailable.");
            return;
        }
        try {
            if (!wifi.startScan()) showMessage("Scan unavailable", "Scan could not be started. Wi-Fi may be off, Location services may be disabled, or scanning may be throttled. Try again later.");
        } catch (SecurityException denied) {
            showMessage("Scan unavailable", "Wi-Fi scanning was denied by the system. Check Location permission and Location services.");
        }
        refreshRows();
    }

    private void refreshRows() {
        boolean enabled = false;
        WifiInfo info = null;
        if (wifi != null) {
            try {
                enabled = wifi.isWifiEnabled();
                info = wifi.getConnectionInfo();
            } catch (SecurityException denied) { /* Keep the informational rows available. */ }
        }
        String connected = connectionName(info);
        // Read public WifiInfo data here; connectionName rejects unknown or disconnected SSIDs.
        String reportedSsid = info == null ? "" : WifiEntry.unquote(info.getSSID());
        if (reportedSsid.trim().isEmpty()) connected = "";
        ArrayList<String> rows = new ArrayList<String>();
        rows.add("Wi-Fi: " + (enabled ? "On" : "Off"));
        rows.add("Connected: " + (connected.isEmpty() ? "Not connected" : connected));
        rows.add("IP: " + (connected.isEmpty() || info == null ? "Unavailable" : ipv4(info.getIpAddress())));
        rows.add("Scan again");
        entries = readEntries(connected);
        for (WifiEntry entry : entries) {
            rows.add(entry.getSsid() + "  |  " + entry.getSignalLevel() + " dBm  |  " + securityLabel(entry));
        }
        setRows("Network", rows);
    }

    private static String connectionName(WifiInfo info) {
        if (info == null || info.getNetworkId() < 0) return "";
        String ssid = WifiEntry.unquote(info.getSSID());
        return ssid.trim().isEmpty() || "<unknown ssid>".equalsIgnoreCase(ssid) ? "" : ssid;
    }

    private static String ipv4(int value) {
        if (value == 0) return "Unavailable";
        return (value & 255) + "." + ((value >>> 8) & 255) + "." + ((value >>> 16) & 255) + "." + ((value >>> 24) & 255);
    }

    private List<WifiEntry> readEntries(final String connected) {
        Map<String, WifiEntry> strongest = new HashMap<String, WifiEntry>();
        Map<String, Integer> saved = new HashMap<String, Integer>();
        if (wifi == null || !hasLocationPermission()) return new ArrayList<WifiEntry>();
        try {
            List<WifiConfiguration> configurations = wifi.getConfiguredNetworks();
            if (configurations != null) for (WifiConfiguration config : configurations) {
                if (config == null || config.networkId < 0) continue;
                String name = WifiEntry.unquote(config.SSID);
                Integer previous = saved.get(name);
                if (previous == null || config.networkId < previous) saved.put(name, config.networkId);
            }
            List<ScanResult> scans = wifi.getScanResults();
            if (scans != null) for (ScanResult scan : scans) {
                if (scan == null) continue;
                String name = WifiEntry.unquote(scan.SSID);
                if (name.trim().isEmpty()) continue;
                Integer id = saved.get(name);
                WifiEntry entry = new WifiEntry(scan.SSID, scan.BSSID, scan.level, scan.capabilities, id == null ? -1 : id);
                WifiEntry previous = strongest.get(name);
                if (previous == null || entry.getSignalLevel() > previous.getSignalLevel()
                        || (entry.getSignalLevel() == previous.getSignalLevel()
                        && entry.getBssid().compareTo(previous.getBssid()) < 0)) strongest.put(name, entry);
            }
        } catch (SecurityException denied) { /* Permission may be revoked between check and read. */ }
        List<WifiEntry> result = new ArrayList<WifiEntry>(strongest.values());
        Collections.sort(result, new Comparator<WifiEntry>() {
            @Override public int compare(WifiEntry a, WifiEntry b) {
                boolean ac = !connected.isEmpty() && connected.equals(a.getSsid());
                boolean bc = !connected.isEmpty() && connected.equals(b.getSsid());
                if (ac != bc) return ac ? -1 : 1;
                int signal = Integer.compare(b.getSignalLevel(), a.getSignalLevel());
                if (signal != 0) return signal;
                int name = a.getSsid().compareToIgnoreCase(b.getSsid());
                return name != 0 ? name : a.getSsid().compareTo(b.getSsid());
            }
        });
        return result;
    }

    private static String securityLabel(WifiEntry entry) {
        WifiSecurity.Kind kind = WifiSecurity.classify(entry.getCapabilities());
        if (kind == WifiSecurity.Kind.OPEN) return "Open";
        if (kind == WifiSecurity.Kind.PSK) return "Secured";
        return "Unsupported security";
    }

    @Override protected void onListItemClick(ListView list, View view, int position, long id) {
        if (position < 0) return;
        if (position == 3) { requestScan(); return; }
        int index = position - 4;
        if (index < 0 || index >= entries.size()) return;
        showNetwork(entries.get(index));
    }

    private void showNetwork(final WifiEntry entry) {
        WifiSecurity.Kind kind = WifiSecurity.classify(entry.getCapabilities());
        if (kind == WifiSecurity.Kind.UNSUPPORTED) {
            showMessage(entry.getSsid(), "Unsupported security. Only open and WPA/WPA2 personal PSK networks are supported; enterprise, WEP, SAE and other security modes cannot be configured here.");
            return;
        }
        if (entry.getSavedNetworkId() >= 0) {
            new AlertDialog.Builder(this).setTitle(entry.getSsid())
                    .setItems(new String[] {"Connect", "Forget"}, new DialogInterface.OnClickListener() {
                        @Override public void onClick(DialogInterface dialog, int which) {
                            if (which == 0) connectId(entry.getSavedNetworkId());
                            else if (which == 1) confirmForget(entry);
                        }
                    }).show();
        } else if (kind == WifiSecurity.Kind.OPEN) connectOpen(entry);
        else showPassword(entry);
    }

    private static String quote(String value) {
        // API 28 strips the enclosing pair; interior characters are literal bytes.
        return "\"" + value + "\"";
    }

    private void connectOpen(WifiEntry entry) {
        if (wifi == null) { showMessage("Connection failed", "Wi-Fi service is unavailable."); return; }
        WifiConfiguration config = new WifiConfiguration();
        config.SSID = quote(entry.getSsid());
        config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE);
        try { connectId(wifi.addNetwork(config)); }
        catch (SecurityException denied) { showMessage("Connection failed", "The system denied saving this Wi-Fi network."); }
    }

    private void showPassword(final WifiEntry entry) {
        final EditText password = new EditText(this);
        password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        password.setSaveEnabled(false);
        password.setSingleLine(true);
        final AlertDialog dialog = new AlertDialog.Builder(this).setTitle(entry.getSsid())
                .setMessage("Enter the Wi-Fi password (8-63 characters).")
                .setView(password).setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton("Connect", null).create();
        dialog.setOnDismissListener(new DialogInterface.OnDismissListener() {
            @Override public void onDismiss(DialogInterface dismissed) { password.setText(""); }
        });
        dialog.show();
        dialog.getButton(DialogInterface.BUTTON_POSITIVE).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) {
                if (connectPsk(entry, password)) dialog.dismiss();
            }
        });
        password.requestFocus();
    }

    private boolean connectPsk(WifiEntry entry, EditText password) {
        String value = password.getText().toString();
        if (value.length() < 8 || value.length() > 63) {
            password.setError("Password must contain 8-63 characters.");
            return false;
        }
        if (wifi == null) { showMessage("Connection failed", "Wi-Fi service is unavailable."); return false; }
        WifiConfiguration config = new WifiConfiguration();
        config.SSID = quote(entry.getSsid());
        config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK);
        config.preSharedKey = quote(value);
        try { connectId(wifi.addNetwork(config)); }
        catch (SecurityException denied) { showMessage("Connection failed", "The system denied saving this Wi-Fi network."); }
        return true;
    }

    private void connectId(int networkId) {
        if (networkId < 0) { showMessage("Connection failed", "Could not save this Wi-Fi network."); return; }
        if (wifi == null) { showMessage("Connection failed", "Wi-Fi service is unavailable."); return; }
        try {
            if (!wifi.enableNetwork(networkId, true)) { showMessage("Connection failed", "Could not enable this Wi-Fi network."); return; }
            if (!wifi.reconnect()) { showMessage("Connection failed", "Could not reconnect to Wi-Fi."); return; }
            // Status broadcasts report the actual connection; API acceptance is not success.
            refreshRows();
        } catch (SecurityException denied) { showMessage("Connection failed", "The system denied connecting to this Wi-Fi network."); }
    }

    private void confirmForget(final WifiEntry entry) {
        new AlertDialog.Builder(this).setTitle("Forget " + entry.getSsid() + "?")
                .setMessage("Remove the saved Wi-Fi configuration for this network?")
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton("Forget", new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface dialog, int which) {
                        forgetNetwork(entry.getSavedNetworkId());
                    }
                }).show();
    }

    private void forgetNetwork(int networkId) {
        if (wifi == null || networkId < 0) { showMessage("Forget failed", "Saved Wi-Fi network is unavailable."); return; }
        try {
            if (!wifi.removeNetwork(networkId)) { showMessage("Forget failed", "Could not forget this Wi-Fi network."); return; }
            if (!wifi.saveConfiguration()) showMessage("Forget failed", "Could not save the Wi-Fi configuration after removal.");
            refreshRows();
            scanWithPermission();
        } catch (SecurityException denied) { showMessage("Forget failed", "The system denied removing this Wi-Fi network."); }
    }
}
