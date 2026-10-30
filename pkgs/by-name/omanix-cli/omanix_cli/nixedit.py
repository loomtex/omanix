"""A comment-preserving editor for host-repo Nix files (DESIGN §h.8, U19).

`omanix set` rewrites one literal definition in place, appends a new one
under the marker line of configuration.nix (home.nix for home.* paths), or
refuses with file:line for each definition it can't edit safely. The edits
are byte splices on a tree-sitter-nix parse, so everything outside the
edited value (comments, layout, other bindings) stays byte-identical.

U19 named nix-editor (rnix) first and a tree-sitter-nix editor as the
fallback; nix-editor is not in nixpkgs, so this is the tree-sitter one, and
checks.set-roundtrip settles it.

Nothing here evaluates Nix: the resolver reports which files define a path
(live eval), this module finds the binding inside each file.
"""

from __future__ import annotations

import json
import re
import warnings
from dataclasses import dataclass, field

import tree_sitter_nix
from tree_sitter import Language, Parser

with warnings.catch_warnings():
    warnings.simplefilter("ignore", DeprecationWarning)   # the grammar hands over an int pointer
    _LANG = Language(tree_sitter_nix.language())
_PARSER = Parser(_LANG)

MARKER = "# Below this line: changes made by the agent or by you."
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_'-]*$")
KEYWORDS = {"if", "then", "else", "assert", "with", "let", "in", "rec", "inherit", "or"}


class EditError(Exception):
    """An edit that can't be made safely (exit 2: edit by hand)."""


class Raw(str):
    """Nix text written as it is (an identifier list like `[ pkgs.hello ]`)."""


# ---------------------------------------------------------------- rendering


def nix_string(s: str) -> str:
    out = s.replace("\\", "\\\\").replace('"', '\\"').replace("${", "\\${")
    out = out.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    return f'"{out}"'


def attr_name(name: str) -> str:
    return name if IDENT.match(name) and name not in KEYWORDS else nix_string(name)


def attrpath(path: list[str]) -> str:
    return ".".join(attr_name(p) for p in path)


def render(value, indent: str = "  ") -> str:
    """JSON → a Nix literal. Lists and attrsets of more than one element go
    one per line (nixfmt's layout), so diffs on the card stay readable."""
    if isinstance(value, Raw):
        return str(value)
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        r = repr(value)
        return r if ("." in r or "e" in r) else r + ".0"
    if isinstance(value, str):
        return nix_string(value)
    inner = indent + "  "
    if isinstance(value, list):
        if not value:
            return "[ ]"
        items = [render(v, inner) for v in value]
        if len(items) == 1 and "\n" not in items[0]:
            return f"[ {items[0]} ]"
        return "[\n" + "".join(f"{inner}{i}\n" for i in items) + f"{indent}]"
    if isinstance(value, dict):
        if not value:
            return "{ }"
        lines = [f"{inner}{attr_name(k)} = {render(v, inner)};\n" for k, v in value.items()]
        return "{\n" + "".join(lines) + f"{indent}}}"
    raise EditError(f"can't write a {type(value).__name__} as Nix")


# ---------------------------------------------------------------- parsing


def parse(src: bytes):
    tree = _PARSER.parse(src)
    if tree.root_node.has_error:
        raise EditError("the file doesn't parse as Nix")
    return tree


def _text(node) -> str:
    return node.text.decode()


def _attrs(attrpath_node) -> list[str] | None:
    """Names of an attrpath; None when one is interpolated."""
    out = []
    for c in attrpath_node.named_children:
        if c.type == "identifier":
            out.append(_text(c))
        elif c.type == "string_expression":
            frags = [x for x in c.named_children]
            if any(x.type != "string_fragment" for x in frags):
                return None
            out.append(json.loads('"' + "".join(_text(x) for x in frags).replace('"', '\\"') + '"')
                       if frags else "")
        else:
            return None
    return out


def _unparen(n):
    while n is not None and n.type == "parenthesized_expression":
        n = n.named_children[0]
    return n


