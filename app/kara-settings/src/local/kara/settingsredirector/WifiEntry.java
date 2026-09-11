package local.kara.settingsredirector;

import java.util.Locale;

/** Immutable snapshot. SSID identity preserves case/spaces and removes one quote pair.
 * BSSID identity trims whitespace and folds case; its namespace is separate from SSID. */
public final class WifiEntry {
    private final String ssid;
    private final String bssid;
    private final int signalLevel;
    private final String capabilities;
    private final int savedNetworkId;

    public WifiEntry(String ssid, String bssid, int signalLevel, String capabilities, int savedNetworkId) {
        this.ssid = unquote(ssid);
        this.bssid = bssid == null ? "" : bssid.trim().toLowerCase(Locale.US);
        this.signalLevel = signalLevel;
        this.capabilities = capabilities == null ? "" : capabilities;
        this.savedNetworkId = savedNetworkId;
    }

    public String getSsid() { return ssid; }
    public String getBssid() { return bssid; }
    public int getSignalLevel() { return signalLevel; }
    public String getCapabilities() { return capabilities; }
    public int getSavedNetworkId() { return savedNetworkId; }

    public static String unquote(String value) {
        if (value == null) return "";
        if (value.length() >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
            return value.substring(1, value.length() - 1);
        }
        return value;
    }

    private String identity() { return bssid.isEmpty() ? "s:" + ssid : "b:" + bssid; }
    @Override public boolean equals(Object other) {
        return other instanceof WifiEntry && identity().equals(((WifiEntry) other).identity());
    }
    @Override public int hashCode() { return identity().hashCode(); }
}
