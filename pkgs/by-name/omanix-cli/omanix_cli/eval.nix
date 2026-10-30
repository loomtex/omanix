# omanix CLI: live evaluation of the working copy (DESIGN §h.8).
# Inlined into `nix eval <repo>#nixosConfigurations.host --apply`, so it
# runs under pure evaluation and may not import anything by path.
#
#   req.op = "where": the option at req.path, every definition of it (file,
#            priority, value) and the current value. A path that walks into
#            home-manager.users.<u> (or starts with home./xdg./programs. via
#            req.hm) is resolved in that user's HM configuration.
#   req.op = "value": the current values of req.paths.
#   req.op = "info":  host facts the CLI needs (user, agent, sources).
{ host, req }:

let
  lib = host.pkgs.lib;
  inherit (host) config options;
  user = config.loom.user.name or null;

  # ---- JSON-safe values ------------------------------------------------
  # Derivations become "<derivation name>", functions "<function>"; strings
  # lose their store context so nothing is built or copied.
  san = depth: v:
    let r = builtins.tryEval (
      if lib.isDerivation v then "<derivation ${v.name or "?"}>"
      else if builtins.isFunction v then "<function>"
      else if builtins.isPath v then toString v
      else if builtins.isString v then builtins.unsafeDiscardStringContext v
      else if builtins.isList v then
        (if depth <= 0 then "<list>" else map (san (depth - 1)) (lib.take 200 v))
      else if builtins.isAttrs v then
        (if v ? _type && v ? text then { _type = v._type; text = builtins.unsafeDiscardStringContext v.text; }
         else if depth <= 0 then "<attrs>"
         else lib.mapAttrs (_: san (depth - 1)) (removeAttrs v [ "_module" ]))
      else v);
    in if r.success then r.value else "<error>";

  srcPath = toString (config.loom.host.src or "");
  inputs = host._module.specialArgs.inputs or { };
  inputPaths = lib.mapAttrsToList (n: i: { name = n; path = builtins.unsafeDiscardStringContext (toString (i.outPath or "")); })
    (lib.filterAttrs (n: i: n != "self" && (i ? outPath)) inputs);

  origin = file:
    let
      f = builtins.unsafeDiscardStringContext (toString file);
      host' = builtins.unsafeDiscardStringContext srcPath;
      hit = lib.findFirst (i: i.path != "" && lib.hasPrefix (i.path + "/") f) null inputPaths;
    in
    if host' != "" && lib.hasPrefix (host' + "/") f then { kind = "host"; file = lib.removePrefix (host' + "/") f; }
    else if hit != null then { kind = "input"; input = hit.name; file = lib.removePrefix (hit.path + "/") f; }
    else { kind = "other"; file = f; };

  # ---- definitions, with priorities from the mk* wrappers -----------------
  # A definition's raw value may wrap the part we want in mkIf/mkOverride/
  # mkMerge/mkOrder; unwrap down the remaining path. Functions and anything
  # else not an attrset literal are reported as opaque.
  unwrap = prio: v:
    if builtins.isAttrs v && v ? _type then
      if v._type == "if" then (if v.condition then unwrap prio v.content else [ ])
      else if v._type == "override" then unwrap v.priority v.content
      else if v._type == "merge" then lib.concatMap (unwrap prio) v.contents
      else if v._type == "order" then unwrap prio v.content
      else [ { inherit prio; value = v; } ]
    else [ { inherit prio; value = v; } ];

  dig = rest: d:
    if rest == [ ] then [ d ]
    else
      let v = d.value; in
      if builtins.isFunction v then [ (d // { opaque = true; }) ]
      else if builtins.isAttrs v && !(v ? _type) then
        (if v ? ${builtins.head rest} then lib.concatMap (dig (builtins.tail rest)) (unwrap d.prio v.${builtins.head rest})
         else if v ? config || v ? imports then [ (d // { opaque = true; }) ] else [ ])
      else [ ];

  defsOf = opt: rest:
    lib.concatMap (d:
      map (x: {
        origin = origin d.file;
        priority = x.prio;
        opaque = x.opaque or false;
        value = if x.opaque or false then null else san 4 x.value;
      }) (lib.concatMap (dig rest) (unwrap 100 d.value)))
    (opt.definitionsWithLocations or [ ]);

  isOption = lib.isOption;

  # Walk `path` through the option tree; descend into submodule values
  # (home-manager.users.<u>, attrsOf submodule) through valueMeta.
  walk = opts: path:
    if path == [ ] then { node = opts; rest = [ ]; }
    else
      let n = builtins.head path; t = builtins.tail path; in
      if isOption opts then
        let
          vm = opts.valueMeta or { };
          sub =
            if vm ? attrs && vm.attrs ? ${n} && vm.attrs.${n} ? configuration then { o = vm.attrs.${n}.configuration.options; r = t; }
            else if vm ? configuration && vm.configuration.options ? ${n} then { o = vm.configuration.options.${n}; r = t; }
            else null;
        in
        if sub != null then walk sub.o sub.r else { node = opts; rest = path; }
      else if builtins.isAttrs opts && opts ? ${n} then walk opts.${n} t
      else { node = null; rest = path; };

  hmPath = p: [ "home-manager" "users" user ] ++ p;

  where = p:
    let
      full = if req.hm or false then hmPath p else p;
      w = walk options full;
      opt = w.node;
      found = opt != null && isOption opt;
      val = builtins.tryEval (lib.attrByPath full "<unset>" config);
      tyDesc = o: (builtins.tryEval (o.type.description or null)).value or null;
      group = opt != null && !(isOption opt) && builtins.isAttrs opt;
    in
    {
      path = p;
      fullPath = full;
      kind = if found then "option" else if group then "group" else "missing";
      optionPath = if found then opt.loc else null;
      rest = w.rest;
      type = if found && w.rest == [ ] then tyDesc opt else null;
      description = if found then (opt.description.text or opt.description or null) else null;
      readOnly = if found then opt.readOnly or false else false;
      highestPrio = if found then opt.highestPrio or null else null;
      declarations = if found then map (d: origin d) (opt.declarations or [ ]) else [ ];
      definitions = if found then defsOf opt w.rest else [ ];
      children = if group then lib.take 100 (builtins.attrNames (removeAttrs opt [ "_module" ])) else [ ];
      value = if val.success then san 6 val.value else "<error>";
      hasValue = val.success && val.value != "<unset>";
    };

  info = {
    inherit user;
    agent = if config.loom.agent.enable or false then config.loom.agent.name else null;
    hostSrc = srcPath;
    inputs = inputPaths;
    hostName = config.networking.hostName or null;
    hostId = config.loom.host.id or null;
    release = config.omanix.release or null;
  };
in
if req.op == "where" then where req.path
else if req.op == "value" then lib.listToAttrs (map (p: {
  name = lib.concatStringsSep "." p;
  value = let full = if req.hm or false then hmPath p else p; r = builtins.tryEval (lib.attrByPath full "<unset>" config); in
    if r.success then san 6 r.value else "<error>";
}) req.paths)
else if req.op == "info" then info
else if req.op == "keys" then {
  generated = config.loom.keys.generated or null;
}
else if req.op == "assertions" then {
  failed = map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);
  warnings = config.warnings;
}
else throw "omanix eval: unknown op ${req.op}"
