package com.kele.kele_vpn

import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 轮询 mihomo `/traffic`。TUN 建立后须 protect 套接字。
 */
object MihomoTrafficPoller {
    private const val TAG = "MihomoTrafficPoller"

    private val running = AtomicBoolean(false)
    private var thread: Thread? = null
    private var idlePolls = 0

    fun start(handler: (up: Long, down: Long) -> Unit) {
        stop()
        running.set(true)
        thread = Thread({
            Log.i(TAG, "traffic poll loop started")
            while (running.get()) {
                val sample = pollOnce()
                if (sample != null) {
                    handler(sample.first, sample.second)
                }
                try {
                    Thread.sleep(500)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }, "mihomo-traffic").apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        running.set(false)
        thread?.interrupt()
        try {
            thread?.join(1500)
        } catch (_: InterruptedException) {
        }
        thread = null
    }

    /** 读取 /traffic 流中的一帧速率数据 */
    fun pollOnce(): Pair<Long, Long>? {
        val socket = Socket()
        return try {
            socket.tcpNoDelay = true
            socket.soTimeout = 5000
            socket.connect(
                InetSocketAddress(MihomoController.HOST, MihomoController.PORT),
                5000,
            )
            if (!StarVpnService.protectSocket(socket)) {
                Log.w(TAG, "protect failed on traffic poll")
            }
            val req = buildString {
                append("GET /traffic HTTP/1.1\r\n")
                append("Host: ${MihomoController.HOST}:${MihomoController.PORT}\r\n")
                append("Authorization: Bearer ${MihomoController.SECRET}\r\n")
                append("Accept: application/json\r\n")
                append("Connection: close\r\n")
                append("\r\n")
            }
            socket.getOutputStream().write(req.toByteArray(StandardCharsets.UTF_8))
            socket.getOutputStream().flush()

            val reader = BufferedReader(
                InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8),
            )
            val status = reader.readLine()
            if (status == null || !status.contains("200")) {
                Log.w(TAG, "traffic HTTP status: $status")
                return null
            }
            var chunked = false
            while (true) {
                val header = reader.readLine() ?: break
                if (header.isEmpty()) break
                if (header.lowercase().startsWith("transfer-encoding:") &&
                    header.lowercase().contains("chunked")
                ) {
                    chunked = true
                }
            }
            val line = if (chunked) readFirstChunkedLine(reader) else reader.readLine()
            val sample = parseLine(line)
            if (sample != null) {
                if (sample.first > 0 || sample.second > 0) {
                    Log.i(TAG, "traffic up=${sample.first} down=${sample.second}")
                    idlePolls = 0
                } else {
                    idlePolls++
                    if (idlePolls == 10) {
                        Log.w(TAG, "traffic still zero after ${idlePolls} polls")
                        idlePolls = 0
                    }
                }
            }
            sample
        } catch (e: Exception) {
            Log.w(TAG, "pollOnce: ${e.message}")
            null
        } finally {
            try {
                socket.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun readFirstChunkedLine(reader: BufferedReader): String? {
        val sizeLine = reader.readLine() ?: return null
        val chunkSize = sizeLine.substringBefore(';').trim().toIntOrNull(16) ?: 0
        if (chunkSize <= 0) return null
        val buf = CharArray(chunkSize)
        var read = 0
        while (read < chunkSize) {
            val n = reader.read(buf, read, chunkSize - read)
            if (n < 0) break
            read += n
        }
        return if (read > 0) String(buf, 0, read) else null
    }

    private fun parseLine(line: String?): Pair<Long, Long>? {
        val trimmed = line?.trim() ?: return null
        if (trimmed.isEmpty() || !trimmed.startsWith("{")) return null
        return try {
            val json = JSONObject(trimmed)
            val up = json.optLong("up", 0L)
            val down = json.optLong("down", 0L)
            Pair(up, down)
        } catch (_: Exception) {
            null
        }
    }
}
