package local.kara.settingsredirector;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.ListView;

import java.util.Arrays;

public final class MainActivity extends TvListActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setRows("Kara Settings", Arrays.asList(
                "Network",
                "Controllers & Bluetooth",
                "Device & About"));
    }

    @Override
    protected void onListItemClick(ListView list, View view, int position, long id) {
        Class<?>[] targets = {NetworkActivity.class, BluetoothActivity.class, AboutActivity.class};
        if (position < 0 || position >= targets.length) {
            return;
        }
        startActivity(new Intent(this, targets[position]));
    }
}
