{
  pkgs,
  pkgsUnstable,
  productionConfig ? ../assets/homelab-dns/dnsdist.conf,
}:
let
  python = pkgs.python3.withPackages (ps: [ ps.dnspython ]);
in
pkgs.runCommand "dns-process-integration"
  {
    nativeBuildInputs = [
      python
      pkgs.openssl
      pkgsUnstable.dnsdist
    ];
    # A normal derivation uses Nix's isolated network namespace, with loopback only.
  }
  ''
    export HOME="$TMPDIR"
    timeout 90s python ${../../tests/dns/process.py} ${productionConfig}
    touch "$out"
  ''
