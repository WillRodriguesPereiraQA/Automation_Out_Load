#!/usr/bin/env python3
"""Quality gate do JTL: taxa de erro e p95 do fluxo de negocio.

Percentil nearest-rank: ordena o elapsed e toma a posicao ceil(percentil/100 * n),
em base 1. O p99 do fluxo e impresso no log; a decisao de latencia usa o p95.
A mesma regra esta em scripts/quality-gate.ps1.
"""
import csv
import math
import sys

FLOW_LABEL = "TX - Fluxo completo reserva"
ERROR_EPSILON = 0.00001


def nearest_rank(values, percentile):
    ordered = sorted(values)
    count = len(ordered)
    if count == 0:
        raise ValueError("percentil sem amostras")
    rank = math.ceil((percentile / 100.0) * count)
    rank = min(max(rank, 1), count)
    return ordered[rank - 1]


def evaluate_jtl(path, max_error_rate, max_p95_ms, flow_label=FLOW_LABEL):
    total = 0
    failures = 0
    flow = []
    with open(path, newline="", encoding="utf-8", errors="replace") as handle:
        reader = csv.DictReader(handle)
        fieldnames = set(reader.fieldnames or [])
        missing = {"elapsed", "label", "success"} - fieldnames
        if missing:
            return {
                "passed": False,
                "reasons": [
                    "JTL sem colunas obrigatorias: " + ", ".join(sorted(missing))
                ],
            }
        for row in reader:
            total += 1
            if (row.get("success") or "").strip().lower() == "false":
                failures += 1
            if row.get("label") == flow_label:
                flow.append(float(row["elapsed"]))

    if total == 0:
        return {"passed": False, "reasons": ["Nenhuma amostra no JTL."]}

    rate = (failures / total) * 100.0
    result = {
        "total": total,
        "failures": failures,
        "error_rate": rate,
        "max_error_rate": max_error_rate,
        "flow_label": flow_label,
        "flow_samples": len(flow),
        "max_p95_ms": max_p95_ms,
        "reasons": [],
    }
    if rate > max_error_rate + ERROR_EPSILON:
        result["reasons"].append(
            f"taxa de erro {rate:.4f}% excede o maximo {max_error_rate:.4f}%."
        )
    if not flow:
        result["reasons"].append(f"nenhuma amostra do fluxo '{flow_label}'.")
        result["passed"] = False
        return result

    p95 = nearest_rank(flow, 95)
    p99 = nearest_rank(flow, 99)
    result["p95"] = p95
    result["p99"] = p99
    if p95 > max_p95_ms + ERROR_EPSILON:
        result["reasons"].append(
            f"p95 do fluxo {p95:.0f} ms excede o maximo {max_p95_ms:.0f} ms."
        )
    result["passed"] = not result["reasons"]
    return result


def _print_result(result):
    if "total" not in result:
        for reason in result["reasons"]:
            print(f"REPROVADO: {reason}")
        return
    print(
        "Samples: {total}  Failures: {failures}  Error rate: {error_rate:.4f}%  (max {max_error_rate:.4f}%)".format(
            **result
        )
    )
    if "p95" in result:
        print(
            "Flow '{flow_label}': samples={flow_samples}  p95={p95:.0f} ms  p99={p99:.0f} ms  (max p95 {max_p95_ms:.0f} ms)".format(
                **result
            )
        )
    for reason in result["reasons"]:
        print(f"REPROVADO: {reason}")
    if result["passed"]:
        print("APROVADO: taxa de erro e p95 do fluxo dentro dos limites.")


def main(argv):
    if len(argv) not in (4, 5):
        print(
            "Uso: evaluate-quality-gate.py <jtl> <max_error_rate_percent> <max_flow_p95_ms> [flow_label]",
            file=sys.stderr,
        )
        return 2
    path = argv[1]
    try:
        max_error = float(argv[2])
        max_p95 = float(argv[3])
    except ValueError:
        print("REPROVADO: limiares do quality gate devem ser numericos.", file=sys.stderr)
        return 2
    flow_label = argv[4] if len(argv) == 5 else FLOW_LABEL
    try:
        result = evaluate_jtl(path, max_error, max_p95, flow_label)
    except FileNotFoundError:
        print(f"REPROVADO: JTL nao encontrado: {path}")
        return 1
    except ValueError as exc:
        print(f"REPROVADO: elapsed invalido no JTL ({exc}).")
        return 1
    _print_result(result)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
