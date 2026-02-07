# My dotfiles

Managed with [chezmoi](https://www.chezmoi.io/).

## Install

### Linux / macOS

```sh
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply jetersen
```

### Windows

```powershell
iex "&{$(irm 'https://get.chezmoi.io/ps1')} init --aply jetersen"
```

## Update

```sh
chezmoi update
```
