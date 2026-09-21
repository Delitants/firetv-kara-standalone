import android.app.admin.IDevicePolicyManager;
import android.content.ComponentName;
import android.os.IBinder;
import android.os.ServiceManager;

public final class ClearProfileOwner {
    private ClearProfileOwner() { }

    public static void main(String[] args) throws Exception {
        System.out.println("clearProfileOwner: resolving device_policy");
        IBinder binder = ServiceManager.getService("device_policy");
        IDevicePolicyManager manager = IDevicePolicyManager.Stub.asInterface(binder);
        ComponentName admin = new ComponentName(
                "com.amazon.tv.parentalcontrols",
                "com.amazon.tv.parentalcontrols.PCONAdminReceiver");
        System.out.println("clearProfileOwner: invoking as profile-owner UID");
        manager.clearProfileOwner(admin);
        System.out.println("clearProfileOwner: completed");
    }
}
