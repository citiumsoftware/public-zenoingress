#!/usr/bin/env python3
"""Regenerate NOTICE + THIRD-PARTY-LICENSES.txt from the Rust dependency tree.

Per release, run tools/regen-notice.sh <source tree>: it scans what the images
contain (controller, proxy with `--features full`, edge) with cargo-about
(config: about.toml at the source root; accepted licenses mirror deny.toml),
merges the result and calls this script:

       python3 tools/gen-third-party-notice.py shipped.json .

First-party Citium crates (zenoingress-*, zenolms*, LicenseRef-Proprietary) are
excluded. Aborts if any bundled component is under a copyleft-only license.
"""
import json
import sys

# Verbatim proprietary header (kept in sync by hand; the third-party section
# below it is generated).
HEADER = """\
zenoingress
Copyright (c) 2026 Citium Software. All rights reserved.

This product is proprietary software licensed under the terms in the LICENSE
file in this repository. "Citium", "zenoingress", and related names and logos
are trademarks of Citium Software.

The currently published versions of zenoingress may be run free of charge in up
to one (1) production Kubernetes cluster and in an unlimited number of
non-production (development and test) clusters, subject to the LICENSE. Any other
use requires a commercial license. The LICENSE file is the authoritative and
complete statement of terms; this NOTICE is a summary and does not modify it.

--------------------------------------------------------------------------------
Third-party components
"""

COPYLEFT = ("GPL", "AGPL", "EUPL", "CDDL", "EPL", "SSPL", "OSL")


def is_first_party(name, lic):
    lic = lic or ""
    return (
        name.startswith("zenoingress")
        or name.startswith("zenolms")
        or "LicenseRef-Proprietary" in lic
    )


def norm(expr):
    return " ".join((expr or "").split())


def main(json_path, out_dir):
    data = json.load(open(json_path))

    crates = {}
    for group in data["licenses"]:
        for u in group.get("used_by", []):
            c = u["crate"]
            name, ver = c["name"], c["version"]
            lic = norm(c.get("license") or group.get("id"))
            if is_first_party(name, lic):
                continue
            crates[(name, ver)] = {
                "name": name,
                "version": ver,
                "license": lic,
                "repository": (c.get("repository") or "").rstrip("/"),
            }

    items = sorted(crates.values(), key=lambda x: (x["name"].lower(), x["version"]))

    by_lic = {}
    copyleft = []
    for it in items:
        by_lic[it["license"]] = by_lic.get(it["license"], 0) + 1
        if any(t in it["license"] for t in COPYLEFT) and " OR " not in it["license"]:
            copyleft.append(it)
    if copyleft:
        sys.exit("ABORT: copyleft-only component(s): "
                 + ", ".join(f"{c['name']} ({c['license']})" for c in copyleft))

    # ---- NOTICE (header + third-party list) --------------------------------
    n = [HEADER, ""]
    n.append("The zenoingress container images bundle third-party open-source Rust")
    n.append("components. All are under permissive licenses (no copyleft). The full,")
    n.append(f"verbatim license texts for the {len(items)} components listed below are")
    n.append("reproduced in the accompanying THIRD-PARTY-LICENSES.txt file.")
    n.append("")
    n.append("Generated from the Rust dependency tree with `cargo about` (see")
    n.append("tools/gen-third-party-notice.py). Regenerate on every release.")
    n.append("")
    n.append("Licenses in use:")
    for lic, cnt in sorted(by_lic.items(), key=lambda x: (-x[1], x[0])):
        n.append(f"  {cnt:3d} x  {lic}")
    n.append("")
    n.append("Components  (name  version  —  license  —  source):")
    n.append("")
    for it in items:
        repo = f"  —  {it['repository']}" if it["repository"] else ""
        n.append(f"  {it['name']} {it['version']}  —  {it['license']}{repo}")
    n.append("")
    open(f"{out_dir}/NOTICE", "w").write("\n".join(n))

    # ---- companion: full license texts -------------------------------------
    t = [
        "THIRD-PARTY-LICENSES for zenoingress",
        "=" * 78,
        "",
        "Verbatim license texts of the third-party open-source components bundled in",
        "the zenoingress container images, grouped by license text, with the crates",
        "each covers. Generated with `cargo about`; see tools/gen-third-party-notice.py.",
    ]
    groups = 0
    for group in data["licenses"]:
        users = [u for u in group.get("used_by", [])
                 if not is_first_party(u["crate"]["name"], u["crate"].get("license"))]
        text = (group.get("text") or "").strip()
        if not users or not text:
            continue
        groups += 1
        names = sorted({f"{u['crate']['name']} {u['crate']['version']}" for u in users})
        t += ["", "-" * 78, f"{group.get('name') or group.get('id')}  ({group.get('id')})",
              "", "Applies to:"]
        t += [f"  - {x}" for x in names]
        t += ["", text, ""]
    open(f"{out_dir}/THIRD-PARTY-LICENSES.txt", "w").write("\n".join(t) + "\n")

    print(f"components: {len(items)} | license-text groups: {groups}")
    print(f"wrote {out_dir}/NOTICE and {out_dir}/THIRD-PARTY-LICENSES.txt")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: gen-third-party-notice.py <third-party.json> <out_dir>")
    main(sys.argv[1], sys.argv[2])
