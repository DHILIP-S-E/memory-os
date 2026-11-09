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
        // Some devices answer MODE_DEFAULT even when the user has allowed it; the permission says which.
        return if (mode == AppOpsManager.MODE_DEFAULT) {
            context.checkCallingOrSelfPermission(android.Manifest.permission.PACKAGE_USAGE_STATS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            mode == AppOpsManager.MODE_ALLOWED
        }
    }

    private fun installed(packages: List<String>): List<String> = packages.filter {
        try {
            context.packageManager.getPackageInfo(it, 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Total time the given apps spent in the foreground during the last [windowMinutes].
     * Looks a few hours further back so a session that began before the window still counts
     * from the window's start, and tracks each activity so switching screens inside one app
     * (several activities) does not lose time.
     */
    @Suppress("DEPRECATION")
    private fun foregroundMinutes(packages: Set<String>, windowMinutes: Int): Int {
        if (packages.isEmpty()) return 0
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val start = end - windowMinutes * 60_000L
        val events = manager.queryEvents(start - LOOKBACK_MS, end)
        val event = UsageEvents.Event()
        val openedAt = HashMap<String, Long>()
        val activities = HashMap<String, MutableSet<String>>()
        var total = 0L

        fun addSpan(from: Long, to: Long) {
            total += maxOf(0L, minOf(to, end) - maxOf(from, start))
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName
            if (pkg !in packages) continue
            val open = activities.getOrPut(pkg) { mutableSetOf() }
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    if (open.isEmpty()) openedAt[pkg] = event.timeStamp
                    open.add(event.className ?: "")
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    open.remove(event.className ?: "")
                    if (open.isEmpty()) {
                        // No matching foreground event seen: it was already open when we started looking.
                        addSpan(openedAt.remove(pkg) ?: start, event.timeStamp)
                    }
                }
            }
        }
        // Apps still on screen right now.
        openedAt.forEach { (pkg, from) -> if (activities[pkg]?.isNotEmpty() == true) addSpan(from, end) }
        return (total / 60_000L).toInt()
    }

    companion object {
        private const val LOOKBACK_MS = 3 * 60 * 60_000L
    }
}
