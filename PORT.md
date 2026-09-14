# The 1.12 build

This branch is the copy of this addon that runs on World of Warcraft **1.12.1**
(`## Interface: 11200`), taken off the Project Legacy client it was living on at
`C:\Users\Oleg\Games\Project Legacy\Interface\AddOns\WordHunterWoW`.

It is an orphan branch, with no ancestor on `main`, because it is a different
build of the same idea rather than a divergence from a commit. Merging it into
`main` is not the intention and would not make sense.

## Why it is here at all

Because until 2026-09-14 it was in exactly one place. An audit went looking and
found no repository, no branch, no tag, and `Vanilla.lua` -- a file this build
has and `main` does not -- in no commit of any branch. `Tools/build_release.ps1`
accepts only `retail` and `classic`, so nothing built it. Deleting that game
folder would have deleted the work.

## What it knows that main did not

`Compat.lua` here answers `CLASSIC` when `WOW_PROJECT_ID` is not a number, where
`main` answered `RETAIL`. 1.12 defines neither that global nor
`WOW_PROJECT_MAINLINE`, so `main` on this client called itself Retail and every
branch that read the answer took the wrong one.

That inversion has now been carried back to `main` in 1.19.3, with the build
number consulted first and a test that fails if the old answer returns. So this
branch is no longer the only place the fix exists -- but it is where it was
worked out.

## What is not decided

Whether this is maintained or frozen. It is a snapshot as it ran, unmodified.
