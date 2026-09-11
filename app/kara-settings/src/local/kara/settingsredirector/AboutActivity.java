package local.kara.settingsredirector;

import android.os.Bundle;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;

public final class AboutActivity extends TvListActivity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinkedHashMap<String, String> facts = DeviceFacts.collect(this);
        ArrayList<String> rows = new ArrayList<>();
        for (Map.Entry<String, String> fact : facts.entrySet()) {
            rows.add(fact.getKey() + ": " + fact.getValue());
        }
        setRows("Device & About", rows);
    }
}
