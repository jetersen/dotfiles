# Choose project context without launching Git or cloud CLIs on every prompt.
function __dotfiles_project_context --on-variable PWD
  set -l directory "$PWD"
  set -l cloud 0
  set -l homelab 0
  while test "$directory" != /; and test "$directory" != "$HOME"
    for marker in Pulumi.yaml Pulumi.yml Pulumi.json main.tf provider.tf terragrunt.hcl Chart.yaml helmfile.yaml kustomization.yaml kustomization.yml
      if test -f "$directory/$marker"
        set cloud 1
        break
      end
    end
    if test -e "$directory/.git"
      switch (path basename "$directory")
        case homelab dotfiles
          set cloud 1
          set homelab 1
        case 'devops-*'
          set cloud 1
      end
      break
    end
    set directory (path dirname "$directory")
  end

  if test "$cloud" = 1
    set -gx STARSHIP_CONFIG '@cloudConfig@'
  else
    set -gx STARSHIP_CONFIG '@baseConfig@'
  end

  # Export the saved value so nested Fish shells can also restore it on exit.
  if test "$homelab" = 1
    if not set -q DOTFILES_KUBE_OVERRIDE
      set -gx DOTFILES_KUBE_BASE_SET 0
      set -gx DOTFILES_KUBE_BASE ''
      if set -q KUBECONFIG
        set -gx DOTFILES_KUBE_BASE_SET 1
        set -gx DOTFILES_KUBE_BASE "$KUBECONFIG"
      end
    end
    set -l base "$DOTFILES_KUBE_BASE"
    if test -z "$base"
      set base "$HOME/.kube/config"
    end
    set -gx KUBECONFIG '@homelabConfig@':"$base"
    set -gx DOTFILES_KUBE_OVERRIDE 1
  else if set -q DOTFILES_KUBE_OVERRIDE
    if test "$DOTFILES_KUBE_BASE_SET" = 1
      set -gx KUBECONFIG "$DOTFILES_KUBE_BASE"
    else
      set -eg KUBECONFIG
    end
    set -eg DOTFILES_KUBE_OVERRIDE DOTFILES_KUBE_BASE DOTFILES_KUBE_BASE_SET
  end
end

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
__dotfiles_project_context
