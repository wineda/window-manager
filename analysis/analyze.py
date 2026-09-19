#!/usr/bin/env python3
"""操作ログ(docs/logging.md)から、第7章の λ・W・d・r・p・k を計算する。

使い方:
    python analyze.py <CSV ファイルまたはフォルダ>...  [--min-life 秒] [--cluster px]

標準ライブラリだけで動く。CSV は UTF-8(BOM付き)、列は docs/logging.md 第4章。
"""
import argparse
import csv
import glob
import os
import statistics
import sys
from collections import defaultdict

MS_PER_HOUR = 3_600_000.0


# ----------------------------------------------------------------------
# 読み込み
# ----------------------------------------------------------------------
def load_rows(paths):
    """指定されたファイル・フォルダの CSV を読み、(session, seq) 順の行の一覧を返す。"""
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += sorted(glob.glob(os.path.join(p, "*.csv")))
        else:
            files.append(p)
    rows = []
    for f in files:
        with open(f, encoding="utf-8-sig", newline="") as fh:
            for r in csv.DictReader(fh):
                if not r.get("event"):
                    continue
                r["tick"] = int(r["tick"])
                r["seq"] = int(r["seq"])
                r["_wid"] = int(r["wid"]) if r.get("wid") else None
                r["_detail"] = parse_detail(r.get("detail", ""))
                rows.append(r)
    rows.sort(key=lambda r: (r["session"], r["seq"]))
    return rows


def parse_detail(s):
    out = {}
    for part in s.split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k] = v
    return out


def rect(r):
    try:
        return (int(r["x"]), int(r["y"]), int(r["w"]), int(r["h"]))
    except (KeyError, ValueError):
        return None


