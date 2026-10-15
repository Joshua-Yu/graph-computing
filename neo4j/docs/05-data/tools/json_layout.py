"""Infer the field layout of JSON event messages, as rows for a contract's Schema sheet.

Usage: python json_layout.py events.jsonl [--schema registry.json] [--csv out.csv]

events.jsonl holds one sample event per line. The more events (inserts, updates,
deletes, persons, organisations), the better Required and the types will be.
If --schema is given (the topic's JSON Schema from the registry), it is the
authority for paths, types and required; samples only add examples and stats.
"""
import argparse, csv, json, re, sys
from collections import defaultdict

DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TS = re.compile(r"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$")
EPOCH_MS_KEYS = re.compile(r"(^|_)(ts|time|timestamp)(_ms)?$", re.I)


def physical(v, key):
    """(logical type, physical type) for one JSON value."""
    if v is None:
        return None, "JSON null"
    if isinstance(v, bool):
        return "boolean", "JSON boolean"
    if isinstance(v, int):
        if EPOCH_MS_KEYS.search(key) and v > 10**12:
            return "timestamp", "JSON number (epoch milliseconds)"
        return "integer", "JSON number"
    if isinstance(v, float):
        return "number", "JSON number"
    if isinstance(v, str):
        if DATE.match(v):
            return "date", "JSON string (YYYY-MM-DD)"
        if TS.match(v):
            return "timestamp", "JSON string (ISO 8601" + (", UTC)" if v.endswith("Z") else ")")
        return "string", "JSON string"
    if isinstance(v, list):
        return "array", "JSON array"
    return "object", "JSON object"


def walk(node, prefix, out):
    """Flatten to dotted paths; arrays become path[] and their items are walked."""
    if isinstance(node, dict):
        for k, v in node.items():
            path = f"{prefix}.{k}" if prefix else k
            out.append((path, k, v))
            if isinstance(v, (dict, list)):
                walk(v, path, out)
    elif isinstance(node, list):
        for item in node:
            out.append((f"{prefix}[]", prefix.rsplit(".", 1)[-1], item))
            if isinstance(item, (dict, list)):
                walk(item, f"{prefix}[]", out)


def array_stats(node, prefix, acc):
    """Per array path: item counts per instance, and child keys unique within every instance."""
    if isinstance(node, dict):
        for k, v in node.items():
            array_stats(v, f"{prefix}.{k}" if prefix else k, acc)
    elif isinstance(node, list):
        a = acc.setdefault(prefix, {"lengths": [], "keys": None, "pairs": None, "item_kind": set()})
        a["lengths"].append(len(node))
        dicts = [i for i in node if isinstance(i, dict)]
        a["item_kind"].update("object" if isinstance(i, dict) else "array" if isinstance(i, list)
                              else "scalar" for i in node)
        if dicts:
            def unique(cols):
                vals = [tuple(d.get(c) for c in cols) for d in dicts]
                return all(v is not None for t in vals for v in t) and len(set(vals)) == len(vals)
            fields = sorted({k for d in dicts for k, v in d.items() if not isinstance(v, (dict, list))})
            singles = {f for f in fields if unique([f])}
            pairs = {(x, y) for i, x in enumerate(fields) for y in fields[i + 1:] if unique([x, y])}
            a["keys"] = singles if a["keys"] is None else a["keys"] & singles
            a["pairs"] = pairs if a["pairs"] is None else a["pairs"] & pairs
        for item in node:
            array_stats(item, f"{prefix}[]", acc)


def describe_array(a):
    lens = a["lengths"]
    kind = "/".join(sorted(a["item_kind"])) or "unknown (always empty)"
    note = f"items {min(lens)}..{max(lens)}, empty in {sum(1 for l in lens if l == 0)}/{len(lens)}"
    if a["keys"]:
        note += "; item key candidates: " + ", ".join(sorted(a["keys"]))
    elif a["pairs"]:
        note += "; composite item key candidates: " + ", ".join("+".join(p) for p in sorted(a["pairs"]))
    elif "object" in a["item_kind"]:
        note += "; NO item key found: ask the source how items are identified"
    return kind, note


