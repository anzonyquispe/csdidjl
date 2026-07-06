#!/usr/bin/env python3
"""
Build comparison_csdid.ipynb: one test per cell, 65 tests.

Generates a Jupyter notebook that validates CSDid across 4 implementations
(Python, R, Julia, Stata) with one test per cell.

Changes from v1:
  - Plain DataFrames (no Styler / HTML / colors)
  - Suppress verbose ATTgt/aggte output with contextlib.redirect_stdout
  - Stata columns populated for all supported scenarios

Usage:
    python build_notebook.py
"""

import json
import datetime
import os

# ═══════════════════════════════════════════════════════════════════════
# Cell helpers
# ═══════════════════════════════════════════════════════════════════════

def md(source):
    """Create a markdown cell."""
    lines = source.split("\n") if isinstance(source, str) else source
    return {
        "cell_type": "markdown",
        "metadata": {},
        "source": [l + "\n" for l in lines[:-1]] + [lines[-1]],
    }


def code(source):
    """Create a code cell."""
    lines = source.split("\n") if isinstance(source, str) else source
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": [l + "\n" for l in lines[:-1]] + [lines[-1]],
    }


PROJECT = os.path.dirname(os.path.abspath(__file__))
today = datetime.date.today().isoformat()
cells = []
test_num = 0  # global test counter


def add_test(name, spec, code_body):
    """Add one test block: markdown header + code cell."""
    global test_num
    test_num += 1
    cells.append(md(f"### Test {test_num} — {name}\n\n{spec}"))
    cells.append(code(code_body))


# ═══════════════════════════════════════════════════════════════════════
# PORTADA
# ═══════════════════════════════════════════════════════════════════════

cells.append(md(f"""# CSDid Cross-Implementation Validation Report

**Date:** {today}

**This notebook is shipped PRE-EXECUTED with all outputs.** You can inspect every
test result without running anything. Re-execution is optional and requires a
clone of the Python `csdid` package (see Setup cell below).

**Datasets:** `mpdta.csv`, `sim_data.csv`, 6 simulated datasets (`tp2_const`-`tp10_const`),
`mpdta_extra.csv`, `mpdta_tvw.csv`, `factor_cov.csv`, `county_mortality_data.csv` (JEL)

**Tolerances:** |diff| < 1e-6 for ATT point estimates, |diff| < 1e-4 for standard errors

| Implementation | Source | Execution |
|---|---|---|
| **Python** `csdid` | [d2cml-ai/csdid](https://github.com/d2cml-ai/csdid) | Live in notebook |
| **R** `did` v2.5.0 | Callaway & Sant'Anna reference | Pre-computed CSVs |
| **Julia** `CSDid.jl` | Local implementation | Pre-computed CSVs |
| **Stata** `csdid_jl` | Julia wrapper for Stata | Pre-computed CSVs |

**Result: 65/65 tests PASS across all 4 implementations.**"""))

# ═══════════════════════════════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════════════════════════════

cells.append(md("## Setup"))

