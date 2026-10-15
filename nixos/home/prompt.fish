function __dotfiles_prompt_battery --on-event fish_prompt
  set -eg DOTFILES_PROMPT_BATTERY DOTFILES_PROMPT_BATTERY_LOW
  if test '@showBattery@' != 1
    return
  end
  for supply in /sys/class/power_supply/*/online
    read -l online < "$supply"
    if test "$online" = 1
      return
    end
  end
  for battery in /sys/class/power_supply/BAT*/capacity
    read -l capacity < "$battery"
    if string match -rq '^[0-9]{1,3}$' -- "$capacity"
      if test "$capacity" -le 20
        set -gx DOTFILES_PROMPT_BATTERY_LOW "$capacity%"
      else
        set -gx DOTFILES_PROMPT_BATTERY "$capacity%"
      end
      return
    end
  end
end

set -eg DOTFILES_PROMPT_IDENTITY
if set -q SSH_CONNECTION; or set -q SSH_CLIENT; or set -q SSH_TTY; or test (@id@ -u) = 0
  set -gx DOTFILES_PROMPT_IDENTITY 1
else if set -q LOGNAME; and test "$USER" != "$LOGNAME"
  set -gx DOTFILES_PROMPT_IDENTITY 1
end
