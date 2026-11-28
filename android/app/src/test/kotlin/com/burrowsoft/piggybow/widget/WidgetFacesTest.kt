package com.burrowsoft.piggybow.widget

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * What the widget draws from each example of test/contracts/widget_snapshot.json,
 * the snapshot the app writes (test/widget_snapshot_test.dart builds the same
 * examples in Dart); a snapshot from an earlier day; one it can't read; and
 * when the next day starts.
 */
class WidgetFacesTest {
    // Gradle runs these with android/app as the working directory.
    private val examples: Map<String, String> =
        JSONObject(File("../../test/contracts/widget_snapshot.json").readText())
            .getJSONArray("examples")
            .let { list ->
                (0 until list.length()).associate {
                    val example = list.getJSONObject(it)
                    example.getString("id") to example.getJSONObject("snapshot").toString()
                }
            }

    private fun face(id: String, today: String = "2026-10-02"): WidgetFace =
        WidgetFaces.decide(examples.getValue(id), today, "Tap to open")

    private val texts = arrayOf("Spent today", "Nothing noted today", "No goal yet")

    @Test
    fun `W1 today's spends and the goal, with its band`() {
        assertEquals(
            WidgetFace.Ready(
                theme = "default",
                spentLabel = texts[0],
                spentToday = "\$15.50",
                nothingToday = texts[1],
                goal = WidgetFace.Goal(
                    name = "Bike",
                    progress = "\$320.00 of \$1,000.00",
                    bands = listOf(true, false, false, false, false),
                    label = "Rainbow 32% filled: \$320.00 of \$1,000.00",
                ),
                noGoal = texts[2],
            ),
            face("W1"),
        )
    }

    @Test
    fun `W2 nothing noted today, and no goal`() {
        assertEquals(
            WidgetFace.Ready("sea", texts[0], null, texts[1], null, texts[2]),
            face("W2"),
        )
    }

    @Test
    fun `W3 a save and no spend is 0, and every band past the target`() {
        val face = face("W3") as WidgetFace.Ready
        assertEquals("\$0.00", face.spentToday)
        assertEquals(List(5) { true }, face.goal?.bands)
    }

    @Test
    fun `W4 the lock on - Tap to open, in the theme`() {
        assertEquals(WidgetFace.Closed("Tap to open", "sea"), face("W4"))
    }

    @Test
    fun `W5 no Plus - Part of Plus, in the default theme`() {
        assertEquals(WidgetFace.Plus("Part of Plus", "default"), face("W5"))
    }

    @Test
    fun `a snapshot from an earlier day - nothing noted today, the goal as it was`() {
        val face = face("W1", today = "2026-10-03") as WidgetFace.Ready
        assertEquals(null, face.spentToday)
        assertEquals("Bike", face.goal?.name)
    }

    @Test
    fun `none yet, one that can't be read, or one it doesn't know - Tap to open`() {
        val closed = WidgetFace.Closed("Tap to open", "default")
        for (snapshot in listOf(
            null,
            "",
            "not json",
            """{"version":2,"state":"ready","theme":"default","text":{}}""",
            """{"version":1,"state":"sideways","theme":"default","text":{}}""",
            """{"version":1,"state":"ready","theme":"default","text":{"spentToday":"Spent today"}}""",
            """{"version":1,"state":"locked","theme":"default","text":{}}""",
        )) {
            assertEquals(snapshot, closed, WidgetFaces.decide(snapshot, "2026-10-02", "Tap to open"))
        }
    }

    @Test
    fun `a goal without five bands - Tap to open`() {
        val snapshot = JSONObject(examples.getValue("W1")).apply {
            getJSONObject("goal").put("bands", org.json.JSONArray(listOf(true, false)))
        }.toString()
        assertEquals(
            WidgetFace.Closed("Tap to open", "default"),
            WidgetFaces.decide(snapshot, "2026-10-02", "Tap to open"),
        )
    }

    @Test
    fun `the next day starts at its own midnight, in the phone's zone`() {
        val bangkok = ZoneId.of("Asia/Bangkok")
        val now = ZonedDateTime.of(2026, 10, 2, 8, 30, 0, 0, bangkok)
        assertEquals(ZonedDateTime.of(2026, 10, 3, 0, 0, 0, 0, bangkok), WidgetFaces.nextDay(now))
        // Late in the evening, still the next day, never later.
        val late = ZonedDateTime.of(2026, 10, 2, 23, 59, 0, 0, bangkok)
        assertEquals(ZonedDateTime.of(2026, 10, 3, 0, 0, 0, 0, bangkok), WidgetFaces.nextDay(late))
        // Across a clock change (New York, 8 March 2026): still the next date.
        val newYork = ZoneId.of("America/New_York")
        val before = ZonedDateTime.of(2026, 3, 7, 22, 0, 0, 0, newYork)
        val next = WidgetFaces.nextDay(before)
        assertEquals("2026-03-08", next.toLocalDate().toString())
        assertEquals(LocalTime.MIDNIGHT, next.toLocalTime())
        assertTrue(next.isAfter(before))
    }
}
