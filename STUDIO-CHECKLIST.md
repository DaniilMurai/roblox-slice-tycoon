# Ручная проверка Slice Tycoon в Studio (T-17)

Всё, что проверяется headless — логика ядра, валидность конфига, сборка — уже зелёное
в CI. Здесь только то, что в терминале не проверяется принципиально: Roblox-рантайм,
DataStore, ввод игрока.

Заполняй колонку «Итог» прямо в этом файле и коммить: следующая сессия и аудитор
на стадии 8 читают его, а не переписку.

## Подготовка

1. Плагин Rojo в Studio: `rojo plugin install` в терминале либо Plugins → Manage Plugins.
2. **Опубликованное место обязательно.** На неопубликованном Place1 у DataModel нет
   `placeId`, Studio не пускает к DataStore, ProfileStore уходит в mock — AC-6 в такой
   среде непроверяем в принципе (проверено 2026-08-25 на срезе).
   Подойдёт experience «Slice Tycoon (dev)» со стадии 5 либо новая: File → Publish to
   Roblox As → Private.
3. В той же experience: Experience Settings → Security → **Enable Studio Access to
   API Services**. Признак успеха в Output:
   `[profilestore]: Roblox API services available - data will be saved`.
   Если вместо этого `Roblox API services unavailable` — дальше идти бессмысленно,
   сохранений не будет.
4. В корне тайтла: `rojo serve`, в Studio — Rojo → Connect.

## Чек-лист

| # | Проверка | Что должно быть | Итог |
|---|---|---|---|
| 1 | Rojo Connect | дерево тайтла доехало: Baseplate, SpawnLocation, `ServerScriptService.Server` | |
| 2 | Play | в Output `[slice-tycoon] server up: 1 upgrades, autosave 60s` и `[slice-tycoon] loaded <userId>: coins=0` | |
| 3 | HUD | панель слева сверху: `0 c`, ниже `+1.0/s · rebirth 0`, ниже кнопка `Conveyor lvl 0 · 25` и `Rebirth · 10000` | |
| 4 | Доход идёт | баланс растёт на 1 в секунду | |
| 5 | Отказ по деньгам | нажать `Conveyor` при балансе меньше 25 — кнопка на миг показывает `InsufficientFunds`, баланс не меняется | |
| 6 | Покупка | на 25+ монетах кнопка срабатывает: баланс −25, текст `Conveyor lvl 1 · 33`, доход `+2.0/s` | |
| 7 | Вторая покупка | списывается ровно 33 (кривая, а не фиксированная цена) | |
| 8 | **AC-6** | Stop → в Output `[slice-tycoon] saving <userId>: coins=<N> conveyor=<L>`. Снова Play → `loaded <userId>: coins=<тот же N> conveyor=<тот же L>`, HUD совпадает | |
| 9 | **AC-2** | не выходя, изменить в `src/server/init.server.luau` текст финального `print`, сохранить; Stop → Play — в Output новая строка | |
| 10 | Ребёрт недоступен | кнопка `Rebirth · 10000` серая, нажатие даёт `RebirthNotAffordable`, состояние не меняется | |

Расхождение чисел в `saving` и `loaded` — баг сохранения, а не округление.

## Чего здесь намеренно нет

- **Session-lock** (T-22). В Studio не воспроизводится: локальный тест Test → 2 Players
  выдаёт клиентам разные UserId, значит и ключи профилей разные, кику взяться неоткуда.
  Проверяется двумя реальными входами в опубликованную игру.
- **Геймпасс и множитель** (T-20, AC-7). `passes` в конфиге пусты: настоящий `gamepassId`
  появится, когда геймпасс будет создан на аккаунте.
- **Ребёрт целиком** (T-19). Порог 10 000 монет — это часы гринда; проверять его руками
  до пересчёта кривых симулятором бессмысленно.

## После прогона

Откатить правку из пункта 9. Если что-то из 1–10 не сошлось — это задача в
`docs/pipeline/tasks.md` фабрики, а не повод идти дальше.
