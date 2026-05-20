package app

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

func newSubnetAnalyzer(sourceOverrides map[string]string) *subnetAnalyzer {
	providers := defaultProviderRanges()
	for name, sourceURL := range sourceOverrides {
		key := strings.ToLower(strings.TrimSpace(name))
		provider, ok := providers[key]
		if !ok {
			continue
		}
		provider.refreshURL = sourceURL
		provider.sourceURL = sourceURL
		providers[key] = provider
	}
	return &subnetAnalyzer{
		rfc1918Ranges: mustIPv4Nets("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"),
		rfc6598Range:  mustIPv4Net("100.64.0.0/10"),
		providers:     providers,
	}
}

func defaultProviderRanges() map[string]providerRangeSet {
	return map[string]providerRangeSet{
		"cloudflare": {
			name:       "cloudflare",
			source:     "bundled",
			sourceURL:  "https://www.cloudflare.com/ips/",
			refreshURL: "https://www.cloudflare.com/ips-v4",
			parser:     "cloudflare-text-v4",
			sourceNote: "Cloudflare publishes separate IPv4 and IPv6 text feeds.",
			ipv4: mustIPv4Nets(
				"173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
				"141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
				"197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
				"104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
			),
			ipv6: mustIPv6Nets("2400:cb00::/32", "2606:4700::/32", "2803:f800::/32", "2405:b500::/32", "2405:8100::/32", "2a06:98c0::/29", "2c0f:f248::/32"),
		},
		"aws": {
			name:       "aws",
			source:     "bundled",
			sourceURL:  "https://ip-ranges.amazonaws.com/ip-ranges.json",
			refreshURL: "https://ip-ranges.amazonaws.com/ip-ranges.json",
			parser:     "aws-json",
			sourceNote: "AWS publishes a JSON feed with IPv4 and IPv6 prefixes.",
			ipv4:       mustIPv4Nets("3.5.140.0/22"),
			ipv6:       mustIPv6Nets("2600:1f14::/35"),
		},
		"azure": {
			name:       "azure",
			source:     "bundled",
			sourceURL:  "configurable: Azure Service Tags Public JSON download",
			parser:     "azure-service-tags-json",
			sourceNote: "Microsoft publishes Azure Service Tags as a date-stamped JSON download and via authenticated APIs.",
			ipv4:       mustIPv4Nets("20.33.0.0/16"),
		},
		"stripe": {
			name:       "stripe",
			source:     "bundled",
			sourceURL:  "https://stripe.com/files/ips/ips_webhooks.json",
			refreshURL: "https://stripe.com/files/ips/ips_webhooks.json",
			parser:     "stripe-json",
			sourceNote: "Stripe publishes JSON feeds for webhook and API IP addresses.",
			ipv4:       mustIPv4Nets("3.18.12.63/32", "3.130.192.231/32"),
		},
		"openai": {
			name:       "openai",
			source:     "unpublished",
			sourceNote: "OpenAI documents customer IP allowlisting for ChatGPT workspaces, but does not publish an official provider IP range feed for general allowlisting.",
		},
	}
}

type subnetAnalyzer struct {
	mu            sync.RWMutex
	rfc1918Ranges []*net.IPNet
	rfc6598Range  *net.IPNet
	providers     map[string]providerRangeSet
}

type providerRangeSet struct {
	name       string
	source     string
	sourceURL  string
	refreshURL string
	parser     string
	sourceNote string
	ipv4       []*net.IPNet
	ipv6       []*net.IPNet
	liveIPv4   []*net.IPNet
	liveIPv6   []*net.IPNet
	cachedAt   time.Time
}

