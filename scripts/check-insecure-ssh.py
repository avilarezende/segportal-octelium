#!/usr/bin/env python3
"""Valida que os recursos YAML/templates do bundle não têm insecureIgnoreHostKey ativo.

Corre no CI após validar os YAML. Ignora linhas comentadas.
"""
from pathlib import Path

BAD_PATTERN = "insecureIgnoreHostKey: true"


def main() -> int:
    bad: list[str] = []
    for path in sorted(Path(".").rglob("*")):
        if path.suffix not in (".yaml", ".tpl"):
            continue
        if ".git" in path.parts or ".github" in path.parts:
            continue
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for lineno, line in enumerate(text.splitlines(), 1):
            stripped = line.lstrip()
            if stripped.startswith("#"):
                continue
            if BAD_PATTERN in stripped:
                bad.append(f"{path}:{lineno}: {stripped}")

    if bad:
        print("ERRO: insecureIgnoreHostKey ativo encontrado:")
        for item in bad:
            print(f"  {item}")
        return 1
    print("OK: nenhum insecureIgnoreHostKey: true ativo nos recursos YAML/templates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())