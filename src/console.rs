//! A `console` global that records each line for the caller instead of writing to stdout.

use std::sync::{Arc, Mutex};

use rquickjs::prelude::{Func, Rest};
use rquickjs::{Ctx, Object, Result, Value};

#[derive(Clone, Default)]
pub struct Console(Arc<Mutex<Vec<String>>>);

impl Console {
    pub fn push(&self, line: String) {
        self.0.lock().unwrap().push(line);
    }

    pub fn lines(&self) -> Vec<String> {
        self.0.lock().unwrap().clone()
    }

    pub fn install(&self, ctx: &Ctx<'_>) -> Result<()> {
        let console = Object::new(ctx.clone())?;
        for level in ["log", "info", "debug", "warn", "error"] {
            let prefix = match level {
                "warn" | "error" => format!("[{level}] "),
                _ => String::new(),
            };
            let lines = self.clone();
            let log = move |args: Rest<Value<'_>>| {
                let line = match args.0.first() {
                    Some(first) => format_values(&first.ctx().clone(), args.0),
                    None => String::new(),
                };
                lines.push(format!("{prefix}{line}"));
            };
            console.set(level, Func::from(log))?;
        }
        ctx.globals().set("console", console)
    }
}

/// Formats values the way `console.log` prints them.
pub fn format_values<'js>(ctx: &Ctx<'js>, values: Vec<Value<'js>>) -> String {
    llrt_logging::format_plain(ctx.clone(), true, Rest(values))
        .unwrap_or_else(|error| format!("<unformattable value: {error}>"))
}
