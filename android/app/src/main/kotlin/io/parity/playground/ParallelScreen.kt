package io.parity.playground

import android.os.SystemClock
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import uniffi.playground.ConsoleListener
import uniffi.playground.runScript

/** The script for one parallel sandbox, with its number written into the source. */
private object WorkerScript {
    fun source(worker: Int) = """console.log("worker $worker start");
await new Promise((resolve) => setTimeout(resolve, 200));
console.log("worker $worker done");"""
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ParallelScreen(onBack: () -> Unit) {
    var count by rememberSaveable { mutableIntStateOf(10) }
    var log by remember { mutableStateOf(listOf<String>()) }
    var summary by remember { mutableStateOf<String?>(null) }
    var isRunning by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Parallel sandboxes") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Sandboxes: $count", modifier = Modifier.weight(1f))
                OutlinedButton(onClick = { count-- }, enabled = !isRunning && count > 1) { Text("−") }
                OutlinedButton(onClick = { count++ }, enabled = !isRunning && count < 100) { Text("+") }
            }
            CodeBlock("Script for sandbox 1", WorkerScript.source(1))
            Button(
                onClick = {
                    log = emptyList()
                    summary = null
                    isRunning = true
                    val sandboxes = count
                    val console = object : ConsoleListener {
                        override fun onLine(line: String) {
                            scope.launch { log = log + line }
                        }
                    }
                    scope.launch {
                        val started = SystemClock.elapsedRealtime()
                        coroutineScope {
                            for (worker in 1..sandboxes) {
                                launch {
                                    runScript(WorkerScript.source(worker), console).error?.let {
                                        log = log + "worker $worker failed: $it"
                                    }
                                }
                            }
                        }
                        summary = "$sandboxes sandboxes finished in ${SystemClock.elapsedRealtime() - started} ms"
                        isRunning = false
                    }
                },
                enabled = !isRunning,
            ) {
                Text(if (isRunning) "Running…" else "Run")
            }
            summary?.let { Text(it, style = MaterialTheme.typography.titleMedium) }
            if (log.isNotEmpty()) {
                CodeBlock("Console, in arrival order", log.joinToString("\n"))
            }
        }
    }
}
