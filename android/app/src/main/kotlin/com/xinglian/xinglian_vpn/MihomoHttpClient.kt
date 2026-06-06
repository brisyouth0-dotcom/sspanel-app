package com.kele.kele_vpn

import android.util.Log
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.charset.StandardCharsets

/** 访问本机 mihomo external-controller（需在 connect 之后 protect） */
internal object MihomoHttpClient {
    private const val TAG = "MihomoHttpClient"

    data class Response(val statusCode: Int, val body: String)

    fun request(
        method: String,
        path: String,
        body: String? = null,
        protect: Boolean = false,
        timeoutMs: Int = 8000,
    ): Response? {
        val socket = Socket()
        return try {
            socket.tcpNoDelay = true
            socket.connect(
                InetSocketAddress(MihomoController.HOST, MihomoController.PORT),
                timeoutMs,
            )
            if (protect) {
                StarVpnService.protectSocket(socket)
            }
            val payload = body?.toByteArray(StandardCharsets.UTF_8)
            val req = buildString {
                append("$method $path HTTP/1.1\r\n")
                append("Host: ${MihomoController.HOST}:${MihomoController.PORT}\r\n")
                append("Authorization: Bearer ${MihomoController.SECRET}\r\n")
                if (payload != null) {
                    append("Content-Type: application/json\r\n")
                    append("Content-Length: ${payload.size}\r\n")
                }
                append("Connection: close\r\n")
                append("\r\n")
            }
            socket.getOutputStream().write(req.toByteArray(StandardCharsets.UTF_8))
            if (payload != null) {
                socket.getOutputStream().write(payload)
            }
            socket.getOutputStream().flush()
            socket.shutdownOutput()

            parseResponse(socket)
        } catch (e: Exception) {
            Log.w(TAG, "$method $path failed: ${e.message}")
            null
        } finally {
            try {
                socket.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun parseResponse(socket: Socket): Response? {
        val reader = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
        val statusLine = reader.readLine() ?: return null
        val code = statusLine.split(' ').getOrNull(1)?.toIntOrNull() ?: 0
        var chunked = false
        var contentLength = -1
        while (true) {
            val header = reader.readLine() ?: break
            if (header.isEmpty()) break
            val lower = header.lowercase()
            if (lower.startsWith("transfer-encoding:") && lower.contains("chunked")) {
                chunked = true
            }
            if (lower.startsWith("content-length:")) {
                contentLength = header.substringAfter(':').trim().toIntOrNull() ?: -1
            }
        }
        val body = when {
            chunked -> readChunkedBody(reader)
            contentLength > 0 -> {
                val buf = CharArray(contentLength)
                var read = 0
                while (read < contentLength) {
                    val n = reader.read(buf, read, contentLength - read)
                    if (n < 0) break
                    read += n
                }
                String(buf, 0, read)
            }
            else -> reader.readText()
        }
        return Response(code, body)
    }

    private fun readChunkedBody(reader: BufferedReader): String {
        val sb = StringBuilder()
        while (true) {
            val sizeLine = reader.readLine() ?: break
            val chunkSize = sizeLine.substringBefore(';').trim().toIntOrNull(16) ?: 0
            if (chunkSize == 0) {
                reader.readLine()
                break
            }
            val buf = CharArray(chunkSize)
            var read = 0
            while (read < chunkSize) {
                val n = reader.read(buf, read, chunkSize - read)
                if (n < 0) break
                read += n
            }
            reader.readLine()
            if (read > 0) {
                sb.append(buf, 0, read)
            }
        }
        return sb.toString()
    }

    fun isSuccess(code: Int): Boolean = code in 200..299
}
