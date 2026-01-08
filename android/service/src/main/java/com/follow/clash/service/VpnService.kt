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
    // -----------------------------------

    override fun onCreate() {
        super.onCreate()
        
        // ZIVPN WakeLock Logic
        val powerManager = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
        wakeLock = powerManager.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "FlClash:ZivpnWakeLock")
        wakeLock?.acquire(10*60*60*1000L) // 10 hours safety limit
        
        handleCreate()
    }

    override fun onDestroy() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        stopZivpnCores() // Stop ZIVPN Cores
        handleDestroy()
        super.onDestroy()
    }

    private val connectivity by lazy {
        getSystemService<ConnectivityManager>()
    }
    private val uidPageNameMap = mutableMapOf<Int, String>()

    private fun resolverProcess(
        protocol: Int,
        source: InetSocketAddress,
        target: InetSocketAddress,
        uid: Int,
    ): String {
        val nextUid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectivity?.getConnectionOwnerUid(protocol, source, target) ?: -1
        } else {
            uid
        }
        if (nextUid == -1) {
            return ""
        }
        if (!uidPageNameMap.containsKey(nextUid)) {
            uidPageNameMap[nextUid] = this.packageManager?.getPackagesForUid(nextUid)?.first() ?: ""
        }
        return uidPageNameMap[nextUid] ?: ""
    }

    val VpnOptions.address
        get(): String = buildString {
            append(IPV4_ADDRESS)
            if (ipv6) {
                append(",")
                append(IPV6_ADDRESS)
            }
        }

    val VpnOptions.dns
        get(): String {
            if (dnsHijacking) {
                return NET_ANY
            }
            return buildString {
                append(DNS)
                if (ipv6) {
                    append(",")
                    append(DNS6)
                }
            }
        }


    override fun onLowMemory() {
        Core.forceGC()
        super.onLowMemory()
    }

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): VpnService = this@VpnService

        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            try {
                val isSuccess = super.onTransact(code, data, reply, flags)
                if (!isSuccess) {
                    GlobalState.log("VpnService disconnected")
                    handleDestroy()
                }
                return isSuccess
            } catch (e: RemoteException) {
                GlobalState.log("VpnService onTransact $e")
                return false
            }
        }
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    private fun handleStart(options: VpnOptions) {
        val fd = with(Builder()) {
            val cidr = IPV4_ADDRESS.toCIDR()
            addAddress(cidr.address, cidr.prefixLength)
            Log.d(
                "addAddress", "address: ${cidr.address} prefixLength:${cidr.prefixLength}"
            )
            val routeAddress = options.getIpv4RouteAddress()
            if (routeAddress.isNotEmpty()) {
                try {
                    routeAddress.forEach { i ->
                        Log.d(
                            "addRoute4", "address: ${i.address} prefixLength:${i.prefixLength}"
                        )
                        addRoute(i.address, i.prefixLength)
                    }
                } catch (_: Exception) {
                    addRoute(NET_ANY, 0)
                }
            } else {
                addRoute(NET_ANY, 0)
            }
            if (options.ipv6) {
                try {
                    val cidr = IPV6_ADDRESS.toCIDR()
                    Log.d(
                        "addAddress6", "address: ${cidr.address} prefixLength:${cidr.prefixLength}"
                    )
                    addAddress(cidr.address, cidr.prefixLength)
                } catch (_: Exception) {
                    Log.d(
                        "addAddress6", "IPv6 is not supported."
                    )
                }

                try {
                    val routeAddress = options.getIpv6RouteAddress()
                    if (routeAddress.isNotEmpty()) {
                        try {
                            routeAddress.forEach { i ->
                                Log.d(
                                    "addRoute6",
                                    "address: ${i.address} prefixLength:${i.prefixLength}"
                                )
                                addRoute(i.address, i.prefixLength)
                            }
                        } catch (_: Exception) {
                            addRoute("::", 0)
                        }
                    } else {
                        addRoute(NET_ANY6, 0)
                    }
                } catch (_: Exception) {
                    addRoute(NET_ANY6, 0)
                }
            }
            addDnsServer(DNS)
            if (options.ipv6) {
                addDnsServer(DNS6)
            }
            
            // Dynamic MTU from Settings
            val prefs = getSharedPreferences("zivpn_config", 4)
            val mtu = prefs.getString("mtu", "9000")?.toIntOrNull() ?: 9000
            setMtu(mtu)
            Log.d("FlClash", "VPN Interface configured with MTU: $mtu")

            options.accessControl.let { accessControl ->
                if (accessControl.enable) {
                    when (accessControl.mode) {
                        AccessControlMode.ACCEPT_SELECTED -> {
                            (accessControl.acceptList + packageName).forEach {
                                addAllowedApplication(it)
                            }
                        }

                        AccessControlMode.REJECT_SELECTED -> {
                            (accessControl.rejectList - packageName).forEach {
                                addDisallowedApplication(it)
                            }
                        }
                    }
                }
            }
            setSession("FlClash")
            setBlocking(false)
            if (Build.VERSION.SDK_INT >= 29) {
                setMetered(false)
            }
            if (options.allowBypass) {
                allowBypass()
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && options.systemProxy) {
                GlobalState.log("Open http proxy")
                setHttpProxy(
                    ProxyInfo.buildDirectProxy(
                        "127.0.0.1", options.port, options.bypassDomain
                    )
                )
            }
            establish()?.detachFd()
                ?: throw NullPointerException("Establish VPN rejected by system")
        }
        Core.startTun(
            fd,
            protect = this::protect,
            resolverProcess = this::resolverProcess,
            options.stack,
            options.address,
            options.dns
        )
    }

    override fun start() {
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
            // Kill existing processes to free ports
            try {
                // Note: killall might not work for system libs if names match system processes, 
                // but these are unique enough. 
                // However, we track process objects now, so this is just a safety net.
                Runtime.getRuntime().exec("killall libuz.so libload.so")
                delay(500) 
            } catch (e: Exception) {}

            // Use Native Library Directory (Safe execution on Android 10+)
            val nativeDir = applicationInfo.nativeLibraryDir
            
            val libUz = java.io.File(nativeDir, "libuz.so").absolutePath
            val libLoad = java.io.File(nativeDir, "libload.so").absolutePath

            if (!java.io.File(libUz).exists()) {
                Log.e("FlClash", "Native Binary libuz.so not found at $libUz. Ensure it is in jniLibs.")
                return@withContext
            }
            
            // Note: No chmod needed for nativeLibraryDir (it is already r-x)

            val prefs = getSharedPreferences("zivpn_config", 4)
            val ip = prefs.getString("ip", "202.10.48.173") ?: "202.10.48.173"
            val pass = prefs.getString("pass", "asd63") ?: "asd63"
            val obfs = prefs.getString("obfs", "hu``hqb`c") ?: "hu``hqb`c"
            val portRange = prefs.getString("port_range", "6000-19999") ?: "6000-19999"

            Log.i("FlClash", "Starting ZIVPN Cores with IP: $ip, Range: $portRange")

            val tunnels = mutableListOf<String>()
            val ports = listOf(1080, 1081, 1082, 1083)
            val ranges = portRange.split(",").map { it.trim() }.filter { it.isNotEmpty() }

            for ((index, port) in ports.withIndex()) {
                val currentRange = if (ranges.isNotEmpty()) ranges[index % ranges.size] else "6000-19999"
                
                // MATCH ZIVPN NATIVE: Use Triple Quote Raw String for 100% safety
                val configContent = """{"server":"$ip:$currentRange","obfs":"$obfs","auth":"$pass","socks5":{"listen":"127.0.0.1:$port"},"insecure":true,"recvwindowconn":131072,"recvwindow":327680}"""
                
                // FIXED: Pass config content directly as string, matching service_turbo.sh behavior
                val pb = ProcessBuilder(libUz, "-s", obfs, "--config", configContent)
                
                // Use nativeDir for libraries
                pb.environment()["LD_LIBRARY_PATH"] = nativeDir
                
                Log.i("FlClash", "Exec Core-$port: $libUz -s $obfs --config [HIDDEN_JSON]")

                val process = pb.start()
                coreProcesses.add(process)
                startProcessLogger(process, "Core-$port")
                tunnels.add("127.0.0.1:$port")
            }

            // Wait for cores to initialize (Critical for success)
            delay(2000)

            // Start Load Balancer (Matching ZIVPN Native params)
            // FIXED: Added missing "-tunnel" flag
            val lbArgs = mutableListOf(libLoad, "-lport", "7777", "-tunnel")
            lbArgs.addAll(tunnels)
            val lbPb = ProcessBuilder(lbArgs)
            // Use nativeDir for libraries
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