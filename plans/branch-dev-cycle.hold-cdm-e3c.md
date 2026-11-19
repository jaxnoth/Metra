# Hold: CDM E3c until Metra bite start works

Status: HOLD (2026-11-18)

Do not start ColleagueDataMover E3c (OIDC) as a branch bite until:

1. `.\metra.ps1 bite start -Name Metra -Bite <id>` succeeds on a clean Metra tree.
2. At least one Metra dogfood ship through `bite pack` → Bing approve → `bite ship` has landed.

Then register CDM `protectedBranches` / `ownerAffirmPaths` and run E3c as the first CDM branch bite.
