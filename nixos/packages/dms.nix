{ dms }:
dms.overrideAttrs (old: {
  # kdl-go otherwise writes properties in random Go map order.
  patches = (old.patches or [ ]) ++ [ ./dms-stable-keybinds.patch ];
})
