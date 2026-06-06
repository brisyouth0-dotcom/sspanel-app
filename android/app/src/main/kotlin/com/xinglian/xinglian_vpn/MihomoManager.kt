package com.kele.kele_vpn

import android.content.Context
import android.os.Build
import android.util.Log
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileDescriptor
import java.io.FileOutputStream

/**
 * 管理 mihomo 子进程。
 * Android 10+ 禁止从 filesDir 执行二进制，需使用 jniLibs 中的 libmihomo.so。
 * VPN 模式下由 [StarVpnService] 传入 TUN fd，写入配置 file-descriptor 后启动。
 */
object MihomoManager {
    private const val TAG = "MihomoManager"

    private var process: Process? = null
    var lastStartError: String? = null
        private set

    fun fail(msg: String) {
        lastStartError = msg
    }

    fun resolveBinary(context: Context): String? {
        val nativeLib = File(context.applicationInfo.nativeLibraryDir, "libmihomo.so")
        if (nativeLib.exists() && nativeLib.length() > 0L) {
            return nativeLib.absolutePath
        }

        val cacheBin = File(context.codeCacheDir, "mihomo")
        if (cacheBin.canExecute() && cacheBin.length() > 0L) {
            return cacheBin.absolutePath
        }

        return try {
            context.assets.open("mihomo").use { input ->
                FileOutputStream(cacheBin).use { output -> input.copyTo(output) }
            }
            cacheBin.setReadable(true, false)
            cacheBin.setExecutable(true, false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                cacheBin.setWritable(false, false)
            }
            if (!cacheBin.canExecute()) {
                lastStartError =
                    "mihomo 无执行权限，请确认已打包 jniLibs/arm64-v8a/libmihomo.so"
                return null
            }
            cacheBin.absolutePath
        } catch (e: Exception) {
            lastStartError = "解压 mihomo 失败：${e.message}"
            null
        }
    }

    fun start(context: Context, configPath: String, tunFd: Int? = null): Boolean {
        stop()
        lastStartError = null
        if (MihomoReachability.isSocksReady()) {
            lastStartError =
                "端口 7890 已被占用，请先关闭其他 VPN/代理应用（如 FlClash、Clash 等）"
            Log.e(TAG, lastStartError!!)
            return false
        }
        val binary = resolveBinary(context) ?: return false
        Log.i(TAG, "starting mihomo binary=$binary")
        val configFile = File(configPath)
        if (!configFile.exists()) {
            lastStartError = "配置文件不存在"
            return false
        }
        val workDir = configFile.parentFile?.absolutePath ?: context.filesDir.absolutePath
        val inheritedFd = tunFd?.let { prepareInheritedFd(it) }
        val effectiveConfig = if (inheritedFd != null) {
            patchConfigWithTunFd(configFile, inheritedFd)
        } else {
            ensureTunDisabled(configFile)
        }
        return try {
            val proc = launchProcess(binary, workDir, effectiveConfig)
            Thread.sleep(500)
            if (!proc.isAlive) {
                lastStartError = readProcessOutput(proc).ifEmpty {
                    "mihomo 进程已退出（code ${proc.exitValue()}）"
                }
                return false
            }
            if (!MihomoReachability.waitForSocks(maxMs = 10000)) {
                lastStartError = readProcessOutput(proc).ifEmpty {
                    "mihomo 端口未就绪，请关闭其他代理应用后重试"
                }
                stop()
                return false
            }
            process = proc
            true
        } catch (e: Exception) {
            lastStartError = "启动失败：${e.message}"
            false
        }
    }

