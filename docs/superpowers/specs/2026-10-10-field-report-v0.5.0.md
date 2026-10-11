# Field report: `opencode-delegate` v0.5.0

Living document: append a numbered finding as each issue occurs.

Severity: Critical = lost work or wrong status; Important = controller cannot
tell what happened; Minor = friction. Mark "Cause" **verified** only where it
was checked against logs or code; otherwise it is a hypothesis.

For each finding, record:
- the run id
- the session id
- the time (UTC)
- what was observed, and what was expected
- the run's own files: `.oc-runs/RUNID.summary`, `.oc-runs/RUNID.json`
  (`state`, `exit_code`, `internal_error`), and the `level=ERROR` lines of
  `.oc-runs/RUNID.serve.log`

v0.5.0 writes a summary on every exit path. A run that ends with no summary
at all, or whose record still says `"state": "running"` after its wrapper is
gone, is itself a finding.
