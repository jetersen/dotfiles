//! Workstation fields. Read live kernel state directly; cache expensive commands
//! by immutable store target, never by a timeout or a Nix hash query.
use crate::{Error, Fields};
use std::{
  collections::BTreeSet,
  env, format, fs,
  io::{self, Write},
  path::{Path, PathBuf},
  process::{Command, Stdio},
  string::{String, ToString},
  vec::Vec,
};

fn read(path: impl AsRef<Path>) -> String {
  fs::read_to_string(path)
    .unwrap_or_default()
    .trim()
    .to_string()
}
fn setting(text: &str, key: &str) -> Option<String> {
  text
    .lines()
    .filter_map(|l| l.trim().split_once('='))
    .find_map(|(k, v)| (k.trim() == key).then(|| v.trim().trim_matches('"').to_string()))
}
fn command(program: &str, args: &[&str]) -> Option<String> {
  let out = Command::new(program)
    .args(args)
    .env("LC_ALL", "C")
    .stdin(Stdio::null())
    .stderr(Stdio::null())
    .output()
    .ok()?;
  out
    .status
    .success()
    .then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}
fn cache_root() -> PathBuf {
  env::var_os("XDG_CACHE_HOME")
    .map(PathBuf::from)
    .unwrap_or_else(|| home().join(".cache"))
    .join("microfetch/v2")
}
fn home() -> PathBuf {
  env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}
