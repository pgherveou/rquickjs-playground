package io.parity.playground

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import uniffi.playground.ScriptOutcome
import uniffi.playground.runScript

private val ResultGreen = Color(0xFF2E7D32)

@Composable
fun PlaygroundApp(samples: List<Sample>) {
    var selectedFile by rememberSaveable { mutableStateOf<String?>(null) }
    var showParallel by rememberSaveable { mutableStateOf(false) }
    val selected = samples.firstOrNull { it.fileName == selectedFile }
    when {
        showParallel -> {
            BackHandler { showParallel = false }
            ParallelScreen(onBack = { showParallel = false })
        }
        selected != null -> {
            BackHandler { selectedFile = null }
            SampleDetail(selected, onBack = { selectedFile = null })
        }
        else -> SampleList(
            samples,
            onSelect = { selectedFile = it.fileName },
            onParallel = { showParallel = true },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SampleList(samples: List<Sample>, onSelect: (Sample) -> Unit, onParallel: () -> Unit) {
    Scaffold(topBar = { TopAppBar(title = { Text("QuickJS sandbox") }) }) { padding ->
        LazyColumn(contentPadding = padding) {
            item {
                ListItem(
                    headlineContent = { Text("Parallel sandboxes") },
                    modifier = Modifier.clickable(onClick = onParallel),
                )
                HorizontalDivider()
                Text(
                    "Samples",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, top = 24.dp, bottom = 8.dp),
                )
            }
            items(samples, key = { it.fileName }) { sample ->
                ListItem(
                    headlineContent = { Text(sample.title) },
                    modifier = Modifier.clickable { onSelect(sample) },
                )
                HorizontalDivider()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SampleDetail(sample: Sample, onBack: () -> Unit) {
    var outcome by remember(sample) { mutableStateOf<ScriptOutcome?>(null) }
    var isRunning by remember(sample) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(sample.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
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
            CodeBlock("Script", sample.source)
            Button(
                onClick = {
                    outcome = null
                    isRunning = true
                    scope.launch {
                        outcome = runScript(sample.source)
                        isRunning = false
                    }
                },
                enabled = !isRunning,
            ) {
                Text(if (isRunning) "Running…" else "Run")
            }
            outcome?.let { result ->
                result.value?.let { CodeBlock("Result", it, ResultGreen) }
                result.error?.let { CodeBlock("Error", it, MaterialTheme.colorScheme.error) }
                if (result.console.isNotEmpty()) {
                    CodeBlock("Console", result.console.joinToString("\n"))
                }
                Text(
                    "${result.durationMs} ms",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
fun CodeBlock(title: String, text: String, color: Color = Color.Unspecified) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(
            text,
            fontFamily = FontFamily.Monospace,
            fontSize = 13.sp,
            color = color,
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(8.dp))
                .padding(10.dp),
        )
    }
}