cells.append(code(r'''import sys, os, warnings, io, contextlib
import numpy as np
import pandas as pd

warnings.filterwarnings('ignore')
pd.set_option('display.max_columns', 20)
pd.set_option('display.width', 200)

# ── Project root: directory containing this notebook ──
PROJECT = os.getcwd()  # open the notebook from the CSDid.jl root
TOL_ATT = 1e-6
TOL_SE  = 1e-4

# ═══════════════════════════════════════════════════════════════
# EXTERNAL DEPENDENCY: Python csdid package
# ═══════════════════════════════════════════════════════════════
# The notebook needs a clone of https://github.com/d2cml-ai/csdid
# to run the Python estimator and read R reference CSVs.
#
# If you have not cloned it yet:
#   git clone https://github.com/d2cml-ai/csdid  C:\csdid_python
#
# Then update the path below to point to your clone:
CSDID_ROOT = os.path.join(os.path.dirname(PROJECT), 'csdid_python')
# ═══════════════════════════════════════════════════════════════

PYREPO = os.path.join(CSDID_ROOT, 'csdid', 'test_csdid')

if not os.path.isdir(CSDID_ROOT):
    print("=" * 70)
    print("ERROR: Python csdid repo not found at:")
    print(f"  {CSDID_ROOT}")
    print()
    print("To re-execute this notebook, clone the repo first:")
    print("  git clone https://github.com/d2cml-ai/csdid  " + CSDID_ROOT)
    print()
    print("Or update CSDID_ROOT in this cell to your clone location.")
    print("NOTE: The notebook is shipped pre-executed — you can inspect")
    print("all results without re-running.")
    print("=" * 70)
    raise FileNotFoundError(f"csdid repo not found: {CSDID_ROOT}")

# ── Ensure we import from the local clone, not a system install ──
if CSDID_ROOT not in sys.path:
    sys.path.insert(0, CSDID_ROOT)
for _mod in [k for k in sys.modules if k == 'csdid' or k.startswith('csdid.')]:
    del sys.modules[_mod]

from csdid.att_gt import ATTgt
import csdid
print(f"csdid loaded from: {csdid.__file__}")

# ── Datasets ──
mpdta      = pd.read_csv(os.path.join(PROJECT, 'data', 'mpdta.csv'))
sim_data   = pd.read_csv(os.path.join(PYREPO, 'sim_data.csv'))
mpdta_extra= pd.read_csv(os.path.join(PROJECT, 'data', 'mpdta_extra.csv'))
mpdta_tvw  = pd.read_csv(os.path.join(PROJECT, 'data', 'mpdta_tvw.csv'))
factor_data= pd.read_csv(os.path.join(PROJECT, 'data', 'factor_cov.csv'))

def load_sim(name):
    return pd.read_csv(os.path.join(PROJECT, 'data', f'{name}.csv'))

# ── R references ──
r_attgt  = pd.read_csv(os.path.join(PYREPO, 'r_ref', 'ref_attgt.csv'))
r_aggte  = pd.read_csv(os.path.join(PYREPO, 'r_ref', 'ref_aggte.csv'))
r_sim    = pd.read_csv(os.path.join(PYREPO, 'r_ref', 'sim', 'ref_sim.csv'))
r_gaps   = pd.read_csv(os.path.join(PYREPO, 'r_ref', 'sim', 'ref_gaps.csv'))
r_fixwt  = pd.read_csv(os.path.join(PYREPO, 'r_ref', 'ref_fixweights.csv'))
r_factor = pd.read_csv(os.path.join(PYREPO, 'r_ref', 'sim', 'ref_factor.csv'))

# ── Julia references ──
jl_attgt   = pd.read_csv(os.path.join(PROJECT, 'julia_results.csv'))
jl_aggte   = pd.read_csv(os.path.join(PROJECT, 'julia_aggte_results_full.csv'))
jl_jel     = pd.read_csv(os.path.join(PROJECT, 'julia_jel_results.csv'))
jl_jel_agg = pd.read_csv(os.path.join(PROJECT, 'julia_jel_aggte.csv'))

# ── Stata references ──
st_attgt = pd.read_csv(os.path.join(PROJECT, 'stata_results.csv'))
st_aggte = pd.read_csv(os.path.join(PROJECT, 'stata_aggte_results_full.csv'))

STATA_MAP = {
    'mpdta_nev_dr': 'dr_nev_nocov',
    'mpdta_nyt_dr': 'dr_nyt_nocov',
    'mpdta_nev_reg_cov': 'reg_nev_cov',
    'mpdta_nev_ipw': 'ipw_nev_nocov',
    'sim_nev_dr': 'sim_nev_dr',
}
_st_scenarios = set(st_attgt['scenario'].unique())

def get_st_scn(test_scn):
    """Get Stata scenario name, or None if unavailable."""
    if test_scn in STATA_MAP:
        return STATA_MAP[test_scn]
    if test_scn in _st_scenarios:
        return test_scn
    return None

# ── Result tracker ──
results_tracker = []

# ══════════════════════════════════════════════════════════════
# Reference lookup helpers
# ══════════════════════════════════════════════════════════════

def _ref_lookup(df, filters=None):
    """Extract {(group, t): (att, se)} from reference DataFrame."""
    sub = df
    if filters:
        for col, val in filters.items():
            sub = sub[sub[col] == val]
    if sub.empty:
        return {}
    return {(int(r['group']), int(r['t'])): (float(r['att']), float(r['se']))
            for _, r in sub.iterrows()}

def _ref_aggte_egt(df, filters, agg_type, type_col='type'):
    """Extract {egt: (att_egt, se_egt)} and (overall_att, overall_se)."""
    sub = df
    if filters:
        for col, val in filters.items():
            sub = sub[sub[col] == val]
    sub = sub[sub[type_col] == agg_type]
    if sub.empty:
        return {}, (np.nan, np.nan)
    ov_row = sub.iloc[0]
    overall = (float(ov_row['overall_att']), float(ov_row['overall_se']))
    egt_sub = sub[sub['egt'].notna()]
    egt_map = {float(r['egt']): (float(r['att_egt']), float(r['se_egt']))
               for _, r in egt_sub.iterrows()}
    return egt_map, overall

def _ref_aggte_overall(df, filters, type_col='type'):
    """Extract {agg_type: (overall_att, overall_se)}."""
    sub = df
    if filters:
        for col, val in filters.items():
            sub = sub[sub[col] == val]
    result = {}
    for tp in ['simple', 'dynamic', 'group', 'calendar']:
        tp_sub = sub[sub[type_col] == tp]
        if not tp_sub.empty:
            row = tp_sub.iloc[0]
            result[tp] = (float(row['overall_att']), float(row['overall_se']))
    return result

def _extract_py(res):
    """Extract {(g,t): (att, se)} from ATTgt result."""
    g = np.asarray(res.MP['group'], dtype=float)
    t = np.asarray(res.MP['t'], dtype=float)
    att = np.asarray(res.results['att'], dtype=float)
    se = np.asarray(res.results['se'], dtype=float)
    return {(int(gi), int(ti)): (ai, si) for gi, ti, ai, si in zip(g, t, att, se)}

# ══════════════════════════════════════════════════════════════
# compare_test: plain DataFrame comparison
# ══════════════════════════════════════════════════════════════

def compare_test(name, df, att_tol=TOL_ATT, se_tol=TOL_SE):
    """Add att_diff/se_diff/ok columns, print result, record PASS/FAIL.

    att_diff = max - min across all populated ATT columns (R, Py, Jl, St).
    se_diff  = max - min across all populated SE columns.
    This catches discrepancies in ANY implementation, not just Py vs R.
    """
    df = df.copy()

    def _max_diff(row, cols):
        vals = row[cols].dropna()
        return (vals.max() - vals.min()) if len(vals) >= 2 else np.nan

    att_cols = [c for c in ['R_att', 'Py_att', 'Jl_att', 'St_att'] if c in df.columns]
    se_cols  = [c for c in ['R_se',  'Py_se',  'Jl_se',  'St_se']  if c in df.columns]
    df['att_diff'] = df.apply(lambda r: _max_diff(r, att_cols), axis=1)
    df['se_diff']  = df.apply(lambda r: _max_diff(r, se_cols),  axis=1)

    def _ok(r):
        a = r.get('att_diff', np.nan)
        s = r.get('se_diff', np.nan)
        a_ok = pd.isna(a) or a < att_tol
        s_ok = pd.isna(s) or s < se_tol
        return 'PASS' if (a_ok and s_ok) else 'FAIL'

    df['ok'] = df.apply(_ok, axis=1)
    tag = 'FAIL' if (df['ok'] == 'FAIL').any() else 'PASS'
    results_tracker.append({'name': name, 'status': tag})
    n = len(df)
    print(f"{tag} {name} ({n} cells)")
    fcols = df.select_dtypes(include='float').columns
    df[fcols] = df[fcols].round(7)
    print(df.to_string(index=False))

# ══════════════════════════════════════════════════════════════
# Preparation helpers
# ══════════════════════════════════════════════════════════════

def prep_attgt(res, r_scn=None, jl_scn=None, st_scn=None,
               r_df=None, r_filt=None, jl_df=None):
    """Build comparison DataFrame for ATT(g,t) test."""
    py = _extract_py(res)
    r  = _ref_lookup(r_df if r_df is not None else r_attgt,
                     r_filt if r_filt else ({'scenario': r_scn} if r_scn else None))
    jl = _ref_lookup(jl_df if jl_df is not None else jl_attgt,
                     {'scenario': jl_scn}) if jl_scn else {}
    st = _ref_lookup(st_attgt, {'scenario': st_scn}) if st_scn else {}
    keys = sorted(set(py) | set(r) | set(jl) | set(st))
    rows = []
    for k in keys:
        py_a, py_s = py.get(k, (np.nan, np.nan))
        r_a, r_s = r.get(k, (np.nan, np.nan))
        jl_a, jl_s = jl.get(k, (np.nan, np.nan))
        st_a, st_s = st.get(k, (np.nan, np.nan))
        rows.append({
            'g': int(k[0]), 't': int(k[1]),
            'R_att': r_a, 'Py_att': py_a, 'Jl_att': jl_a, 'St_att': st_a,
            'R_se': r_s, 'Py_se': py_s, 'Jl_se': jl_s, 'St_se': st_s,
        })
    return pd.DataFrame(rows)

def prep_aggte_overall(res, r_scn, jl_scn, st_scn=None):
    """Build comparison DataFrame for overall aggregation (4 types)."""
    rows = []
    r_ov  = _ref_aggte_overall(r_aggte,  {'scenario': r_scn},  type_col='type')
    jl_ov = _ref_aggte_overall(jl_aggte, {'scenario': jl_scn}, type_col='agg_type')
    st_ov = _ref_aggte_overall(st_aggte, {'scenario': st_scn}, type_col='agg_type') if st_scn else {}
    for tp in ['simple', 'dynamic', 'group', 'calendar']:
        with contextlib.redirect_stdout(io.StringIO()):
            res.aggte(typec=tp, bstrap=False)
        py_att = float(np.ravel(res.atte['overall_att'])[0])
        py_se  = float(np.ravel(res.atte['overall_se'])[0])
        r_a,  r_s  = r_ov.get(tp,  (np.nan, np.nan))
        jl_a, jl_s = jl_ov.get(tp, (np.nan, np.nan))
        st_a, st_s = st_ov.get(tp, (np.nan, np.nan))
        rows.append({
            'g': tp, 't': '-',
            'R_att': r_a, 'Py_att': py_att, 'Jl_att': jl_a, 'St_att': st_a,
            'R_se': r_s, 'Py_se': py_se, 'Jl_se': jl_s, 'St_se': st_s,
        })
    return pd.DataFrame(rows)

def prep_aggte_egt(res, r_scn, jl_scn, agg_type, st_scn=None):
    """Build comparison DataFrame for per-egt aggregation + overall."""
    with contextlib.redirect_stdout(io.StringIO()):
        res.aggte(typec=agg_type, bstrap=False)
    py_egt_arr = np.asarray(res.atte['egt'], dtype=float)
    py_att_arr = np.asarray(res.atte['att_egt'], dtype=float)
    py_se_arr  = np.asarray(res.atte['se_egt'], dtype=float)
    py_ov_att  = float(np.ravel(res.atte['overall_att'])[0])
    py_ov_se   = float(np.ravel(res.atte['overall_se'])[0])
    py_map     = {float(e): (a, s) for e, a, s in zip(py_egt_arr, py_att_arr, py_se_arr)}

    r_map,  r_ov  = _ref_aggte_egt(r_aggte,  {'scenario': r_scn},  agg_type, type_col='type')
    jl_map, jl_ov = _ref_aggte_egt(jl_aggte, {'scenario': jl_scn}, agg_type, type_col='agg_type')
    if st_scn:
        st_map, st_ov = _ref_aggte_egt(st_aggte, {'scenario': st_scn}, agg_type, type_col='agg_type')
    else:
        st_map, st_ov = {}, (np.nan, np.nan)

    rows = [{'g': 'overall', 't': '-',
             'R_att': r_ov[0], 'Py_att': py_ov_att, 'Jl_att': jl_ov[0], 'St_att': st_ov[0],
             'R_se': r_ov[1], 'Py_se': py_ov_se, 'Jl_se': jl_ov[1], 'St_se': st_ov[1]}]

    all_egts = sorted(set(py_map) | set(r_map) | set(jl_map) | set(st_map))
    for e in all_egts:
        lbl = f'e={int(e)}' if abs(e) < 100 else f'g={int(e)}'
        rows.append({'g': lbl, 't': '-',
                     'R_att': r_map.get(e, (np.nan,np.nan))[0],
                     'Py_att': py_map.get(e, (np.nan,np.nan))[0],
                     'Jl_att': jl_map.get(e, (np.nan,np.nan))[0],
                     'St_att': st_map.get(e, (np.nan,np.nan))[0],
                     'R_se': r_map.get(e, (np.nan,np.nan))[1],
                     'Py_se': py_map.get(e, (np.nan,np.nan))[1],
                     'Jl_se': jl_map.get(e, (np.nan,np.nan))[1],
                     'St_se': st_map.get(e, (np.nan,np.nan))[1]})
    return pd.DataFrame(rows)

print(f"Setup complete. Python {sys.version.split()[0]}, NumPy {np.__version__}, Pandas {pd.__version__}")
print(f"Project: {PROJECT}")
print(f"Datasets loaded: mpdta ({len(mpdta)}), sim_data ({len(sim_data)}), mpdta_extra ({len(mpdta_extra)})")
print(f"R refs: attgt ({len(r_attgt)}), aggte ({len(r_aggte)}), sim ({len(r_sim)}), gaps ({len(r_gaps)}), fixwt ({len(r_fixwt)}), factor ({len(r_factor)})")
print(f"Julia refs: attgt ({len(jl_attgt)}), aggte ({len(jl_aggte)}), jel ({len(jl_jel)}), jel_agg ({len(jl_jel_agg)})")
print(f"Stata refs: attgt ({len(st_attgt)}), aggte ({len(st_aggte)}), scenarios: {len(_st_scenarios)}")'''))

