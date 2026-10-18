//! Use the standard runtime for filesystem/process support in our workstation build.
fn main() {
  use std::{env, ffi::CString, os::unix::ffi::OsStrExt, process};
  let args: Vec<_> = env::args_os()
    .filter_map(|s| CString::new(s.as_bytes()).ok())
    .collect();
  let vars: Vec<_> = env::vars_os()
    .filter_map(|(k, v)| {
      let mut value = k.as_bytes().to_vec();
      value.push(b'=');
      value.extend_from_slice(v.as_bytes());
      CString::new(value).ok()
    })
    .collect();
  let mut argv: Vec<_> = args.iter().map(|s| s.as_ptr().cast::<u8>()).collect();
  argv.push(std::ptr::null());
  argv.extend(vars.iter().map(|s| s.as_ptr().cast::<u8>()));
  argv.push(std::ptr::null());
  // Microfetch expects a contiguous argv/null/envp/null pointer array.
  if unsafe { microfetch_lib::run_with_environment(args.len() as i32, argv.as_ptr()) }.is_err() {
    process::exit(1);
  }
}
