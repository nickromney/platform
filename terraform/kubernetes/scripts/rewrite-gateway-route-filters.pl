# Rewrites an HTTPRoute's NGINX SnippetsFilter ExtensionRef into a core Gateway
# API ResponseHeaderModifier. Run with `perl -0pi` over one route file.
#
# Kept as a file rather than inlined into sync-gitea-policies.sh because the
# pattern is multi-line and quoting it through a shell heredoc silently stops it
# matching -- the rewrite then no-ops and the route keeps a filter whose CRD
# does not exist in this mode.
#
# FRAME_OPTIONS selects the X-Frame-Options value: SAMEORIGIN for Keycloak
# admin, which needs same-origin framing for its browser storage check, DENY
# everywhere else.
my $frame = $ENV{FRAME_OPTIONS} // 'DENY';
s{
  ^([ ]+)filters:\n
  [ ]+-[ ]type:[ ]ExtensionRef\n
  [ ]+extensionRef:\n
  [ ]+group:[ ]gateway\.nginx\.org\n
  [ ]+kind:[ ]SnippetsFilter\n
  [ ]+name:[ ][^\n]+\n
}{
  my $i = $1;
  $i . "filters:\n"
    . $i . "  - type: ResponseHeaderModifier\n"
    . $i . "    responseHeaderModifier:\n"
    . $i . "      set:\n"
    . $i . "        - name: Strict-Transport-Security\n"
    . $i . "          value: \"max-age=63072000; includeSubDomains\"\n"
    . $i . "        - name: X-Content-Type-Options\n"
    . $i . "          value: \"nosniff\"\n"
    . $i . "        - name: X-Frame-Options\n"
    . $i . "          value: \"" . $frame . "\"\n"
    . $i . "        - name: Referrer-Policy\n"
    . $i . "          value: \"strict-origin-when-cross-origin\"\n"
}gmex
