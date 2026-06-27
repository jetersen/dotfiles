local approved_aur = {
  ["freelens-bin"] = true,
  ["gdbuspp"] = true,
  ["greetd-dms-greeter-git"] = true,
  ["input-remapper-bin"] = true,
  ["oh-my-posh-bin"] = true,
  ["openai-codex-bin"] = true,
  ["openvpn3"] = true,
  ["powershell-bin"] = true,
  ["proton-pass-cli-bin"] = true,
  ["pulumi-language-dotnet"] = true,
  ["qt6ct-kde"] = true,
  ["rider"] = true,
  ["rustdesk-bin"] = true,
  ["slack-desktop-wayland"] = true,
  ["t3code-bin"] = true,
  ["tiny-rdm-bin"] = true,
  ["topgrade"] = true,
  ["visual-studio-code-bin"] = true,
  ["whisper.cpp-model-large-v3-turbo"] = true,
}

local function sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_output(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then
    return ""
  end

  local out = p:read("*a") or ""
  p:close()
  return out
end

local function is_approved(data)
  if approved_aur[data.base] then
    return true
  end

  for _, package in ipairs(data.packages or {}) do
    if approved_aur[package.name] then
      return true
    end
  end

  return false
end

local function is_safe_pkgbuild_line(line)
  line = line:gsub("^[+-]", ""):gsub("^%s+", "")
  return line == ""
    or line:match("^pkgver=")
    or line:match("^pkgrel=")
    or line:match("^epoch=")
    or line:match("^[a-z0-9]+sums=")
    or line:match("^[a-z0-9]+sums_%w+=")
    or line:match("^[%s'\"]*[a-fA-F0-9]+[%s'\"]*$")
    or line:match("^[%)%(]%s*$")
end

local function source_same_except_version(old, new)
  local function normalize(s)
    return s
      :gsub("^[+-]", "")
      :gsub("%f[%w][vV]?%d[%w._-]*", "@VERSION@")
      :gsub("pkgver=[^&'\") ]+", "pkgver=@VERSION@")
      :gsub("version=[^&'\") ]+", "version=@VERSION@")
      :gsub("ver=[^&'\") ]+", "ver=@VERSION@")
  end

  return normalize(old) == normalize(new)
end

local function pkgbuild_diff_is_safe(dir)
  local qdir = sh_quote(dir)
  local diff = command_output("git -C " .. qdir .. " diff --unified=0 HEAD@{1}..HEAD -- PKGBUILD")
  if diff == "" then
    diff = command_output("git -C " .. qdir .. " diff --unified=0 HEAD~1..HEAD -- PKGBUILD")
  end
  if diff == "" then
    return true
  end

  local pending_source
  for line in diff:gmatch("[^\n]+") do
    if line:match("^[-+]source[_%w]*=") or line:match("^[-+].*https?://") then
      if line:sub(1, 1) == "-" then
        pending_source = line
      elseif not (pending_source and source_same_except_version(pending_source, line)) then
        return false
      else
        pending_source = nil
      end
    elseif line:match("^[+-]") and not line:match("^[+-][+-][+-]") and not is_safe_pkgbuild_line(line) then
      return false
    end
  end

  return not pending_source
end

yay.create_autocmd("UpgradeSelect", {
  desc = "show diffs for unapproved AUR packages",
  callback = function(event)
    for _, upgrade in ipairs(event.data.upgrades) do
      if upgrade.repository == "aur" and not (approved_aur[upgrade.name] or approved_aur[upgrade.base]) then
        yay.log.info("unapproved AUR package " .. upgrade.name .. "; diff review required")
        yay.opt.diff_menu = true
      end
    end

    return { skip_menu = false }
  end,
})

yay.create_autocmd("AURPreInstall", {
  desc = "auto-allow only version/checksum PKGBUILD updates",
  callback = function(event)
    if not is_approved(event.data) then
      yay.log.warn(event.data.base .. ": unapproved AUR package; diff review required")
      yay.opt.diff_menu = true
    elseif not pkgbuild_diff_is_safe(event.data.dir) then
      yay.log.warn(event.data.base .. ": PKGBUILD changed beyond version/checksum; diff review required")
      yay.opt.diff_menu = true
    end
  end,
})
