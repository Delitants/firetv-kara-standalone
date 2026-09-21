package local.kara.settingsredirector;

public final class DeveloperFacts {
    private DeveloperFacts() {}

    public static String adbLabel(int enabled) {
        if (enabled == 1) return "ADB debugging: Enabled";
        if (enabled == 0) return "ADB debugging: Disabled";
        return "ADB debugging: Unknown";
    }

    public static String usbLabel(String config) {
        String value = clean(config);
        return "USB configuration: " + (value.isEmpty() ? "Unavailable" : value);
    }

    public static String tcpLabel(String port) {
        String value = clean(port);
        if (value.isEmpty() || "-1".equals(value) || "0".equals(value)) value = "Not active";
        return "TCP ADB port: " + value;
    }

    public static String endpointLabel(String address, String port) {
        String cleanAddress = clean(address);
        String cleanPort = clean(port);
        if (cleanAddress.isEmpty() || cleanPort.isEmpty() || "-1".equals(cleanPort) || "0".equals(cleanPort)) {
            return "Wi-Fi ADB endpoint: Unavailable";
        }
        return "Wi-Fi ADB endpoint: " + cleanAddress + ":" + cleanPort;
    }

    public static String ipv4(int value) {
        if (value == 0) return "";
        return (value & 255) + "." + ((value >>> 8) & 255) + "."
                + ((value >>> 16) & 255) + "." + ((value >>> 24) & 255);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