fn cached_value(text: &str, target: &str) -> Option<String> {
  let (key, value) = text.split_once('\n')?;
  (key == target && !value.trim().is_empty()).then(|| value.trim().to_string())
}
fn write_cache(path: &Path, target: &str, value: &str) {
  if let Some(parent) = path.parent() {
    if fs::create_dir_all(parent).is_err() {
      return;
    }
    let tmp = path.with_extension(format!("{}.tmp", std::process::id()));
    if fs::write(&tmp, format!("{target}\n{value}\n")).is_ok() {
      let _ = fs::rename(&tmp, path);
    }
    let _ = fs::remove_file(tmp);
  }
}
fn versioned_package(name: &str) -> bool {
  let name = name
    .split_once('-')
    .filter(|(hash, _)| hash.len() == 32)
    .map_or(name, |(_, name)| name);
  if name.starts_with("nixos-system-")
    || ["-doc", "-man", "-info", "-dev", "-bin"]
      .iter()
      .any(|s| name.ends_with(s))
  {
    return false;
  }
  name
    .as_bytes()
    .windows(3)
    .any(|w| w[0].is_ascii_digit() && w[1] == b'.' && w[2].is_ascii_digit())
}
fn count_profile_with(
  profile: &Path,
  cache: &Path,
  query: impl FnOnce(&Path) -> Option<String>,
) -> Option<u32> {
  let target = fs::canonicalize(profile).ok()?;
  // Only immutable store targets are safe cache keys.
  if !target.starts_with("/nix/store") {
    return None;
  }
  count_target_with(&target, cache, query)
}
fn count_target_with(
  target: &Path,
  cache: &Path,
  query: impl FnOnce(&Path) -> Option<String>,
) -> Option<u32> {
  let key = target.to_str()?;
  if let Some(count) = cached_value(&read(cache), key).and_then(|v| v.parse().ok()) {
    return Some(count);
  }
  let paths = query(target)?;
  let count = paths
    .lines()
    .filter(|p| {
      let p = Path::new(p);
      p.is_dir()
        && p
          .file_name()
          .and_then(|n| n.to_str())
          .is_some_and(versioned_package)
    })
    .count() as u32;
  write_cache(cache, key, &count.to_string());
  Some(count)
}
fn packages() -> String {
  let user = env::var("USER").unwrap_or_default();
  let state = env::var_os("XDG_STATE_HOME")
    .map(PathBuf::from)
    .unwrap_or_else(|| home().join(".local/state"));
  let profiles = [
    ("system", PathBuf::from("/run/current-system")),
    ("default", PathBuf::from("/nix/var/nix/profiles/default")),
    ("user", home().join(".nix-profile")),
    ("user", state.join("nix/profile")),
    ("user", PathBuf::from("/etc/profiles/per-user").join(user)),
  ];
  let mut seen = BTreeSet::new();
  let mut counts = [None, None, None];
  for (i, (kind, profile)) in profiles.iter().enumerate() {
    let Ok(target) = fs::canonicalize(profile) else {
      continue;
    };
    if !seen.insert((kind, target)) {
      continue;
    }
    let count = count_profile_with(
      profile,
      &cache_root().join(format!("packages-{i}")),
      |target| {
        command(
          env!("MICROFETCH_NIX_STORE"),
          &["--query", "--requisites", target.to_str()?],
        )
      },
    );
    let slot = match *kind {
      "system" => 0,
      "default" => 1,
      _ => 2,
    };
    if let Some(count) = count {
      counts[slot] = Some(counts[slot].unwrap_or(0) + count);
    }
  }
  counts
    .iter()
    .zip(["nix-system", "nix-default", "nix-user"])
    .filter_map(|(n, k)| n.map(|n| format!("{n} ({k})")))
    .collect::<Vec<_>>()
    .join(", ")
}
fn shell_version(fallback: &str) -> String {
  let Some(shell) = env::var_os("SHELL") else {
    return fallback.to_string();
  };
  let Ok(target) = fs::canonicalize(&shell) else {
    return fallback.to_string();
  };
  let key = target.to_string_lossy();
  let cache = cache_root().join("shell-version");
  if target.starts_with("/nix/store") {
    if let Some(value) = cached_value(&read(&cache), &key) {
      return value;
    }
  }
  let Some(output) = command(&key, &["--version"]) else {
    return fallback.to_string();
  };
  let version = output
    .split_whitespace()
    .find(|s| s.starts_with(|c: char| c.is_ascii_digit()))
    .unwrap_or("")
    .trim_end_matches([',', ')']);
  let value = format!("{fallback} {version}");
  if target.starts_with("/nix/store") {
    write_cache(&cache, &key, &value);
  }
  value
}
fn gpu_rows() -> Vec<String> {
  let ids = read(env!("MICROFETCH_PCI_IDS"));
  let mut result = Vec::new();
  let Ok(entries) = fs::read_dir("/sys/class/drm") else {
    return result;
  };
  for entry in entries.flatten() {
    let name = entry.file_name().to_string_lossy().into_owned();
    if !name.starts_with("card") || !name[4..].chars().all(|c| c.is_ascii_digit()) {
      continue;
    }
    let device = entry.path().join("device");
    let vendor = read(device.join("vendor"))
      .trim_start_matches("0x")
      .to_string();
    let id = read(device.join("device"))
      .trim_start_matches("0x")
      .to_string();
    if vendor.is_empty() || id.is_empty() {
      continue;
    }
    let mut in_vendor = false;
    let mut label = format!("PCI {vendor}:{id}");
    for line in ids.lines() {
      if line.starts_with('#') || line.is_empty() {
        continue;
      }
      if !line.starts_with('\t') {
        in_vendor = line.starts_with(&format!("{vendor}  "));
      } else if in_vendor && line.starts_with(&format!("\t{id}  ")) {
        label = line[7..].trim().to_string();
        break;
      }
    }
    let driver = fs::read_link(device.join("driver"))
      .ok()
      .and_then(|p| p.file_name().map(|s| s.to_string_lossy().into_owned()));
    if let Some(driver) = driver {
      label.push_str(&format!(" [{driver}]"));
    }
    result.push(label);
  }
  result
}
fn edid_model(edid: &[u8]) -> Option<String> {
  if edid.len() < 128 || edid[..8] != [0, 255, 255, 255, 255, 255, 255, 0] {
    return None;
  }
  let vendor = u16::from_be_bytes([edid[8], edid[9]]);
  let mut manufacturer = String::new();
  for shift in [10, 5, 0] {
    let letter = ((vendor >> shift) & 31) as u8;
    if !(1..=26).contains(&letter) {
      return None;
    }
    manufacturer.push((b'A' + letter - 1) as char);
  }
  let id = format!(
    "{manufacturer}{:04X}",
    u16::from_le_bytes([edid[10], edid[11]])
  );
  let name = edid[54..126].chunks_exact(18).find_map(|block| {
    (block[..5] == [0, 0, 0, 0xfc, 0])
      .then(|| String::from_utf8_lossy(&block[5..]).trim().to_string())
      .filter(|name| !name.is_empty())
  });
  Some(name.map_or(id.clone(), |name| format!("{name} [{id}]")))
}
fn display_model(connector: &str) -> Option<String> {
  fs::read_dir("/sys/class/drm")
    .ok()?
    .flatten()
    .find_map(|entry| {
      let name = entry.file_name();
      let (_, output) = name.to_str()?.split_once('-')?;
      if output != connector {
        return None;
      }
      edid_model(&fs::read(entry.path().join("edid")).ok()?)
    })
}
fn displays() -> Vec<String> {
  // Niri IPC includes live mode, scaling, refresh rate and physical dimensions.
  if env::var_os("NIRI_SOCKET").is_none() {
    return Vec::new();
  }
  let Some(text) = command(env!("MICROFETCH_NIRI"), &["msg", "outputs"]) else {
    return Vec::new();
  };
  parse_displays(&text, display_model)
}
fn parse_displays(text: &str, model: impl Fn(&str) -> Option<String>) -> Vec<String> {
  let mut result = Vec::new();
  let mut name = String::new();
  let mut mode = String::new();
  let mut scale = String::new();
  let mut size = String::new();
  let flush = |result: &mut Vec<String>, name: &str, mode: &str, scale: &str, size: &str| {
    if !mode.is_empty() {
      result.push(format!("{name}: {mode}{scale}{size}"));
    }
  };
  for line in text.lines() {
    if line.starts_with("Output ") {
      flush(&mut result, &name, &mode, &scale, &size);
      let connector = line
        .rsplit_once('(')
        .map(|(_, s)| s.trim_end_matches(')'))
        .unwrap_or("Display");
      let description = line
        .strip_prefix("Output \"")
        .and_then(|s| s.rsplit_once("\" ("))
        .map(|(description, _)| description);
      name = model(connector)
        .or_else(|| {
          description
            .filter(|s| !s.is_empty())
            .map(ToString::to_string)
        })
        .map_or_else(
          || connector.to_string(),
          |model| format!("{model} ({connector})"),
        );
      mode.clear();
      scale.clear();
      size.clear();
    } else if let Some(value) = line.trim().strip_prefix("Current mode: ") {
      if value != "disabled" {
        mode = value.replace(" (preferred)", "");
      }
    } else if let Some(value) = line.trim().strip_prefix("Scale: ") {
      scale = format!(", {value}x");
    } else if let Some(value) = line.trim().strip_prefix("Physical size: ") {
      size = format!(", {value}");
    }
  }
  flush(&mut result, &name, &mode, &scale, &size);
  result
}
fn swap() -> String {
  let text = read("/proc/meminfo");
  let value = |key: &str| {
    text
      .lines()
      .find_map(|line| {
        line
          .strip_prefix(key)?
          .split_whitespace()
          .next()?
          .parse::<f64>()
          .ok()
      })
      .unwrap_or(0.0)
  };
  let total = value("SwapTotal:");
  let free = value("SwapFree:");
  if total == 0.0 {
    return "Disabled".to_string();
  }
  format!(
    "{:.2} GiB / {:.2} GiB ({:.0}%)",
    (total - free) / 1048576.0,
    total / 1048576.0,
    (total - free) / total * 100.0
  )
}
fn filesystem() -> String {
  read("/proc/self/mountinfo")
    .lines()
    .find_map(|line| {
      let (mount, rest) = line.split_once(" - ")?;
      (mount.split_whitespace().nth(4)? == "/")
        .then(|| rest.split_whitespace().next().unwrap_or("").to_string())
    })
    .unwrap_or_default()
}
fn battery_info(path: &Path) -> String {
  let capacity = read(path.join("capacity"));
  if capacity.is_empty() {
    return String::new();
  }
  let status = read(path.join("status"));
  let mut value = format!("{capacity}% [{status}]");
  if status == "Discharging" {
    // energy/power and charge/current both yield hours. Ignore idle readings.
    for (amount, rate) in [("energy_now", "power_now"), ("charge_now", "current_now")] {
      let amount = read(path.join(amount)).parse::<f64>().unwrap_or(0.0);
      let rate = read(path.join(rate)).parse::<f64>().unwrap_or(0.0);
      let minutes = amount / rate * 60.0;
      if rate > 0.0 && (1.0..1440.0).contains(&minutes) {
        value.push_str(&format!(
          ", {}h {}m remaining",
          minutes as u64 / 60,
          minutes as u64 % 60
        ));
        break;
      }
    }
  }
  value
}
fn power_rows() -> Vec<(String, String)> {
  let mut rows = Vec::new();
  let mut adapters = Vec::new();
  let mut ac_connected = false;
  let mut has_adapter = false;
  if let Ok(entries) = fs::read_dir("/sys/class/power_supply") {
    let mut entries: Vec<_> = entries.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
      let path = entry.path();
      if read(path.join("type")) == "Battery" {
        let value = battery_info(&path);
        if !value.is_empty() {
          rows.push(("Battery".to_string(), value));
        }
      } else if path.join("online").exists() {
        has_adapter = true;
        if read(path.join("online")) != "1" {
          continue;
        }
        ac_connected = true;
        let voltage = read(path.join("voltage_max")).parse::<f64>().unwrap_or(0.0);
        let current = read(path.join("current_max")).parse::<f64>().unwrap_or(0.0);
        if voltage > 0.0 && current > 0.0 {
          let kind = read(path.join("type"));
          adapters.push(format!("{kind} ({:.0} W)", voltage * current / 1e12));
        }
      }
    }
  }
  if has_adapter {
    let value = if !ac_connected {
      "Disconnected".to_string()
    } else if adapters.is_empty() {
      "Connected".to_string()
    } else {
      adapters.join(", ")
    };
    rows.push(("Power adapter".to_string(), value));
  }
  rows
}
fn terminal_hint(term: &str, program: &str) -> Option<String> {
  if term == "alacritty" {
    Some("Alacritty".to_string())
  } else {
    (!program.is_empty()).then(|| program.to_string())
  }
}
fn days_on_linux(now: std::time::SystemTime) -> String {
  // First day on Linux: 2024-06-07, matching the former fastfetch command.
  const START: u64 = 1_717_718_400;
  let seconds = now
    .duration_since(std::time::UNIX_EPOCH)
    .unwrap_or_default()
    .as_secs();
  format!("{} days", seconds.saturating_sub(START) / 86_400)
}
fn terminal() -> String {
  if let Some(term) = terminal_hint(
    &env::var("TERM").unwrap_or_default(),
    &env::var("TERM_PROGRAM").unwrap_or_default(),
  ) {
    return term;
  }
  let mut pid = std::process::id();
  for _ in 0..12 {
    let status = read(format!("/proc/{pid}/status"));
    let Some(parent) = status
      .lines()
      .find_map(|l| l.strip_prefix("PPid:")?.trim().parse::<u32>().ok())
    else {
      break;
    };
    if parent <= 1 {
      break;
    }
    pid = parent;
    let name = read(format!("/proc/{pid}/comm"));
    if [
      "alacritty",
      "kitty",
      "foot",
      "wezterm-gui",
      "codex",
      "konsole",
      "gnome-terminal-",
    ]
    .iter()
    .any(|n| name.starts_with(n))
    {
      return name;
    }
  }
  env::var("TERM").unwrap_or_default()
}
fn config_dir() -> PathBuf {
  env::var_os("XDG_CONFIG_HOME")
    .map(PathBuf::from)
    .unwrap_or_else(|| home().join(".config"))
}
fn alacritty_font(text: &str) -> Option<String> {
  let mut section = "";
  let mut font = None;
  let mut size = None;
  for line in text.lines().map(str::trim) {
    if line.starts_with('[') {
      section = line;
    }
    if section == "[font]" {
      font = setting(line, "normal.family").or(font);
      size = setting(line, "size").or(size);
    } else if section == "[font.normal]" {
      font = setting(line, "family").or(font);
    }
  }
  font.map(|font| {
    format!(
      "{font}{}",
      size.map(|s| format!(" ({s}pt)")).unwrap_or_default()
    )
  })
}
fn appearance() -> Vec<(String, String)> {
  let config = config_dir();
  let gtk = read(config.join("gtk-3.0/settings.ini"));
  let gtk4 = read(config.join("gtk-4.0/settings.ini"));
  let mut rows = Vec::new();
  for (label, key) in [
    ("Theme", "gtk-theme-name"),
    ("Icons", "gtk-icon-theme-name"),
    ("Font", "gtk-font-name"),
  ] {
    if let Some(value) = setting(&gtk, key).or_else(|| setting(&gtk4, key)) {
      rows.push((label.to_string(), value));
    }
  }
  let cursor = env::var("XCURSOR_THEME")
    .ok()
    .or_else(|| setting(&gtk, "gtk-cursor-theme-name"));
  let size = env::var("XCURSOR_SIZE")
    .ok()
    .or_else(|| setting(&gtk, "gtk-cursor-theme-size"));
  if let Some(cursor) = cursor {
    rows.push((
      "Cursor".to_string(),
      format!(
        "{cursor}{}",
        size.map(|s| format!(" ({s})")).unwrap_or_default()
      ),
    ));
  }
  // Niri does not expose a separate WM theme. GTK theme is reported above.
  let term = terminal();
  if !term.is_empty() {
    rows.push(("Terminal".to_string(), term.clone()));
  }
  if term.eq_ignore_ascii_case("alacritty") {
    let text = read(config.join("alacritty/alacritty.toml"));
    if let Some(font) = alacritty_font(&text) {
      rows.push(("Terminal font".to_string(), font));
    }
  }
  rows
}
fn local_ips() -> Vec<String> {
  command(
    env!("MICROFETCH_IP"),
    &["-o", "-4", "addr", "show", "up", "scope", "global"],
  )
  .unwrap_or_default()
  .lines()
  .filter_map(|line| {
    let mut parts = line.split_whitespace();
    parts.next()?;
    let iface = parts.next()?;
    parts.next()?;
    let addr = parts.next()?;
    // Avoid listing container bridges and overlay networks on the startup card.
    (iface.starts_with("en") || iface.starts_with("eth") || iface.starts_with("wl"))
      .then(|| format!("{iface}: {addr}"))
  })
  .collect()
}

