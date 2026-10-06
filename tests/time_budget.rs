//! The sandbox stops a script once its time budget runs out. A host that expects longer scripts, such as
//! the parallel benchmark keeping every sandbox alive for seconds, grants a larger budget for those runs
//! only, while every other script keeps the default.

use std::time::Duration;

use playground::run_script;

const WAITS_1500_MS: &str = r#"
    await new Promise((resolve) => setTimeout(resolve, 1500));
    "waited"
"#;

#[tokio::test]
async fn the_default_budget_stops_a_script_waiting_longer_than_a_second() {
    let outcome = run_script(WAITS_1500_MS.to_string(), None, None).await;

    assert_eq!(
        (outcome.value, outcome.error),
        (None, Some("time budget of 1s exceeded".to_string()))
    );
}

#[tokio::test]
async fn a_larger_budget_lets_the_same_script_finish() {
    let outcome = run_script(
        WAITS_1500_MS.to_string(),
        None,
        Some(Duration::from_secs(2)),
    )
    .await;

    assert_eq!(
        (outcome.value, outcome.error),
        (Some("waited".to_string()), None)
    );
}
