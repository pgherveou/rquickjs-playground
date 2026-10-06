//! The app awaits many sandboxes from a few threads, so a run must not hold its caller's thread while
//! the script waits.

use std::time::{Duration, Instant};

use playground::run_script;
use tokio::task::JoinSet;

#[tokio::test]
async fn one_caller_thread_awaits_ten_waiting_scripts_at_once() {
    let script = "await new Promise((resolve) => setTimeout(resolve, 200)); 'done'";
    let started = Instant::now();

    let mut runs = JoinSet::new();
    for _ in 0..10 {
        runs.spawn(run_script(script.to_string(), None, None));
    }
    let values: Vec<_> = runs
        .join_all()
        .await
        .into_iter()
        .map(|outcome| outcome.value)
        .collect();

    assert_eq!(values, vec![Some("done".to_string()); 10]);
    assert!(
        started.elapsed() < Duration::from_secs(1),
        "runs were serialized: {:?}",
        started.elapsed()
    );
}
