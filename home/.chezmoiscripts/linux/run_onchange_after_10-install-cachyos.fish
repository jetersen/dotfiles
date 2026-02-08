#!/usr/bin/env fish

# Exit early if not on Arch/CachyOS
if not test -f /etc/arch-release
  exit 0
end

echo "Going to ask for sudo password to install packages"
if sudo -v
  echo "Thanks!"
else
  echo "Sudo password is required to proceed."
  exit 1
end

# Update system and install packages using Pacman
echo "Installing packages with Pacman..."
paru -Sq --needed --noconfirm --overwrite="*" \
  age \
  aspnet-runtime-bin \
  aspnet-targeting-pack-bin \
  aws-cli-bin \
  bitwarden \
  bitwarden-cli \
  btop \
  claude-code \
  discord \
  docker \
  docker-compose \
  dotnet-host-bin \
  dotnet-runtime-bin \
  dotnet-sdk-bin \
  dotnet-targeting-pack-bin \
  fluxcd \
  freerdp \
  git \
  git-delta \
  git-lfs \
  github-cli \
  go \
  go-yq \
  helm \
  jq \
  krdc \
  krew \
  kubectl \
  kubectx \
  kustomize \
  lens-bin \
  meld \
  oh-my-posh-bin \
  powershell-bin \
  pulumi \
  pulumi-language-dotnet \
  rider \
  rustdesk-bin \
  slack-desktop-wayland \
  sops \
  talhelper \
  talosctl \
  ttf-jetbrains-mono \
  ttf-jetbrains-mono-nerd \
  virt-manager \
  visual-studio-code-bin \
  wl-clipboard \
  youtube-music \
  zen-browser-bin

# Check for discrete GPU using fastfetch
fastfetch --structure GPU --format json 2>/dev/null | jq -e '.[] | select(.type == "GPU") | .result[] | select(.type == "Discrete")' >/dev/null
and begin
  echo "Installing game-related AUR packages with Paru..."
  paru -Sq --needed --noconfirm --overwrite="*" \
    bottles \
    raiderio-client \
    warcraftlogsuploader \
    wowup-cf-bin
end

# Update all packages
echo "Updating all packages..."
paru -Syu --noconfirm

# Create sensitive directories
echo "Creating sensitive directories..."
for dir in ~/.ssh ~/.aws ~/.kube ~/.local
  mkdir -p -m 700 $dir
end

# Create general directories
echo "Creating general directories..."
for dir in ~/.local/bin ~/git/code ~/git/work
  mkdir -p -m 751 $dir
end

echo "Setup complete!"
