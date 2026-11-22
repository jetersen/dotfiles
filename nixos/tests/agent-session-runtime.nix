{ pkgs, packages }:
pkgs.runCommand "agent-session-runtime-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  mkdir -m 700 "$TMPDIR/embeddings"
  ln -s ${packages.nomic-embed-text}/nomic-embed-text-v1.5 "$TMPDIR/embeddings/nomic-embed-text-v1.5"
  ${packages.kennembed}/bin/kennembed -data-dir "$TMPDIR/embeddings" -listen 127.0.0.1:18122 > "$TMPDIR/runtime.log" 2>&1 &
  runtime_pid=$!
  trap 'kill "$runtime_pid" 2>/dev/null || true' EXIT
  python3 - <<'PY'
  import json, math, time, urllib.request, urllib.error
  for attempt in range(100):
      try:
          with urllib.request.urlopen("http://127.0.0.1:18122/v1/models", timeout=2) as response:
              assert "nomic-embed-text" in json.load(response)["models"]
          break
      except (urllib.error.URLError, TimeoutError):
          time.sleep(0.1)
  else:
      raise RuntimeError("Packaged embedding runtime did not become ready")
  request = urllib.request.Request("http://127.0.0.1:18122/v1/embeddings",
      data=json.dumps({"model": "nomic-embed-text", "input": ["search_query: configure agent services"]}).encode(),
      headers={"Content-Type": "application/json"})
  with urllib.request.urlopen(request, timeout=120) as response:
      vector=json.load(response)["data"][0]["embedding"]
  assert len(vector) == 768 and all(math.isfinite(value) for value in vector)
  assert sum(value * value for value in vector) > 0
  PY
  ${packages.agentsview}/bin/agentsview --version
  touch "$out"
''