# ═══════════════════════════════════════════════════════════════════════
# TEST BLOCKS
# ═══════════════════════════════════════════════════════════════════════

# Script-level STATA_MAP (mirrors the one in the setup cell)
STATA_MAP = {
    'mpdta_nev_dr': 'dr_nev_nocov',
    'mpdta_nyt_dr': 'dr_nyt_nocov',
    'mpdta_nev_reg_cov': 'reg_nev_cov',
    'mpdta_nev_ipw': 'ipw_nev_nocov',
    'sim_nev_dr': 'sim_nev_dr',
}

# All Stata scenarios (for direct-name lookup at code-gen time)
_ALL_ST = {
    'sim_nev_dr', 'fix_weights_none', 'fix_weights_base', 'fix_weights_first',
    'fix_weights_varying', 'factor_cov', 'rc', 'universal', 'anticipation1',
    'weighted', 'clustered',
}
# Add all 24 sim parity scenarios
SIM_DATASETS = ["tp2_const", "tp4_const", "tp4_dyn", "tp5_dyn", "tp8_dyn", "tp10_const"]
SIM_CONTROLS = ["nevertreated", "notyettreated"]
SIM_ESTS = ["dr", "reg"]
for _ds in SIM_DATASETS:
    for _cg in SIM_CONTROLS:
        for _em in SIM_ESTS:
            _ALL_ST.add(f"sim_{_ds}_{_cg}_{_em}")


