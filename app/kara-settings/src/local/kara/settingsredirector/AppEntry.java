package local.kara.settingsredirector;

import java.util.Comparator;

public final class AppEntry {
    public static final Comparator<AppEntry> ORDER = new Comparator<AppEntry>() {
        @Override public int compare(AppEntry left, AppEntry right) {
            if (left.system != right.system) return left.system ? 1 : -1;
            int label = left.label.compareToIgnoreCase(right.label);
            if (label != 0) return label;
            return left.packageName.compareTo(right.packageName);
        }
    };

    private final String label;
    private final String packageName;
    private final String version;
    private final boolean system;
    private final boolean launchable;

    public AppEntry(String label, String packageName, String version, boolean system, boolean launchable) {
        this.label = label == null || label.trim().isEmpty() ? packageName : label.trim();
        this.packageName = packageName == null ? "" : packageName;
        this.version = version == null || version.trim().isEmpty() ? "Unknown version" : version.trim();
        this.system = system;
        this.launchable = launchable;
    }

    public String getLabel() { return label; }
    public String getPackageName() { return packageName; }
    public String getVersion() { return version; }
    public boolean isSystem() { return system; }
    public boolean isLaunchable() { return launchable; }

    public boolean canUninstall(String settingsPackage) {
        return !system && !packageName.equals(settingsPackage);
    }

    public String rowLabel() {
        return label + " — " + version;
    }
}