func (s *server) validateAddress(w http.ResponseWriter, r *http.Request) {
	var req validateRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.Address == "" {
		writeJSON(w, http.StatusUnprocessableEntity, errorResponse{Detail: "Missing address"})
		return
	}
	resp, err := s.analyzer.validateAddress(req.Address)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) checkPrivate(w http.ResponseWriter, r *http.Request) {
	var req validateRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	resp, err := s.analyzer.checkPrivate(req.Address)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) checkCloudflare(w http.ResponseWriter, r *http.Request) {
	var req validateRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	resp, err := s.analyzer.checkCloudflare(req.Address)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) checkProviderRange(w http.ResponseWriter, r *http.Request) {
	var req providerRangeRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	resp, err := s.analyzer.checkProviderRange(req.Provider, req.Address)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) invalidateProviderRangeCache(w http.ResponseWriter, r *http.Request) {
	var req providerRangeRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	resp, err := s.analyzer.invalidateProviderRangeCache(req.Provider)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) refreshProviderRangeCache(w http.ResponseWriter, r *http.Request) {
	var req providerRangeRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	resp, err := s.analyzer.refreshProviderRangeCache(r, req.Provider)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) allocateNetworkPlan(w http.ResponseWriter, r *http.Request) {
	var req networkPlanRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	resp, err := s.analyzer.allocateNetworkPlan(req)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) subnetInfoIPv4(w http.ResponseWriter, r *http.Request) {
	var req subnetIPv4Request
	if !decodeJSON(w, r, &req) {
		return
	}
	resp, err := s.analyzer.subnetInfoIPv4(req.Network, req.Mode)
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
	resp, err := s.analyzer.subnetInfoIPv6(req.Network)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Detail: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (a *subnetAnalyzer) validateAddress(value string) (map[string]any, error) {
	ip, network, ok := parseAnyIPOrNet(value)
	if !ok {
		return nil, fmt.Errorf("Invalid IP address or network")
	}
	resp := map[string]any{"valid": true, "address": value, "is_ipv4": ip.To4() != nil, "is_ipv6": ip.To4() == nil}
	if network == nil {
		resp["type"] = "address"
		resp["address"] = ip.String()
		return resp, nil
	}

	ones, _ := network.Mask.Size()
	resp["type"] = "network"
	resp["network_address"] = network.IP.String()
	resp["netmask"] = net.IP(network.Mask).String()
	resp["prefix_length"] = ones
	if ip.To4() != nil {
		resp["num_addresses"] = uint64(1) << uint(32-ones)
	} else {
		resp["num_addresses"] = ipv6AddressCount(ones)
	}
	return resp, nil
}

func (a *subnetAnalyzer) checkPrivate(value string) (map[string]any, error) {
	ip, network, ok := parseAnyIPOrNet(value)
	if !ok || ip.To4() == nil {
		return nil, fmt.Errorf("This endpoint only supports IPv4 addresses")
	}

	target := ipOrNet{ip: ip, network: network}
	resp := map[string]any{"address": value, "is_rfc1918": false, "is_rfc6598": false}
	for _, rng := range a.rfc1918Ranges {
		if target.overlapsOrContains(rng) {
			resp["is_rfc1918"] = true
			resp["matched_rfc1918_range"] = rng.String()
			break
		}
	}
	if target.overlapsOrContains(a.rfc6598Range) {
		resp["is_rfc6598"] = true
		resp["matched_rfc6598_range"] = a.rfc6598Range.String()
	}
	return resp, nil
}

func (a *subnetAnalyzer) checkCloudflare(value string) (map[string]any, error) {
	resp, err := a.checkProviderRange("cloudflare", value)
	if err != nil {
		return nil, err
	}
	resp["is_cloudflare"] = resp["is_provider_range"]
	return resp, nil
}

func (a *subnetAnalyzer) checkProviderRange(provider, value string) (map[string]any, error) {
	provider = strings.ToLower(strings.TrimSpace(provider))
	if provider == "" {
		return nil, fmt.Errorf("Missing provider")
	}
	ip, network, ok := parseAnyIPOrNet(value)
	if !ok {
		return nil, fmt.Errorf("Invalid IP address or network")
	}
	a.mu.RLock()
	defer a.mu.RUnlock()
	rangeSet, ok := a.providers[provider]
	if !ok {
		return nil, fmt.Errorf("Unknown provider")
	}
	target := ipOrNet{ip: ip, network: network}
	ranges := rangeSet.effectiveIPv6()
	version := 6
	if ip.To4() != nil {
		ranges = rangeSet.effectiveIPv4()
		version = 4
	}
	matched := []string{}
	for _, rng := range ranges {
		if target.overlapsOrContains(rng) {
			matched = append(matched, rng.String())
		}
	}
	resp := map[string]any{
		"address":           value,
		"provider":          rangeSet.name,
		"is_provider_range": len(matched) > 0,
		"ip_version":        version,
		"range_source":      rangeSet.effectiveSource(),
	}
	if rangeSet.sourceURL != "" {
		resp["range_source_url"] = rangeSet.sourceURL
	}
	if rangeSet.sourceNote != "" {
		resp["range_source_note"] = rangeSet.sourceNote
	}
	if len(matched) > 0 {
		resp["matched_ranges"] = matched
	}
	return resp, nil
}

func (p providerRangeSet) effectiveIPv4() []*net.IPNet {
	if p.liveIPv4 != nil || p.liveIPv6 != nil {
		return p.liveIPv4
	}
	return p.ipv4
}

func (p providerRangeSet) effectiveIPv6() []*net.IPNet {
	if p.liveIPv4 != nil || p.liveIPv6 != nil {
		return p.liveIPv6
	}
	return p.ipv6
}

func (p providerRangeSet) effectiveSource() string {
	if p.liveIPv4 != nil || p.liveIPv6 != nil {
		return "live-cache"
	}
	return p.source
}

func (a *subnetAnalyzer) invalidateProviderRangeCache(provider string) (map[string]any, error) {
	provider = strings.ToLower(strings.TrimSpace(provider))
	if provider == "" {
		return nil, fmt.Errorf("Missing provider")
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	rangeSet, ok := a.providers[provider]
	if !ok {
		return nil, fmt.Errorf("Unknown provider")
	}
	rangeSet.liveIPv4 = nil
	rangeSet.liveIPv6 = nil
	rangeSet.cachedAt = time.Time{}
	a.providers[provider] = rangeSet
	return map[string]any{
		"provider":     rangeSet.name,
		"cache_status": "invalidated",
	}, nil
}

func (a *subnetAnalyzer) refreshProviderRangeCache(r *http.Request, provider string) (map[string]any, error) {
	provider = strings.ToLower(strings.TrimSpace(provider))
	if provider == "" {
		return nil, fmt.Errorf("Missing provider")
	}

	a.mu.RLock()
	rangeSet, ok := a.providers[provider]
	a.mu.RUnlock()
	if !ok {
		return nil, fmt.Errorf("Unknown provider")
	}
	if rangeSet.refreshURL == "" {
		return nil, fmt.Errorf("Provider does not have a configured refresh source")
	}

	client := &http.Client{Timeout: 20 * time.Second}
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, rangeSet.refreshURL, nil)
	if err != nil {
		return nil, fmt.Errorf("Invalid provider refresh source")
	}
	res, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Provider refresh failed: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode > 299 {
		return nil, fmt.Errorf("Provider refresh returned HTTP %d", res.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(res.Body, 16<<20))
	if err != nil {
		return nil, fmt.Errorf("Provider refresh read failed: %w", err)
	}
	ipv4, ipv6, err := parseProviderRangePayload(rangeSet.parser, body)
	if err != nil {
		return nil, err
	}

	a.mu.Lock()
	rangeSet.liveIPv4 = ipv4
	rangeSet.liveIPv6 = ipv6
	rangeSet.cachedAt = time.Now().UTC()
	a.providers[provider] = rangeSet
	a.mu.Unlock()

	return map[string]any{
		"provider":         rangeSet.name,
		"cache_status":     "refreshed",
		"range_source":     "live-cache",
		"range_count_v4":   len(ipv4),
		"range_count_v6":   len(ipv6),
		"range_source_url": rangeSet.refreshURL,
	}, nil
}

func parseProviderRangePayload(parser string, body []byte) ([]*net.IPNet, []*net.IPNet, error) {
	switch parser {
	case "aws-json":
		var payload struct {
			Prefixes []struct {
				IPPrefix string `json:"ip_prefix"`
			} `json:"prefixes"`
			IPv6Prefixes []struct {
				IPv6Prefix string `json:"ipv6_prefix"`
			} `json:"ipv6_prefixes"`
		}
		if err := json.Unmarshal(body, &payload); err != nil {
			return nil, nil, fmt.Errorf("Invalid AWS range payload")
		}
		ipv4 := make([]*net.IPNet, 0, len(payload.Prefixes))
		for _, prefix := range payload.Prefixes {
			if prefix.IPPrefix == "" {
				continue
			}
			network, err := parseCIDR(prefix.IPPrefix)
			if err != nil {
				return nil, nil, err
			}
			ipv4 = append(ipv4, network)
		}
		ipv6 := make([]*net.IPNet, 0, len(payload.IPv6Prefixes))
		for _, prefix := range payload.IPv6Prefixes {
			if prefix.IPv6Prefix == "" {
				continue
			}
			network, err := parseCIDR(prefix.IPv6Prefix)
			if err != nil {
				return nil, nil, err
			}
			ipv6 = append(ipv6, network)
		}
		return ipv4, ipv6, nil
	case "stripe-json":
		var payload map[string][]string
		if err := json.Unmarshal(body, &payload); err != nil {
			return nil, nil, fmt.Errorf("Invalid Stripe range payload")
		}
		return parseAddressOrCIDRList(payload["WEBHOOKS"])
	case "cloudflare-text-v4":
		lines := strings.Fields(string(body))
		ipv4, _, err := parseAddressOrCIDRList(lines)
		return ipv4, nil, err
	case "azure-service-tags-json":
		var payload struct {
			Values []struct {
				Properties struct {
					AddressPrefixes []string `json:"addressPrefixes"`
				} `json:"properties"`
			} `json:"values"`
		}
		if err := json.Unmarshal(body, &payload); err != nil {
			return nil, nil, fmt.Errorf("Invalid Azure Service Tags payload")
		}
		var prefixes []string
		for _, value := range payload.Values {
			prefixes = append(prefixes, value.Properties.AddressPrefixes...)
		}
		return parseAddressOrCIDRList(prefixes)
	default:
		return nil, nil, fmt.Errorf("Provider refresh parser is not configured")
	}
}

func parseAddressOrCIDRList(values []string) ([]*net.IPNet, []*net.IPNet, error) {
	ipv4 := []*net.IPNet{}
	ipv6 := []*net.IPNet{}
	for _, value := range values {
		network, err := parseAddressOrCIDR(value)
		if err != nil {
			return nil, nil, err
		}
		if network.IP.To4() != nil {
			ipv4 = append(ipv4, network)
		} else {
			ipv6 = append(ipv6, network)
		}
	}
	return ipv4, ipv6, nil
}

func parseAddressOrCIDR(value string) (*net.IPNet, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, fmt.Errorf("Empty provider range")
	}
	if strings.Contains(value, "/") {
		return parseCIDR(value)
	}
	ip := net.ParseIP(value)
	if ip == nil {
		return nil, fmt.Errorf("Invalid provider range")
	}
	if ip.To4() != nil {
		return parseCIDR(value + "/32")
	}
	return parseCIDR(value + "/128")
}

func parseCIDR(value string) (*net.IPNet, error) {
	_, network, err := net.ParseCIDR(value)
	if err != nil {
		return nil, fmt.Errorf("Invalid provider range")
	}
	return network, nil
}

func (a *subnetAnalyzer) subnetInfoIPv6(value string) (map[string]any, error) {
	ip, network, err := net.ParseCIDR(value)
	if err != nil || ip.To4() != nil {
		return nil, fmt.Errorf("This endpoint only supports IPv6 networks")
	}
	ones, _ := network.Mask.Size()
	return map[string]any{
		"network":         value,
		"network_address": network.IP.String(),
		"prefix_length":   ones,
		"total_addresses": ipv6AddressCount(ones),
		"note":            "IPv6 subnets do not have reserved addresses like IPv4",
	}, nil
}

func (a *subnetAnalyzer) subnetInfoIPv4(networkStr, mode string) (subnetIPv4Response, error) {
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

func (a *subnetAnalyzer) allocateNetworkPlan(req networkPlanRequest) (networkPlanResponse, error) {
	if len(req.Requirements) == 0 {
		return networkPlanResponse{}, fmt.Errorf("At least one requirement is required")
	}
	if _, err := modeOffset(req.Mode); err != nil {
		return networkPlanResponse{}, err
	}
	ip, parent, err := net.ParseCIDR(req.Parent)
	if err != nil || ip.To4() == nil {
		return networkPlanResponse{}, fmt.Errorf("parent must be an IPv4 CIDR network")
	}
	parentPrefix, bits := parent.Mask.Size()
	if bits != 32 {
		return networkPlanResponse{}, fmt.Errorf("parent must be an IPv4 CIDR network")
	}
	parentStart := ipv4ToUint32(parent.IP)
	parentSize := uint64(1) << uint(32-parentPrefix)
	parentEnd := uint64(parentStart) + parentSize

	requirements := append([]networkPlanRequirement(nil), req.Requirements...)
	for _, requirement := range requirements {
		if strings.TrimSpace(requirement.Name) == "" {
			return networkPlanResponse{}, fmt.Errorf("requirement name is required")
		}
		if requirement.Hosts == 0 {
			return networkPlanResponse{}, fmt.Errorf("requirement hosts must be greater than zero")
		}
	}
	sort.SliceStable(requirements, func(i, j int) bool {
		return requirements[i].Hosts > requirements[j].Hosts
	})

	cursor := uint64(parentStart)
	allocations := make([]networkPlanAllocation, 0, len(requirements))
	for _, requirement := range requirements {
		prefix, total, err := smallestIPv4PrefixForHosts(requirement.Hosts, req.Mode)
		if err != nil {
			return networkPlanResponse{}, err
		}
		cursor = alignToBlock(cursor, total)
		if cursor+total > parentEnd {
			return networkPlanResponse{}, fmt.Errorf("requirements do not fit inside parent network")
		}
		network := fmt.Sprintf("%s/%d", uint32ToIPv4(uint32(cursor)).String(), prefix)
		info, err := a.subnetInfoIPv4(network, req.Mode)
		if err != nil {
			return networkPlanResponse{}, err
		}
		allocations = append(allocations, networkPlanAllocation{
			Name:            requirement.Name,
			Network:         network,
			PrefixLength:    prefix,
			TotalAddresses:  info.TotalAddresses,
			UsableAddresses: info.UsableAddresses,
			FirstUsableIP:   info.FirstUsableIP,
			LastUsableIP:    info.LastUsableIP,
		})
		cursor += total
	}

	return networkPlanResponse{Parent: req.Parent, Mode: req.Mode, Allocations: allocations}, nil
}

func smallestIPv4PrefixForHosts(hosts uint64, mode string) (int, uint64, error) {
	for prefix := 32; prefix >= 0; prefix-- {
		total := uint64(1) << uint(32-prefix)
		usable, err := usableIPv4Addresses(prefix, total, mode)
		if err != nil {
			return 0, 0, err
		}
		if usable >= hosts {
			return prefix, total, nil
		}
	}
	return 0, 0, fmt.Errorf("host requirement is too large")
}

func usableIPv4Addresses(prefix int, total uint64, mode string) (uint64, error) {
	offset, err := modeOffset(mode)
	if err != nil {
		return 0, err
	}
	if prefix == 31 || prefix == 32 {
		return total, nil
	}
	reserved := uint64(offset) + 1
	if total <= reserved {
		return 0, nil
	}
	return total - reserved, nil
}

func alignToBlock(value, blockSize uint64) uint64 {
	if blockSize == 0 || value%blockSize == 0 {
		return value
	}
	return value + blockSize - (value % blockSize)
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

func ipv6AddressCount(prefixLength int) string {
	if prefixLength < 0 || prefixLength > 128 {
		return "0"
	}
	return new(big.Int).Lsh(big.NewInt(1), uint(128-prefixLength)).String()
}
