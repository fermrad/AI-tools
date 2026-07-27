---
name: code-review
description: Review staged changes or a PR diff for bugs, security issues, and quality
---

Review the current changes (staged diff, a PR number, or a specific file range).

1. **Get the diff** — use whichever is relevant:
   ```bash
   git diff HEAD          # unstaged changes
   git diff --cached      # staged changes
   gh pr diff <number>    # a specific PR
   ```

2. **Read any files referenced** in the diff that provide context (e.g. the interface a changed function implements, the test file for a changed module).

3. **Evaluate against these criteria** (only flag real issues, not style opinions):

   **🔴 Critical — must fix:**
   - Logic errors or off-by-one bugs
   - Security issues: SQL injection, XSS, auth bypass, exposed secrets, missing input validation
   - Data loss risks: unhandled errors that could corrupt state
   - Broken types or missing null checks that will throw at runtime

   **🟡 Suggestion — worth considering:**
   - Missing edge case handling
   - Inefficient queries (N+1, missing index use)
   - Unclear naming that will confuse the next reader
   - Missing or wrong test coverage

   **🟢 Positive — call out what's done well**

4. **Output the review** as a markdown list grouped by severity. Be specific: include file names and line numbers. Do not repeat what the code already makes obvious.

5. If there are critical issues, ask whether to fix them before the PR is opened.