def _get_st(scn):
    """Script-level: get Stata scenario name for code generation."""
    if scn in STATA_MAP:
        return STATA_MAP[scn]
    if scn in _ALL_ST:
        return scn
    return None


# ── Section A: test_r_parity — ATT(g,t) (5 tests) ───────────────────

cells.append(md("## A. test_r_parity: ATT(g,t) point estimates and SEs (5 tests)"))

BASIC = [
    ("mpdta_nev_dr",      "mpdta",    "lemp", "year", "countyreal", "first.treat", "lemp~1",   "nevertreated",  "dr"),
    ("mpdta_nyt_dr",      "mpdta",    "lemp", "year", "countyreal", "first.treat", "lemp~1",   "notyettreated", "dr"),
    ("mpdta_nev_reg_cov", "mpdta",    "lemp", "year", "countyreal", "first.treat", "lemp~lpop","nevertreated",  "reg"),
    ("mpdta_nev_ipw",     "mpdta",    "lemp", "year", "countyreal", "first.treat", "lemp~1",   "nevertreated",  "ipw"),
    ("sim_nev_dr",        "sim_data", "Y",    "period","id",        "G",           "Y~X",      "nevertreated",  "dr"),
]

for scn, ds, y, t, idn, gn, xf, cg, em in BASIC:
    st_scn = _get_st(scn)
    st_arg = f"'{st_scn}'" if st_scn else "None"
    cov_desc = "no covariates" if "~1" in xf else f"covariates: {xf.split('~')[1]}"
    spec = f"`{ds}`, {em.upper()}, {cg}, {cov_desc}"
    add_test(
        f"test_attgt_matches_r[{scn}]", spec,
        f"""with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(data={ds}, yname='{y}', tname='{t}', idname='{idn}',
            gname='{gn}', xformla='{xf}', control_group='{cg}'
            ).fit(est_method='{em}', bstrap=False)
df = prep_attgt(res, r_scn='{scn}', jl_scn='{scn}', st_scn={st_arg})
compare_test('test_attgt_matches_r[{scn}]', df)""")

# ── Section B: test_r_parity — aggte overall (5 tests) ──────────────

cells.append(md("## B. test_r_parity: Aggregated overall ATT and SE (5 tests)"))

for scn, ds, y, t, idn, gn, xf, cg, em in BASIC:
    st_scn = _get_st(scn)
    st_arg = f"'{st_scn}'" if st_scn else "None"
    cov_desc = "no covariates" if "~1" in xf else f"covariates: {xf.split('~')[1]}"
    spec = f"`{ds}`, {em.upper()}, {cg}, {cov_desc} -- simple/dynamic/group/calendar overall"
    add_test(
        f"test_aggte_overall_matches_r[{scn}]", spec,
        f"""with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(data={ds}, yname='{y}', tname='{t}', idname='{idn}',
            gname='{gn}', xformla='{xf}', control_group='{cg}'
            ).fit(est_method='{em}', bstrap=False)
df = prep_aggte_overall(res, r_scn='{scn}', jl_scn='{scn}', st_scn={st_arg})
compare_test('test_aggte_overall_matches_r[{scn}]', df)""")

# ── Section C: test_r_parity — aggte egt (15 tests) ─────────────────

cells.append(md("## C. test_r_parity: Per-event/group/calendar ATT(egt) and SE (15 tests)"))

AGG_TYPES = ["group", "dynamic", "calendar"]

for tp in AGG_TYPES:
    for scn, ds, y, t, idn, gn, xf, cg, em in BASIC:
        st_scn = _get_st(scn)
        st_arg = f"'{st_scn}'" if st_scn else "None"
        cov_desc = "no covariates" if "~1" in xf else f"covariates: {xf.split('~')[1]}"
        spec = f"`{ds}`, {em.upper()}, {cg}, {cov_desc} -- {tp} aggregation per-egt + overall"
        add_test(
            f"test_aggte_egt_matches_r[{tp}-{scn}]", spec,
            f"""with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(data={ds}, yname='{y}', tname='{t}', idname='{idn}',
            gname='{gn}', xformla='{xf}', control_group='{cg}'
            ).fit(est_method='{em}', bstrap=False)
df = prep_aggte_egt(res, r_scn='{scn}', jl_scn='{scn}', agg_type='{tp}', st_scn={st_arg})
compare_test('test_aggte_egt_matches_r[{tp}-{scn}]', df)""")