def module_body(tree):
    """The attrset a module file returns: `{ … }` or `{ args }: { … }`."""
    root = tree.root_node
    exprs = [c for c in root.named_children if c.type != "comment"]
    if len(exprs) != 1:
        raise EditError("not a single module expression")
    e = _unparen(exprs[0])
    while e is not None and e.type == "function_expression":
        e = _unparen(e.child_by_field_name("body"))
    if e is None or e.type not in ("attrset_expression", "rec_attrset_expression"):
        raise EditError("the module doesn't return an attrset literal")
    return e


def _bindings(attrset):
    for c in attrset.named_children:
        if c.type == "binding_set":
            for b in c.named_children:
                if b.type in ("binding", "inherit", "inherit_from"):
                    yield b


def is_literal(n) -> bool:
    n = _unparen(n)
    t = n.type
    if t in ("integer_expression", "float_expression"):
        return True
    if t == "string_expression" or t == "indented_string_expression":
        return all(c.type in ("string_fragment", "escape_sequence", "dollar_escape") for c in n.named_children)
    if t == "variable_expression":
        return _text(n) in ("true", "false", "null")
    if t == "unary_expression":
        return _text(n).lstrip().startswith("-") and is_literal(n.named_children[-1])
    if t == "list_expression":
        return all(is_literal(c) for c in n.named_children if c.type != "comment")
    if t == "attrset_expression":
        for b in _bindings(n):
            if b.type != "binding" or _attrs(b.child_by_field_name("attrpath")) is None:
                return False
            if not is_literal(b.child_by_field_name("expression")):
                return False
        return True
    return False


@dataclass
class Match:
    kind: str                 # "value" | "partial" | "opaque"
    binding: object           # the binding node
    value: object = None      # the value node (kind == value)
    rest: list = field(default_factory=list)

    @property
    def line(self) -> int:
        return self.binding.start_point[0] + 1


def find(attrset, path: list[str]) -> list[Match]:
    """Bindings of `path` in an attrset literal, descending into nested
    non-recursive attrset literals."""
    out = []
    for b in _bindings(attrset):
        if b.type != "binding":
            names = [_text(x) for x in b.named_children if x.type in ("identifier",)]
            if path and path[0] in names:
                out.append(Match("opaque", b))
            continue
        names = _attrs(b.child_by_field_name("attrpath"))
        val = b.child_by_field_name("expression")
        if names is None:
            out.append(Match("opaque", b))
            continue
        k = 0
        while k < len(names) and k < len(path) and names[k] == path[k]:
            k += 1
        if k == 0:
            continue
        if k == len(names) == len(path):
            out.append(Match("value", b, val))
        elif k == len(names) < len(path):
            inner = _unparen(val)
            if inner.type == "attrset_expression":
                out += find(inner, path[k:])
            else:
                out.append(Match("opaque", b, val, path[k:]))
        elif k == len(path) < len(names):
            out.append(Match("partial", b, val))
    return out


def find_in_module(tree, path: list[str]) -> list[Match]:
    body = module_body(tree)
    found = find(body, path)
    if not found:
        # `{ config = { … }; options = …; }` modules define under config.
        for m in find(body, ["config"] + path):
            found.append(m)
    return found


# ---------------------------------------------------------------- editing


def _line_bounds(src: bytes, start: int, end: int) -> tuple[int, int]:
    """Widen [start, end) to whole lines when only blanks surround it."""
    ls = src.rfind(b"\n", 0, start) + 1
    le = src.find(b"\n", end)
    le = len(src) if le < 0 else le + 1
    before = src[ls:start]
    after = src[end:le].strip()
    if before.strip() == b"" and (after == b"" or after.startswith(b"#")):
        return ls, le
    return start, end


def replace_value(src: bytes, m: Match, value) -> bytes:
    if m.kind != "value":
        raise EditError("not a single definition")
    node = m.value
    col = node.start_point[1]
    line_start = src.rfind(b"\n", 0, node.start_byte) + 1
    indent = re.match(rb"[ \t]*", src[line_start:]).group().decode()
    text = render(value, indent).encode()
    del col
    return src[: node.start_byte] + text + src[node.end_byte:]


def delete_binding(src: bytes, m: Match) -> bytes:
    s, e = _line_bounds(src, m.binding.start_byte, m.binding.end_byte)
    return src[:s] + src[e:]


