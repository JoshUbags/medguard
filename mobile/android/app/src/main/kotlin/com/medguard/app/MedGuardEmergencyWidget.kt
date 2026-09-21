package com.medguard.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Emergency-card widget rendered on the user's home screen
 * and (where the OEM exposes it) the lock screen. Reads its payload from
 * shared prefs written by the Flutter [LockScreenWidgetService] via the
 * home_widget plugin, so no MethodChannel plumbing is required.
 *
 * Tapping the widget launches the app at the emergency card route.
 */
class MedGuardEmergencyWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val name = prefs.getString("mg_name", "MedGuard") ?: "MedGuard"
        val allergies = prefs.getString("mg_allergies", "None recorded")
            ?: "None recorded"
        val blood = prefs.getString("mg_blood", "—") ?: "—"
        val contact = prefs.getString("mg_contact", "") ?: ""

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_emergency_card)
            views.setTextViewText(R.id.widget_name, name)
            views.setTextViewText(R.id.widget_allergies, "Allergies: $allergies")
            views.setTextViewText(R.id.widget_blood, "Blood: $blood")
            if (contact.isNotBlank()) {
                views.setTextViewText(R.id.widget_contact, contact)
            } else {
                views.setTextViewText(R.id.widget_contact, "No emergency contact")
            }

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                data = android.net.Uri.parse("medguard://emergency")
            }
            val pending = PendingIntent.getActivity(
                context,
                widgetId,
                launchIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    companion object {
        fun refresh(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, MedGuardEmergencyWidget::class.java),
            )
            val intent = Intent(context, MedGuardEmergencyWidget::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}
