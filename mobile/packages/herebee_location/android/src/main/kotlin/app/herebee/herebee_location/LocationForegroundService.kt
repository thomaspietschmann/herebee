package app.herebee.herebee_location

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/**
 * Keeps location updates coming while HereBee is in the background.
 *
 * Android only lets an app receive location in the background through a
 * foreground service of type `location`, started while the app is visible. That
 * is exactly the shape of the feature — you tap "share location" and then put
 * the phone away — so the restriction costs nothing.
 *
 * It uses the framework [LocationManager] rather than the Fused Location
 * Provider on purpose: FLP lives in Google Play Services, and keeping that out
 * of the APK is what lets the app run on de-Googled phones and makes the
 * "no third-party SDKs" claim verifiable.
 *
 * The service never touches the network. It hands fixes to Dart, which encrypts
 * them, so no coordinate exists in this process in a form it could send anywhere.
 */
class LocationForegroundService : Service(), LocationListener {

    companion object {
        const val ACTION_START = "app.herebee.location.START"
        const val ACTION_STOP = "app.herebee.location.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_STOP_LABEL = "stopLabel"
        const val EXTRA_INTERVAL_MS = "intervalMs"
        const val EXTRA_DISTANCE_FILTER = "distanceFilter"

        private const val CHANNEL_ID = "herebee.sharing"
        private const val NOTIFICATION_ID = 4711

        /** Set by the plugin while a Dart listener is attached. */
        @Volatile
        var onFix: ((Location) -> Unit)? = null

        /** Called when the service stops for a reason the user did not choose. */
        @Volatile
        var onStopped: ((String) -> Unit)? = null

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var locationManager: LocationManager? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // Came from the notification's Stop action, so it IS a user choice.
            onStopped?.invoke("stoppedFromNotification")
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Sharing your location"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: ""
        val stopLabel = intent?.getStringExtra(EXTRA_STOP_LABEL) ?: "Stop"
        val intervalMs = intent?.getLongExtra(EXTRA_INTERVAL_MS, 1000L) ?: 1000L
        val distanceFilter = intent?.getFloatExtra(EXTRA_DISTANCE_FILTER, 3f) ?: 3f

        try {
            startForegroundCompat(buildNotification(title, body, stopLabel))
        } catch (e: Exception) {
            // The platform can still refuse (a revoked permission, or a
            // background-start restriction). Letting it propagate out of
            // onStartCommand kills the app; tell Dart and stop instead.
            onStopped?.invoke("killedBySystem")
            stopSelf()
            return START_NOT_STICKY
        }
        acquireWakeLock()

        if (!requestUpdates(intervalMs, distanceFilter)) {
            onStopped?.invoke("servicesDisabled")
            stopSelf()
            return START_NOT_STICKY
        }

        isRunning = true
        // NOT sticky: a restart by the system would resurrect sharing without
        // the user asking, and sharing a location must always be a deliberate act.
        return START_NOT_STICKY
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ requires the type at startForeground, not only in the manifest.
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun requestUpdates(intervalMs: Long, distanceFilter: Float): Boolean {
        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return false
        locationManager = manager

        // GPS for precision outdoors, network for a usable fix indoors and for a
        // fast first result. Whichever reports, Dart gets it; the wire format
        // carries the accuracy so peers can see how vague a position is.
        var subscribed = false
        for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            if (!manager.isProviderEnabled(provider)) continue
            try {
                manager.requestLocationUpdates(provider, intervalMs, distanceFilter, this, Looper.getMainLooper())
                subscribed = true
            } catch (_: SecurityException) {
                // Permission revoked between the check and here.
                onStopped?.invoke("permissionLost")
                return false
            }
        }
        return subscribed
    }

    private fun acquireWakeLock() {
        // A partial wake lock costs battery, and it is the only thing that keeps
        // several vendors' power managers from suspending the process minutes
        // after the screen goes off, foreground service or not. Released in
        // onDestroy, and sharing is short-lived by design.
        //
        // onStartCommand can run more than once for the same session, so bail if
        // we already hold one: overwriting the field would orphan the previous
        // lock and keep the CPU awake until its timeout, long after sharing ended.
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "herebee:sharing").apply {
            setReferenceCounted(false)
            acquire(4 * 60 * 60 * 1000L) // hard ceiling: never hold it for a whole day
        }
    }

    private fun buildNotification(title: String, body: String, stopLabel: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, title, NotificationManager.IMPORTANCE_LOW).apply {
                    description = body
                    setShowBadge(false)
                },
            )
        }

        val stopIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, LocationForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 1, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .also { if (openIntent != null) it.setContentIntent(openIntent) }
            .addAction(Notification.Action.Builder(null, stopLabel, stopIntent).build())
            .build()
    }

    override fun onLocationChanged(location: Location) {
        onFix?.invoke(location)
    }

    @Deprecated("Required by LocationListener on API < 29; never called on newer releases.")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

    override fun onProviderEnabled(provider: String) = Unit

    override fun onProviderDisabled(provider: String) {
        // Location switched off device-wide while sharing; say so rather than
        // going quiet and looking like a bug to the people watching.
        val manager = locationManager ?: return
        val anyLeft = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .any { manager.isProviderEnabled(it) }
        if (!anyLeft) {
            onStopped?.invoke("servicesDisabled")
            stopSelf()
        }
    }

    override fun onDestroy() {
        isRunning = false
        try {
            locationManager?.removeUpdates(this)
        } catch (_: SecurityException) {
            // Permission already gone; nothing to release.
        }
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The user swiped the app away. Treat that as "stop sharing": continuing
        // to broadcast a location from a dismissed app would be a nasty surprise.
        //
        // This is only delivered because the manifest does NOT set
        // stopWithTask; with that flag the platform stops the service without
        // calling this, and Dart would never learn why sharing ended.
        onStopped?.invoke("stoppedFromNotification")
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }
}
