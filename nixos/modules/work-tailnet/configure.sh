preferences=(--operator=joseph --accept-dns=false --accept-routes=true --ssh=false --netfilter-mode=off)
if [[ -s /var/lib/work-tailnet/hostname ]]; then
  work_node_name=$(</var/lib/work-tailnet/hostname)
  preferences+=("--hostname=$work_node_name")
fi
tailscale --socket=/run/work-tailnet/tailscaled.sock set "${preferences[@]}"
tailscale --socket=/run/work-tailnet/tailscaled.sock down
