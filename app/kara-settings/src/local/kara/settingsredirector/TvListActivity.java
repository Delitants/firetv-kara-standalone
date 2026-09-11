package local.kara.settingsredirector;

import android.app.AlertDialog;
import android.app.ListActivity;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.StateListDrawable;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.ListView;
import android.widget.TextView;

import java.util.List;

public class TvListActivity extends ListActivity {
    private static final int FOCUSED_ROW_COLOR = Color.rgb(70, 70, 70);
    private static final int ROW_COLOR = Color.rgb(35, 35, 35);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ListView listView = getListView();
        listView.setFocusable(true);
        listView.setFocusableInTouchMode(true);
    }

    protected final void setRows(String title, List<String> rows) {
        setTitle(title);
        setListAdapter(new RowAdapter(this, rows));
        getListView().requestFocus();
    }

    protected final void showMessage(String title, String message) {
        new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, null)
                .show();
    }

    protected final int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static final class RowAdapter extends ArrayAdapter<String> {
        private final TvListActivity activity;

        RowAdapter(TvListActivity activity, List<String> rows) {
            super(activity, android.R.layout.simple_list_item_1, rows);
            this.activity = activity;
        }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            TextView row = (TextView) super.getView(position, convertView, parent);
            row.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
            row.setPadding(activity.dp(24), activity.dp(12), activity.dp(24), activity.dp(12));
            row.setTextColor(Color.WHITE);
            row.setFocusable(false);
            row.setBackground(rowBackground());
            return row;
        }
    }

    private static Drawable rowBackground() {
        StateListDrawable background = new StateListDrawable();
        background.addState(new int[] {android.R.attr.state_focused},
                new ColorDrawable(FOCUSED_ROW_COLOR));
        background.addState(new int[] {android.R.attr.state_selected},
                new ColorDrawable(FOCUSED_ROW_COLOR));
        background.addState(new int[0], new ColorDrawable(ROW_COLOR));
        return background;
    }
}
