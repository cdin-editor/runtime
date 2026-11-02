# Git flow

`config.default` is the committed template. In a real Git checkout,
`scripts/init-git-flow.sh` copies it to `.gix/config` and runs `gix flow init`;
gix does not read the template directly. Commit the generated `.gix/config` so
every clone shares one branch model. See `docs/development/build-and-test.md`
and `CONTRIBUTING.md` for the branch model and commands.
