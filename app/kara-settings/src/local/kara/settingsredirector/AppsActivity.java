package local.kara.settingsredirector;

import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.widget.ListView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class AppsActivity extends TvListActivity {
    private List<AppEntry> entries = new ArrayList<AppEntry>();

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
    }

    @Override protected void onResume() {
        super.onResume();
        refreshRows();
    }

    private void refreshRows() {
        PackageManager manager = getPackageManager();
        ArrayList<AppEntry> current = new ArrayList<AppEntry>();
        for (ApplicationInfo info : manager.getInstalledApplications(0)) {
            String packageName = info.packageName;
            String label = String.valueOf(manager.getApplicationLabel(info));
            String version = "Unknown version";
            try {
                PackageInfo packageInfo = manager.getPackageInfo(packageName, 0);
                if (packageInfo.versionName != null) version = packageInfo.versionName;
            } catch (PackageManager.NameNotFoundException ignored) { continue; }
            boolean system = (info.flags & (ApplicationInfo.FLAG_SYSTEM | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0;
            boolean launchable = manager.getLaunchIntentForPackage(packageName) != null;
            current.add(new AppEntry(label, packageName, version, system, launchable));
        }
        Collections.sort(current, AppEntry.ORDER);
        entries = current;
        ArrayList<String> rows = new ArrayList<String>();
        for (AppEntry entry : entries) rows.add(entry.rowLabel());
        setRows("Applications", rows);
    }

    @Override protected void onListItemClick(ListView list, View view, int position, long id) {
        if (position < 0 || position >= entries.size()) return;
        showApp(entries.get(position));
    }

    private void showApp(final AppEntry entry) {
        ArrayList<String> actions = new ArrayList<String>();
        if (entry.isLaunchable()) actions.add("Open");
        if (entry.canUninstall(getPackageName())) actions.add("Uninstall");
        String type = entry.isSystem() ? "System app" : "User app";
        String message = entry.getPackageName() + "\n" + entry.getVersion() + "\n" + type;
        if (actions.isEmpty()) {
            showMessage(entry.getLabel(), message + "\n\nNo safe management action is available.");
            return;
        }
        final String[] choices = actions.toArray(new String[actions.size()]);
        new AlertDialog.Builder(this).setTitle(entry.getLabel()).setMessage(message)
                .setItems(choices, new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface dialog, int which) {
                        if (which < 0 || which >= choices.length) return;
                        if ("Open".equals(choices[which])) openApp(entry);
                        else if ("Uninstall".equals(choices[which])) requestUninstall(entry);
                    }
                }).setNegativeButton(android.R.string.cancel, null).show();
    }

    private void openApp(AppEntry entry) {
        Intent launch = getPackageManager().getLaunchIntentForPackage(entry.getPackageName());
        if (launch == null) { showMessage("Open unavailable", "This app has no launchable activity."); return; }
        try { startActivity(launch); }
        catch (ActivityNotFoundException unavailable) { showMessage("Open unavailable", "The app activity is unavailable."); }
    }

    private void requestUninstall(AppEntry entry) {
        if (!entry.canUninstall(getPackageName())) {
            showMessage("Uninstall unavailable", "System apps and Kara Settings cannot be uninstalled here.");
            return;
        }
        try {
            Intent uninstall = new Intent(Intent.ACTION_DELETE, Uri.parse("package:" + entry.getPackageName()));
            startActivity(uninstall);
        } catch (ActivityNotFoundException unavailable) {
            showMessage("Uninstall unavailable", "The Android package uninstaller is unavailable.");
        }
    }
}
