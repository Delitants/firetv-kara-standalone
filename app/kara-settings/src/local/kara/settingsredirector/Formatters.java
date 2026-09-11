package local.kara.settingsredirector;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.Locale;

public final class Formatters {
    private Formatters() {}

    public static String formatBytes(long bytes) {
        if (bytes < 0) return "Unavailable";
        if (bytes < 1024) return bytes + " B";
        String[] units = {"B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"};
        double value = bytes;
        int unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return String.format(Locale.US, "%.1f %s", value, units[unit]);
    }

    public static String readFirstLine(File file, String fallback) {
        try {
            if (file == null || !file.isFile() || !file.canRead()) return fallback;
            try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
                String line = reader.readLine();
                if (line == null || line.trim().isEmpty()) return fallback;
                return line.trim();
            }
        } catch (IOException | SecurityException ignored) {
            return fallback;
        }
    }
}
