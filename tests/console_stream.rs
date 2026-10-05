//! A host showing several sandboxes interleaves their console lines as they are logged, so a line must
//! reach the listener when the script logs it, not when the script ends.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use playground::{ConsoleListener, run_script};

struct Recorder {
    started: Instant,
    lines: Mutex<Vec<(String, Duration)>>,
}

impl ConsoleListener for Recorder {
    fn on_line(&self, line: String) {
        self.lines
            .lock()
            .unwrap()
            .push((line, self.started.elapsed()));
    }
}

#[tokio::test]
async fn each_console_line_reaches_the_listener_when_it_is_logged() {
    let recorder = Arc::new(Recorder {
        started: Instant::now(),
        lines: Mutex::new(Vec::new()),
    });
    let script = r#"
        console.log("start");
        await new Promise((resolve) => setTimeout(resolve, 300));
        console.log("done");
    "#;

    let outcome = run_script(script.to_string(), Some(recorder.clone())).await;

    let lines = recorder.lines.lock().unwrap().clone();
    let names: Vec<_> = lines.iter().map(|(line, _)| line.as_str()).collect();
    assert_eq!(names, ["start", "done"]);
    assert_eq!(outcome.console, ["start", "done"]);
    assert!(
        lines[0].1 < Duration::from_millis(150),
        "start arrived late: {:?}",
        lines[0].1
    );
    assert!(
        lines[1].1 >= Duration::from_millis(300),
        "done arrived early: {:?}",
        lines[1].1
    );
}
