package hev.sockstun;

/**
 * JNI 桥接 hev-socks5-tunnel（与 sockstun 相同包名/方法名，供预编译 .so 使用）。
 */
public final class TProxyService {
    static {
        System.loadLibrary("hev-socks5-tunnel");
    }

    private TProxyService() {
    }

    public static native void TProxyStartService(String configPath, int fd);

    public static native void TProxyStopService();

    public static native long[] TProxyGetStats();
}
