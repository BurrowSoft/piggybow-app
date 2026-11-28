package com.burrowsoft.piggybow.widget

import android.content.Context

/**
 * The last snapshot the app handed the widget, in a SharedPreferences file of
 * its own (piggybow_widget.xml). The backup rules name only the journal and
 * the app's settings, so this file is never backed up or moved to a new
 * phone: the app writes it again when it opens.
 */
object WidgetStore {
    private const val FILE = "piggybow_widget"
    private const val SNAPSHOT = "snapshot"

    fun load(context: Context): String? =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString(SNAPSHOT, null)

    /** Kept before the widget is drawn from it (commit, not apply). */
    fun save(context: Context, snapshot: String) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putString(SNAPSHOT, snapshot)
            .commit()
    }
}
