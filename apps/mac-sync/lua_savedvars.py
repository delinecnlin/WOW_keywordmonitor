"""Small, deliberately limited parser for WoW SavedVariables (Lua table data only).

Never execute Lua or evaluate arbitrary expressions. Reject unsupported syntax.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

_NUMBER = re.compile(r"-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


@dataclass(frozen=True)
class Token:
    kind: str
    value: object


def tokenize(source: str) -> list[Token]:
    tokens: list[Token] = []
    i = 0
    while i < len(source):
        ch = source[i]
        if ch.isspace():
            i += 1
            continue
        if source.startswith("--", i):
            end = source.find("\n", i)
            i = len(source) if end < 0 else end + 1
            continue
        if ch in "{}[]=,;":
            tokens.append(Token(ch, ch))
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            output = bytearray()
            while i < len(source):
                c = source[i]
                i += 1
                if c == quote:
                    break
                if c != "\\":
                    output.extend(c.encode("utf-8"))
                    continue
                if i >= len(source):
                    raise ValueError("Incomplete Lua string escape")
                escaped = source[i]
                i += 1
                if escaped.isdigit():
                    digits = escaped
                    while len(digits) < 3 and i < len(source) and source[i].isdigit():
                        digits += source[i]
                        i += 1
                    code = int(digits, 10)
                    if code > 255:
                        raise ValueError("Invalid Lua decimal byte escape")
                    output.append(code)
                elif escaped in ("n", "r", "t"):
                    output.extend({"n": b"\n", "r": b"\r", "t": b"\t"}[escaped])
                elif escaped in ("\\", '"', "'"):
                    output.extend(escaped.encode())
                elif escaped == "\n":
                    output.extend(b"\n")
                else:
                    raise ValueError("Unsupported Lua escape: " + escaped)
            else:
                raise ValueError("Unclosed Lua string")
            tokens.append(Token("STRING", output.decode("utf-8", errors="replace")))
            continue
        numeric = _NUMBER.match(source, i)
        if numeric:
            value = numeric.group()
            tokens.append(Token("NUMBER", float(value) if any(c in value for c in ".eE") else int(value)))
            i = numeric.end()
            continue
        identifier = _IDENT.match(source, i)
        if identifier:
            tokens.append(Token("IDENT", identifier.group()))
            i = identifier.end()
            continue
        raise ValueError(f"Unsupported Lua syntax at byte/char offset {i}: {source[i:i+20]!r}")
    tokens.append(Token("EOF", None))
    return tokens


class _Reader:
    def __init__(self, tokens: list[Token]) -> None:
        self.tokens = tokens
        self.index = 0

    def peek(self, offset: int = 0) -> Token:
        return self.tokens[self.index + offset]

    def expect(self, kind: str) -> Token:
        token = self.peek()
        if token.kind != kind:
            raise ValueError(f"Expected {kind}, got {token.kind}")
        self.index += 1
        return token

    def value(self, depth: int = 0) -> object:
        if depth > 48:
            raise ValueError("Lua data nested too deeply")
        token = self.peek()
        if token.kind == "{":
            return self.table(depth + 1)
        if token.kind in ("STRING", "NUMBER"):
            self.index += 1
            return token.value
        if token.kind == "IDENT" and token.value in ("true", "false", "nil"):
            self.index += 1
            return {"true": True, "false": False, "nil": None}[str(token.value)]
        raise ValueError(f"Unsupported Lua value: {token}")

    def table(self, depth: int) -> dict[object, object]:
        self.expect("{")
        mapping: dict[object, object] = {}
        next_index = 1
        while self.peek().kind != "}":
            if self.peek().kind == "[":
                self.expect("[")
                key = self.value(depth)
                self.expect("]")
                self.expect("=")
                value = self.value(depth)
            elif self.peek().kind == "IDENT" and self.peek(1).kind == "=":
                key = self.expect("IDENT").value
                self.expect("=")
                value = self.value(depth)
            else:
                key = next_index
                value = self.value(depth)
                next_index += 1
            if not isinstance(key, (int, str)) or isinstance(key, bool):
                raise ValueError("Invalid SavedVariables table key")
            mapping[key] = value
            if self.peek().kind in (",", ";"):
                self.index += 1
            elif self.peek().kind != "}":
                raise ValueError("Missing Lua table separator")
        self.expect("}")
        return mapping


def _normalize(value: object) -> object:
    if isinstance(value, dict):
        result = {k: _normalize(v) for k, v in value.items()}
        if result and all(isinstance(k, int) and k > 0 for k in result):
            if set(result) == set(range(1, len(result) + 1)):
                return [result[i] for i in range(1, len(result) + 1)]
        return result
    return value


def parse_savedvariables(source: str, variable: str = "AuctionCollectorDB") -> dict:
    reader = _Reader(tokenize(source))
    while reader.peek().kind != "EOF":
        name = reader.expect("IDENT").value
        reader.expect("=")
        value = reader.value()
        if reader.peek().kind == ";":
            reader.expect(";")
        if name == variable:
            normalized = _normalize(value)
            if not isinstance(normalized, dict):
                raise ValueError("SavedVariables root must be a table")
            return normalized
    raise ValueError(f"Variable {variable!r} not found")
