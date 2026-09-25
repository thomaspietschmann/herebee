package app.herebee.herebee_location

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Bridges [LocationForegroundService] to Dart.
 *
 * Deliberately thin: it starts and stops the service, answers permission
 * questions, and forwards fixes. Everything that could leak a position — the
 * encryption, the socket — stays in Dart.
 */
class HerebeeLocationPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private companion object {
        const val PERMISSION_REQUEST_CODE = 4711
    }

    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var sink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "app.herebee/location")
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "app.herebee/location/updates")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        LocationForegroundService.onFix = null
        LocationForegroundService.onStopped = null
        // Nothing consumes fixes once the engine is gone, so a service left
        // running would hold GPS and a wake lock while dropping every fix — the
        // notification would still claim the location is being shared. There is
        // no state in this app where that is useful.
        if (LocationForegroundService.isRunning) {
            context.stopService(Intent(context, LocationForegroundService::class.java))
        }
    }

    // --- event channel ----------------------------------------------------

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) {
        sink = eventSink
        LocationForegroundService.onFix = { location -> main.post { emitFix(location) } }
        LocationForegroundService.onStopped = { reason ->
            main.post { sink?.success(mapOf("event" to "stopped", "reason" to reason)) }
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        LocationForegroundService.onFix = null
        LocationForegroundService.onStopped = null
    }

    private fun emitFix(location: Location) {
        // Heading and speed are only meaningful when the fix actually reports
        // them; passing 0 for "unknown" would make a standing peer look like it
        // is heading due north.
        sink?.success(
            mapOf(
                "event" to "fix",
                "lat" to location.latitude,
                "lng" to location.longitude,
                "acc" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
                "hdg" to if (location.hasBearing()) location.bearing.toDouble() else null,
                "spd" to if (location.hasSpeed()) location.speed.toDouble() else null,
                "at" to location.time,
            ),
        )
    }

    // --- method channel ---------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkPermission" -> result.success(permissionState())
            "requestPermission" -> requestPermission(result)
            "start" -> start(call, result)
            "stop" -> {
                context.stopService(Intent(context, LocationForegroundService::class.java))
                result.success(null)
            }
            "reconfigure" -> {
                LocationForegroundService.current?.reconfigure(
                    (call.argument<Number>("intervalMs")?.toLong() ?: 1000L),
                    (call.argument<Number>("distanceFilter")?.toFloat() ?: 3f),
                )
                result.success(null)
            }
            "isSharing" -> result.success(LocationForegroundService.isRunning)
            "isBatteryOptimized" -> result.success(isBatteryOptimized())
            "openBatterySettings" -> {
                openSettings(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS, withPackage = false)
                result.success(null)
            }
            "openAppSettings" -> {
                openSettings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, withPackage = true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        if (permissionState() !in setOf("whileInUse", "coarseOnly")) {
            result.error("permission", "location permission not granted", null)
            return
        }
        if (!notificationsAllowed()) {
            // The ongoing notification carries the Stop button. Sharing a
            // location with no visible way to stop it is worse than not starting.
            result.error("notifications", "notification permission not granted", null)
            return
        }
        if (!locationEnabled()) {
            result.error("servicesDisabled", "location is switched off on this device", null)
            return
        }
        val intent = Intent(context, LocationForegroundService::class.java)
            .setAction(LocationForegroundService.ACTION_START)
            .putExtra(LocationForegroundService.EXTRA_TITLE, call.argument<String>("notificationTitle"))
            .putExtra(LocationForegroundService.EXTRA_BODY, call.argument<String>("notificationBody"))
            .putExtra(LocationForegroundService.EXTRA_STOP_LABEL, call.argument<String>("notificationStopLabel"))
            .putExtra(
                LocationForegroundService.EXTRA_INTERVAL_MS,
                (call.argument<Number>("intervalMs")?.toLong() ?: 1000L),
            )
            .putExtra(
                LocationForegroundService.EXTRA_DISTANCE_FILTER,
                (call.argument<Number>("distanceFilter")?.toFloat() ?: 3f),
            )
        try {
            ContextCompat.startForegroundService(context, intent)
            result.success(null)
        } catch (e: Exception) {
            // Android refuses a location foreground service started from the
            // background. The app only calls this from a tap, so this means the
            // platform disagreed and the user must know.
            result.error("startFailed", e.message ?: "could not start the sharing service", null)
        }
    }

    private fun locationEnabled(): Boolean {
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return false
        return manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    private fun granted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun permissionState(): String = when {
        !locationEnabled() -> "servicesDisabled"
        granted(Manifest.permission.ACCESS_FINE_LOCATION) -> "whileInUse"
        granted(Manifest.permission.ACCESS_COARSE_LOCATION) -> "coarseOnly"
        activity?.let {
            ActivityCompat.shouldShowRequestPermissionRationale(it, Manifest.permission.ACCESS_FINE_LOCATION)
        } == true -> "denied"
        else -> "notDetermined"
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val current = permissionState()
        if (current == "whileInUse" || current == "coarseOnly" || current == "servicesDisabled") {
            result.success(current)
            return
        }
        val act = activity
        if (act == null) {
            result.error("noActivity", "permission can only be requested from the foreground", null)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("pending", "a permission request is already in flight", null)
            return
        }
        pendingPermissionResult = result

        val wanted = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        // Android 13+ needs notification permission too, or the foreground
        // service's ongoing notification is silently suppressed and the user
        // loses the Stop button.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            wanted += Manifest.permission.POST_NOTIFICATIONS
        }
        ActivityCompat.requestPermissions(act, wanted.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null

        if (grantResults.isEmpty()) {
            // Documented as "the request was cancelled" (the user swiped it away,
            // or another dialog took over). Reporting deniedForever here would
            // send someone to the Settings app who was never actually asked.
            result.success("notDetermined")
            return true
        }

        val act = activity
        val state = when {
            granted(Manifest.permission.ACCESS_FINE_LOCATION) -> "whileInUse"
            granted(Manifest.permission.ACCESS_COARSE_LOCATION) -> "coarseOnly"
            // No rationale offered after a denial means "don't ask again"; only
            // the Settings app can change it from here.
            act != null && !ActivityCompat.shouldShowRequestPermissionRationale(
                act,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) -> "deniedForever"
            else -> "denied"
        }
        result.success(state)
        return true
    }

    private fun notificationsAllowed(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            granted(Manifest.permission.POST_NOTIFICATIONS)

    private fun isBatteryOptimized(): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return !pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun openSettings(action: String, withPackage: Boolean) {
        val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (withPackage) intent.data = Uri.fromParts("package", context.packageName, null)
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            // Some vendor ROMs do not ship the standard screen; nothing to do.
        }
    }

    // --- activity binding -------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }
}