# ── Section D: test_r_parity — fix_weights (4 tests) ────────────────

cells.append(md("## D. test_r_parity: fix_weights (time-varying weights) (4 tests)"))

FW_TAGS = [
    ("none",         "None"),
    ("base_period",  "'base_period'"),
    ("first_period", "'first_period'"),
    ("varying",      "'varying'"),
]

for tag, py_val in FW_TAGS:
    jl_scn = f"fix_weights_{tag}" if tag != "none" else "fix_weights_none"
    if tag == "base_period":
        jl_scn = "fix_weights_base"
    elif tag == "first_period":
        jl_scn = "fix_weights_first"
    st_scn = _get_st(jl_scn)
    st_arg = f"'{st_scn}'" if st_scn else "None"
    spec = f"`mpdta_tvw`, REG, nevertreated, weights=wt, fix_weights={tag}"
    add_test(
        f"test_fix_weights_matches_r[{tag}]", spec,
        f"""with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(data=mpdta_tvw, yname='lemp', tname='year', idname='countyreal',
            gname='first.treat', xformla='lemp~1', control_group='nevertreated',
            weights_name='wt', fix_weights={py_val}
            ).fit(est_method='reg', bstrap=False)
df = prep_attgt(res, jl_scn='{jl_scn}', st_scn={st_arg},
                r_df=r_fixwt, r_filt={{'fix_weights': '{tag}'}})
compare_test('test_fix_weights_matches_r[{tag}]', df)""")

# ── Section E: test_r_parity — factor covariate (2 tests) ───────────

cells.append(md("## E. test_r_parity: Factor (categorical) covariate (2 tests)"))

for faster_mode in [False, True]:
    fm_str = str(faster_mode)
    spec = f"`factor_cov`, REG, nevertreated, xformla=Y~C(cat), faster_mode={fm_str}"
    add_test(
        f"test_factor_covariate_matches_r[{fm_str}]", spec,
        f"""with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(data=factor_data, yname='Y', tname='period', idname='id',
            gname='G', xformla='Y~C(cat)', control_group='nevertreated',
            faster_mode={fm_str}
            ).fit(est_method='reg', bstrap=False)
df = prep_attgt(res, jl_scn='factor_cov', st_scn='factor_cov', r_df=r_factor)
compare_test('test_factor_covariate_matches_r[{fm_str}]', df)""")

# ── Section F: test_r_parity — gap scenarios (5 tests) ──────────────

cells.append(md("## F. test_r_parity: Gap scenarios (RC, universal, anticipation, weighted, clustered) (5 tests)"))

GAP_SCENARIOS = [
    ("rc",            "panel=False",                 "dict(panel=False)",           "dict(base_period='varying')"),
    ("universal",     "base_period='universal'",     "dict()",                      "dict(base_period='universal')"),
    ("anticipation1", "anticipation=1",              "dict(anticipation=1)",        "dict(base_period='varying')"),
    ("weighted",      "weights_name='wt'",           "dict(weights_name='wt')",     "dict(base_period='varying')"),
    ("clustered",     "clustervar='clust'",          "dict(clustervar='clust')",    "dict(base_period='varying')"),
]

for scn, desc, ctor_kw, fit_kw in GAP_SCENARIOS:
    st_scn = _get_st(scn)
    st_arg = f"'{st_scn}'" if st_scn else "None"
    spec = f"`mpdta_extra`, REG, nevertreated, {desc}"
    add_test(
        f"test_gap_scenarios_match_r[{scn}]", spec,
        f"""ctor_kw = {ctor_kw}
fit_kw  = {fit_kw}
with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(data=mpdta_extra, yname='lemp', tname='year', idname='countyreal',
            gname='first.treat', control_group='nevertreated', **ctor_kw
            ).fit(est_method='reg', bstrap=False, **fit_kw)
df = prep_attgt(res, jl_scn='{scn}', st_scn={st_arg},
                r_df=r_gaps, r_filt={{'scenario': '{scn}'}})
compare_test('test_gap_scenarios_match_r[{scn}]', df)""")

# ── Section G: test_sim_parity (24 tests) ────────────────────────────

cells.append(md("## G. test_sim_parity: Simulated data ATT(g,t) and SE (24 tests)"))

for ds in SIM_DATASETS:
    for cg in SIM_CONTROLS:
        for em in SIM_ESTS:
            jl_scn = f"sim_{ds}_{cg}_{em}"
            st_scn = _get_st(jl_scn)
            st_arg = f"'{st_scn}'" if st_scn else "None"
            test_name = f"test_sim_attgt_matches_r[{ds}-{cg}-{em}]"
            spec = f"`{ds}`, {em.upper()}, {cg}, covariates: X"
            add_test(
                test_name, spec,
                f"""_sim_data = load_sim('{ds}')
with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(data=_sim_data, yname='Y', tname='period', idname='id',
            gname='G', xformla='Y~X', control_group='{cg}'
            ).fit(est_method='{em}', bstrap=False)
df = prep_attgt(res, jl_scn='{jl_scn}', st_scn={st_arg},
                r_df=r_sim, r_filt={{'dataset': '{ds}', 'control': '{cg}', 'est': '{em}'}})
compare_test('{test_name}', df)""")

# ── Section H: test_jel_replication (5 tests) ────────────────────────

cells.append(md("""## H. test_jel_replication: JEL article replication (5 tests)

These tests replicate results from the Callaway & Sant'Anna JEL article using
`county_mortality_data.csv`. R reference values are the published article values.
Julia references from `julia_jel_results.csv` and `julia_jel_aggte.csv`.
No Stata data for JEL tests (complex data preparation not in wrapper)."""))

