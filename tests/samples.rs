//! Every sample states what it must produce in its header; the iOS app shows the same files, so a
//! sample that passes here is one the app can be checked against by eye.

use std::fs;
use std::path::Path;

use playground::run_script;

#[derive(Debug, Default, PartialEq)]
struct Observed {
    value: Option<String>,
    error_contains: Option<String>,
    console: Vec<String>,
}

fn expected(source: &str) -> Observed {
    let mut expected = Observed::default();
    for line in source.lines() {
        if let Some(value) = line.strip_prefix("// expect: ") {
            expected.value = Some(value.to_string());
        } else if let Some(error) = line.strip_prefix("// expect-error: ") {
            expected.error_contains = Some(error.to_string());
        } else if let Some(console) = line.strip_prefix("// expect-console: ") {
            expected.console.push(console.to_string());
        }
    }
    expected
}

async fn observed(source: &str, expected: &Observed) -> Observed {
    let outcome = run_script(source.to_string(), None).await;
    let error_contains = match (&outcome.error, &expected.error_contains) {
        (Some(error), Some(fragment)) if error.contains(fragment.as_str()) => {
            Some(fragment.clone())
        }
        (error, _) => error.clone(),
    };
    Observed {
        value: outcome.value,
        error_contains,
        console: outcome.console,
    }
}

#[tokio::test]
async fn every_sample_produces_what_its_header_expects() {
    let samples_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("samples");
    let mut paths: Vec<_> = fs::read_dir(&samples_dir)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "js"))
        .collect();
    paths.sort();
    assert!(!paths.is_empty(), "no samples in {}", samples_dir.display());

    let mut mismatches = Vec::new();
    for path in &paths {
        let source = fs::read_to_string(path).unwrap();
        let expected = expected(&source);
        let observed = observed(&source, &expected).await;
        if observed != expected {
            let name = path.file_name().unwrap().to_string_lossy();
            mismatches.push(format!(
                "{name}\n  expected {expected:?}\n  observed {observed:?}"
            ));
        }
    }

    assert_eq!(mismatches, Vec::<String>::new());
}
