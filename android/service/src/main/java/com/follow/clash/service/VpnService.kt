package com.follow.clash.service

import android.content.Intent
import android.net.ConnectivityManager
import android.net.ProxyInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Parcel
import android.os.RemoteException
import android.util.Log
import androidx.core.content.getSystemService
import com.follow.clash.common.AccessControlMode
import com.follow.clash.common.GlobalState
import com.follow.clash.core.Core
import com.follow.clash.service.models.VpnOptions
import com.follow.clash.service.models.getIpv4RouteAddress
import com.follow.clash.service.models.getIpv6RouteAddress
import com.follow.clash.service.models.toCIDR
import com.follow.clash.service.modules.NetworkObserveModule
import com.follow.clash.service.modules.NotificationModule
import com.follow.clash.service.modules.SuspendModule
import com.follow.clash.service.modules.moduleLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay

import java.net.InetSocketAddress

class VpnService : android.net.VpnService(), IBaseService,
    CoroutineScope by CoroutineScope(Dispatchers.Default) {

    private val self: VpnService
        get() = this

    private val loader = moduleLoader {
        install(NetworkObserveModule(self))
        install(NotificationModule(self))
        install(SuspendModule(self))
    }

    // --- ZIVPN Turbo Logic Variables ---
    private val coreProcesses = mutableListOf<Process>()
    private var wakeLock: android.os.PowerManager.WakeLock? = null
    private var wifiLock: android.net.wifi.WifiManager.WifiLock? = null
    // -----------------------------------

    override fun onCreate() {
        super.onCreate()
        
        // ZIVPN High Performance Lock Logic
        val powerManager = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
        wakeLock = powerManager.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "FlClash:ZivpnWakeLock")
        wakeLock?.setReferenceCounted(false) // Ensure simple acquire/release logic

        val wifiManager = applicationContext.getSystemService(android.content.Context.WIFI_SERVICE) as android.net.wifi.WifiManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            wifiLock = wifiManager.createWifiLock(android.net.wifi.WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "FlClash:ZivpnWifiLock")
        } else {
            @Suppress("DEPRECATION")
            wifiLock = wifiManager.createWifiLock(android.net.wifi.WifiManager.WIFI_MODE_FULL_HIGH_PERF, "FlClash:ZivpnWifiLock")
        }
        wifiLock?.setReferenceCounted(false)
        
        handleCreate()
    }

    override fun onDestroy() {
        releaseLocks()
        stopZivpnCores() // Stop ZIVPN Cores
        handleDestroy()
        super.onDestroy()
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (e: Exception) {
            Log.e("FlClash", "Error releasing locks: ${e.message}")
        }
    }

    // ... (rest of imports)

    // ... (resolverProcess, etc)

    // ... (VpnOptions extensions)

    // ... (Binder)

    // ... (handleStart)

    override fun start() {
        // Acquire Locks Immediately on Start
        try {
            wakeLock?.acquire()
            wifiLock?.acquire()
            Log.i("FlClash", "High Performance Locks Acquired (WakeLock + WifiLock)")
        } catch (e: Exception) {
            Log.e("FlClash", "Failed to acquire locks: ${e.message}")
        }

        launch(Dispatchers.IO) {
            try {
                startZivpnCores() // Start ZIVPN Cores (Suspend)
                loader.load()
                State.options?.let {
                    withContext(Dispatchers.Main) {
                        handleStart(it)
                    }
                }
            } catch (_: Exception) {
                stop()
            }
        }
    }

    override fun stop() {
        stopZivpnCores() // Stop ZIVPN Cores
        releaseLocks() // Release Locks
        loader.cancel()
        Core.stopTun()
        stopSelf()
    }

    // --- ZIVPN Turbo Native Logic ---

    private fun startProcessLogger(process: Process, tag: String) {
        val logDir = java.io.File(filesDir, "zivpn_logs")
        if (!logDir.exists()) logDir.mkdirs()
        val logFile = java.io.File(logDir, "zivpn_core.log")
        
        // Append mode
        val writer = java.io.FileWriter(logFile, true)
        val dateFormat = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())

        fun writeLog(msg: String, isError: Boolean) {
            val timestamp = dateFormat.format(java.util.Date())
            val type = if (isError) "ERR" else "OUT"
            val logLine = "[$timestamp] [$tag] [$type] $msg\n"
            
            // Write to Logcat
            if (isError) Log.e("FlClash", "[$tag] $msg") else Log.i("FlClash", "[$tag] $msg")
            
            // Write to File
            try {
                writer.write(logLine)
                writer.flush()
            } catch (e: Exception) {}
        }

        Thread {
            try {
                process.inputStream.bufferedReader().use { reader ->
                    reader.forEachLine { writeLog(it, false) }
                }
            } catch (e: Exception) {}
        }.start()
        
        Thread {
            try {
                process.errorStream.bufferedReader().use { reader ->
                    reader.forEachLine { writeLog(it, true) }
                }
            } catch (e: Exception) {}
        }.start()
    }

    private suspend fun startZivpnCores() = withContext(Dispatchers.IO) {
        try {
            // 1. CLEANUP PHASE
            stopZivpnCores()
            // Force Kill everything matching the binary names to be 100% sure
            try {
                Runtime.getRuntime().exec("pkill -9 -f libuz.so").waitFor()
                Runtime.getRuntime().exec("pkill -9 -f libload.so").waitFor()
            } catch (e: Exception) {}
            
            // Give OS time to release sockets (TIME_WAIT state)
            delay(500) 

            // 2. SETUP PHASE
            val nativeDir = applicationInfo.nativeLibraryDir
            val libUz = java.io.File(nativeDir, "libuz.so").absolutePath
            val libLoad = java.io.File(nativeDir, "libload.so").absolutePath

            if (!java.io.File(libUz).exists()) {
                Log.e("FlClash", "Native Binary libuz.so not found at $libUz")
                return@withContext
            }

            val prefs = getSharedPreferences("zivpn_config", 4)
            val ip = prefs.getString("ip", "") ?: ""
            val pass = prefs.getString("pass", "") ?: ""
            val obfs = prefs.getString("obfs", "hu``hqb`c") ?: ""
            val portRange = prefs.getString("port_range", "6000-19999") ?: "6000-19999"

            Log.i("FlClash", "Starting ZIVPN Cores with IP: $ip, Range: $portRange")

            val tunnels = mutableListOf<String>()
            val ports = listOf(1080, 1081, 1082, 1083)
            val ranges = portRange.split(",").map { it.trim() }.filter { it.isNotEmpty() }

            // 3. EXECUTION PHASE (With Retry)
            // We start cores sequentially to avoid CPU spikes and race conditions
            for ((index, port) in ports.withIndex()) {
                val currentRange = if (ranges.isNotEmpty()) ranges[index % ranges.size] else "6000-19999"
                val configContent = """{"server":"$ip:$currentRange","obfs":"$obfs","auth":"$pass","socks5":{"listen":"127.0.0.1:$port"},"insecure":true,"recvwindowconn":131072,"recvwindow":327680}"""
                
                val pb = ProcessBuilder(libUz, "-s", obfs, "--config", configContent)
                pb.environment()["LD_LIBRARY_PATH"] = nativeDir
                
                val process = pb.start()
                coreProcesses.add(process)
                startProcessLogger(process, "Core-$port")
                tunnels.add("127.0.0.1:$port")
                delay(100) // Small staggering
            }

            delay(1000) // Wait for cores to bind ports

            // Start Load Balancer
            val lbArgs = mutableListOf(libLoad, "-lport", "7777", "-tunnel")
            lbArgs.addAll(tunnels)
            val lbPb = ProcessBuilder(lbArgs)
            lbPb.environment()["LD_LIBRARY_PATH"] = nativeDir
            
            val lbProcess = lbPb.start()
            coreProcesses.add(lbProcess)
            startProcessLogger(lbProcess, "LoadBalancer")

            Log.i("FlClash", "ZIVPN Turbo Engine started successfully on port 7777")

        } catch (e: Exception) {
            Log.e("FlClash", "Failed to start ZIVPN Cores: ${e.message}", e)
        }
    }

    private fun stopZivpnCores() {
        coreProcesses.forEach { 
            try {
                it.destroy() 
            } catch(e: Exception) {}
        }
        coreProcesses.clear()
        
        // Force kill to prevent port binding issues (ZIVPN success pattern)
        try {
            Runtime.getRuntime().exec("killall libuz.so libload.so")
        } catch (e: Exception) {}
        
        Log.i("FlClash", "ZIVPN Cores stopped")
    }
    // -----------------------------------

    companion object {
        private const val IPV4_ADDRESS = "172.19.0.1/30"
        private const val IPV6_ADDRESS = "fdfe:dcba:9876::1/126"
        private const val DNS = "172.19.0.2"
        private const val DNS6 = "fdfe:dcba:9876::2"
        private const val NET_ANY = "0.0.0.0"
        private const val NET_ANY6 = "::"
    }
}