def overlaps(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


# ----------------------------------------------------------------------
# 区間の演算(tick のミリ秒)
# ----------------------------------------------------------------------
def merge(intervals):
    out = []
    for s, e in sorted(intervals):
        if out and s <= out[-1][1]:
            out[-1][1] = max(out[-1][1], e)
        else:
            out.append([s, e])
    return [(s, e) for s, e in out]


def subtract(span, holes):
    """span から holes(結合済み)を除いた区間の一覧。"""
    s, e = span
    out = []
    for hs, he in holes:
        if he <= s or hs >= e:
            continue
        if hs > s:
            out.append((s, hs))
        s = max(s, he)
    if s < e:
        out.append((s, e))
    return out


def total(intervals):
    return sum(e - s for s, e in intervals)


# ----------------------------------------------------------------------
# セッションごとの解析
# ----------------------------------------------------------------------
class Window:
    def __init__(self, wid, proc):
        self.wid = wid
        self.proc = proc
        self.first = None          # 初めて見た tick
        self.created = None        # create の tick(起動前からある窓は None)
        self.destroyed = None
        self.points = []           # (tick, status, cause)  status: aligned / misaligned / hidden
        self.rects = []            # (state, rect) 状態が normal のときの矩形
        self.created_misaligned = False


def status_of(row, cloaked):
    if cloaked or row["state"] == "min":
        return "hidden"
    return "aligned" if row["zone"] else "misaligned"


def analyze_session(rows, min_life_ms):
    """1セッション分の行から統計を集める。戻り値は dict。"""
    start = rows[0]["tick"]
    end = rows[-1]["tick"]
    windows = {}
    idle, lock = [], []
    idle_open = lock_open = None
    snapshots = []                 # 各スナップショットの行の一覧
    monitors = {}                  # mon → 作業領域 (l, t, w, h)
    tool = defaultdict(int)
    fg = defaultdict(int)          # wid → 前面だった ms
    fg_wid, fg_since = None, None
    cloaked = set()
    cur_snap = None

    for r in rows:
        ev, t, wid = r["event"], r["tick"], r["_wid"]
        if ev == "snapshot":
            # 1回のスナップショットは数十 ms で書き終わる。間が空くか、同じ窓が再び出たら次の回
            if (cur_snap is None or t - cur_snap[0]["tick"] > 5000
                    or any(x["_wid"] == wid for x in cur_snap)):
                cur_snap = []
                snapshots.append(cur_snap)
            cur_snap.append(r)
        else:
            cur_snap = None

        if ev == "monitor":
            d = r["_detail"]
            try:
                l, tt, w, h = (int(v) for v in d["work"].split("/"))
                monitors[d["mon"]] = (l, tt, w, h)
            except (KeyError, ValueError):
                pass
        elif ev == "idle":
            idle_open = int(r["_detail"].get("since", t))
        elif ev == "resume":
            if idle_open is not None:
                idle.append((idle_open, int(r["_detail"].get("at", t))))
                idle_open = None
        elif ev == "lock":
            lock_open = t
        elif ev == "unlock":
            if lock_open is not None:
                lock.append((lock_open, t))
                lock_open = None
        elif ev == "tool":
            tool[(r["action"], r["result"])] += 1

        if wid is None:
            continue
        w = windows.get(wid)
        if w is None:
            w = windows[wid] = Window(wid, r["proc"])
            w.first = t
        if ev == "create":
            w.created = t
            w.created_misaligned = (r["state"] != "min" and not r["zone"])
        elif ev == "destroy":
            w.destroyed = t
        elif ev == "cloak":
            cloaked.add(wid)
        elif ev == "uncloak":
            cloaked.discard(wid)
        elif ev == "activate":
            if fg_wid is not None:
                fg[fg_wid] += t - fg_since
            fg_wid, fg_since = wid, t

        if ev in ("snapshot", "create", "move", "minimize", "restore", "maximize",
                  "unmaximize", "activate", "tool", "cloak", "uncloak"):
            st = status_of(r, wid in cloaked)
            if not w.points or w.points[-1][1] != st:
                w.points.append((t, st, r["cause"]))
            if r["state"] == "normal" and rect(r):
                if not w.rects or w.rects[-1] != rect(r):
                    w.rects.append(rect(r))

    if idle_open is not None:
        idle.append((idle_open, end))
    if lock_open is not None:
        lock.append((lock_open, end))
    if fg_wid is not None:
        fg[fg_wid] += end - fg_since

    holes = merge(idle + lock)
    active = subtract((start, end), holes)
    active_ms = total(active)

    # ---- 窓ごとの整列・非整列の延べ時間と遷移 ----
    aligned_ms = misaligned_ms = 0.0
    a2m, m2a = defaultdict(int), defaultdict(int)
    lifetimes, censored = [], 0
    open_time = 0.0                 # N の計算用(窓が開いていた延べ ms)
    for w in windows.values():
        last = w.destroyed if w.destroyed is not None else end
        life_from = w.created if w.created is not None else start
        open_time += last - life_from
        if w.created is not None:
            if w.destroyed is not None:
                lifetimes.append(w.destroyed - w.created)
            else:
                censored += 1
        prev = None
        for i, (t, st, cause) in enumerate(w.points):
            nxt = w.points[i + 1][0] if i + 1 < len(w.points) else last
            dur = max(0, nxt - t)
            if st == "aligned":
                aligned_ms += dur
            elif st == "misaligned":
                misaligned_ms += dur
            if prev == "aligned" and st == "misaligned":
                a2m[cause or "?"] += 1
            elif prev == "misaligned" and st == "aligned":
                m2a[cause or "?"] += 1
            if st != "hidden":
                prev = st

    # ---- p:スナップショットごとの重なり ----
    pairs = overlap_pairs = 0
    big = normal = 0
    for snap in snapshots:
        by_mon = defaultdict(list)
        for r in snap:
            if r["state"] != "normal" or not rect(r):
                continue
            by_mon[r["mon"]].append(rect(r))
            normal += 1
            work = monitors.get(r["mon"])
            if work and rect(r)[2] > work[2] / 2 and rect(r)[3] > work[3] / 2:
                big += 1
        for rs in by_mon.values():
            for i in range(len(rs)):
                for j in range(i + 1, len(rs)):
                    pairs += 1
                    if overlaps(rs[i], rs[j]):
                        overlap_pairs += 1

    creates = [w for w in windows.values() if w.created is not None]
    popups = [w for w in creates if w.destroyed is not None and w.destroyed - w.created < min_life_ms]
    return {
        "start": start, "end": end, "span_ms": end - start, "active_ms": active_ms,
        "windows": windows, "creates": len(creates), "popups": len(popups),
        "created_misaligned": sum(1 for w in creates if w.created_misaligned),
        "lifetimes": lifetimes, "censored": censored,
        "long_lifetimes": [l for l in lifetimes if l >= min_life_ms],
        "open_time": open_time,
        "aligned_ms": aligned_ms, "misaligned_ms": misaligned_ms, "a2m": a2m, "m2a": m2a,
        "pairs": pairs, "overlap_pairs": overlap_pairs, "normal": normal, "big": big,
        "tool": tool, "fg": fg, "snapshots": len(snapshots),
    }


# ----------------------------------------------------------------------
# 複数セッションの合算
# ----------------------------------------------------------------------
def combine(results):
    c = {
        "sessions": len(results),
        "span_ms": 0, "active_ms": 0, "creates": 0, "popups": 0, "created_misaligned": 0,
        "lifetimes": [], "long_lifetimes": [], "censored": 0, "open_time": 0.0,
        "aligned_ms": 0.0, "misaligned_ms": 0.0, "a2m": defaultdict(int), "m2a": defaultdict(int),
        "pairs": 0, "overlap_pairs": 0, "normal": 0, "big": 0, "tool": defaultdict(int),
        "rects_by_proc": defaultdict(list), "fg_by_proc": defaultdict(int), "snapshots": 0,
    }
    for r in results:
        for k in ("span_ms", "active_ms", "creates", "popups", "created_misaligned", "censored",
                  "open_time", "aligned_ms", "misaligned_ms", "pairs", "overlap_pairs",
                  "normal", "big", "snapshots"):
            c[k] += r[k]
        c["lifetimes"] += r["lifetimes"]
        c["long_lifetimes"] += r["long_lifetimes"]
        for d in ("a2m", "m2a", "tool"):
            for k, v in r[d].items():
                c[d][k] += v
        for w in r["windows"].values():
            c["rects_by_proc"][w.proc] += w.rects
            c["fg_by_proc"][w.proc] += r["fg"].get(w.wid, 0)
    return c


def cluster_count(rects, tol):
    """矩形を、4辺とも tol 以内なら同じ位置とみなしてまとめた数。"""
    centers = []
    for r in rects:
        for c in centers:
            if all(abs(r[i] - c[i]) <= tol for i in range(4)):
                break
        else:
            centers.append(r)
    return len(centers)


# ----------------------------------------------------------------------
# 表示
# ----------------------------------------------------------------------
def fmt_min(ms):
    return f"{ms / 60000:.1f} 分"


def report(c, cluster_px, out=sys.stdout):
    p = lambda *a: print(*a, file=out)
    hours = c["active_ms"] / MS_PER_HOUR
    wall_h = c["span_ms"] / MS_PER_HOUR
    p(f"セッション数: {c['sessions']}  記録時間: {wall_h:.2f} 時間  活動時間 T: {hours:.2f} 時間"
      f"  スナップショット: {c['snapshots']} 回")
    p()
    p("■ N・λ・W(リトルの法則 N = λ × W)")
    n_bar = c["open_time"] / c["span_ms"] if c["span_ms"] else 0.0
    p(f"  N(開いている窓の数の平均)      : {n_bar:.2f}")
    lam = c["creates"] / hours if hours else 0.0
    lam_long = (c["creates"] - c["popups"]) / hours if hours else 0.0
    p(f"  λ(1時間に開く数)              : {lam:.2f} /時間  "
      f"(すぐ閉じた一時的な窓 {c['popups']} 件を除くと {lam_long:.2f} /時間)")
    if c["long_lifetimes"]:
        mean = statistics.mean(c["long_lifetimes"])
        med = statistics.median(c["long_lifetimes"])
        p(f"  W(1つを開いておく時間)        : 平均 {fmt_min(mean)} / 中央値 {fmt_min(med)}"
          f"  (閉じた窓 {len(c['long_lifetimes'])} 件、まだ開いている窓 {c['censored']} 件は除外)")
        p(f"  検算 λ × W                       : {lam_long * mean / MS_PER_HOUR:.2f}"
          f"  (N={n_bar:.2f}。起動前からある窓と閉じていない窓の分だけずれる)")
    else:
        p("  W: 閉じた窓がまだありません")
    p(f"  作られた時点でずれていた窓      : {c['created_misaligned']} / {c['creates']} 件")
    p()
    p("■ d・r(ずれている割合 = d / (d + r))")
    a_h, m_h = c["aligned_ms"] / MS_PER_HOUR, c["misaligned_ms"] / MS_PER_HOUR
    d = sum(c["a2m"].values()) / a_h if a_h else 0.0
    r = sum(c["m2a"].values()) / m_h if m_h else 0.0
    p(f"  整列していた延べ時間             : {a_h:.2f} 窓・時間")
    p(f"  ずれていた延べ時間               : {m_h:.2f} 窓・時間")
    p(f"  d(ずれる頻度)                  : {d:.2f} /窓・時間  内訳 {dict(c['a2m'])}")
    p(f"  r(片付く頻度)                  : {r:.2f} /窓・時間  内訳 {dict(c['m2a'])}")
    obs = m_h / (a_h + m_h) if (a_h + m_h) else 0.0
    pred = d / (d + r) if (d + r) else 0.0
    p(f"  ずれている割合  実測 {obs:.3f}  /  予測 d/(d+r) {pred:.3f}")
    p()
    p("■ p(重なり)")
    pr = c["overlap_pairs"] / c["pairs"] if c["pairs"] else 0.0
    p(f"  重なっているペアの割合 p         : {pr:.3f}  ({c['overlap_pairs']} / {c['pairs']} ペア)")
    bigr = c["big"] / c["normal"] if c["normal"] else 0.0
    p(f"  画面の半分より大きい窓の割合     : {bigr:.3f}  ({c['big']} / {c['normal']} 窓)")
    p()
    p(f"■ k(アプリごとの置き場所の数、許容 {cluster_px}px)")
    for proc, rects in sorted(c["rects_by_proc"].items(), key=lambda kv: -len(kv[1]))[:15]:
        fgm = c["fg_by_proc"].get(proc, 0)
        p(f"  {proc:<24} k={cluster_count(rects, cluster_px):<3} 前面 {fmt_min(fgm)}")
    p()
    p("■ ツールの操作")
    for (action, result), n in sorted(c["tool"].items()):
        p(f"  {action:<10} {result:<10} {n} 回")


def main(argv=None):
    ap = argparse.ArgumentParser(description="操作ログの解析")
    ap.add_argument("paths", nargs="+", help="CSV ファイルまたはフォルダ")
    ap.add_argument("--min-life", type=float, default=3.0, help="この秒数未満で閉じた窓は一時的な窓とみなす(既定 3)")
    ap.add_argument("--cluster", type=int, default=16, help="k の計算で同じ位置とみなす許容 px(既定 16)")
    args = ap.parse_args(argv)
    rows = load_rows(args.paths)
    if not rows:
        print("行がありません", file=sys.stderr)
        return 1
    by_session = defaultdict(list)
    for r in rows:
        by_session[r["session"]].append(r)
    results = [analyze_session(rs, args.min_life * 1000) for rs in by_session.values()]
    report(combine(results), args.cluster)
    return 0


if __name__ == "__main__":
    sys.exit(main())