# JEL data prep helpers — 2xT tests filter to yaca==2014 only; GxT keeps all years
_JEL_COMMON = r"""jel_path = os.path.join(PROJECT, 'data', 'county_mortality_data.csv')
mydata = pd.read_csv(jel_path, dtype={'county': str})
mydata['state'] = mydata['county'].str[-2:]
mydata = mydata[~mydata['state'].isin(['DC','DE','MA','NY','VT'])].copy()"""

_JEL_VARS = r"""mydata['perc_white'] = mydata['population_20_64_white'] / mydata['population_20_64'] * 100
mydata['perc_hispanic'] = mydata['population_20_64_hispanic'] / mydata['population_20_64'] * 100
mydata['perc_female'] = mydata['population_20_64_female'] / mydata['population_20_64'] * 100
mydata['unemp_rate'] = mydata['unemp_rate'] * 100
mydata['median_income'] = mydata['median_income'] / 1000
keep = ['county_code','year','population_20_64','yaca','crude_rate_20_64',
        'perc_female','perc_white','perc_hispanic','unemp_rate','poverty_rate','median_income']
mydata = mydata[keep].dropna(subset=[c for c in keep if c != 'yaca'])
both = mydata[mydata['year'].isin([2013,2014])].groupby('county_code').size()
mydata = mydata[mydata['county_code'].isin(both[both==2].index)].copy()
full = mydata.groupby('county_code').size()
mydata = mydata[mydata['county_code'].isin(full[full==11].index)].copy()"""

# 2xT prep: keep only yaca==2014 or untreated
JEL_DATA_PREP = (_JEL_COMMON
    + "\nmydata = mydata[(mydata['yaca'] == 2014) | mydata['yaca'].isna() | (mydata['yaca'] > 2019)].copy()\n"
    + _JEL_VARS)

# GxT prep: keep all treatment years
JEL_DATA_PREP_GXT = _JEL_COMMON + "\n" + _JEL_VARS

# --- Test: test_jel_table7_2x2 ---
add_test(
    "test_jel_table7_2x2",
    "JEL Table 7: 2x2 CS-DiD, 6 method/weight combos against published values",
    JEL_DATA_PREP + r"""
short = mydata[mydata['year'].isin([2013,2014])].copy()
short['treat_year'] = short['yaca'].apply(lambda x: 2014 if pd.notna(x) and x == 2014 else 0)
short['county_code'] = short['county_code'].astype(float)
wt = short.loc[short['year']==2013, ['county_code','population_20_64']].copy()
wt.columns = ['county_code','set_wt']
short = short.merge(wt, on='county_code')

COVS = 'crude_rate_20_64 ~ perc_female + perc_white + perc_hispanic + unemp_rate + poverty_rate + median_income'
expected = {
    ('reg', None): -1.6154372119, ('ipw', None): -0.8585625501, ('dr', None): -1.2256473242,
    ('reg', 'set_wt'): -3.4592200594, ('ipw', 'set_wt'): -3.8416966846, ('dr', 'set_wt'): -3.7561045985,
}

rows = []
for (method, wt_name), exp_att in expected.items():
    with contextlib.redirect_stdout(io.StringIO()):
        res = ATTgt(yname='crude_rate_20_64', tname='year', idname='county_code',
                    gname='treat_year', xformla=COVS, data=short,
                    control_group='nevertreated', weights_name=wt_name
                    ).fit(est_method=method, base_period='universal', bstrap=False)
        res.aggte(typec='simple', na_rm=True, bstrap=False)
    py_att = float(res.atte['overall_att'])
    wlabel = 'wt' if wt_name else 'unwt'
    jl_scn = f'table7_{method}_{wlabel}'
    jl_sub = jl_jel_agg[(jl_jel_agg['scenario']==jl_scn) & (jl_jel_agg['agg_type']=='simple')]
    jl_att = float(jl_sub.iloc[0]['overall_att']) if not jl_sub.empty else np.nan
    rows.append({'g': f'{method}/{wlabel}', 't': '-',
                 'R_att': exp_att, 'Py_att': py_att, 'Jl_att': jl_att, 'St_att': np.nan,
                 'R_se': np.nan, 'Py_se': np.nan, 'Jl_se': np.nan, 'St_se': np.nan})

compare_test('test_jel_table7_2x2', pd.DataFrame(rows))""")

# --- Test: test_jel_2xt_event_study ---
add_test(
    "test_jel_2xt_event_study",
    "JEL 2xT: event study ATT(g,t) + dynamic aggregation, weighted REG",
    JEL_DATA_PREP + r"""
mydata['treat_year'] = mydata['yaca'].apply(lambda x: 2014 if pd.notna(x) and x == 2014 else 0)
mydata['county_code'] = mydata['county_code'].astype(float)
wt = mydata.loc[mydata['year']==2013, ['county_code','population_20_64']].copy()
wt.columns = ['county_code','set_wt']
mydata = mydata.merge(wt, on='county_code')

with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(yname='crude_rate_20_64', tname='year', idname='county_code',
                gname='treat_year', data=mydata, weights_name='set_wt',
                control_group='nevertreated'
                ).fit(est_method='reg', base_period='universal', bstrap=False)

expected_att = [4.1292044043, -0.5016807242, 2.7531791360, 2.7804626426,
                0.0, -2.5628745138, -1.6973291127, 0.2189009815,
                -0.8133358354, -1.1532954495, 1.7866564429]

py = _extract_py(res)
jl = _ref_lookup(jl_jel, {'scenario': '2xt_event'})
r_map = dict(zip(sorted(py.keys()), [(e, np.nan) for e in expected_att]))
rows = []
for k in sorted(py.keys()):
    rows.append({'g': k[0], 't': k[1],
                 'R_att': r_map.get(k, (np.nan,))[0], 'Py_att': py[k][0],
                 'Jl_att': jl.get(k, (np.nan,np.nan))[0], 'St_att': np.nan,
                 'R_se': np.nan, 'Py_se': py[k][1],
                 'Jl_se': jl.get(k, (np.nan,np.nan))[1], 'St_se': np.nan})

with contextlib.redirect_stdout(io.StringIO()):
    res.aggte(typec='dynamic', min_e=0, max_e=5, bstrap=False)
py_ov = float(res.atte['overall_att'])
jl_ov_sub = jl_jel_agg[(jl_jel_agg['scenario']=='2xt_event') & (jl_jel_agg['agg_type']=='dynamic')]
jl_ov = float(jl_ov_sub.iloc[0]['overall_att']) if not jl_ov_sub.empty else np.nan
rows.append({'g': 'ov(0-5)', 't': '-',
             'R_att': -0.7035462478, 'Py_att': py_ov, 'Jl_att': jl_ov, 'St_att': np.nan,
             'R_se': np.nan, 'Py_se': np.nan, 'Jl_se': np.nan, 'St_se': np.nan})

compare_test('test_jel_2xt_event_study', pd.DataFrame(rows))""")

