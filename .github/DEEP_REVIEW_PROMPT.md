# Independent AI review

Read the actual PR diff, relevant callers, tests, access boundaries and failure paths.
Check the full head SHA and target base before reading and recheck before posting.

Post the full reviewed head SHA, your model/reviewer identity, an explicit verdict
(PASS, PASS WITH NOTES or CHANGES REQUIRED), and material finding dispositions.
Use `P0/P1/P2 | file:line | impact | fix or validation` for findings.

Sensitive changes require two independent AI reviews from distinct models.
The implementer's own reading is not a review. Hosted Codex plus a completed
CodeRabbit review is one supported pair. Two named, distinct models in fresh
read-only review sessions also qualify. Human approval, attestation comments
and `deep-reviewed` labels are not part of the review requirement.

Resolve material findings and pass required checks. The Steward verifies
reviews and merge eligibility. Review-only agents do not merge or label PRs.
