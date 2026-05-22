// Shared browser helpers for platform apps using oauth2-proxy /.auth/me.
(function () {
  function normalizeGatewaySession(payload) {
    if (Array.isArray(payload)) {
      return payload[0] || null;
    }
    if (payload && payload.clientPrincipal) {
      return payload.clientPrincipal;
    }
    return null;
  }

  function gatewayDisplayName(session) {
    const claims = Array.isArray(session && session.claims) ? session.claims : [];
    const claimValue = (name) => {
      const found = claims.find((claim) => claim.typ === name || claim.type === name);
      return found ? found.val || found.value : "";
    };
    return (
      claimValue("email") ||
      claimValue("name") ||
      claimValue("preferred_username") ||
      session.userDetails ||
      session.user_details ||
      session.email ||
      session.preferred_username ||
      session.name ||
      session.user_id ||
      session.userId ||
      "authenticated user"
    );
  }

  async function fetchGatewaySession(path) {
    const response = await fetch(path || "/.auth/me", {
      cache: "no-store",
      headers: {Accept: "application/json"},
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    return normalizeGatewaySession(await response.json());
  }

  function gatewayLogoutURL(returnPath) {
    const oauthSignOut = new URL("/oauth2/sign_out", window.location.origin);
    oauthSignOut.searchParams.set("rd", returnPath || "/signed-out.html");
    return oauthSignOut.toString();
  }

  window.PlatformIdpAuth = Object.freeze({
    normalizeGatewaySession,
    gatewayDisplayName,
    fetchGatewaySession,
    gatewayLogoutURL,
  });
})();
