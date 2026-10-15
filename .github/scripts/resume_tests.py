#!/usr/bin/env python3
"""Résumé Markdown d'un rapport `flutter test --file-reporter json:…` (pour $GITHUB_STEP_SUMMARY).

Usage : resume_tests.py rapport.json "Titre"
Tableau par fichier : réussis, échoués, ignorés, durée ; puis la liste des tests en échec.
"""
import json
import os
import sys
from collections import OrderedDict


def main(chemin: str, titre: str) -> int:
    suites, tests, fichiers = {}, {}, OrderedDict()
    debut, fin = None, 0
    if not os.path.exists(chemin):
        print(f"## {titre}\n\nRapport absent ({chemin}) : les tests n'ont pas pu démarrer.")
        return 0
    with open(chemin, encoding="utf-8") as f:
        for ligne in f:
            ligne = ligne.strip()
            if not ligne.startswith("{"):
                continue
            e = json.loads(ligne)
            t = e.get("type")
            if t == "suite":
                s = e["suite"]
                suites[s["id"]] = os.path.relpath(s.get("path") or "?", os.getcwd())
            elif t == "testStart":
                tt = e["test"]
                if tt.get("url") is None and tt["name"].startswith("loading "):
                    continue
                tests[tt["id"]] = {"nom": tt["name"], "suite": tt["suiteID"], "debut": e["time"]}
            elif t == "testDone" and e["testID"] in tests:
                d = tests[e["testID"]]
                if e.get("hidden"):
                    del tests[e["testID"]]
                    continue
                d["resultat"] = "ignoré" if e.get("skipped") else e["result"]
                d["duree"] = e["time"] - d["debut"]
            elif t == "done":
                fin = e["time"]
    for d in tests.values():
        nom = suites.get(d["suite"], "?")
        r = fichiers.setdefault(nom, {"ok": 0, "ko": 0, "ign": 0, "ms": 0, "echecs": []})
        res = d.get("resultat", "error")
        r["ms"] += d.get("duree", 0)
        if res == "ignoré":
            r["ign"] += 1
        elif res == "success":
            r["ok"] += 1
        else:
            r["ko"] += 1
            r["echecs"].append(d["nom"])
    ok = sum(r["ok"] for r in fichiers.values())
    ko = sum(r["ko"] for r in fichiers.values())
    ign = sum(r["ign"] for r in fichiers.values())
    etat = "✅" if ko == 0 else "❌"
    print(f"## {etat} {titre}\n")
    print(f"**{ok} réussis**, **{ko} en échec**, {ign} ignorés — {len(fichiers)} fichiers, {fin / 1000:.0f} s.\n")
    print("| Fichier | Réussis | Échecs | Ignorés | Durée |")
    print("|---|---:|---:|---:|---:|")
    for nom, r in fichiers.items():
        print(f"| `{nom}` | {r['ok']} | {r['ko']} | {r['ign']} | {r['ms'] / 1000:.1f} s |")
    echecs = [(n, t) for n, r in fichiers.items() for t in r["echecs"]]
    if echecs:
        print("\n### Tests en échec\n")
        for n, t in echecs:
            print(f"- `{n}` : {t}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "Tests"))
