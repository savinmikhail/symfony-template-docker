# Alert fixes awaiting main history reconciliation

Status: deferred for owner review on 16 October 2026.

Local canonical main contains atomic fixes:

- `bb93c22` — classify Symfony lazy timeout exceptions as timeout; four regression cases.
- `0c41e53` — distinguish a `.json` file path from a JSON decoding/encoding failure.

Verified: template Rector, PHP-CS-Fixer, full PHPStan, PHPUnit (4 tests / 16
assertions), notification templates, and real Loki 2.9.8 synthetic classification.
AST graph was updated. There is no production target for the template itself.

Publishing was rejected as non-fast-forward. After fetching origin/main, main
had 17 local and 20 remote commits since merge-base
`47c9d2c18f9fc81c046d974331d225b68055cb39`; 15 local commits predate this task.
Some are patch-equivalent to remote commits; others overlap infrastructure,
security and logging changes with different patches. The pre-existing commits
were preserved. No force push, reset, rebase of earlier work, or broad merge was
performed. Review which earlier local changes should be retained before publishing
this branch. The two current fixes can be ported independently after that decision.

The later shared-host deployment incident also produced a mirrored
`fix(deploy): isolate remote registry credentials per run` commit on local main.
Its actual deployment shell blocks pass concurrent fake-host tests: success,
failed-deploy cleanup, and syntax checks. This addition remains unpublished with
the same history-reconciliation decision. Production secret files were not changed.
