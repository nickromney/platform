package app

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strconv"
)

var (
	rfc1918Ranges = mustIPv4Nets("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
	rfc6598Range  = mustIPv4Net("100.64.0.0/10")
	cloudflareV4  = mustIPv4Nets(
		"173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
		"141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
		"197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
		"104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
	)
	cloudflareV6 = mustIPv6Nets("2400:cb00::/32", "2606:4700::/32", "2803:f800::/32", "2405:b500::/32", "2405:8100::/32", "2a06:98c0::/29", "2c0f:f248::/32")
)

func (s *server) validateAddress(w http.ResponseWriter, r *http.Request) {
	var req validateRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.Address == "" {
		writeJSON(w, http.StatusUnprocessableEntity, errorResponse{Detail: "Missing address"})
		return
	}
	if ip, network, ok := parseAnyIPOrNet(req.Address); ok {
		resp := map[string]any{"valid": true, "address": req.Address, "is_ipv4": ip.To4() != nil, "is_ipv6": ip.To4() == nil}
		if network != nil {
			ones, _ := network.Mask.Size()
			resp["type"] = "network"
			resp["network_address"] = network.IP.String()
			resp["netmask"] = net.IP(network.Mask).String()
			resp["prefix_length"] = ones
			if ip.To4() != nil {
				resp["num_addresses"] = uint64(1) << uint(32-ones)
			} else {
				resp["num_addresses"] = strconv.FormatUint(uint64(1)<<(min(63, 128-ones)), 10)
			}
		} else {
			resp["type"] = "address"
			resp["address"] = ip.String()
		}
		writeJSON(w, http.StatusOK, resp)
		return
	}
	writeJSON(w, http.StatusBadRequest, errorResponse{Detail: "Invalid IP address or network"})
}

func (s *server) checkPrivate(w http.ResponseWriter, r *http.Request) {
	var req validateRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	ip, network, ok := parseAnyIPOrNet(req.Address)
	if !ok || ip.To4() == nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: "This endpoint only supports IPv4 addresses"})
		return
	}

	target := ipOrNet{ip: ip, network: network}
	resp := map[string]any{"address": req.Address, "is_rfc1918": false, "is_rfc6598": false}
	for _, rng := range rfc1918Ranges {
		if target.overlapsOrContains(rng) {
			resp["is_rfc1918"] = true
			resp["matched_rfc1918_range"] = rng.String()
			break
		}
	}
	if target.overlapsOrContains(rfc6598Range) {
		resp["is_rfc6598"] = true
		resp["matched_rfc6598_range"] = rfc6598Range.String()
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) checkCloudflare(w http.ResponseWriter, r *http.Request) {
	var req validateRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	ip, network, ok := parseAnyIPOrNet(req.Address)
	if !ok {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: "Invalid IP address or network"})
		return
	}
	target := ipOrNet{ip: ip, network: network}
	ranges := cloudflareV6
	version := 6
	if ip.To4() != nil {
		ranges = cloudflareV4
		version = 4
	}
	matched := []string{}
	for _, rng := range ranges {
		if target.overlapsOrContains(rng) {
			matched = append(matched, rng.String())
		}
	}
	resp := map[string]any{"address": req.Address, "is_cloudflare": len(matched) > 0, "ip_version": version}
	if len(matched) > 0 {
		resp["matched_ranges"] = matched
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) subnetInfoIPv4(w http.ResponseWriter, r *http.Request) {
	var req subnetIPv4Request
	if !decodeJSON(w, r, &req) {
		return
	}
	resp, err := calculateIPv4(req.Network, req.Mode)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) subnetInfoIPv6(w http.ResponseWriter, r *http.Request) {
	var req subnetIPv6Request
	if !decodeJSON(w, r, &req) {
		return
	}
	ip, network, err := net.ParseCIDR(req.Network)
	if err != nil || ip.To4() != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: "This endpoint only supports IPv6 networks"})
		return
	}
	ones, _ := network.Mask.Size()
	writeJSON(w, http.StatusOK, map[string]any{
		"network":         req.Network,
		"network_address": network.IP.String(),
		"prefix_length":   ones,
		"total_addresses": "340282366920938463463374607431768211456",
		"note":            "IPv6 subnets do not have reserved addresses like IPv4",
	})
}

