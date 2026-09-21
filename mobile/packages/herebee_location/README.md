# herebee_location

Foreground and background location for HereBee, written by hand rather than
taken off the shelf.

Every common Flutter location package pulls in
`com.google.android.gms:play-services-location`. Keeping that out is what lets
the app run on de-Googled phones and makes the "no third-party SDKs" claim on
the store listing something a reader can check. Android here uses the framework
`LocationManager`; iOS uses CoreLocation.

**The plugin has no network access.** It hands raw fixes to Dart, which encrypts
them, so no coordinate exists in native code in a form it could send anywhere.

## Background behaviour

Android runs a `foregroundServiceType="location"` service with an ongoing
notification carrying a Stop action, plus a partial wake lock, which together
survive a locked screen and deep Doze. iOS uses `UIBackgroundModes: location`
with `allowsBackgroundLocationUpdates` and automatic pausing switched off.

Only **When-In-Use** permission is requested on both platforms. Sharing therefore
ends when the user swipes the app away, and neither platform relaunches it. That
is deliberate: relaunching would need far broader permission than a link-scoped,
ephemeral session justifies.

See `docs/mobile-plan.md` §8 for the measurements and the full rationale.
