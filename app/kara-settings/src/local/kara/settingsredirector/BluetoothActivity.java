package local.kara.settingsredirector;

import android.Manifest;
import android.app.AlertDialog;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.view.View;
import android.widget.ListView;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

public final class BluetoothActivity extends TvListActivity {
    private static final int LOCATION_REQUEST = 41;
    private static final Comparator<BluetoothEntry> ORDER = new Comparator<BluetoothEntry>() {
        @Override public int compare(BluetoothEntry a, BluetoothEntry b) { return BluetoothEntry.compare(a, b); }
    };
    private BluetoothAdapter adapter;
    private boolean receiverRegistered;
    private boolean permissionRequested;
    private boolean permissionDenied;
    private boolean discovering;
    private AlertDialog pairDialog;
    private final Map<String, BluetoothEntry> models = new HashMap<String, BluetoothEntry>();
    private final Map<String, BluetoothDevice> devices = new HashMap<String, BluetoothDevice>();
    private List<BluetoothEntry> entries = new ArrayList<BluetoothEntry>();
    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { handleBroadcast(intent); }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        adapter = BluetoothAdapter.getDefaultAdapter();
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
            filter.addAction(BluetoothDevice.ACTION_FOUND);
            filter.addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED);
            filter.addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);
            filter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED);
            registerReceiver(receiver, filter);
            receiverRegistered = true;
        }
        refreshBonded();
        refreshRows();
    }

    @Override protected void onPause() {
        cancelDiscovery();
        if (receiverRegistered) {
            unregisterReceiver(receiver);
            receiverRegistered = false;
        }
        if (pairDialog != null) {
            pairDialog.dismiss();
            pairDialog = null;
        }
        super.onPause();
    }

    private void handleBroadcast(Intent intent) {
        if (!receiverRegistered || intent == null) return;
        String action = intent.getAction();
        if (BluetoothDevice.ACTION_FOUND.equals(action)) {
            mergeDevice((BluetoothDevice) intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE));
        } else if (BluetoothDevice.ACTION_BOND_STATE_CHANGED.equals(action)) {
            mergeDevice((BluetoothDevice) intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE));
            refreshBonded();
        } else if (BluetoothAdapter.ACTION_DISCOVERY_STARTED.equals(action)) {
            discovering = true;
        } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)) {
            discovering = false;
        } else return;
        refreshRows();
    }

    private boolean hasLocationPermission() {
        return checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean requireEnabled() {
        if (adapter == null) {
            showMessage("Bluetooth unavailable", "This device has no Bluetooth adapter.");
            return false;
        }
        try {
            if (adapter.isEnabled()) return true;
            showMessage("Bluetooth is off", "Choose Request Bluetooth enable before scanning or pairing.");
        } catch (SecurityException denied) {
            showMessage("Bluetooth unavailable", "Bluetooth access was denied by the system.");
        }
        return false;
    }

    private void requestEnable() {
        if (adapter == null) {
            showMessage("Bluetooth unavailable", "This device has no Bluetooth adapter.");
            return;
        }
        try {
            if (adapter.isEnabled()) {
                showMessage("Bluetooth is on", "Bluetooth is already enabled.");
                return;
            }
            startActivity(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE));
        } catch (SecurityException denied) {
            showMessage("Bluetooth unavailable", "The system denied the Bluetooth enable request.");
        } catch (ActivityNotFoundException unavailable) {
            showMessage("Bluetooth unavailable", "The system Bluetooth confirmation screen is unavailable.");
        }
    }

    private void requestScan() {
        if (!requireEnabled()) return;
        if (hasLocationPermission()) {
            permissionDenied = false;
            scanWithPermission();
        } else if (permissionDenied) {
            showMessage("Scan unavailable", "Location permission is required to discover Bluetooth devices. Permission was denied. Paired devices remain available; grant Location permission in app permissions before scanning again.");
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
        permissionRequested = false;
        permissionDenied = !granted;
        if (!receiverRegistered) return;
        refreshRows();
        if (granted) scanWithPermission();
        else showMessage("Scan unavailable", "Location permission is required for discovery. Paired devices remain available.");
    }

    private void scanWithPermission() {
        if (!hasLocationPermission()) return;
        if (!receiverRegistered || !requireEnabled()) return;
        try {
            if (adapter.isDiscovering()) adapter.cancelDiscovery();
            if (!adapter.startDiscovery()) {
                showMessage("Scan unavailable", "Could not start discovery. Check Location services and try again.");
            }
        } catch (SecurityException denied) {
            showMessage("Scan unavailable", "Discovery was denied by the system. Check Location permission and Location services.");
        }
        refreshRows();
    }

    private void cancelDiscovery() {
        discovering = false;
        if (adapter == null) return;
        try {
            if (adapter.isDiscovering()) adapter.cancelDiscovery();
        } catch (SecurityException denied) { /* Lifecycle cleanup must still unregister the receiver. */ }
    }

    private void mergeDevice(BluetoothDevice device) {
        if (device == null) return;
        try {
            BluetoothEntry incoming = new BluetoothEntry(device.getName(), device.getAddress(), device.getBondState());
            String address = incoming.getAddress();
            if (address.isEmpty()) return;
            BluetoothEntry previous = models.get(address);
            if (incoming.getName().isEmpty() && previous != null) {
                incoming = new BluetoothEntry(previous.getName(), address, incoming.getBondState());
            }
            models.put(address, incoming);
            devices.put(address, device);
        } catch (SecurityException denied) { /* Retain known rows if one device cannot be read. */ }
    }

    private void refreshBonded() {
        if (adapter == null) return;
        try {
            // Refresh current states of discovered entries as well as the bonded source.
            for (BluetoothDevice device : new ArrayList<BluetoothDevice>(devices.values())) mergeDevice(device);
            Set<BluetoothDevice> bonded = adapter.getBondedDevices();
            if (bonded != null) for (BluetoothDevice device : bonded) mergeDevice(device);
        } catch (SecurityException denied) { /* Bonded display does not require a location scan. */ }
    }

    private void refreshRows() {
        boolean enabled = false;
        if (adapter != null) {
            try { enabled = adapter.isEnabled(); }
            catch (SecurityException denied) { /* Keep the base rows usable. */ }
        }
        ArrayList<String> rows = new ArrayList<String>();
        rows.add("Bluetooth: " + (enabled ? "On" : "Off"));
        rows.add("Request Bluetooth enable");
        rows.add("Scan again");
        entries = new ArrayList<BluetoothEntry>(models.values());
        Collections.sort(entries, ORDER);
        for (BluetoothEntry entry : entries) {
            String status = entry.getBondState() == BluetoothDevice.BOND_BONDED ? "Paired"
                    : entry.getBondState() == BluetoothDevice.BOND_BONDING ? "Pairing in progress" : "Not paired";
            rows.add(entry.displayName() + "  |  " + status);
        }
        setRows(discovering ? "Controllers & Bluetooth — Scanning" : "Controllers & Bluetooth", rows);
    }

    @Override protected void onListItemClick(ListView list, View view, int position, long id) {
        if (position < 0) return;
        if (position == 1) { requestEnable(); return; }
        if (position == 2) { requestScan(); return; }
        int index = position - 3;
        if (index < 0 || index >= entries.size()) return;
        BluetoothEntry entry = entries.get(index);
        BluetoothDevice device = devices.get(entry.getAddress());
        if (device != null) showDevice(entry, device);
    }

    private void showDevice(BluetoothEntry entry, BluetoothDevice device) {
        try {
            int state = device.getBondState();
            if (state == BluetoothDevice.BOND_BONDED) {
                showMessage(entry.displayName(), "Paired");
                return;
            }
            if (state == BluetoothDevice.BOND_BONDING) {
                showMessage(entry.displayName(), "Pairing in progress");
                return;
            }
            if (state == BluetoothDevice.BOND_NONE) confirmPair(entry, device);
        } catch (SecurityException denied) {
            showMessage("Pairing unavailable", "Bluetooth device access was denied by the system.");
        }
    }

    private void confirmPair(BluetoothEntry entry, final BluetoothDevice device) {
        if (pairDialog != null) pairDialog.dismiss();
        pairDialog = new AlertDialog.Builder(this)
                .setTitle("Pair Bluetooth device?")
                .setMessage(entry.displayName())
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton("Pair", new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface dialog, int which) { pairConfirmed(device); }
                }).show();
    }

    private void pairConfirmed(BluetoothDevice device) {
        if (!receiverRegistered || !requireEnabled()) return;
        try {
            // The state may change while the confirmation dialog is open.
            if (device.getBondState() != BluetoothDevice.BOND_NONE) {
                refreshBonded();
                refreshRows();
                return;
            }
            if (!device.createBond()) {
                showMessage("Pairing unavailable", "Could not start pairing. Try again after checking the device.");
            }
        } catch (SecurityException denied) {
            showMessage("Pairing unavailable", "Pairing was denied by the system.");
        }
    }
}