func calculateIPv4(networkStr, mode string) (subnetIPv4Response, error) {
	offset, err := modeOffset(mode)
	if err != nil {
		return subnetIPv4Response{}, err
	}
	ip, network, err := net.ParseCIDR(networkStr)
	if err != nil {
		return subnetIPv4Response{}, fmt.Errorf("invalid network format: %w", err)
	}
	if ip.To4() == nil {
		return subnetIPv4Response{}, fmt.Errorf("this endpoint only supports IPv4 networks")
	}
	ones, bitsLen := network.Mask.Size()
	if bitsLen != 32 {
		return subnetIPv4Response{}, fmt.Errorf("this endpoint only supports IPv4 networks")
	}
	networkIP := ipv4ToUint32(network.IP)
	total := uint64(1) << uint(32-ones)
	broadcast := networkIP + uint32(total) - 1
	netmask := net.IP(network.Mask).String()
	wildcard := net.IPv4(^network.Mask[0], ^network.Mask[1], ^network.Mask[2], ^network.Mask[3]).String()

	if ones == 31 {
		return subnetIPv4Response{
			Network: networkStr, Mode: mode, NetworkAddress: uint32ToIPv4(networkIP).String(), BroadcastAddress: nil,
			Netmask: netmask, WildcardMask: wildcard, PrefixLength: ones, TotalAddresses: 2, UsableAddresses: 2,
			FirstUsableIP: uint32ToIPv4(networkIP).String(), LastUsableIP: uint32ToIPv4(networkIP + 1).String(),
			Note: "RFC 3021 point-to-point link (no broadcast)",
		}, nil
	}
	if ones == 32 {
		return subnetIPv4Response{
			Network: networkStr, Mode: mode, NetworkAddress: uint32ToIPv4(networkIP).String(), BroadcastAddress: nil,
			Netmask: netmask, WildcardMask: wildcard, PrefixLength: ones, TotalAddresses: 1, UsableAddresses: 1,
			FirstUsableIP: uint32ToIPv4(networkIP).String(), LastUsableIP: uint32ToIPv4(networkIP).String(),
			Note: "Single host address",
		}, nil
	}
	broadcastStr := uint32ToIPv4(broadcast).String()
	return subnetIPv4Response{
		Network: networkStr, Mode: mode, NetworkAddress: uint32ToIPv4(networkIP).String(), BroadcastAddress: &broadcastStr,
		Netmask: netmask, WildcardMask: wildcard, PrefixLength: ones, TotalAddresses: total,
		UsableAddresses: total - uint64(offset) - 1, FirstUsableIP: uint32ToIPv4(networkIP + offset).String(),
		LastUsableIP: uint32ToIPv4(broadcast - 1).String(),
	}, nil
}

func modeOffset(mode string) (uint32, error) {
	switch mode {
	case "Azure", "AWS":
		return 4, nil
	case "OCI":
		return 2, nil
	case "Standard", "":
		return 1, nil
	default:
		return 0, fmt.Errorf("invalid mode")
	}
}

func decodeJSON(w http.ResponseWriter, r *http.Request, out any) bool {
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(out); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: "Invalid JSON body"})
		return false
	}
	return true
}

func parseAnyIPOrNet(value string) (net.IP, *net.IPNet, bool) {
	if ip, network, err := net.ParseCIDR(value); err == nil {
		return ip, network, true
	}
	if ip := net.ParseIP(value); ip != nil {
		return ip, nil, true
	}
	return nil, nil, false
}

type ipOrNet struct {
	ip      net.IP
	network *net.IPNet
}

func (t ipOrNet) overlapsOrContains(candidate *net.IPNet) bool {
	if t.network == nil {
		return candidate.Contains(t.ip)
	}
	return cidrOverlap(t.network, candidate)
}

func cidrOverlap(a, b *net.IPNet) bool {
	return a.Contains(b.IP) || b.Contains(a.IP)
}

func mustIPv4Net(value string) *net.IPNet {
	_, network, err := net.ParseCIDR(value)
	if err != nil {
		panic(err)
	}
	return network
}

func mustIPv4Nets(values ...string) []*net.IPNet {
	nets := make([]*net.IPNet, 0, len(values))
	for _, value := range values {
		nets = append(nets, mustIPv4Net(value))
	}
	return nets
}

func mustIPv6Nets(values ...string) []*net.IPNet {
	return mustIPv4Nets(values...)
}

func ipv4ToUint32(ip net.IP) uint32 {
	return binary.BigEndian.Uint32(ip.To4())
}

func uint32ToIPv4(value uint32) net.IP {
	var b [4]byte
	binary.BigEndian.PutUint32(b[:], value)
	return net.IPv4(b[0], b[1], b[2], b[3])
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