pub(super) fn render(fields: &Fields) -> Result<(), Error> {
  let mut rows: Vec<(String, String)> = Vec::new();
  let mut add = |k: &str, v: String| {
    if !v.is_empty() {
      rows.push((k.to_string(), v));
    }
  };
  add("", fields.user_info.clone());
  add("System", fields.os_name.clone());
  let host = ["product_name", "product_version"]
    .map(|f| read(Path::new("/sys/class/dmi/id").join(f)))
    .into_iter()
    .filter(|s| !s.is_empty() && s != "Default string")
    .collect::<Vec<_>>()
    .join(" ");
  add("Host", host);
  add("Kernel", fields.kernel_version.clone());
  add("Uptime", fields.uptime.clone());
  add("Packages", packages());
  add("Shell", shell_version(&fields.shell));
  for display in displays() {
    add("Display", display);
  }
  add("Desktop", fields.desktop.clone());
  for (key, value) in appearance() {
    add(&key, value);
  }
  add("CPU", fields.cpu_name.clone());
  add("Topology", fields.cpu_cores.clone());
  for gpu in gpu_rows() {
    add("GPU", gpu);
  }
  add("Memory", fields.memory_usage.clone());
  add("Swap", swap());
  add(
    "Storage (/)",
    format!("{} [{}]", fields.storage, filesystem()),
  );
  for ip in local_ips() {
    add("Local IP", ip);
  }
  for (key, value) in power_rows() {
    add(&key, value);
  }
  add(
    "Locale",
    ["LC_ALL", "LC_MESSAGES", "LANG"]
      .iter()
      .find_map(|key| env::var(key).ok().filter(|s| !s.is_empty()))
      .unwrap_or_default(),
  );
  add("Days on Linux", days_on_linux(std::time::SystemTime::now()));
  add("Colors", fields.colors.clone());
  let c = crate::colors::Colors::new(crate::colors::is_no_color());
  let logo = [
    "⠀⠀⠀⠀⠀⠀⢼⣿⣄⠀⠀⠀⠹⣿⣷⡀⠀⣠⣿⡧⠀⠀⠀⠀⠀⠀",
    "⠀⠀⠀⠀⠀⠀⠈⢿⣿⣆⠀⠀⠀⠘⣿⣿⣴⣿⡿⠁⠀⠀⠀⠀⠀⠀",
    "⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⡜⢿⣿⣟⠀⠀⠀⢀⡄⠀⠀⠀",
    "⠀⠀⠀⠉⠉⠉⠉⣩⣭⡭⠉⠉⠉⠉⠉⠈⢿⣿⣆⠀⢠⣿⣿⠂⠀⠀",
    "⠀⠀⠀⠀⠀⠀⣼⣿⡟⠀⠀⠀⠀⠀⠀⠀⠀⢻⡟⣡⣿⣿⠃⠀⠀⠀",
    "⢸⣿⣿⣿⣿⣿⣿⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⣿⣿⣿⣿⣿⡇",
    "⠀⠀⠀⢠⣿⣿⢋⣼⣧⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⡟⠀⠀⠀⠀⠀⠀",
    "⠀⠀⠠⣿⣿⠃⠀⠹⣿⣷⡀⣀⣀⣀⣀⣀⣚⣛⣋⣀⣀⣀⣀⠀⠀⠀",
    "⠀⠀⠀⠘⠁⠀⠀⠀⣽⣿⣷⡜⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠃⠀⠀⠀",
    "⠀⠀⠀⠀⠀⠀⢀⣾⣿⠟⣿⣿⡄⠀⠀⠀⠹⣿⣷⡀⠀⠀⠀⠀⠀⠀",
    "⠀⠀⠀⠀⠀⠀⢺⣿⠋⠀⠈⢿⣿⣆⠀⠀⠀⠙⣿⡗⠀⠀⠀⠀⠀⠀",
  ];
  let width = logo
    .iter()
    .map(|line| line.chars().count())
    .max()
    .unwrap_or(0);
  let mut out = String::from("\n");
  for (i, (key, value)) in rows.iter().enumerate() {
    let art = logo.get(i).copied().unwrap_or("");
    let padding = width.saturating_sub(art.chars().count());
    let color = if i % 2 == 0 { c.blue } else { c.cyan };
    out.push_str(&format!("    {color}{art}{:padding$}{}  ", "", c.reset));
    if key.is_empty() {
      out.push_str(value);
    } else {
      out.push_str(&format!("{}{key:<14}{} {value}", c.cyan, c.reset));
    }
    out.push('\n');
  }
  out.push('\n');
  io::stdout()
    .lock()
    .write_all(out.as_bytes())
    .map_err(|_| Error::WriteError)
}

