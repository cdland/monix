// Answer workers' ask-cockpit questions with an advisor model.
//
// The drainer stages each escalated question into
// <tasks>/guidance/<worker>/<task>/question-N.md alongside the task's
// prompt.md and a guidance-model file; a systemd path unit starts this
// oneshot whenever a question appears. Questions routed to the live cockpit
// (`guidance: cockpit`) are left alone — the drainer publishes those to the
// task's live view and `fleet answer` resolves them.
//
// Runs as the primary user (the guidance spool is root:users 0770), never as
// root: the question text is untrusted worker output and the advisor model
// runs with all tools disallowed.

use std::env;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const ADVISOR_TIMEOUT: Duration = Duration::from_secs(300);
const ADVISOR_UNREACHABLE: &str =
    "(the supervising model could not be reached; proceed on your best judgment)";
const NO_ADVISOR: &str =
    "No advisor is configured for this task — proceed on your own best judgment.";

fn main() {
    let tasks = env::var("FLEET_TASKS_DIR").unwrap_or_else(|_| "/var/lib/agents/tasks".into());
    let default_model = env::var("FLEET_GUIDANCE_MODEL").unwrap_or_default();
    let guidance_root = Path::new(&tasks).join("guidance");
    while sweep(&guidance_root, &default_model) {}
}

/// One pass over every staged question; true if any question was answered
/// (new ones may have appeared meanwhile, so the caller sweeps again).
fn sweep(guidance_root: &Path, default_model: &str) -> bool {
    let mut did_work = false;
    for worker in directories(guidance_root) {
        for task in directories(&worker) {
            for question in questions(&task) {
                did_work |= answer_question(&task, &question, default_model);
            }
        }
    }
    did_work
}

fn directories(path: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<PathBuf> = fs::read_dir(path)
        .map(|reader| {
            reader
                .filter_map(|entry| entry.ok())
                .map(|entry| entry.path())
                .filter(|path| path.is_dir())
                .collect()
        })
        .unwrap_or_default();
    entries.sort();
    entries
}

fn questions(task: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<PathBuf> = fs::read_dir(task)
        .map(|reader| {
            reader
                .filter_map(|entry| entry.ok())
                .map(|entry| entry.path())
                .filter(|path| {
                    path.file_name()
                        .and_then(OsStr::to_str)
                        .map(|name| name.starts_with("question-") && name.ends_with(".md"))
                        .unwrap_or(false)
                })
                .collect()
        })
        .unwrap_or_default();
    entries.sort();
    entries
}

/// The advisor model token, sanitized the way untrusted spool bytes must be:
/// strip everything outside [A-Za-z0-9._/-], keep at most 64 characters.
fn advisor_model(task: &Path, default_model: &str) -> String {
    let raw = fs::read_to_string(task.join("guidance-model")).unwrap_or_default();
    let sanitized: String = raw
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || "._/-".contains(*c))
        .take(64)
        .collect();
    match sanitized.as_str() {
        "none" | "NONE" => String::new(),
        "" => default_model.to_string(),
        _ => sanitized,
    }
}

/// Answer one question; true if it was resolved (false = left for the
/// cockpit or unreadable).
fn answer_question(task: &Path, question: &Path, default_model: &str) -> bool {
    let model = advisor_model(task, default_model);
    if model == "cockpit" {
        return false;
    }
    let Some(number) = question
        .file_name()
        .and_then(OsStr::to_str)
        .and_then(|name| name.strip_prefix("question-"))
        .and_then(|name| name.strip_suffix(".md"))
    else {
        return false;
    };
    let answer = task.join(format!("answer-{number}.md"));

    let body = if model.is_empty() || model == "none" || model == "NONE" {
        format!("{NO_ADVISOR}\n")
    } else {
        println!("answering {}", question.display());
        let question_text = fs::read_to_string(question).unwrap_or_default();
        let guidance = ask_advisor(task, &model, &question_text);
        format!("## Question\n{question_text}\n## Guidance\n{guidance}\n")
    };

    let staged = answer.with_extension("md.tmp");
    if fs::write(&staged, body).is_err() || fs::rename(&staged, &answer).is_err() {
        let _ = fs::remove_file(&staged);
        return false;
    }
    let _ = fs::remove_file(question);
    true
}

fn ask_advisor(task: &Path, model: &str, question: &str) -> String {
    let task_prompt =
        fs::read_to_string(task.join("prompt.md")).unwrap_or_else(|_| "(prompt unavailable)".into());
    let prompt = format!(
        "You supervise a fleet of sandboxed coding/research agents. One of them is \
         working on the task below and has asked you a question. Give concise, decisive \
         guidance it can act on immediately.\n\n\
         == THE AGENT'S TASK ==\n{task_prompt}\n\n\
         == THE AGENT'S QUESTION ==\n{question}"
    );
    let child = Command::new("claude")
        .arg("-p")
        .arg(&prompt)
        .args(["--model", model])
        .arg("--disallowedTools")
        .args([
            "Bash",
            "Edit",
            "Write",
            "Read",
            "Grep",
            "Glob",
            "Task",
            "WebFetch",
            "WebSearch",
            "NotebookEdit",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .spawn();
    let Ok(child) = child else {
        return ADVISOR_UNREACHABLE.into();
    };
    match wait_bounded(child, ADVISOR_TIMEOUT) {
        Some(output) if !output.is_empty() => output,
        _ => ADVISOR_UNREACHABLE.into(),
    }
}

/// Wait for the advisor with a deadline; on expiry kill it and give up.
/// Returns captured stdout only on clean exit.
fn wait_bounded(mut child: std::process::Child, timeout: Duration) -> Option<String> {
    use std::io::Read;
    let deadline = Instant::now() + timeout;
    let mut stdout = child.stdout.take()?;

    let reader = std::thread::spawn(move || {
        let mut buffer = String::new();
        let _ = stdout.read_to_string(&mut buffer);
        buffer
    });
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let output = reader.join().ok()?;
                return status.success().then_some(output.trim_end().to_string());
            }
            Ok(None) if Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                let _ = reader.join();
                return None;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(200)),
            Err(_) => {
                let _ = child.kill();
                let _ = child.wait();
                let _ = reader.join();
                return None;
            }
        }
    }
}