def profile(events):
    stats = defaultdict(lambda: {"seen": 0, "nonnull": 0, "types": set(), "phys": set(), "values": []})
    for ev in events:
        flat = []
        walk(ev, "", flat)
        present = set()
        for path, key, v in flat:
            if path in present and "[]" not in path:
                continue
            present.add(path)
            s = stats[path]
            s["seen"] += 1
            lt, pt = physical(v, key)
            if lt:
                s["nonnull"] += 1
                s["types"].add(lt)
                s["phys"].add(pt)
                if lt not in ("object", "array") and len(s["values"]) < 50:
                    s["values"].append(v)
    arrays = {}
    for ev in events:
        array_stats(ev, "", arrays)
    n = len(events)
    rows = []
    for path, s in stats.items():
        if s["types"] <= {"object", "array"} and s["types"]:
            leaf = False
        else:
            leaf = True
        if path.endswith("[]") and "scalar" not in arrays.get(path[:-2], {}).get("item_kind", ()):
            continue  # object items are described by their own fields
        parent = path.rsplit(".", 1)[0] if "." in path else None
        # Denominator: events (or array items) where the parent is a non-null object.
        denom = stats[parent]["nonnull"] if parent else n
        # Required: present and non-null whenever its parent object is present.
        required = "Y" if s["nonnull"] == denom and denom else "N"
        types = s["types"] or {"string"}
        # Mixed int/float -> number; anything else mixed -> flag it for review.
        if types == {"integer", "number"}:
            types = {"number"}
        logical = types.pop() if len(types) == 1 else "REVIEW: " + "/".join(sorted(s["types"]))
        distinct = sorted({str(v) for v in s["values"]})
        valid = ", ".join(distinct) if 1 < len(distinct) <= 6 and logical == "string" and all(len(d) <= 3 for d in distinct) else None
        rows.append({
            "Field": path,
            "Logical type": logical,
            "Physical type": "; ".join(sorted(s["phys"])) if s["phys"] else "JSON null (always null in samples)",
            "Required": required,
            "Unique": "N", "Primary key": "N",
            "Classification": "",  # never inferred: source owner and steward decide
            "Description": "",
            "Example": "",  # deliberately blank: examples in the repo must be invented
            "Valid values": valid or "",
            "Upstream column": "",
            "_leaf": leaf,
            "_fill": f"{s['nonnull']}/{denom}",
        })
        if path in arrays:
            kind, note = describe_array(arrays[path])
            rows[-1].update({"Logical type": "array", "Physical type": f"JSON array of {kind}",
                             "_leaf": True, "_array": note})
    return rows


def from_json_schema(schema, prefix="", required_here=True, out=None):
    """Flatten a JSON Schema (object/properties/items, nullable via type lists or anyOf)."""
    out = [] if out is None else out
    req = set(schema.get("required", []))
    for name, prop in schema.get("properties", {}).items():
        path = f"{prefix}.{name}" if prefix else name
        t = prop.get("type")
        if t is None and "anyOf" in prop:
            branches = [b for b in prop["anyOf"] if b.get("type") != "null"]
            prop = {**branches[0], **{k: v for k, v in prop.items() if k != "anyOf"}} if branches else prop
            t = prop.get("type")
        types = t if isinstance(t, list) else [t]
        nullable = "null" in types
        base = next((x for x in types if x != "null"), "string")
        fmt = prop.get("format")
        logical = {"date": "date", "date-time": "timestamp"}.get(fmt, {"integer": "integer", "number": "number",
                   "boolean": "boolean", "object": "object", "array": "array"}.get(base, "string"))
        out.append({
            "Field": path, "Logical type": logical,
            "Physical type": f"JSON {base}" + (f" ({fmt})" if fmt else ""),
            "Required": "Y" if name in req and not nullable else "N",
            "Unique": "N", "Primary key": "N", "Classification": "",
            "Description": prop.get("description", ""), "Example": "",
            "Valid values": ", ".join(map(str, prop["enum"])) if "enum" in prop else "",
            "Upstream column": "", "_leaf": base != "object", "_fill": "schema",
        })
        if base == "object":
            from_json_schema(prop, path, out=out)
        elif base == "array" and isinstance(prop.get("items"), dict):
            from_json_schema(prop["items"], path + "[]", out=out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("events")
    ap.add_argument("--schema")
    ap.add_argument("--csv")
    ap.add_argument("--containers", action="store_true", help="also list object/array paths")
    a = ap.parse_args()

    with open(a.events) as f:
        events = [json.loads(l) for l in f if l.strip()]
    sampled = {r["Field"]: r for r in profile(events)}

    if a.schema:
        with open(a.schema) as f:
            rows = from_json_schema(json.load(f))
        declared = {r["Field"] for r in rows}
        for r in rows:  # fill gaps the schema leaves (e.g. no format on a date string)
            s = sampled.get(r["Field"])
            if s:
                r["_fill"], r["_array"] = s["_fill"], s.get("_array", "")
                if r["Logical type"] == "string" and s["Logical type"] in ("date", "timestamp"):
                    r["Logical type"], r["Physical type"] = s["Logical type"], s["Physical type"]
                if not r["Valid values"]:
                    r["Valid values"] = s["Valid values"]
        for p in sorted(sampled.keys() - declared):  # drift: in data, not in the registered schema
            print(f"WARNING: {p} appears in samples but not in the registry schema", file=sys.stderr)
    else:
        rows = list(sampled.values())

    rows = [r for r in rows if r["_leaf"] or a.containers]
    rows.sort(key=lambda r: r["Field"])
    cols = ["Field", "Logical type", "Physical type", "Required", "Unique", "Primary key", "Classification",
            "Description", "Example", "Valid values", "Upstream column", "_fill", "_array"]
    out = open(a.csv, "w", newline="") if a.csv else sys.stdout
    w = csv.DictWriter(out, fieldnames=cols, extrasaction="ignore")
    w.writeheader()
    w.writerows(rows)


if __name__ == "__main__":
    main()
