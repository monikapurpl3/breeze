# Translating Breeze

The messages live in `parts/<group>_<lang>.arb`, one file per screen group and
language; `python3 tool/l10n_merge.py` assembles them into `app_<lang>.arb`
and refuses if any language lacks a key, has an extra one, or changes a
message's `{placeholders}`. English (`*_en.arb`) is the template and the only
file with `@descriptions`. Shared words -- modes, fan speeds, flaps, the
common buttons -- are in `parts/common_*.arb`; use them rather than defining
your own.

## Languages

| Code | Language | Script | Notes |
|---|---|---|---|
| `en` | English | | the template |
| `hr` | Croatian | Latin | |
| `sr` | Serbian | **Cyrillic** | ekavian, as in Serbia: грејање, не гријање |
| `sl` | Slovenian | Latin | dual forms in plurals (`two`) |
| `fr` | French | Latin | |
| `it` | Italian | Latin | |
| `zh` | Chinese | **Simplified** (Mandarin, as in mainland China) | no spaces between words; full-width punctuation (，。：！？（）) |

## Tone

Plain, short and friendly, as the English is. Address the reader directly:

- **Croatian, Serbian, Slovenian, Italian:** informal (ti / ти / ti / tu).
- **French:** vous, as French apps do.
- **Chinese:** 你.

Keep sentence case as the English has it: lower-case labels stay lower case
where the language allows (mode names, fan speeds), and headings and buttons
take a capital only on the first word. Short over literal: a button has the
room of its English word, not of a sentence. Where English uses "--" or a
dash for an aside, use what the language normally uses (a comma or
parentheses are fine).

## Never translated

**Breeze**, **Breeze Core**, **Nerd** (the screen's name; "Nerd screen" →
"Nerd zaslon", "écran Nerd", "Nerd 页面"), **Midea**, **NetHome Plus**,
**MSmartHome**, **Android Auto**, **TalkBack**, **SSE**, **API**, **JSON**,
**IP**, **LAN**, **Wi-Fi**, **Ed25519**, **v1/v2**, error codes, units (°C, °F,
ms, KiB), and anything a person types or reads off another screen
(addresses, keys, codes).

## Terms

| English | hr | sr | sl | fr | it | zh |
|---|---|---|---|---|---|---|
| air conditioner / unit | klima-uređaj / uređaj | клима-уређај / уређај | klimatska naprava / naprava | climatiseur | condizionatore | 空调 |
| server | poslužitelj | сервер | strežnik | serveur | server | 服务器 |
| pair, pairing | upariti, uparivanje | упарити, упаривање | seznaniti, seznanjanje | appairer, appairage | abbinare, abbinamento | 配对 |
| pairing code | kod za uparivanje | код за упаривање | koda za seznanjanje | code d'appairage | codice di abbinamento | 配对码 |
| approve | odobriti | одобрити | odobriti | approuver | approvare | 批准 |
| device (a phone, a client) | uređaj | уређај | naprava | appareil | dispositivo | 设备 |
| target temperature | ciljana temperatura | циљна температура | ciljna temperatura | température cible | temperatura impostata | 目标温度 |
| indoor / outdoor | unutra / vani | унутра / напољу | notri / zunaj | intérieur / extérieur | interna / esterna | 室内 / 室外 |
| mode | način rada | режим | način | mode | modalità | 模式 |
| fan speed | brzina ventilatora | брзина вентилатора | hitrost ventilatorja | vitesse de ventilation | velocità della ventola | 风速 |
| flap (swing) | lamela | ламела | loputa | volet | aletta | 摆风 |
| sleep timer (turn off after) | isključivanje nakon | искључивање након | izklop čez | arrêt programmé | spegnimento programmato | 定时关机 |
| scheduled start (turn on at) | uključivanje u | укључивање у | vklop ob | démarrage programmé | accensione programmata | 定时开机 |
| program | program | програм | program | programme | programma | 程序 |
| favourite (a saved scene) | omiljeno | омиљено | priljubljeno | favori | preferito | 收藏 |
| schedule | raspored | распоред | urnik | planning | programmazione | 定时计划 |
| curve (temperature over a day) | krivulja | крива | krivulja | courbe | curva | 曲线 |
| scene (a saved set of settings) | scena | сцена | prizor | scène | scena | 场景 |
| diagnostics | dijagnostika | дијагностика | diagnostika | diagnostic | diagnostica | 诊断 |
| settings | postavke | подешавања | nastavitve | réglages | impostazioni | 设置 |
| refused (the unit did not accept) | odbijeno | одбијено | zavrnjeno | refusé | rifiutato | 被拒绝 |
| online / offline | dostupan / izvan mreže | доступан / ван мреже | povezan / brez povezave | en ligne / hors ligne | online / offline | 在线 / 离线 |
| live updates | ažuriranja uživo | ажурирања уживо | sprotne posodobitve | mises à jour en direct | aggiornamenti in tempo reale | 实时更新 |
| fallback address | rezervna adresa | резервна адреса | nadomestni naslov | adresse de secours | indirizzo di riserva | 备用地址 |
| home-screen widget | widget na početnom zaslonu | виџет на почетном екрану | pripomoček na začetnem zaslonu | widget d'écran d'accueil | widget della schermata Home | 桌面小部件 |

## Messages with numbers

Use ICU plurals with every category the language has, never "1 unit(s)":

- **en, it:** one, other. **fr:** one (0 and 1), other.
- **hr, sr:** one, few, other (1 sat, 2 sata, 5 sati; 21 sat).
- **sl:** one, two, few, other (1 ura, 2 uri, 3 ure, 5 ur).
- **zh:** other only.

```json
"unitsCount": "{count, plural, =0{no units} one{{count} unit} other{{count} units}}"
```

Numbers with decimals go through `fmtTemp` or `fmtDecimal`, which use the
language's own separator (23,5 in hr, sr, sl, fr and it); never format them
into a message yourself.
