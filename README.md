# SaveTinker editors

Save editors for [SaveTinker](https://github.com/mrissaoussama/SaveTinker).

| Editor | Console |
|---|---|
| Mario Kart 7 | 3DS |
| Kid Icarus: Uprising | 3DS |
| Super Kirby Clash | Switch |
| Hyrule Warriors: Age of Calamity | Switch |
| JSON Save Editor (generic) | Any |

The game editors are ports of Marc Robledo's [savegame-editors](https://github.com/marcrobledo/savegame-editors) (MIT, see
`LICENSE-savegame-editors`), checked against the sample saves from that project.

The JSON Save Editor is generic: it is offered for every game and opens saves stored as JSON text (many Unity
games), changing values in place so the rest of the file stays byte for byte the same.

## Adding the repository in SaveTinker

Repositories tab, *Add repository*, then the raw URL of `repo/repo.json`:

```
https://raw.githubusercontent.com/mrissaoussama/savetinker-editors/main/repo/repo.json
```

The repository must be public for the console to download it.

## Updating

```sh
savetinker-cli validate editors/*
savetinker-cli pack editors repo --name "SaveTinker editors" --maintainer mrissaoussama
```
