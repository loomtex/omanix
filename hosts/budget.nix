# The size guards of the reference hosts (§e.1, checks.closure-budget): what
# must never reach a release cache. Only the reference hosts carry them; a
# user's host may install TeX or Haskell if it wants to.
#
# Deviation from §e.1's list: no `-doc$`. git and mpv reference their own doc
# outputs at runtime (16 MiB together), so it can't be a hard ban;
# documentation.doc is off (modules/omanix/packages.nix) and
# checks.closure-budget caps what doc outputs remain instead.
#
# texlive: evince links kpathsea from texlive-bin (37 MiB, DVI support), so
# only texlive-bin is allowed; any other TeX Live path is refused (three
# regexes: nixpkgs splices each one into a `[[ ]]` unquoted, so no groups).
{
  system.forbiddenDependenciesRegexes = [ "texlive-[^b]" "texlive-b[^i]" "texlive-bi[^n]" "ghc-" ];
}
