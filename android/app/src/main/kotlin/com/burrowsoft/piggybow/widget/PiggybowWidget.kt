package com.burrowsoft.piggybow.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import com.burrowsoft.piggybow.MainActivity
import com.burrowsoft.piggybow.R
import java.time.ZonedDateTime

/**
 * The home-screen widget (feature 16): today's spending and a goal's
 * rainbow, drawn from the snapshot the app hands it ([WidgetStore]). With
 * the app lock on, or without Plus, it shows only the pig and one line.
 *
 * It wakes the phone for nothing: no periodic updates. It's drawn when the
 * app hands it a snapshot, when the system asks (after a restart too), when
 * the time or the time zone changes, and at the start of each day, from an
 * inexact alarm that needs no permission.
 */
class PiggybowWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        draw(context, manager, ids)
        armNextDay(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        draw(context, manager, intArrayOf(id))
    }

    override fun onEnabled(context: Context) = armNextDay(context)

    override fun onDisabled(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(nextDayIntent(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_NEXT_DAY, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> {
                drawAll(context)
                armNextDay(context)
            }
        }
    }

    companion object {
        private const val ACTION_NEXT_DAY = "com.burrowsoft.piggybow.widget.NEXT_DAY"

        /** Wider than this (dp), the widget has room for the goal and "+". */
        private const val WIDE_MIN_WIDTH = 180
        private const val WIDE_MIN_HEIGHT = 100

        /** Every widget on the home screen, from the stored snapshot. */
        fun drawAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PiggybowWidget::class.java))
            if (ids.isNotEmpty()) draw(context, manager, ids)
        }

        private fun draw(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val face = WidgetFaces.decide(
                WidgetStore.load(context),
                WidgetFaces.today(),
                context.getString(R.string.widget_tap_to_open),
            )
            for (id in ids) {
                val options = manager.getAppWidgetOptions(id)
                val wide = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) >= WIDE_MIN_WIDTH &&
                    options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) >= WIDE_MIN_HEIGHT
                manager.updateAppWidget(id, views(context, face, wide))
            }
        }

        private fun views(context: Context, face: WidgetFace, wide: Boolean): RemoteViews {
            val views = RemoteViews(
                context.packageName,
                if (wide) R.layout.widget_wide else R.layout.widget_small,
            )
            // The default theme's colours (the layouts): each Plus theme's own
            // join with the themes (PR #51), from face.theme.
            views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
            when (face) {
                is WidgetFace.Closed -> closed(views, face.text, wide)
                is WidgetFace.Plus -> closed(views, face.text, wide)
                is WidgetFace.Ready -> ready(context, views, face, wide)
            }
            return views
        }

        /**
         * The pig and one line; nothing else, and no "+". (Both layouts have
         * the label, the amount and "+"; only the wide one has the goal.)
         */
        private fun closed(views: RemoteViews, text: String, wide: Boolean) {
            views.setTextViewText(R.id.widget_label, text)
            views.setViewVisibility(R.id.widget_amount, View.GONE)
            views.setViewVisibility(R.id.widget_add, View.GONE)
            if (wide) views.setViewVisibility(R.id.widget_goal, View.GONE)
        }

        private fun ready(context: Context, views: RemoteViews, face: WidgetFace.Ready, wide: Boolean) {
            views.setTextViewText(R.id.widget_label, face.spentLabel)
            views.setViewVisibility(R.id.widget_amount, View.VISIBLE)
            views.setTextViewText(R.id.widget_amount, face.spentToday ?: face.nothingToday)
            if (!wide) {
                views.setViewVisibility(R.id.widget_add, View.GONE)
                return
            }
            views.setViewVisibility(R.id.widget_add, View.VISIBLE)
            views.setOnClickPendingIntent(R.id.widget_add, addSpend(context))
            views.setViewVisibility(R.id.widget_goal, View.VISIBLE)
            val goal = face.goal
            if (goal == null) {
                views.setViewVisibility(R.id.widget_rainbow, View.GONE)
                views.setTextViewText(R.id.widget_goal_name, face.noGoal)
                views.setViewVisibility(R.id.widget_goal_progress, View.GONE)
                return
            }
            views.setViewVisibility(R.id.widget_rainbow, View.VISIBLE)
            views.setContentDescription(R.id.widget_rainbow, goal.label)
            for (i in 0 until 5) {
                views.setImageViewResource(BAND_VIEWS[i], if (goal.bands[i]) BAND_LIT[i] else BAND_TRACK[i])
            }
            views.setTextViewText(R.id.widget_goal_name, goal.name)
            views.setViewVisibility(R.id.widget_goal_progress, View.VISIBLE)
            views.setTextViewText(R.id.widget_goal_progress, goal.progress)
        }

        private val BAND_VIEWS = intArrayOf(
            R.id.widget_band_1, R.id.widget_band_2, R.id.widget_band_3, R.id.widget_band_4, R.id.widget_band_5,
        )
        private val BAND_LIT = intArrayOf(
            R.drawable.widget_band_1, R.drawable.widget_band_2, R.drawable.widget_band_3,
            R.drawable.widget_band_4, R.drawable.widget_band_5,
        )
        private val BAND_TRACK = intArrayOf(
            R.drawable.widget_track_1, R.drawable.widget_track_2, R.drawable.widget_track_3,
            R.drawable.widget_track_4, R.drawable.widget_track_5,
        )

        /**
         * The app, from the widget: its own action, so a running app hears
         * it (onNewIntent) and the lock, if on, comes back first.
         */
        private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            REQUEST_OPEN,
            Intent(context, MainActivity::class.java)
                .setAction(MainActivity.ACTION_OPEN_FROM_WIDGET)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        /**
         * "Add a spend": the home-screen shortcut's own action (#58), which
         * the app answers with the Add sheet on Spent; from the widget, the
         * lock, if on, comes back first.
         */
        private fun addSpend(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            REQUEST_ADD,
            Intent(context, MainActivity::class.java)
                .setAction(MainActivity.ACTION_ADD_SPEND)
                .putExtra(MainActivity.EXTRA_FROM_WIDGET, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        private fun nextDayIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_NEXT_DAY,
            Intent(context, PiggybowWidget::class.java).setAction(ACTION_NEXT_DAY),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        /** An inexact alarm (no permission) for the start of the next day. */
        private fun armNextDay(context: Context) {
            val alarms = context.getSystemService(AlarmManager::class.java) ?: return
            val at = WidgetFaces.nextDay(ZonedDateTime.now()).toInstant().toEpochMilli()
            alarms.set(AlarmManager.RTC, at, nextDayIntent(context))
        }

        private const val REQUEST_OPEN = 1
        private const val REQUEST_ADD = 2
        private const val REQUEST_NEXT_DAY = 3
    }
}
