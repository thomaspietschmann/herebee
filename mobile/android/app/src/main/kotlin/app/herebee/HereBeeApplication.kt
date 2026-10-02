package app.herebee

import android.app.Application
import android.content.Context
import android.content.pm.ApplicationInfo
import app.herebee.crash.CrashOrigin
import java.net.URI
import org.acra.ReportField
import org.acra.config.dialogConfiguration
import org.acra.data.StringFormat
import org.acra.ktx.initAcra

/**
 * Installs ACRA for opt-in crash reports (see docs/mobile-plan.md §3).
 *
 * Nothing leaves the device without consent: after a crash ACRA's dialog asks
 * the user, and only an accepted report is handed to [app.herebee.crash.HereBeeReportSender],
 * which posts it to the HereBee server the app is using. A declined report is
 * deleted on the next start. The collected fields are restricted to the list
 * below, and the sender forwards only those, so no logcat, device ids, settings
 * or preference dumps are ever gathered.
 */
class HereBeeApplication : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        val debuggable = (base.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        // Shown in the dialog so the user sees where the report would go. The
        // sender re-reads the origin when it actually sends.
        val host = try {
            URI(CrashOrigin.resolve(base, allowCleartext = debuggable)).authority
        } catch (_: Exception) {
            null
        } ?: URI(CrashOrigin.DEFAULT).authority
        initAcra {
            reportFormat = StringFormat.JSON
            reportContent = CRASH_REPORT_FIELDS
            // Declined or never answered: gone on the next launch.
            deleteUnapprovedReportsOnApplicationStart = true
            alsoReportToAndroidFramework = false
            includeDropBoxSystemTags = false
            additionalSharedPreferences = emptyList()
            logcatArguments = emptyList()
            pluginConfigurations = listOf(
                dialogConfiguration {
                    title = base.getString(R.string.crash_dialog_title)
                    text = base.getString(R.string.crash_dialog_text, host)
                    commentPrompt = base.getString(R.string.crash_dialog_comment)
                    positiveButtonText = base.getString(R.string.crash_dialog_send)
                    negativeButtonText = base.getString(R.string.crash_dialog_dont_send)
                    resTheme = R.style.CrashDialogTheme
                },
            )
        }
    }

    companion object {
        /** Everything a report may contain. Keep in step with server/src/crash.ts. */
        val CRASH_REPORT_FIELDS = listOf(
            ReportField.REPORT_ID,
            ReportField.APP_VERSION_CODE,
            ReportField.APP_VERSION_NAME,
            ReportField.PACKAGE_NAME,
            ReportField.ANDROID_VERSION,
            ReportField.BRAND,
            ReportField.PHONE_MODEL,
            ReportField.STACK_TRACE,
            ReportField.STACK_TRACE_HASH,
            ReportField.USER_COMMENT,
            ReportField.USER_CRASH_DATE,
        )
    }
}
