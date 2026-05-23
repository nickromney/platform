package app

type Config struct {
	Addr                 string
	AuthMode             string
	APIAuthMode          string
	RuntimeRole          string
	BackendURL           string
	OIDCIssuer           string
	OIDCClientID         string
	OIDCAudience         string
	OIDCJWKSURI          string
	OIDCRedirect         string
	NetworkHops          string
	ShowNetworkPath      string
	ProviderRangeSources map[string]string
}

type subnetIPv4Request struct {
	Network string `json:"network"`
	Mode    string `json:"mode"`
}

type subnetIPv6Request struct {
	Network string `json:"network"`
}

type validateRequest struct {
	Address string `json:"address"`
}

type providerRangeRequest struct {
	Provider string `json:"provider"`
	Address  string `json:"address"`
}

type subnetIPv4Response struct {
	Network          string  `json:"network"`
	Mode             string  `json:"mode"`
	NetworkAddress   string  `json:"network_address"`
	BroadcastAddress *string `json:"broadcast_address"`
	Netmask          string  `json:"netmask"`
	WildcardMask     string  `json:"wildcard_mask"`
	PrefixLength     int     `json:"prefix_length"`
	TotalAddresses   uint64  `json:"total_addresses"`
	UsableAddresses  uint64  `json:"usable_addresses"`
	FirstUsableIP    string  `json:"first_usable_ip"`
	LastUsableIP     string  `json:"last_usable_ip"`
	Note             string  `json:"note,omitempty"`
}
