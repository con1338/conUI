# Contributing to EldoUI

> **Fork-Hinweis:** Dieses Repository ist ein Fork von [EldoUI](https://github.com/Eldodeldo/EldoUI).
> Anders als bei Upstream liegt der Addon-Code hier, und Änderungen kommen per Pull Request (siehe unten).
> Geändert sind gegenüber dem Original die Einleitung, „Improve the Journal data“ und „Pull requests“.

Thanks for wanting to help. This fork holds EldoUI's addon code, its own additions (the German pack and the group board plugin) and its releases; EldoUI itself is developed upstream at [Eldodeldo/EldoUI](https://github.com/Eldodeldo/EldoUI). The most useful things you can do are below.

## Report a bug

Open a **Bug report**. In the game, type `/eui errors`, press **Report** on the error, press Ctrl+C, and paste the text into the form. It already contains your EldoUI version, the game build and the modules you use. Steps to make it happen help a lot.

## Suggest an idea

Open a **Feature request**. Say what you want to see and why. Screenshots or a short clip of another UI doing it are welcome.

## Improve the Journal data

Spotted a wrong drop, quest or boss in the Journal? Use EldoUI's [**Journal data** form](https://github.com/Eldodeldo/EldoUI/issues/new?template=journal-data.yml), as the Journal's own link in the game does: EldoUI maintains that data, not this fork. Each row is checked before it ships.

## Pull requests

Changes to this fork come in as pull requests against `main`. Every push runs the checks described in [tools/ci/README.md](../tools/ci/README.md) (Lua syntax, luacheck, TOC files, offline tests, German texts); a pull request is merged once they pass. A change to EldoUI's own behavior that EldoUI could use as well is worth an issue at [Eldodeldo/EldoUI](https://github.com/Eldodeldo/EldoUI/issues) too.

## Code of conduct

Be kind and constructive. See the [code of conduct](CODE_OF_CONDUCT.md).
