{
  microfetch,
  nix,
  niri,
  iproute2,
  hwdata,
}:
microfetch.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./microfetch/workstation.patch ];
  postPatch = (old.postPatch or "") + ''
    cp ${./microfetch/extra.rs} crates/lib/src/extra.rs
    cp ${./microfetch/main.rs} microfetch/src/main.rs
    # Our extra detectors use std, so retain the normal Rust runtime/linker.
    echo 'fn main() {}' > microfetch/build.rs
    rm .cargo/config.toml
  '';
  MICROFETCH_NIX_STORE = "${nix}/bin/nix-store";
  MICROFETCH_NIRI = "${niri}/bin/niri";
  MICROFETCH_IP = "${iproute2}/bin/ip";
  MICROFETCH_PCI_IDS = "${hwdata}/share/hwdata/pci.ids";
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cargo test --offline --release -p microfetch-lib
    runHook postCheck
  '';
})
