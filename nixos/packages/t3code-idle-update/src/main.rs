use std::env;
use std::path::Path;
use std::process::ExitCode;
use std::time::Duration;

use rusqlite::{Connection, OpenFlags};

fn is_idle(database: &Connection) -> rusqlite::Result<bool> {
  database.query_row(
    "SELECT NOT EXISTS (
       SELECT 1 FROM orchestration_v2_projection_runs
       WHERE status IS NULL OR status NOT IN ('completed', 'interrupted', 'failed', 'cancelled', 'rolled_back')
     )",
    [],
    |row| row.get(0),
  )
}

fn check(path: &Path) -> rusqlite::Result<bool> {
  let database = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
  database.busy_timeout(Duration::from_secs(1))?;
  is_idle(&database)
}

fn main() -> ExitCode {
  let Some(path) = env::var_os("T3_IDLE_UPDATE_DATABASE") else {
    eprintln!("T3_IDLE_UPDATE_DATABASE is unset");
    return ExitCode::from(2);
  };
  match check(Path::new(&path)) {
    Ok(true) => ExitCode::SUCCESS,
    Ok(false) => ExitCode::from(1),
    Err(error) => {
      eprintln!("Cannot check T3 run status: {error}");
      ExitCode::from(2)
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn only_terminal_runs_are_idle() {
    let db = Connection::open_in_memory().unwrap();
    db.execute(
      "CREATE TABLE orchestration_v2_projection_runs (status TEXT)",
      [],
    )
    .unwrap();
    assert!(is_idle(&db).unwrap());
    for status in [
      "completed",
      "interrupted",
      "failed",
      "cancelled",
      "rolled_back",
    ] {
      db.execute(
        "INSERT INTO orchestration_v2_projection_runs VALUES (?)",
        [status],
      )
      .unwrap();
    }
    assert!(is_idle(&db).unwrap());
    for status in [
      Some("queued"),
      Some("preparing"),
      Some("starting"),
      Some("running"),
      Some("waiting"),
      Some("future-status"),
      None,
    ] {
      db.execute(
        "INSERT INTO orchestration_v2_projection_runs VALUES (?)",
        [status],
      )
      .unwrap();
      assert!(!is_idle(&db).unwrap(), "{status:?}");
      db.execute(
        "DELETE FROM orchestration_v2_projection_runs WHERE status IS ?",
        [status],
      )
      .unwrap();
    }
  }

  #[test]
  fn an_unknown_schema_returns_an_error() {
    assert!(is_idle(&Connection::open_in_memory().unwrap()).is_err());
  }
}