#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn edid_reports_name_and_pnp_model() {
    let mut edid = [0u8; 128];
    edid[..12].copy_from_slice(&[0, 255, 255, 255, 255, 255, 255, 0, 0x1e, 0x6d, 0x0d, 0x78]);
    assert_eq!(edid_model(&edid).as_deref(), Some("GSM780D"));
    edid[54..72].copy_from_slice(b"\0\0\0\xfc\0LG ULTRAGEAR+");
    assert_eq!(
      edid_model(&edid).as_deref(),
      Some("LG ULTRAGEAR+ [GSM780D]")
    );
    edid[8..12].copy_from_slice(&[0x1d, 0x89, 0x1c, 0xc2]);
    edid[59..72].copy_from_slice(b"GLKVM\n       ");
    assert_eq!(edid_model(&edid).as_deref(), Some("GLKVM [GLIC21C]"));
    assert_eq!(edid_model(&edid[..127]), None);
    edid[0] = 1;
    assert_eq!(edid_model(&edid), None);
  }
  #[test]
  fn displays_use_edid_when_available() {
    let output = "Output \"LG Electronics LG ULTRAGEAR+ serial\" (DP-1)\n  Current mode: 3440x1440 @ 240.085 Hz\n";
    assert_eq!(
      parse_displays(output, |_| Some("LG ULTRAGEAR+ [GSM780D]".to_string())),
      ["LG ULTRAGEAR+ [GSM780D] (DP-1): 3440x1440 @ 240.085 Hz"]
    );
  }
  #[test]
  fn linux_days_start_at_original_date_and_advance_at_midnight_utc() {
    use std::time::{Duration, UNIX_EPOCH};
    assert_eq!(
      days_on_linux(UNIX_EPOCH + Duration::from_secs(1_717_718_400)),
      "0 days"
    );
    assert_eq!(
      days_on_linux(UNIX_EPOCH + Duration::from_secs(1_717_804_799)),
      "0 days"
    );
    assert_eq!(
      days_on_linux(UNIX_EPOCH + Duration::from_secs(1_717_804_800)),
      "1 days"
    );
    assert_eq!(days_on_linux(UNIX_EPOCH), "0 days");
  }
  #[test]
  fn alacritty_identity_overrides_inherited_terminal_program() {
    assert_eq!(
      terminal_hint("alacritty", "vscode").as_deref(),
      Some("Alacritty")
    );
    assert_eq!(
      terminal_hint("xterm-256color", "WezTerm").as_deref(),
      Some("WezTerm")
    );
    assert_eq!(terminal_hint("linux", ""), None);
  }
  #[test]
  fn alacritty_font_matches_managed_config_and_normal_section() {
    assert_eq!(
      alacritty_font(include_str!("alacritty-test.toml")).as_deref(),
      Some("JetBrainsMono Nerd Font (12.0pt)")
    );
    assert_eq!(
      alacritty_font(
        "[font]\nsize = 13\n[font.bold]\nfamily = \"Bold\"\n[font.normal]\nfamily = \"Normal\""
      )
      .as_deref(),
      Some("Normal (13pt)")
    );
    assert_eq!(alacritty_font("[window]\nopacity = 1"), None);
  }
  #[test]
  fn cache_requires_exact_target_and_nonempty_value() {
    assert_eq!(
      cached_value("/nix/store/a\n42\n", "/nix/store/a"),
      Some("42".to_string())
    );
    assert_eq!(cached_value("/nix/store/a\n42\n", "/nix/store/b"), None);
    assert_eq!(cached_value("/nix/store/a\n", "/nix/store/a"), None);
    assert_eq!(cached_value("broken", "/nix/store/a"), None);
  }
  #[test]
  fn package_filter_excludes_split_outputs_and_system_derivations() {
    assert!(versioned_package("hash-fish-4.0.1"));
    for name in [
      "hash-fish-4.0.1-doc",
      "hash-fish-4.0.1-dev",
      "hash-config",
      "nixos-system-framework-26.05",
      "01234567890123456789012345678901-nixos-system-framework-26.05",
    ] {
      assert!(!versioned_package(name));
    }
  }
  #[test]
  fn profile_cache_skips_queries_and_invalidates_on_target_change() {
    let dir = env::temp_dir().join(format!("microfetch-test-{}", std::process::id()));
    fs::create_dir_all(dir.join("hash-fish-4.0.1")).unwrap();
    let cache = dir.join("cache");
    let a = Path::new("/nix/store/aaaaaaaa-profile");
    let b = Path::new("/nix/store/bbbbbbbb-profile");
    let paths = format!("{}\n", dir.join("hash-fish-4.0.1").display());
    assert_eq!(
      count_target_with(a, &cache, |_| Some(paths.clone())),
      Some(1)
    );
    assert_eq!(
      count_target_with(a, &cache, |_| panic!("warm cache invoked Nix")),
      Some(1)
    );
    assert_eq!(
      count_target_with(b, &cache, |_| Some(String::new())),
      Some(0)
    );
    fs::write(&cache, format!("{}\ninvalid\n", b.display())).unwrap();
    assert_eq!(count_target_with(b, &cache, |_| Some(paths)), Some(1));
    assert_eq!(count_target_with(a, &cache, |_| None), None);
    assert_eq!(
      cached_value(&read(&cache), b.to_str().unwrap()),
      Some("1".to_string())
    );
    fs::remove_dir_all(dir).unwrap();
  }
  #[test]
  fn zero_battery_current_does_not_invent_remaining_time() {
    let dir = env::temp_dir().join(format!("microfetch-battery-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    for (key, value) in [
      ("capacity", "100"),
      ("status", "Discharging"),
      ("charge_now", "4714000"),
      ("current_now", "0"),
    ] {
      fs::write(dir.join(key), value).unwrap();
    }
    assert_eq!(battery_info(&dir), "100% [Discharging]");
    fs::write(dir.join("current_now"), "1000000").unwrap();
    assert!(battery_info(&dir).contains("4h 42m remaining"));
    fs::remove_dir_all(dir).unwrap();
  }
  #[test]
  fn display_parser_ignores_disconnected_outputs() {
    let output = "Output \"Panel\" (eDP-1)\n  Current mode: 2880x1920 @ 120.000 Hz (preferred)\n  Physical size: 280x190 mm\n  Scale: 1.5\nOutput \"Off\" (DP-1)\n  Current mode: disabled\n";
    assert_eq!(
      parse_displays(output, |_| None),
      ["Panel (eDP-1): 2880x1920 @ 120.000 Hz, 1.5x, 280x190 mm"]
    );
  }
}
