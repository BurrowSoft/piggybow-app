package com.burrowsoft.piggybow.widget

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * What the home-screen widget draws (feature 16), decided from the snapshot
 * the app hands it (lib/features/widget/widget_snapshot.dart; its shape is
 * test/contracts/widget_snapshot.json). The widget never reads the journal.
 *
 * Plain Kotlin and org.json, so it's tested on the JVM (src/test).
 */
sealed interface WidgetFace {
    /** The theme's id ("default" without Plus). */
    val theme: String

    /**
     * The pig and one line: no snapshot yet, one the widget can't read or
     * doesn't know, or the app lock on. A tap opens the app.
     */
    data class Closed(val text: String, override val theme: String) : WidgetFace

    /** No Plus: the pig and "Part of Plus". A tap opens the app. */
    data class Plus(val text: String, override val theme: String) : WidgetFace

    /** Today's spending and the goal. The body opens the app; "+" adds. */
    data class Ready(
        override val theme: String,
        val spentLabel: String,
        /** Today's spends, or null: nothing noted today ([nothingToday]). */
        val spentToday: String?,
        val nothingToday: String,
        /** Null: no goal ([noGoal]). */
        val goal: Goal?,
        val noGoal: String,
    ) : WidgetFace

    data class Goal(
        val name: String,
        val progress: String,
        /** Five, outer to inner: lit once reached. */
        val bands: List<Boolean>,
        /** The rainbow for screen readers. */
        val label: String,
    )
}

object WidgetFaces {
    /** The snapshot shape this widget knows. */
    const val VERSION = 1

    /** The theme when no other applies. */
    const val DEFAULT_THEME = "default"

    /**
     * The face for [snapshot] on [today] (the phone's local date, YYYY-MM-DD).
     * [closedText] is "Tap to open" in the app's words, for when there's no
     * snapshot to take it from.
     *
     * A ready snapshot made on an earlier day shows nothing noted today: the
     * day's entries can only be added in the app, which would have written a
     * new one. Its goal stays.
     */
    fun decide(snapshot: String?, today: String, closedText: String): WidgetFace {
        val closed = WidgetFace.Closed(closedText, DEFAULT_THEME)
        if (snapshot == null) return closed
        return try {
            val o = JSONObject(snapshot)
            if (o.optInt("version") != VERSION) return closed
            val text = o.getJSONObject("text")
            when (o.getString("state")) {
                "plus" -> WidgetFace.Plus(text.getString("plus"), DEFAULT_THEME)
                "locked" -> WidgetFace.Closed(text.getString("locked"), o.getString("theme"))
                "ready" -> WidgetFace.Ready(
                    theme = o.getString("theme"),
                    spentLabel = text.getString("spentToday"),
                    spentToday = if (o.getString("day") == today && !o.isNull("spentToday")) {
                        o.getString("spentToday")
                    } else {
                        null
                    },
                    nothingToday = text.getString("nothingToday"),
                    goal = if (o.isNull("goal")) null else goal(o.getJSONObject("goal")),
                    noGoal = text.getString("noGoal"),
                )
                else -> closed
            }
        } catch (e: JSONException) {
            closed
        }
    }

    private fun goal(g: JSONObject): WidgetFace.Goal {
        val bands: JSONArray = g.getJSONArray("bands")
        if (bands.length() != 5) throw JSONException("five bands")
        return WidgetFace.Goal(
            name = g.getString("name"),
            progress = g.getString("progress"),
            bands = List(5) { bands.getBoolean(it) },
            label = g.getString("label"),
        )
    }

    /** Today on the phone, as the snapshot writes it. */
    fun today(zone: ZoneId = ZoneId.systemDefault()): String = LocalDate.now(zone).toString()

    /**
     * When the next day starts after [now], in its own zone: the time to
     * draw "today" again (a day starting off midnight, as some DST changes
     * do, is handled by java.time).
     */
    fun nextDay(now: ZonedDateTime): ZonedDateTime =
        now.toLocalDate().plusDays(1).atStartOfDay(now.zone)
}
