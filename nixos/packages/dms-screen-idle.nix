{ dms }:
dms.overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    chmod u+w "$out/share/quickshell/dms/Services" "$out/share/quickshell/dms/Services/IdleService.qml"
    patch -d "$out/share/quickshell/dms" -p1 < ${./dms-screen-idle.patch}
  '';
})
