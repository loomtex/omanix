# omanix.dns: systemd-resolved behind NetworkManager, with upstream's
# provider presets (bin/omarchy-dns, which is AGENT-INTENT: changing the
# provider is a sentence to the agent, and the read-only reader in fork/add
# prints this option). etc/systemd/resolved.conf.d: no LLMNR or multicast
# DNS in resolved (avahi does mDNS), and a stub for Docker's bridge.
{ config, lib, ... }:

let
  cfg = config.omanix;
  dcfg = cfg.dns;
  quad9 = [ "9.9.9.9#dns.quad9.net" "149.112.112.112#dns.quad9.net" "2620:fe::fe#dns.quad9.net" "2620:fe::9#dns.quad9.net" ];
  presets = {
    cloudflare = {
      nm = [ "1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001" ];
      resolved = map (a: "${a}#cloudflare-dns.com") [ "1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001" ];
    };
    google = {
      nm = [ "8.8.8.8" "8.8.4.4" "2001:4860:4860::8888" "2001:4860:4860::8844" ];
      resolved = map (a: "${a}#dns.google") [ "8.8.8.8" "8.8.4.4" "2001:4860:4860::8888" "2001:4860:4860::8844" ];
    };
    custom = {
      nm = map (s: lib.head (lib.splitString "#" s)) dcfg.servers;
      resolved = dcfg.servers;
    };
  };
  preset = presets.${dcfg.provider} or null;
in
{
  options.omanix.dns = {
    provider = lib.mkOption {
      type = lib.types.enum [ "dhcp" "cloudflare" "google" "custom" ];
      default = "dhcp";
      example = "cloudflare";
      description = "DNS servers: from DHCP, a preset (DNS over TLS when the server offers it), or omanix.dns.servers.";
    };
    servers = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[0-9A-Fa-f:.]+(#[A-Za-z0-9.-]+)?");
      default = [ ];
      example = [ "9.9.9.9#dns.quad9.net" "149.112.112.112#dns.quad9.net" ];
      description = "Servers for provider = \"custom\" (`address` or `address#tls-name`).";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [{
        assertion = dcfg.provider != "custom" || dcfg.servers != [ ];
        message = "omanix.dns.provider = \"custom\" needs omanix.dns.servers.";
      }];
      services.resolved.enable = lib.mkDefault true;
      networking.networkmanager.dns = lib.mkDefault "systemd-resolved";
      services.resolved.settings.Resolve = {
        LLMNR = lib.mkDefault "no";
        MulticastDNS = lib.mkDefault "no";
        DNSStubListenerExtra = lib.mkIf config.virtualisation.docker.enable (lib.mkDefault "172.17.0.1");
      };
    }
    (lib.mkIf (preset != null) {
      networking.networkmanager.settings."global-dns-domain-*".servers = lib.mkDefault (lib.concatStringsSep "," preset.nm);
      services.resolved.settings.Resolve = {
        DNS = lib.mkDefault (lib.concatStringsSep " " preset.resolved);
        FallbackDNS = lib.mkDefault (lib.concatStringsSep " " quad9);
        DNSOverTLS = lib.mkDefault "opportunistic";
      };
    })
  ]);
}
