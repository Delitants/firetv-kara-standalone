package local.kara.settingsredirector;

import android.content.Context;
import android.os.Build;
import android.os.Environment;
import android.os.StatFs;
import android.os.SystemClock;
import java.io.File;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.SocketException;
import java.util.Enumeration;
import java.util.LinkedHashMap;
import java.util.TreeMap;

public final class DeviceFacts {
    private DeviceFacts() {}

    public static LinkedHashMap<String, String> collect(Context context) {
        LinkedHashMap<String, String> facts = new LinkedHashMap<>();
        facts.put("Model", normalize(Build.MODEL));
        facts.put("Product", normalize(Build.PRODUCT));
        facts.put("Device", normalize(Build.DEVICE));
        facts.put("Android", normalize(Build.VERSION.RELEASE));
        facts.put("API", Integer.toString(Build.VERSION.SDK_INT));
        facts.put("Build", normalize(Build.VERSION.INCREMENTAL));
        facts.put("Kernel", kernel());
        facts.put("Boot ID", bootId());
        facts.put("Uptime", uptime());
        facts.put("IPv4", ipv4());
        facts.put("Internal storage total", storage(true));
        facts.put("Internal storage free", storage(false));
        return facts;
    }

    private static String normalize(String value) {
        return value == null || value.trim().isEmpty() ? "Unavailable" : value.trim();
    }

    private static String kernel() {
        try {
            return normalize(System.getProperty("os.version"));
        } catch (SecurityException ignored) {
            return "Unavailable";
        }
    }

    private static String bootId() {
        return normalize(Formatters.readFirstLine(new File("/proc/sys/kernel/random/boot_id"), "Unavailable"));
    }

    private static String uptime() {
        try {
            long milliseconds = SystemClock.elapsedRealtime();
            long seconds = milliseconds < 0 ? 0 : milliseconds / 1000;
            long days = seconds / 86400;
            long hours = seconds / 3600 % 24;
            long minutes = seconds / 60 % 60;
            StringBuilder value = new StringBuilder();
            if (days > 0) value.append(days).append("d ");
            if (days > 0 || hours > 0) value.append(hours).append("h ");
            if (days > 0 || hours > 0 || minutes > 0) value.append(minutes).append("m ");
            return value.append(seconds % 60).append("s").toString();
        } catch (RuntimeException ignored) {
            return "Unavailable";
        }
    }

    private static String ipv4() {
        TreeMap<String, String> candidates = new TreeMap<>();
        try {
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            if (interfaces != null) {
                while (interfaces.hasMoreElements()) {
                    NetworkInterface network = interfaces.nextElement();
                    try {
                        if (!network.isUp() || network.isLoopback()) continue;
                        Enumeration<InetAddress> addresses = network.getInetAddresses();
                        while (addresses.hasMoreElements()) {
                            InetAddress address = addresses.nextElement();
                            if (!(address instanceof Inet4Address) || address.isLoopbackAddress()
                                    || address.isLinkLocalAddress()) continue;
                            String value = normalize(address.getHostAddress());
                            if (!"Unavailable".equals(value)) {
                                candidates.put(network.getName() + "/" + value, value);
                            }
                        }
                    } catch (SocketException | RuntimeException ignored) {
                        // A failing interface must not hide candidates on later interfaces.
                    }
                }
            }
        } catch (SocketException | RuntimeException ignored) {
            // No network connection is made; enumeration can still be denied.
        }
        return candidates.isEmpty() ? "Unavailable" : candidates.firstEntry().getValue();
    }

    private static String storage(boolean total) {
        try {
            StatFs stat = new StatFs(Environment.getDataDirectory().getPath());
            long blocks = total ? stat.getBlockCountLong() : stat.getAvailableBlocksLong();
            long size = stat.getBlockSizeLong();
            if (blocks < 0 || size <= 0 || blocks > Long.MAX_VALUE / size) return "Unavailable";
            return Formatters.formatBytes(blocks * size);
        } catch (RuntimeException ignored) {
            return "Unavailable";
        }
    }
}
