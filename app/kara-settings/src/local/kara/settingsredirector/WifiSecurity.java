package local.kara.settingsredirector;

import java.util.Locale;

public final class WifiSecurity {
    public enum Kind { OPEN, PSK, UNSUPPORTED }
    private WifiSecurity() { }

    public static Kind classify(String capabilities) {
        String value = capabilities == null ? "" : capabilities.toUpperCase(Locale.US).trim();
        if (value.contains("EAP") || value.contains("WEP") || value.contains("SAE")) return Kind.UNSUPPORTED;
        boolean psk = value.contains("PSK");
        // Unknown advertised mechanisms fail closed, even alongside a known PSK token.
        String remainder = value.replace("[ESS]", "").replace("[WPS]", "");
        if (remainder.isEmpty()) return Kind.OPEN;
        if (!psk) return Kind.UNSUPPORTED;
        remainder = remainder.replaceAll("\\[(WPA|WPA2|RSN)-PSK(-(CCMP|TKIP|GCMP|CCMP-256|GCMP-256)([+](CCMP|TKIP|GCMP|CCMP-256|GCMP-256))*)*\\]", "");
        return remainder.isEmpty() ? Kind.PSK : Kind.UNSUPPORTED;
    }
}
