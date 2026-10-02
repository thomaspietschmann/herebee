package app.herebee.crash

import android.content.Context
import android.content.pm.ApplicationInfo
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import org.acra.ReportField
import org.acra.config.CoreConfiguration
import org.acra.data.CrashReportData
import org.acra.sender.ReportSender
import org.acra.sender.ReportSenderException
import org.acra.sender.ReportSenderFactory
import org.json.JSONObject

/** Registered through META-INF/services, which is how ACRA discovers senders. */
class HereBeeReportSenderFactory : ReportSenderFactory {
    override fun create(context: Context, config: CoreConfiguration): ReportSender = HereBeeReportSender()
}

/**
 * Posts an accepted crash report as JSON to `<origin>/api/crash` on the HereBee
 * server the app currently uses, which mails it to the operator. Runs in ACRA's
 * `:acra` process, only for reports the user agreed to send in the dialog.
 *
 * Plain HttpURLConnection on purpose: no HTTP library, no third-party endpoint.
 */
class HereBeeReportSender : ReportSender {
    override fun send(context: Context, errorContent: CrashReportData) {
        val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val origin = CrashOrigin.resolve(context, allowCleartext = debuggable)
        val body = buildPayload(errorContent).toString().toByteArray(Charsets.UTF_8)

        val conn = try {
            URL("$origin/api/crash").openConnection() as HttpURLConnection
        } catch (e: IOException) {
            throw ReportSenderException("crash endpoint unreachable", e)
        }
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = TIMEOUT_MS
            conn.readTimeout = TIMEOUT_MS
            conn.doOutput = true
            conn.useCaches = false
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.setRequestProperty("X-HereBee-Client", "android")
            conn.setFixedLengthStreamingMode(body.size)
            conn.outputStream.use { it.write(body) }
            val status = conn.responseCode
            // 2xx: delivered. Other 4xx (except 429): the server will never accept
            // this report, so drop it instead of retrying on every launch.
            // 429, 5xx (incl. 503 "mail not configured") and network errors:
            // throw, ACRA keeps the approved report and retries later.
            if (status in 200..299) return
            if (status in 400..499 && status != 429) return
            throw ReportSenderException("crash endpoint answered $status")
        } catch (e: IOException) {
            throw ReportSenderException("crash report not delivered", e)
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        private const val TIMEOUT_MS = 15_000

        // Caps mirror server/src/crash.ts, so a long trace is cut here rather
        // than rejected there.
        private const val MAX_STACK = 32_000
        private const val MAX_COMMENT = 2_000
        private const val MAX_SHORT = 200

        /** Builds the wire payload from an explicit allowlist of fields. */
        fun buildPayload(data: CrashReportData): JSONObject {
            fun field(f: ReportField, max: Int): String? =
                data.getString(f)?.let { redact(it).take(max) }?.takeIf { it.isNotEmpty() }

            val json = JSONObject()
            json.put("platform", "android")
            json.put("source", "native")
            fun put(key: String, f: ReportField, max: Int = MAX_SHORT) {
                field(f, max)?.let { json.put(key, it) }
            }
            put("reportId", ReportField.REPORT_ID)
            put("appVersionCode", ReportField.APP_VERSION_CODE)
            put("appVersionName", ReportField.APP_VERSION_NAME)
            put("packageName", ReportField.PACKAGE_NAME)
            put("androidVersion", ReportField.ANDROID_VERSION)
            put("brand", ReportField.BRAND)
            put("phoneModel", ReportField.PHONE_MODEL)
            put("stackTrace", ReportField.STACK_TRACE, MAX_STACK)
            put("stackTraceHash", ReportField.STACK_TRACE_HASH)
            put("userComment", ReportField.USER_COMMENT, MAX_COMMENT)
            put("crashDate", ReportField.USER_CRASH_DATE)
            return json
        }

        // A room link carries the room key in its fragment. Should one ever end
        // up in an exception message, it must not reach a mailbox.
        private val URL_FRAGMENT = Regex("""((?:https?|herebee)://[^\s#]*)#\S*""", RegexOption.IGNORE_CASE)
        private val APP_SCHEME = Regex("""herebee://\S+""", RegexOption.IGNORE_CASE)

        // Coordinates: a decimal with five or more fraction digits.
        private val COORDINATE = Regex("""-?\d{1,3}\.\d{5,}""")

        fun redact(s: String): String = s
            .replace(URL_FRAGMENT, "$1#[redacted]")
            .replace(APP_SCHEME, "herebee://[redacted]")
            .replace(COORDINATE, "[number]")
    }
}

/**
 * The server origin the app uses. The Flutter side mirrors the server in effect
 * (chosen or built in) with `SharedPreferences.getInstance()` under
 * `herebee.reportOrigin` (see reportOriginKey in mobile/lib/core/storage.dart),
 * falling back to the user's choice under `herebee.origin`; on Android that is
 * shared_preferences_android's legacy store: the file "FlutterSharedPreferences"
 * with every key prefixed "flutter.". (The newer SharedPreferencesAsync API keeps
 * its data in a DataStore instead; it is not read here, the default applies.)
 */
object CrashOrigin {
    const val DEFAULT = "https://herebee.app"
    private const val PREFS_FILE = "FlutterSharedPreferences"
    private val PREFS_KEYS = listOf("flutter.herebee.reportOrigin", "flutter.herebee.origin")

    fun resolve(context: Context, allowCleartext: Boolean): String {
        val prefs = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        for (key in PREFS_KEYS) {
            val stored = try {
                prefs.getString(key, null)
            } catch (_: Exception) {
                null // e.g. the key holds a non-string
            }
            normalize(stored, allowCleartext)?.let { return it }
        }
        return DEFAULT
    }

    /** `scheme://host[:port]` of [raw], or null if it is not a usable origin. */
    fun normalize(raw: String?, allowCleartext: Boolean): String? {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return null
        return try {
            val uri = URI(text)
            val scheme = uri.scheme?.lowercase() ?: return null
            if (scheme != "https" && !(allowCleartext && scheme == "http")) return null
            val host = uri.host?.takeIf { it.isNotEmpty() } ?: return null
            if (uri.rawUserInfo != null) return null
            val port = if (uri.port == -1) "" else ":${uri.port}"
            val h = if (host.contains(':') && !host.startsWith("[")) "[$host]" else host
            "$scheme://$h$port"
        } catch (_: Exception) {
            null
        }
    }
}
