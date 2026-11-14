set -euo pipefail

if [[ "$1" == stop ]]; then
  ip -4 rule del priority 5300 table 53 2>/dev/null || true
  ip -6 rule del priority 5300 table 53 2>/dev/null || true
  ip -4 route flush table 53 || true
  ip -6 route flush table 53 || true
  ip link del wt-host 2>/dev/null || true
  ip netns del work-tailnet
  exit
fi

# Fail on collisions rather than removing a namespace or interface we don't own.
for family in -4 -6; do
  if ip "$family" rule show | grep -q '^5300:'; then
    echo "Routing priority 5300 is already in use" >&2
    exit 1
  fi
  if [[ -n "$(ip "$family" route show table 53 2>/dev/null || true)" ]]; then
    echo "Routing table 53 is already in use" >&2
    exit 1
  fi
done
ip netns add work-tailnet
trap 'ip link del wt-host 2>/dev/null || true; ip netns del work-tailnet' ERR
ip link add wt-host type veth peer name wt-peer netns work-tailnet
# Tailscale excludes link-local IPv4 from its usable Internet interfaces.
# Use RFC1918 here so its namespace can discover direct UDP endpoints.
ip addr add 192.168.77.1/30 dev wt-host
ip -6 addr add fd42:77::1/64 dev wt-host nodad
# This veth also carries encrypted Tailscale UDP to the physical network.
# Leave room for tunnel overhead; exported application routes constrain inner MTU.
ip link set wt-host mtu 1500 up
ip -n work-tailnet link set lo up
ip -n work-tailnet addr add 192.168.77.2/30 dev wt-peer
ip -n work-tailnet -6 addr add fd42:77::2/64 dev wt-peer nodad
ip -n work-tailnet link set wt-peer mtu 1500 up
ip -n work-tailnet route add default via 192.168.77.1
ip netns exec work-tailnet sysctl -qw net.ipv4.ip_forward=1
ip netns exec work-tailnet sysctl -qw net.ipv6.conf.all.forwarding=1
# Tailscale manages routes only inside its namespace. NAT host application
# traffic to the work node's identity; never advertise either tailnet as a router.
for family in iptables ip6tables; do
  ip netns exec work-tailnet "$family" -w -t nat -A POSTROUTING -o tailscale-work -j MASQUERADE
done
ip -4 rule add priority 5300 table 53
ip -6 rule add priority 5300 table 53
