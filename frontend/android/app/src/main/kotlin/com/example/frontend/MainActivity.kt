package com.example.frontend

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.subvampireslayer.screentime"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsagePermission" -> {
                    result.success(hasUsagePermission())
                }
                "requestUsagePermission" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(true)
                }
                "getAppUsage" -> {
                    val startTime = call.argument<Long>("startTime")
                    val endTime = call.argument<Long>("endTime")
                    
                    if (startTime == null || endTime == null) {
                        result.error("INVALID_ARGUMENTS", "StartTime and EndTime are required", null)
                        return@setMethodCallHandler
                    }

                    if (!hasUsagePermission()) {
                        result.error("PERMISSION_DENIED", "Usage access permission not granted", null)
                        return@setMethodCallHandler
                    }
                    
                    val usageData = getAppUsageStats(startTime, endTime)
                    result.success(usageData)
                }
                "getInstalledApps" -> {
                    result.success(getInstalledApps())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun hasUsagePermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getAppUsageStats(startTime: Long, endTime: Long): List<Map<String, Any>> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )

        val pm = packageManager
        val usageList = mutableListOf<Map<String, Any>>()
        
        // Aggregate by package
        val aggregatedStats = mutableMapOf<String, Long>()
        val lastUsedStats = mutableMapOf<String, Long>()

        if (stats != null) {
            for (usageStats in stats) {
                val pkg = usageStats.packageName
                aggregatedStats[pkg] = (aggregatedStats[pkg] ?: 0L) + usageStats.totalTimeInForeground
                if (usageStats.lastTimeUsed > (lastUsedStats[pkg] ?: 0L)) {
                    lastUsedStats[pkg] = usageStats.lastTimeUsed
                }
            }
        }

        for ((pkg, time) in aggregatedStats) {
            if (time <= 0) continue
            
            try {
                val appInfo = pm.getApplicationInfo(pkg, 0)
                // Filter: Only apps with launch intents (to skip system services)
                if (pm.getLaunchIntentForPackage(pkg) != null) {
                    val appName = pm.getApplicationLabel(appInfo).toString()
                    usageList.add(mapOf(
                        "packageName" to pkg,
                        "appName" to appName,
                        "totalTimeInForeground" to time,
                        "lastTimeUsed" to (lastUsedStats[pkg] ?: 0L)
                    ))
                }
            } catch (e: PackageManager.NameNotFoundException) {
                // App uninstalled
            }
        }
        
        return usageList
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        val appList = mutableListOf<Map<String, String>>()
        
        for (app in apps) {
            if (pm.getLaunchIntentForPackage(app.packageName) != null) {
                appList.add(mapOf(
                    "packageName" to app.packageName,
                    "appName" to pm.getApplicationLabel(app).toString()
                ))
            }
        }
        return appList
    }
}
