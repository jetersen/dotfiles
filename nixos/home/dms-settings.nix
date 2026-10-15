{
  extraRightWidgets ? [ ],
}:
{
  barConfigs = [
    {
      id = "default";
      name = "Main Bar";
      enabled = true;
      position = 0;
      screenPreferences = [ "all" ];
      showOnLastDisplay = true;
      leftWidgets = [
        "launcherButton"
        "workspaceSwitcher"
        "focusedWindow"
      ];
      centerWidgets = [
        "music"
        "clock"
        "weather"
      ];
      rightWidgets =
        map
          (id: {
            inherit id;
            enabled = true;
          })
          (
            [
              "systemTray"
              "clipboard"
              "cpuUsage"
              "memUsage"
              "notificationButton"
              "systemUpdate"
              "privacyIndicator"
              "controlCenterButton"
            ]
            ++ extraRightWidgets
          );
      spacing = 0;
      innerPadding = 0;
      bottomGap = 0;
      transparency = 1;
      widgetTransparency = 1;
      squareCorners = false;
      noBackground = false;
      gothCornersEnabled = false;
      borderEnabled = false;
      fontScale = 1;
      autoHide = false;
      popupGapsAuto = true;
      widgetPadding = 8;
    }
  ];
  barElevationEnabled = false;
  showOccupiedWorkspacesOnly = true;
  workspaceNameIcons = {
    chat = {
      type = "icon";
      value = "chat";
    };
    music = {
      type = "icon";
      value = "music_note";
    };
    browser = {
      type = "icon";
      value = "home";
    };
  };
  updaterHideWidget = true;
  currentThemeCategory = "registry";
  currentThemeName = "custom";
  registryThemeVariants.catppuccin.dark = {
    flavor = "mocha";
    accent = "mauve";
  };
  matugenScheme = "scheme-fidelity";
  cornerRadius = 0;
  monoFontFamily = "JetBrainsMono Nerd Font";
  animationSpeed = 0;
  modalAnimationSpeed = 0;
  popoutAnimationSpeed = 0;
  syncComponentAnimationSpeeds = false;
  enableRippleEffects = false;
  niriLayoutGapsOverride = 0;
  niriLayoutRadiusOverride = 0;
  niriLayoutBorderSize = 0;
  builtInPluginSettings.dms_settings_search.trigger = "?";
  soundNewNotification = false;
  iconThemeDark = "Papirus-Dark";
  iconThemeLight = "Papirus-Dark";
  iconThemePerMode = false;
  enableFprint = true;
  lockBeforeSuspend = true;
  greeterEnableFprint = false;
  greeterPamExternallyManaged = true;
}
