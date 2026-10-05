//! `setTimeout`, `setInterval`, their `clear` functions and `queueMicrotask`, owned by one runtime.
//!
//! `llrt_timers` keeps its timers in process-wide state, so freeing a runtime with a timer still
//! pending aborts QuickJS on a leaked object. These timers are futures spawned on the runtime
//! itself and die with it.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;
use std::time::Duration;

use rquickjs::prelude::{Func, Opt};
use rquickjs::{CatchResultExt, Ctx, Function, Result};
use tokio::sync::Notify;

use crate::console::Console;

const MIN_INTERVAL: Duration = Duration::from_millis(1);

#[derive(Default)]
struct Timers {
    next_id: Cell<u32>,
    pending: RefCell<HashMap<u32, Rc<Notify>>>,
}

impl Timers {
    fn clear(&self, id: u32) {
        if let Some(cancel) = self.pending.borrow_mut().remove(&id) {
            cancel.notify_one();
        }
    }
}

pub fn install(ctx: &Ctx<'_>, console: Console) -> Result<()> {
    let timers = Rc::new(Timers::default());
    let globals = ctx.globals();

    let (state, log) = (timers.clone(), console.clone());
    globals.set(
        "setTimeout",
        Func::from(move |ctx, callback, delay| {
            schedule(&ctx, &state, &log, callback, delay, false)
        }),
    )?;
    let (state, log) = (timers.clone(), console);
    globals.set(
        "setInterval",
        Func::from(move |ctx, callback, delay| schedule(&ctx, &state, &log, callback, delay, true)),
    )?;
    for name in ["clearTimeout", "clearInterval"] {
        let state = timers.clone();
        globals.set(
            name,
            Func::from(move |id: Opt<u32>| id.0.map(|id| state.clear(id))),
        )?;
    }
    globals.set(
        "queueMicrotask",
        Func::from(|callback: Function| callback.defer::<()>(())),
    )
}

fn schedule<'js>(
    ctx: &Ctx<'js>,
    timers: &Rc<Timers>,
    console: &Console,
    callback: Function<'js>,
    delay: Opt<f64>,
    repeat: bool,
) -> u32 {
    let id = timers.next_id.get();
    timers.next_id.set(id + 1);
    let cancel = Rc::new(Notify::new());
    timers.pending.borrow_mut().insert(id, cancel.clone());

    let delay = Duration::from_millis(delay.0.unwrap_or(0.0).max(0.0) as u64);
    let period = if repeat {
        delay.max(MIN_INTERVAL)
    } else {
        delay
    };
    let (ctx, timers, console) = (ctx.clone(), timers.clone(), console.clone());
    ctx.clone().spawn(async move {
        loop {
            tokio::select! {
                _ = tokio::time::sleep(period) => {}
                _ = cancel.notified() => break,
            }
            if !timers.pending.borrow().contains_key(&id) {
                break;
            }
            if let Err(error) = callback.call::<_, ()>(()).catch(&ctx) {
                console.push(format!(
                    "[error] uncaught in timer: {}",
                    crate::describe_error(error)
                ));
                break;
            }
            if !repeat {
                break;
            }
        }
        timers.pending.borrow_mut().remove(&id);
    });
    id
}
