package local.kara.settingsredirector;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.ListView;
import android.widget.Toast;

import java.util.Arrays;

public final class MainActivity extends TvListActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setRows("Kara Settings", Arrays.asList(
                "Fire TV Settings (Display & Sounds + more)",
                "Network",
                "Applications",
                "Developer & ADB",
                "Controllers & Bluetooth",
                "Device & About"));
    }

    @Override
    protected void onListItemClick(ListView list, View view, int position, long id) {
        if (position == 0) {
            Intent stockSettings = new Intent();
            stockSettings.setClassName("com.amazon.tv.launcher",
                    "com.amazon.tv.launcher.ui.MainSettingsActivity");
            try {
                startActivity(stockSettings);
            } catch (ActivityNotFoundException | SecurityException unavailable) {
                Toast.makeText(this, "Stock Fire TV Settings is unavailable", Toast.LENGTH_LONG).show();
            }
            return;
        }
        Class<?>[] targets = {NetworkActivity.class, AppsActivity.class, DeveloperActivity.class,
                BluetoothActivity.class, AboutActivity.class};
        int localPosition = position - 1;
        if (localPosition < 0 || localPosition >= targets.length) {
            return;
        }
        startActivity(new Intent(this, targets[localPosition]));
    }
}