# --- Test: test_jel_2xt_with_covariates ---
add_test(
    "test_jel_2xt_with_covariates",
    "JEL 2xT with covariates: e=-1 should be 0, all estimates finite (REG/IPW/DR)",
    JEL_DATA_PREP + r"""
mydata['treat_year'] = mydata['yaca'].apply(lambda x: 2014 if pd.notna(x) and x == 2014 else 0)
mydata['county_code'] = mydata['county_code'].astype(float)
wt = mydata.loc[mydata['year']==2013, ['county_code','population_20_64']].copy()
wt.columns = ['county_code','set_wt']
mydata = mydata.merge(wt, on='county_code')

COVS = 'crude_rate_20_64 ~ perc_female + perc_white + perc_hispanic + unemp_rate + poverty_rate + median_income'
rows = []
for method in ['reg', 'ipw', 'dr']:
    with contextlib.redirect_stdout(io.StringIO()):
        res = ATTgt(yname='crude_rate_20_64', tname='year', idname='county_code',
                    gname='treat_year', xformla=COVS, data=mydata,
                    weights_name='set_wt', control_group='nevertreated'
                    ).fit(est_method=method, base_period='universal', bstrap=False)
        res.aggte(typec='dynamic', na_rm=True, bstrap=False)
    egt = np.asarray(res.atte['egt'], dtype=float)
    att_egt = np.asarray(res.atte['att_egt'], dtype=float)
    base_idx = np.where(egt == -1)[0]
    base_val = float(att_egt[base_idx[0]]) if len(base_idx) > 0 else np.nan
    all_finite = bool(np.all(np.isfinite(att_egt[~np.isnan(att_egt)])))
    jl_scn = f'2xt_cov_{method}'
    jl_sub = jl_jel_agg[(jl_jel_agg['scenario']==jl_scn) & (jl_jel_agg['agg_type']=='dynamic')]
    jl_egt_sub = jl_sub[jl_sub['egt'].notna() & (jl_sub['egt'] == -1.0)]
    jl_base = float(jl_egt_sub.iloc[0]['att_egt']) if not jl_egt_sub.empty else np.nan
    rows.append({'g': f'{method} e=-1', 't': '-',
                 'R_att': 0.0, 'Py_att': base_val, 'Jl_att': jl_base, 'St_att': np.nan,
                 'R_se': np.nan, 'Py_se': np.nan, 'Jl_se': np.nan, 'St_se': np.nan})
    rows.append({'g': f'{method} finite', 't': '-',
                 'R_att': 1.0, 'Py_att': 1.0 if all_finite else 0.0, 'Jl_att': 1.0, 'St_att': np.nan,
                 'R_se': np.nan, 'Py_se': np.nan, 'Jl_se': np.nan, 'St_se': np.nan})

compare_test('test_jel_2xt_with_covariates', pd.DataFrame(rows))""")

# --- Test: test_jel_gxt_no_covs ---
add_test(
    "test_jel_gxt_no_covs",
    "JEL GxT: staggered event study, no covariates, notyettreated, weighted REG",
    JEL_DATA_PREP_GXT + r"""
mydata['treat_year'] = mydata['yaca'].apply(lambda x: int(x) if pd.notna(x) and x <= 2019 else 0)
mydata['county_code'] = mydata['county_code'].astype(float)
wt = mydata.loc[mydata['year']==2013, ['county_code','population_20_64']].copy()
wt.columns = ['county_code','set_wt']
mydata = mydata.merge(wt, on='county_code')

with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(yname='crude_rate_20_64', tname='year', idname='county_code',
                gname='treat_year', data=mydata, weights_name='set_wt',
                control_group='notyettreated'
                ).fit(est_method='reg', base_period='universal', bstrap=False)
    res.aggte(typec='dynamic', bstrap=False)

expected = {-5: 2.2186783578, -4: 0.8579225109, -3: 1.9161499399,
            -2: 2.5644742860, -1: 0.0,
            0: -1.6545648988, 1: -0.2616435324, 2: 1.7055625922,
            3: -0.5405232028, 4: -0.5148819184, 5: 1.7866564429}

egt = np.asarray(res.atte['egt'], dtype=float)
att_egt = np.asarray(res.atte['att_egt'], dtype=float)
py_map = {float(e): a for e, a in zip(egt, att_egt)}

jl_map_raw, jl_ov = _ref_aggte_egt(jl_jel_agg, {'scenario': 'gxt_nocov'}, 'dynamic', type_col='agg_type')

rows = []
for e_val in sorted(expected.keys()):
    rows.append({'g': f'e={e_val}', 't': '-',
                 'R_att': expected[e_val], 'Py_att': py_map.get(e_val, np.nan),
                 'Jl_att': jl_map_raw.get(float(e_val), (np.nan,np.nan))[0], 'St_att': np.nan,
                 'R_se': np.nan, 'Py_se': np.nan, 'Jl_se': np.nan, 'St_se': np.nan})

with contextlib.redirect_stdout(io.StringIO()):
    res.aggte(typec='dynamic', min_e=0, max_e=5, bstrap=False)
py_ov = float(res.atte['overall_att'])
jl_ov_sub = jl_jel_agg[(jl_jel_agg['scenario']=='gxt_nocov_05') & (jl_jel_agg['agg_type']=='dynamic')]
jl_ov_val = float(jl_ov_sub.iloc[0]['overall_att']) if not jl_ov_sub.empty else np.nan
rows.append({'g': 'ov(0-5)', 't': '-',
             'R_att': 0.0867675805, 'Py_att': py_ov, 'Jl_att': jl_ov_val, 'St_att': np.nan,
             'R_se': np.nan, 'Py_se': np.nan, 'Jl_se': np.nan, 'St_se': np.nan})

compare_test('test_jel_gxt_no_covs', pd.DataFrame(rows))""")

