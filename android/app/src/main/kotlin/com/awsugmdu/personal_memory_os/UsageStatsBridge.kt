package com.awsugmdu.personal_memory_os

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Lets Dart ask how long chosen apps (Instagram, TikTok, ...) were on screen recently.
 * Needs the user to grant "Usage access" in system settings; nothing is read before that.
 */
class UsageStatsBridge(private val context: Context) {

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAccess" -> result.success(hasAccess())
            "openAccessSettings" -> {
                context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            "installed" -> result.success(installed(call.argument<List<String>>("packages") ?: emptyList()))
            "foregroundMinutes" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                val window = call.argument<Int>("windowMinutes") ?: 60
                result.success(if (hasAccess()) foregroundMinutes(packages.toSet(), window) else 0)
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun hasAccess(): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun installed(packages: List<String>): List<String> = packages.filter {
        try {
            context.packageManager.getPackageInfo(it, 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Total time the given apps spent in the foreground during the last [windowMinutes]. */
    @Suppress("DEPRECATION")
    private fun foregroundMinutes(packages: Set<String>, windowMinutes: Int): Int {
        if (packages.isEmpty()) return 0
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val events = manager.queryEvents(end - windowMinutes * 60_000L, end)
        val event = UsageEvents.Event()
        val openedAt = HashMap<String, Long>()
        var total = 0L
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName
            if (pkg !in packages) continue
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> openedAt[pkg] = event.timeStamp
                UsageEvents.Event.MOVE_TO_BACKGROUND -> openedAt.remove(pkg)?.let { total += event.timeStamp - it }
            }
        }
        // Apps still on screen right now.
        openedAt.values.forEach { total += end - it }
        return (total / 60_000L).toInt()
    }
}
