package io.parity.playground

import android.content.res.AssetManager

/** A script from the repository's `samples/` directory, packaged as an app asset. */
data class Sample(val fileName: String, val title: String, val source: String) {
    companion object {
        private const val TITLE_PREFIX = "// title: "

        fun loadAll(assets: AssetManager): List<Sample> =
            assets.list("").orEmpty()
                .filter { it.endsWith(".js") }
                .sorted()
                .map { fileName ->
                    val source = assets.open(fileName).bufferedReader().use { it.readText() }
                    val title = source.lineSequence()
                        .firstOrNull { it.startsWith(TITLE_PREFIX) }
                        ?.removePrefix(TITLE_PREFIX)
                    Sample(fileName, title ?: fileName, source)
                }
    }
}
