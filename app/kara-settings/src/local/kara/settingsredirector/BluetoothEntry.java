package local.kara.settingsredirector;

import java.util.Locale;

public final class BluetoothEntry {
    private final String name;
    private final String address;
    private final int bondState;

    public static int compare(BluetoothEntry a, BluetoothEntry b) {
        // Public API BluetoothDevice.BOND_BONDED, kept numeric for a pure model.
        boolean aBonded = a.bondState == 12;
        boolean bBonded = b.bondState == 12;
        if (aBonded != bBonded) return aBonded ? -1 : 1;
        int byName = a.displayName().compareToIgnoreCase(b.displayName());
        if (byName != 0) return byName;
        int exact = a.displayName().compareTo(b.displayName());
        return exact != 0 ? exact : a.address.compareTo(b.address);
    }

    public BluetoothEntry(String name, String address, int bondState) {
        this.name = name == null ? "" : name.trim();
        this.address = address == null ? "" : address.trim().toUpperCase(Locale.US);
        this.bondState = bondState;
    }

    public String getName() { return name; }
    public String getAddress() { return address; }
    public int getBondState() { return bondState; }
    public String displayName() { return name.isEmpty() ? address : name + " — " + address; }

    @Override public boolean equals(Object other) {
        if (this == other) return true;
        if (!(other instanceof BluetoothEntry) || address.isEmpty()) return false;
        return address.equals(((BluetoothEntry) other).address);
    }

    @Override public int hashCode() {
        return address.isEmpty() ? System.identityHashCode(this) : address.hashCode();
    }
}