def append_binding(tree, src: bytes, path: list[str], value) -> bytes:
    """Add `path = value;` as the last binding of the module's attrset, so it
    lands under the marker comment of configuration.nix."""
    body = module_body(tree)
    close = body.children[-1]
    assert close.type == "}"
    ls = src.rfind(b"\n", 0, close.start_byte) + 1
    if src[ls:close.start_byte].strip():
        # `{ … }` closed on a line with content: put ours on its own line.
        ins = close.start_byte
        prefix = b"\n"
    else:
        ins = ls
        prefix = b""
    # the indentation of the existing top-level bindings (two spaces by default)
    ind = "  "
    for b in _bindings(body):
        bl = src.rfind(b"\n", 0, b.start_byte) + 1
        ind = re.match(rb"[ \t]*", src[bl:]).group().decode() or ind
        break
    line = f"{ind}{attrpath(path)} = {render(value, ind)};\n".encode()
    return src[:ins] + prefix + line + src[ins:]


def insert_path(tree, src: bytes, path: list[str], value) -> bytes:
    """Add `path = value;` inside the deepest attrset literal of the module
    that already spells a prefix of path (so `omanix.defaults = { … };`
    gains `browser = …;`), else as the module's last binding."""
    body = module_body(tree)
    target, rest = body, path
    while len(rest) > 1:
        nxt = None
        for k in range(len(rest) - 1, 0, -1):
            ms = [m for m in find(target, rest[:k]) if m.kind == "value"]
            if len(ms) == 1 and _unparen(ms[0].value).type == "attrset_expression":
                nxt = (_unparen(ms[0].value), rest[k:])
                break
        if nxt is None:
            break
        target, rest = nxt
    if target is body:
        return append_binding(tree, src, path, value)
    close = target.children[-1]
    one_line = target.start_point[0] == close.start_point[0]
    bl = src.rfind(b"\n", 0, target.start_byte) + 1
    base = re.match(rb"[ \t]*", src[bl:]).group().decode()
    if one_line:
        # `{ a = 1; }` → `{ a = 1; b = 2; }`
        ins = close.start_byte
        text = f"{attrpath(rest)} = {render(value, base)}; "
        if src[ins - 1:ins] != b" ":
            text = " " + text
        return src[:ins] + text.encode() + src[ins:]
    ind = base + "  "
    for b in _bindings(target):
        l = src.rfind(b"\n", 0, b.start_byte) + 1
        ind = re.match(rb"[ \t]*", src[l:]).group().decode() or ind
    ls = src.rfind(b"\n", 0, close.start_byte) + 1
    line = f"{ind}{attrpath(rest)} = {render(value, ind)};\n".encode()
    if src[ls:close.start_byte].strip():
        return src[: close.start_byte] + b"\n" + line + base.encode() + src[close.start_byte:]
    return src[:ls] + line + src[ls:]


def ensure_formal(tree, src: bytes, name: str) -> bytes:
    """`{ pkgs, ... }:` → `{ pkgs, inputs, ... }:`"""
    root = [c for c in tree.root_node.named_children if c.type != "comment"][0]
    root = _unparen(root)
    if root.type != "function_expression":
        raise EditError("the module isn't a function; add `" + name + "` to its arguments by hand")
    formals = root.child_by_field_name("formals")
    if formals is None:
        raise EditError("the module's arguments aren't a set pattern")
    names = [_text(f.child_by_field_name("name")) for f in formals.named_children if f.type == "formal"]
    if name in names:
        return src
    ell = [c for c in formals.named_children if c.type == "ellipses"]
    if ell:
        at = ell[0].start_byte
        return src[:at] + f"{name}, ".encode() + src[at:]
    close = formals.children[-1]
    sep = ", " if names else " "
    return src[: close.start_byte].rstrip() + f"{sep}{name} ".encode() + src[close.start_byte:]


def list_node(n):
    """The list literal of `[ … ]` or `with pkgs; [ … ]`."""
    n = _unparen(n)
    if n.type == "with_expression":
        n = _unparen(n.child_by_field_name("body"))
    return n if n.type == "list_expression" else None


