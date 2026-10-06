//! Runs untrusted JavaScript in a QuickJS sandbox with a small set of LLRT web globals.

mod console;
mod timers;

use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use rquickjs::prelude::{Async, Func};
use rquickjs::{
    AsyncContext, AsyncRuntime, CatchResultExt, CaughtError, Ctx, Exception, Object, Promise, Value,
};
use tokio::sync::oneshot;

use crate::console::{Console, format_values};

uniffi::setup_scaffolding!();

const MEMORY_LIMIT_BYTES: usize = 16 * 1024 * 1024;
const MAX_STACK_BYTES: usize = 1024 * 1024;
const THREAD_STACK_BYTES: usize = 8 * 1024 * 1024;
const DEFAULT_TIME_BUDGET: Duration = Duration::from_secs(1);

/// What a script produced: its final value or the error that stopped it, plus everything it logged.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ScriptOutcome {
    pub value: Option<String>,
    pub error: Option<String>,
    pub console: Vec<String>,
    pub duration_ms: u64,
}

/// Receives each console line from the sandbox thread as soon as the script logs it.
#[uniffi::export(with_foreign)]
pub trait ConsoleListener: Send + Sync {
    fn on_line(&self, line: String);
}

/// Runs `source` in a fresh sandbox on its own thread and resolves once it and every timer it
/// scheduled finish, or the time budget (1 second unless given) runs out. The caller's thread is free
/// while it runs.
#[uniffi::export(default(listener = None, time_budget = None))]
pub async fn run_script(
    source: String,
    listener: Option<Arc<dyn ConsoleListener>>,
    time_budget: Option<Duration>,
) -> ScriptOutcome {
    let time_budget = time_budget.unwrap_or(DEFAULT_TIME_BUDGET);
    let (outcome_sender, outcome) = oneshot::channel();
    thread::Builder::new()
        .name("js-sandbox".into())
        .stack_size(THREAD_STACK_BYTES)
        .spawn(move || {
            let sandbox = tokio::runtime::Builder::new_current_thread()
                .enable_time()
                .build()
                .expect("tokio runtime");
            let _ = outcome_sender.send(sandbox.block_on(run_in_sandbox(
                source,
                listener,
                time_budget,
            )));
        })
        .expect("spawn sandbox thread");
    outcome.await.expect("sandbox thread panicked")
}

async fn run_in_sandbox(
    source: String,
    listener: Option<Arc<dyn ConsoleListener>>,
    time_budget: Duration,
) -> ScriptOutcome {
    let started = Instant::now();
    let console = Console::new(listener);
    let result = match evaluate(source, time_budget, console.clone()).await {
        Ok(result) => result,
        Err(error) => Err(format!("sandbox setup failed: {error}")),
    };
    let (value, error) = match result {
        Ok(value) => (Some(value), None),
        Err(error) => (None, Some(error)),
    };
    ScriptOutcome {
        value,
        error,
        console: console.lines(),
        duration_ms: started.elapsed().as_millis() as u64,
    }
}

async fn evaluate(
    source: String,
    time_budget: Duration,
    console: Console,
) -> rquickjs::Result<Result<String, String>> {
    let deadline = Instant::now() + time_budget;
    let runtime = AsyncRuntime::new()?;
    runtime.set_memory_limit(MEMORY_LIMIT_BYTES).await;
    runtime.set_max_stack_size(MAX_STACK_BYTES).await;
    runtime
        .set_interrupt_handler(Some(Box::new(move || Instant::now() > deadline)))
        .await;
    let context = AsyncContext::full(&runtime).await?;

    let run = async {
        let result = context
            .async_with(async |ctx| {
                if let Err(error) = install_globals(&ctx, console) {
                    return Err(format!("installing globals failed: {error}"));
                }
                let completion = async {
                    let promise: Promise = ctx.eval_promise(source)?;
                    let completion: Object = promise.into_future().await?;
                    completion.get::<_, Value>("value")
                };
                completion
                    .await
                    .catch(&ctx)
                    .map(|value| format_values(&ctx, vec![value]))
                    .map_err(describe_error)
            })
            .await;
        runtime.idle().await;
        result
    };
    Ok(tokio::time::timeout_at(deadline.into(), run)
        .await
        .unwrap_or_else(|_| Err(format!("time budget of {time_budget:?} exceeded"))))
}

fn install_globals(ctx: &Ctx<'_>, console: Console) -> rquickjs::Result<()> {
    for init in [
        llrt_abort::init,
        llrt_buffer::init,
        llrt_crypto::init,
        llrt_events::init,
        llrt_url::init,
        llrt_util::init,
    ] {
        init(ctx)?;
    }
    // `AbortSignal.timeout` schedules through `llrt_timers`, which this sandbox does not install.
    ctx.globals()
        .get::<_, Object>("AbortSignal")?
        .remove("timeout")?;

    console.install(ctx)?;
    timers::install(ctx, console)?;

    let host = Object::new(ctx.clone())?;
    host.set("call", Func::from(Async(host_call)))?;
    ctx.globals().set("host", host)
}

/// The API behind the `host` global, showing a native async function exposed to scripts.
async fn host_call<'js>(
    ctx: Ctx<'js>,
    method: String,
    payload: String,
) -> rquickjs::Result<String> {
    match method.as_str() {
        "echo" => Ok(payload),
        "reverse" => Ok(payload.chars().rev().collect()),
        _ => Err(Exception::throw_message(
            &ctx,
            &format!("unknown host method: {method}"),
        )),
    }
}

fn describe_error(error: CaughtError<'_>) -> String {
    match error {
        CaughtError::Exception(exception) => {
            let name: String = exception.get("name").unwrap_or_else(|_| "Error".into());
            let message = exception.message().unwrap_or_default();
            let stack = exception.stack().unwrap_or_default();
            format!("{name}: {message}\n{stack}").trim_end().to_string()
        }
        CaughtError::Value(value) => format!(
            "thrown: {}",
            format_values(value.ctx(), vec![value.clone()])
        ),
        CaughtError::Error(error) => error.to_string(),
    }
}
