"""Read-only A16 cross-check over the tracked release-v2 files (no raw samples available)."""
import hashlib, json, pathlib, sys, importlib.util
repo = pathlib.Path(sys.argv[1]); run = repo/'runs/kit1-landscape-v5-2026-10-25'; err = run/'data-report-errata/release-v2'
spec = importlib.util.spec_from_file_location('kit', repo/'docs/kit1/tools/kit.py'); k = importlib.util.module_from_spec(spec); spec.loader.exec_module(k)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None
out = {}
report = json.load(open(run/'report.json')); ev = {e['id']: e for e in report['evidence']}
config = json.load(open(run/'config.json'))
policy_path = k.confined(run, config['geodata_policy_path']); policy = k.checked('geodata_policy', policy_path)
binding = json.load(open(err/'errata-binding.json')); app = json.load(open(err/'policy-application-v1.json')); chk = json.load(open(err/'applicable-evidence-check.json'))
hashes = {
 'geodata_policy (config path '+config['geodata_policy_path']+')': (sha(policy_path), app['base_policy']['sha256']),
 'policy-application-v1.json': (sha(err/'policy-application-v1.json'), ev['data_errata_policy']['sha256']),
 'errata-binding.json': (sha(err/'errata-binding.json'), ev['data_errata_binding']['sha256']),
 'applicable-evidence-check.json': (sha(err/'applicable-evidence-check.json'), ev['data_errata_check']['sha256']),
 'runtime-evidence-summary.json': (sha(err/'runtime-evidence-summary.json'), ev['data_errata_summary']['sha256']),
 'independent-review/FINAL_REVIEW.md': (sha(run/'independent-review/FINAL_REVIEW.md'), ev['independent_final_review']['sha256']),
 'independent-review-snapshot.md': (sha(err/'evidence/independent-review-snapshot.md'), binding['review_snapshot']['sha256']),
 'derivation-view.json': (sha(err/'derivation-view.json'), ev['derivation']['sha256']),
}
out['hashes'] = {n: {'actual': a, 'bound': b, 'match': a == b} for n, (a, b) in hashes.items()}
out['reviewer_binding'] = {'producer': report['producer'], 'reviewer': report['reviewer'], 'review_ref': report['review_ref'],
  'review_file_present': (run/report['review_ref']).is_file(), 'independent': report['producer'] != report['reviewer'],
  'all_bound': all(k.bound(report[x]) for x in ('producer', 'reviewer', 'review_ref'))}
levels = {l['id']: {b['metric']: b for b in l['budgets']} for l in policy['levels']}
rows = []; measured = set()
for m in chk['metrics']:
    b = levels[m['level_id']][m['metric']]; measured.add((m['level_id'], m['metric']))
    rows.append({'level_id': m['level_id'], 'metric': m['metric'], 'status': 'PASS' if m['reported_value'] <= b['limit'] else 'FAIL',
                 'reported_value': m['reported_value'], 'limit': b['limit'], 'unit': b['unit'], 'budget_matches_summary': b == m['budget']})
na_app = {(l, mt) for l, d in app['offline_levels'].items() for mt in d.get('not_applicable_metrics', [])}
na_bind = {(x['level_id'], x['metric']) for x in binding['not_applicable']}
for l, mt in sorted(na_app):
    rows.append({'level_id': l, 'metric': mt, 'status': 'NA', 'render_metric': mt in k.NA_METRICS, 'level_in_policy': l in levels,
                 'rendered_in_valid_runs': app['offline_levels'][l]['rendered_in_valid_runs'],
                 'rule': {'artifact_path': 'data-report-errata/release-v2/policy-application-v1.json', 'sha256': sha(err/'policy-application-v1.json')}})
expected = {(l, mt) for l in levels for mt in k.GEO_METRICS}
out['coverage'] = {'expected': len(expected), 'measured': len(measured), 'not_applicable': len(na_app), 'closed': measured | na_app == expected and not (measured & na_app),
                   'na_application_equals_binding': na_app == na_bind,
                   'every_metric_has_measured_level': all(any(mt == x for _, x in measured) for mt in k.GEO_METRICS)}
out['rows'] = rows
print(json.dumps(out, indent=2, ensure_ascii=False))