def list_elements(n) -> list[str]:
    return [_text(c) for c in n.named_children if c.type != "comment"]


def list_append(src: bytes, lst, element: str) -> bytes:
    close = lst.children[-1]
    elems = [c for c in lst.named_children if c.type != "comment"]
    if not elems:
        # `[ ]` → `[ x ]`
        return src[: lst.start_byte] + f"[ {element} ]".encode() + src[lst.end_byte:]
    multiline = lst.start_point[0] != close.start_point[0]
    if multiline:
        last = elems[-1]
        ls = src.rfind(b"\n", 0, last.start_byte) + 1
        ind = re.match(rb"[ \t]*", src[ls:]).group()
        le = src.find(b"\n", last.end_byte)
        return src[: le + 1] + ind + element.encode() + b"\n" + src[le + 1:]
    last = elems[-1]
    return src[: last.end_byte] + b" " + element.encode() + src[last.end_byte:]


def list_remove(src: bytes, lst, element: str) -> bytes:
    for c in lst.named_children:
        if c.type != "comment" and _text(c) == element:
            s, e = _line_bounds(src, c.start_byte, c.end_byte)
            if (s, e) == (c.start_byte, c.end_byte):
                # inline: drop one neighbouring space too
                if src[e:e + 1] == b" ":
                    e += 1
                elif src[s - 1:s] == b" ":
                    s -= 1
            return src[:s] + src[e:]
    raise EditError(f"{element} is not in the list")


def import_add(tree, src: bytes, element: str) -> bytes:
    """Append to the module's `imports = [ … ];`, creating it if absent."""
    body = module_body(tree)
    ms = [m for m in find(body, ["imports"]) if m.kind == "value"]
    if ms:
        lst = list_node(ms[0].value)
        if lst is None:
            raise EditError("imports isn't a list literal")
        if element in list_elements(lst):
            return src
        return list_append(src, lst, element)
    # new binding right after the opening brace
    open_ = body.children[0]
    ind = "  "
    line = f"\n{ind}imports = [ {element} ];".encode()
    if src[open_.end_byte:open_.end_byte + 1] == b"\n":
        return src[: open_.end_byte + 1] + f"{ind}imports = [ {element} ];\n".encode() + src[open_.end_byte + 1:]
    return src[: open_.end_byte] + line + src[open_.end_byte:]


def import_remove(tree, src: bytes, element: str) -> bytes:
    body = module_body(tree)
    for m in find(body, ["imports"]):
        if m.kind == "value":
            lst = list_node(m.value)
            if lst is not None and element in list_elements(lst):
                return list_remove(src, lst, element)
    return src


# ---------------------------------------------------------------- literal values


def literal_value(n):
    """A literal's JSON value (for reporting what a file says)."""
    n = _unparen(n)
    t = n.type
    if t == "integer_expression":
        return int(_text(n))
    if t == "float_expression":
        return float(_text(n))
    if t == "variable_expression":
        return {"true": True, "false": False, "null": None}[_text(n)]
    if t == "unary_expression":
        return -literal_value(n.named_children[-1])
    if t == "string_expression":
        s = ""
        for c in n.named_children:
            if c.type == "string_fragment":
                s += _text(c)
            elif c.type == "escape_sequence":
                s += json.loads('"' + _text(c).replace("\\$", "$") + '"') if _text(c) != "\\$" else "$"
            elif c.type == "dollar_escape":
                s += "$"
        return s
    if t == "indented_string_expression":
        raw = "".join(_text(c) for c in n.named_children)
        lines = raw.split("\n")
        if lines and lines[0].strip() == "":
            lines = lines[1:]
        ind = min((len(l) - len(l.lstrip(" ")) for l in lines if l.strip()), default=0)
        return "\n".join(l[ind:] for l in lines)
    if t == "list_expression":
        return [literal_value(c) for c in n.named_children if c.type != "comment"]
    if t == "attrset_expression":
        out: dict = {}
        for b in _bindings(n):
            names = _attrs(b.child_by_field_name("attrpath"))
            d = out
            for k in names[:-1]:
                d = d.setdefault(k, {})
            d[names[-1]] = literal_value(b.child_by_field_name("expression"))
        return out
    raise EditError("not a literal")