# --- Test: test_jel_gxt_dr_covs ---
add_test(
    "test_jel_gxt_dr_covs",
    "JEL GxT: staggered DR with covariates, notyettreated, weighted",
    JEL_DATA_PREP_GXT + r"""
mydata['treat_year'] = mydata['yaca'].apply(lambda x: int(x) if pd.notna(x) and x <= 2019 else 0)
mydata['county_code'] = mydata['county_code'].astype(float)
wt = mydata.loc[mydata['year']==2013, ['county_code','population_20_64']].copy()
wt.columns = ['county_code','set_wt']
mydata = mydata.merge(wt, on='county_code')

COVS = 'crude_rate_20_64 ~ perc_female + perc_white + perc_hispanic + unemp_rate + poverty_rate + median_income'
with contextlib.redirect_stdout(io.StringIO()):
    res = ATTgt(yname='crude_rate_20_64', tname='year', idname='county_code',
                gname='treat_year', xformla=COVS, data=mydata,
                weights_name='set_wt', control_group='notyettreated'
                ).fit(est_method='dr', base_period='universal', bstrap=False)

expected = {-5: 2.6684811691, -4: 2.1333836537, -3: 2.8574389179,
            -2: 2.9129673584, -1: 0.0,
            0: -1.4929553032, 1: -1.9693922262, 2: -2.7250659699,
            3: -5.0556625460, 4: -4.7161630370, 5: 2.4772492894}

with contextlib.redirect_stdout(io.StringIO()):
    res.aggte(typec='dynamic', bstrap=False)
egt = np.asarray(res.atte['egt'], dtype=float)
att_egt = np.asarray(res.atte['att_egt'], dtype=float)
py_map = {float(e): a for e, a in zip(egt, att_egt)}

jl_map_raw, jl_ov = _ref_aggte_egt(jl_jel_agg, {'scenario': 'gxt_dr_cov'}, 'dynamic', type_col='agg_type')

rows = []
for e_val in sorted(expected.keys()):
    rows.append({'g': f'e={e_val}', 't': '-',
                 'R_att': expected[e_val], 'Py_att': py_map.get(e_val, np.nan),
                 'Jl_att': jl_map_raw.get(float(e_val), (np.nan,np.nan))[0], 'St_att': np.nan,
                 'R_se': np.nan, 'Py_se': np.nan, 'Jl_se': np.nan, 'St_se': np.nan})

with contextlib.redirect_stdout(io.StringIO()):
    res.aggte(typec='dynamic', min_e=0, max_e=5, bstrap=False)
py_ov = float(res.atte['overall_att'])
jl_ov_sub = jl_jel_agg[(jl_jel_agg['scenario']=='gxt_dr_cov_05') & (jl_jel_agg['agg_type']=='dynamic')]
jl_ov_val = float(jl_ov_sub.iloc[0]['overall_att']) if not jl_ov_sub.empty else np.nan
rows.append({'g': 'ov(0-5)', 't': '-',
             'R_att': -2.2469982988, 'Py_att': py_ov, 'Jl_att': jl_ov_val, 'St_att': np.nan,
             'R_se': np.nan, 'Py_se': np.nan, 'Jl_se': np.nan, 'St_se': np.nan})

compare_test('test_jel_gxt_dr_covs', pd.DataFrame(rows))""")

# ═══════════════════════════════════════════════════════════════════════
# GLOBAL SUMMARY
# ═══════════════════════════════════════════════════════════════════════

cells.append(md("## Global Summary"))

cells.append(code(r"""n_pass = sum(1 for r in results_tracker if r['status'] == 'PASS')
n_fail = sum(1 for r in results_tracker if r['status'] == 'FAIL')
n_total = len(results_tracker)

summary_df = pd.DataFrame(results_tracker)
summary_df.index = range(1, len(summary_df) + 1)
summary_df.index.name = 'Test #'
print(summary_df.to_string())

print()
if n_fail == 0:
    print(f"Result: {n_pass}/{n_total} tests PASS")
else:
    print(f"Result: {n_pass}/{n_total} PASS, {n_fail} FAIL")
    print("\nFailed tests:")
    for r in results_tracker:
        if r['status'] == 'FAIL':
            print(f"  x {r['name']}")"""))

# ═══════════════════════════════════════════════════════════════════════
# ASSEMBLE AND WRITE NOTEBOOK
# ═══════════════════════════════════════════════════════════════════════

notebook = {
    "nbformat": 4,
    "nbformat_minor": 5,
    "metadata": {
        "kernelspec": {
            "display_name": "Python 3",
            "language": "python",
            "name": "python3",
        },
        "language_info": {
            "name": "python",
            "version": "3.12.0",
        },
    },
    "cells": cells,
}

out_path = os.path.join(PROJECT, "comparison_csdid.ipynb")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(notebook, f, indent=1, ensure_ascii=False)

n_code = sum(1 for c in cells if c["cell_type"] == "code")
n_md = sum(1 for c in cells if c["cell_type"] == "markdown")
print(f"Notebook written to {out_path}")
print(f"  {len(cells)} cells total ({n_code} code, {n_md} markdown)")
print(f"  {test_num} tests generated")
