#!/usr/bin/env python3
"""analyze.py のテスト。docs/logging.md 第11章の形式で 1 時間分の合成ログを作り、
手計算した値と一致することを確かめる。

    python test_analyze.py            … テストを実行
    python test_analyze.py --write D  … 合成ログを D/2026-09-19.csv に書く(サンプル用)
"""
import csv
import io
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze  # noqa: E402

HEADER = ("ts,tick,session,seq,event,wid,hwnd,proc,cls,mon,state,x,y,w,h,zone,"
          "cause,action,target,result,detail,title").split(",")
T0 = 1_000_000
SESSION = "20260919090000-3f2a"
BASE = datetime(2026, 9, 19, 9, 0, 0, tzinfo=timezone(timedelta(hours=9)))

W1 = dict(wid=1, hwnd="0x1A0F32", proc="msedge.exe", cls="Chrome_WidgetWin_1")
W2 = dict(wid=2, hwnd="0x2B0044", proc="EXCEL.EXE", cls="XLMAIN")
W3 = dict(wid=3, hwnd="0x3C0102", proc="notepad.exe", cls="Notepad")
EDGE_HOME = dict(x=0, y=0, w=1707, h=1400, zone="左2/3")
EDGE_DRAG = dict(x=500, y=100, w=1500, h=1000, zone="")
XL_BORN = dict(x=312, y=180, w=1400, h=900, zone="")
XL_HOME = dict(x=1707, y=0, w=853, h=1400, zone="右1/3")
NP = dict(x=500, y=300, w=800, h=600, zone="")


def make_rows():
    rows = []

    def row(off, event, win=None, rect=None, state="normal", cause="", action="", target="",
            result="", detail=""):
        ts = BASE + timedelta(milliseconds=off)
        r = {k: "" for k in HEADER}
        r.update(ts=ts.strftime("%Y-%m-%dT%H:%M:%S.") + f"{ts.microsecond // 1000:03d}+09:00",
                 tick=T0 + off, session=SESSION, event=event, cause=cause,
                 action=action, target=target, result=result, detail=detail)
        if win:
            r.update(win)
            r.update(mon=1, state=state)
            if rect:
                r.update(rect)
        rows.append(r)

    def snapshot(off, *wins):
        for win, rect in wins:
            row(off, "snapshot", win, rect)

    row(0, "start", detail="schema=1;ver=1.0;ahk=2.0.28;script=claude_hotkey.ahk")
    row(8, "monitor", detail="mon=1;x=0;y=0;w=2560;h=1440;work=0/0/2560/1400;dpi=96;primary=1")
    snapshot(31, (W1, EDGE_HOME))                              # 起動前からある窓
    row(100, "activate", W1, EDGE_HOME, cause="user")
    row(180_000, "create", W2, XL_BORN, detail="via=create")   # Excel を開く(ずれた位置)
    row(180_200, "tool", W2, XL_BORN, action="autoplace", target="作業", result="moved")
    row(180_300, "move", W2, XL_HOME, cause="tool", action="autoplace", target="作業")
    row(180_400, "activate", W2, XL_HOME, cause="user")
    snapshot(300_031, (W1, EDGE_HOME), (W2, XL_HOME))
    row(600_000, "move", W1, EDGE_DRAG, cause="user")          # Edge を手でずらす
    snapshot(600_031, (W1, EDGE_DRAG), (W2, XL_HOME))
    snapshot(900_031, (W1, EDGE_DRAG), (W2, XL_HOME))
    row(905_000, "tool", action="layout", target="作業", result="moved", detail="count=1")
    row(905_050, "move", W1, EDGE_HOME, cause="tool", action="layout", target="作業")
    row(1_200_000, "create", W3, NP, detail="via=create")      # 1秒で閉じるメモ帳
    snapshot(1_200_031, (W1, EDGE_HOME), (W2, XL_HOME), (W3, NP))
    row(1_201_000, "destroy", W3, NP)
    snapshot(1_500_031, (W1, EDGE_HOME), (W2, XL_HOME))
    row(1_800_000, "destroy", W2, XL_HOME)
    snapshot(1_800_031, (W1, EDGE_HOME))
    row(1_800_100, "activate", W1, EDGE_HOME, cause="app")
    row(2_000_000, "minimize", W1, EDGE_HOME, state="min", cause="user")
    row(2_100_000, "restore", W1, EDGE_HOME, cause="user")
    for off in (2_100_031, 2_400_031, 2_700_031, 3_000_031, 3_300_031):
        snapshot(off, (W1, EDGE_HOME))
    row(2_700_010, "idle", detail="since=2400000")             # 40分〜50分は離席
    row(3_000_010, "resume", detail="at=3000000")
    row(3_600_000, "stop")
    rows.sort(key=lambda r: r["tick"])              # 生成順ではなく時刻順に連番を振る
    for i, r in enumerate(rows, 1):
        r["seq"] = i
    return rows


def write_sample(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8-sig", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=HEADER, lineterminator="\r\n")
        w.writeheader()
        w.writerows(make_rows())


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--write":
        write_sample(os.path.join(sys.argv[2], "2026-09-19.csv"))
        print("wrote", os.path.join(sys.argv[2], "2026-09-19.csv"))
        return 0
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "2026-09-19.csv")
        write_sample(path)
        rows = analyze.load_rows([d])
        res = analyze.analyze_session(rows, 3000)
        c = analyze.combine([res])

    # ---- 手計算した期待値(docs/logging.md 第8章の定義)----
    assert res["span_ms"] == 3_600_000
    assert res["active_ms"] == 3_000_000, res["active_ms"]            # 60分 − 離席10分
    assert res["creates"] == 2 and res["popups"] == 1
    assert res["created_misaligned"] == 2
    assert res["long_lifetimes"] == [1_620_000] and res["censored"] == 0
    assert res["open_time"] == 3_600_000 + 1_620_000 + 1_000       # N = 1.45
    # 整列: w1 31→600000, 905050→2000000, 2100000→3600000 / w2 180300→1800000
    assert res["aligned_ms"] == (600_000 - 31) + (2_000_000 - 905_050) + 1_500_000 + 1_619_700, res["aligned_ms"]
    # 非整列: w1 600000→905050 / w2 300ms / w3 1000ms
    assert res["misaligned_ms"] == 305_050 + 300 + 1_000, res["misaligned_ms"]
    assert dict(res["a2m"]) == {"user": 1} and dict(res["m2a"]) == {"tool": 2}, (res["a2m"], res["m2a"])
    assert res["snapshots"] == 12
    assert (res["pairs"], res["overlap_pairs"]) == (7, 3), (res["pairs"], res["overlap_pairs"])
    assert (res["normal"], res["big"]) == (18, 12), (res["normal"], res["big"])
    assert dict(res["tool"]) == {("autoplace", "moved"): 1, ("layout", "moved"): 1}
    assert res["fg"] == {1: 180_300 + 1_799_900, 2: 1_619_700}, res["fg"]
    ks = {p: analyze.cluster_count(r, 16) for p, r in c["rects_by_proc"].items()}
    assert ks == {"msedge.exe": 2, "EXCEL.EXE": 2, "notepad.exe": 1}, ks

    out = io.StringIO()
    analyze.report(c, 16, out=out)
    text = out.getvalue()
    assert "λ(1時間に開く数)              : 2.40 /時間" in text, text
    assert "p         : 0.429" in text, text
    print("OK: すべての検証を通過")
    print("---- レポート ----")
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