    private fun launchProcess(binary: String, workDir: String, configPath: String): Process {
        val args = listOf("-d", workDir, "-f", configPath)
        val commands = buildList {
            add(listOf(binary) + args)
            if (binary.endsWith(".so")) {
                add(listOf("/system/bin/linker64", binary) + args)
                add(listOf("/system/bin/linker", binary) + args)
            }
        }
        var last: Exception? = null
        for (cmd in commands) {
            try {
                val pb = ProcessBuilder(cmd)
                pb.directory(File(workDir))
                pb.redirectErrorStream(true)
                return pb.start()
            } catch (e: Exception) {
                last = e
            }
        }
        throw last ?: IllegalStateException("无法启动 mihomo")
    }

    private fun readProcessOutput(proc: Process): String {
        return try {
            proc.inputStream.bufferedReader().readText().trim()
        } catch (_: Exception) {
            ""
        }
    }

    fun stop() {
        process?.let { proc ->
            try {
                proc.destroy()
            } catch (_: Exception) {
            }
        }
        process = null
    }

    fun isAlive(): Boolean = process?.isAlive == true

    /** 清除 CLOEXEC，确保 fork 出的 mihomo 子进程能继承 TUN fd */
    private fun prepareInheritedFd(fd: Int): Int {
        return try {
            val fileDesc = fileDescriptorFromInt(fd)
            val flags = Os.fcntlInt(fileDesc, OsConstants.F_GETFD, 0)
            Os.fcntlInt(
                fileDesc,
                OsConstants.F_SETFD,
                flags and OsConstants.FD_CLOEXEC.inv(),
            )
            fd
        } catch (_: Exception) {
            fd
        }
    }

    private fun fileDescriptorFromInt(fd: Int): FileDescriptor {
        val desc = FileDescriptor()
        try {
            val setInt = FileDescriptor::class.java.getDeclaredMethod(
                "setInt\$",
                Int::class.javaPrimitiveType,
            )
            setInt.isAccessible = true
            setInt.invoke(desc, fd)
        } catch (_: Exception) {
            val field = FileDescriptor::class.java.getDeclaredField("descriptor")
            field.isAccessible = true
            field.setInt(desc, fd)
        }
        return desc
    }

    /** hev 路径：禁止 mihomo 自行开 TUN，避免与 Android VpnService 冲突 */
    private fun ensureTunDisabled(configFile: File): String {
        val patched = File(configFile.parentFile, "config.no-tun.yaml")
        var text = configFile.readText()
        val tunOff = """
tun:
  enable: false
""".trimIndent()
        if (text.contains("\ntun:")) {
            text = text.replace(Regex("(?ms)^tun:.*?(?=^[a-zA-Z0-9_-]+:|\\z)"), "$tunOff\n")
        } else {
            text = "$text\n$tunOff\n"
        }
        patched.writeText(text)
        return patched.absolutePath
    }

    private fun patchConfigWithTunFd(configFile: File, tunFd: Int): String {
        val patched = File(configFile.parentFile, "config.vpn.yaml")
        var text = configFile.readText()
        val profile = DeviceVpnProfile
        val ipv6Block = if (profile.useIpv6Tunnel) {
            "\n  inet6-address: fd00::1/128"
        } else {
            ""
        }
        val tunBlock = """
tun:
  enable: true
  stack: mixed
  file-descriptor: $tunFd
  inet4-address: 172.19.0.1/30$ipv6Block
  mtu: ${profile.mtu}
  auto-route: false
  auto-detect-interface: false
  strict-route: true
  endpoint-independent-nat: true
  dns-hijack:
    - any:53
""".trimIndent()
        if (text.contains("\ntun:")) {
            text = text.replace(Regex("(?ms)^tun:.*?(?=^[a-zA-Z0-9_-]+:|\\z)"), "$tunBlock\n")
        } else {
            val insertAt = text.indexOf('\n', text.indexOf("secret:"))
            text = if (insertAt > 0) {
                text.substring(0, insertAt + 1) + tunBlock + "\n" + text.substring(insertAt + 1)
            } else {
                "$text\n$tunBlock\n"
            }
        }
        patched.writeText(text)
        return patched.absolutePath
    }
}
