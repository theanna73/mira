package app.mira.mira

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.mira/calendar")
            .setMethodCallHandler { call, result ->
                if (call.method != "add") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val start = call.argument<Number>("start")?.toLong()
                val end = call.argument<Number>("end")?.toLong()
                val title = call.argument<String>("title")
                if (start == null || end == null || end <= start || title.isNullOrBlank()) {
                    result.error("INVALID_EVENT", "Некорректное событие", null)
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)
                    .putExtra(CalendarContract.Events.TITLE, title)
                    .putExtra(CalendarContract.Events.DESCRIPTION, call.argument<String>("notes"))
                    .putExtra(CalendarContract.Events.EVENT_LOCATION, call.argument<String>("location"))
                    .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start)
                    .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
                try {
                    startActivity(intent)
                    // Android returns only whether the editor was opened, not whether the user saved.
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.error("NO_CALENDAR", "На устройстве нет приложения календаря", null)
                }
            }
    }
}
