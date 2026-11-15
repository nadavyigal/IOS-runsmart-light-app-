# Independent PR review

Review the actual diff and relevant callers, tests, and authorization boundaries.
Pin the PR head and target base before reading. Recheck the head before posting.
Report P0/P1/P2 findings with a file and line, impact, and requested validation.
Include the full head SHA, your name/model, explicit verdict (PASS, PASS WITH
NOTES, or CHANGES REQUIRED), and disposition of each material finding. List
anything unverified. An author does not independently review their own work.
Follow the named cross-vendor requirement for sensitive work.

Founder only: after verifying the linked independent review, matching head,
reviewer identity, required review coverage, and resolution of material
findings, post this five-line attestation on the PR, then add deep-reviewed.
After any new push, verify the new review and remove/reapply the label.

    <!-- steward-deep-review sha=<full 40-character head SHA> -->
    Reviewer: <named independent reviewer and model>
    Verdict: PASS
    Findings: resolved
    Evidence: <GitHub link to the completed review>

Use PASS WITH NOTES only for accepted non-material follow-ups. The attestation
and label are evidence for the advisory gate. Merge authority stays with the
founder for sensitive changes. No reviewer may merge, label, push, edit, or
operate production while reviewing.
