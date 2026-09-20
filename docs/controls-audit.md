# Audyt sterowania — Mark Zero

Stan na commit `3e2f46c`, 2026-09-20. Wszystko poniżej odczytane z kodu, nie z
komentarzy — w tym repo komentarze już raz opisywały dokładnie odwrotność tego, co
robi kod.

Gra jest **wyłącznie na pada**. Nie ma i nie będzie ścieżki na klawiaturę, więc każdy
wniosek jest oceniany przy założeniu, że pad to jedyne wejście.

---

## 1. Co jest teraz

Tabela bindów: `scripts/core/pad.gd:29` (`BUTTONS`) i `:57` (`GLYPH`).

### Iron Man — `scripts/suit/suit_pilot.gd`

| Wejście | Działanie | Rodzaj | Kod |
|---|---|---|---|
| Lewa gałka | chód / ciąg w locie | analog | `:224`, `:320` |
| Prawa gałka | obrót ciała | analog | `:216` |
| **✕** / D-pad ↑ | start z ziemi, wznoszenie | trzymanie | `:281`, `:320` |
| D-pad ↓ | opadanie | trzymanie | `:320` |
| **R2** | naddźwiękowa (poza Mark I) | analog | `:302` |
| **R1 / L1** | prawy / lewy repulsor | tap | `:449` |
| **□** | wieżyczka naramienna | trzymanie | `:488` |
| **△ + ○ razem** | laser z nadgarstka | **akord** | `:509` |
| **L3** | gadżet obronny | tap | `:270` |
| **R3** | gadżet zaczepny | tap | `:272` |
| Touchpad / OPTIONS | menu stroju | tap | `:250` |
| OPTIONS | pauza | tap | `pad.gd:46` |
| **L2** | **nic** | — | — |

### Spider-Man / Iron Spider — `scripts/spider/spider_pilot.gd`

| Wejście | Działanie | Rodzaj | Kod |
|---|---|---|---|
| Lewa gałka | ruch | analog | `:176` |
| Prawa gałka | obrót | analog | `:177` |
| **R2** | huśtanie na sieci | analog | `:433` |
| **✕** | skok, doskok w powietrzu, odbicie od ściany | tap | `:311`, `:328`, `:332` |
| D-pad ↑ / ↓ | skracanie / wypuszczanie liny | trzymanie | `:195` |
| **R1 / L1** | strzał siecią z prawej / lewej | tap | `:248` |
| **R1 + L1 razem** | chwyt przedmiotu i obrót | **akord** | `:214` |
| **△** | uderzenie z doskoku | tap | `:342` |
| **□** | cios (tap) / wybicie w powietrze (trzymanie) | oba | `:343` |
| **○** | unik | tap | `:345` |
| **R3** | wyrzut nóg Iron Spidera | tap | `:370` |
| Touchpad | menu | tap | `:189` |
| **L2, L3** | **nic** | — | — |

---

## 2. Błędy, nie kwestie gustu

### 2.1 OPTIONS robi dwie rzeczy naraz — **do naprawy**

```
"menu":  [JOY_BUTTON_TOUCHPAD, JOY_BUTTON_MISC1, JOY_BUTTON_START]
"pause": [JOY_BUTTON_START]
```
`pad.gd:42` i `:46`. START jest w obu. Jedno wciśnięcie OPTIONS wyzwala **i** menu
stroju, **i** pauzę. START trafił do `menu` jako zapasowe wejście, gdy nie działał
touchpad — ale to było zanim powstała pauza, i nikt go potem nie zdjął.

**Poprawka:** usunąć `JOY_BUTTON_START` z `"menu"`. Touchpad (plus MISC1 dla sterowników,
które tak go raportują) zostaje menu stroju, OPTIONS zostaje wyłącznie pauzą. To jest
też konwencja PlayStation: Sony opisuje OPTIONS jako „displays the options menu" i tak
działa każda gra, w którą Jurek grał.

### 2.2 Lista sterowania w grze wymienia trzy rzeczy, których nie ma — **do naprawy**

`scripts/ui/menu.gd:334` rysuje graczowi listę. Są na niej:

- **AIM (SLOWS TIME) — L2.** `Pad.retro()` istnieje (`pad.gd:147`), ale **nie czyta go
  żaden plik w grze**. L2 jest martwe na obu postaciach. Jurek prosił wprost: „L2 to
  celowanie".
- **INTERACT — △.** Akcja `interact` jest zbindowana, ale jedynym miejscem, które ją
  czyta, jest akord na laser. Samo △ nie robi nic u Iron Mana.
- **SUIT ON / OFF — ○.** To samo: `suit_toggle` czyta tylko akord. Zdjęcie stroju,
  o które Jurek prosił osobno, nie jest zaimplementowane.

Ekran, który uczy sterowania, jest jednym z dwóch miejsc, gdzie gracz może się go
nauczyć. Wypisywanie na nim akcji, które nie istnieją, jest gorsze niż brak listy.

### 2.3 Prompty dla Spider-Mana wypisują `?` — **do naprawy**

`GLYPH` (`pad.gd:57`) nie ma wpisów dla `heavy`, `light` ani `dodge`, a `glyph()`
zwraca `"?"` dla nieznanego klucza (`pad.gd:161`). Każdy prompt dla ciosu, uderzenia
z doskoku albo uniku wyrenderuje znak zapytania. Komentarz nad tabelą mówi, że glify
i bindy trzymane są w jednym pliku właśnie po to, żeby się nie rozjechały — i mimo to
się rozjechały.

### 2.4 Laser na akordzie △+○ — **do naprawy**

`suit_pilot.gd:509`. Dwa problemy naraz:

1. **To akord.** Wytyczne dostępności Xboxa (XAG 107) mówią wprost: „Avoid introducing
   mechanics where a player is required to press two buttons simultaneously". Insomniac
   w Spider-Manie 2 wycofał się z akordów z jedynki (L2+R2, L1+R1) na rzecz
   **modyfikatora z przyciskiem twarzy** — L1 trzymane + ✕/○/□/△ to zdolność, R1
   trzymane + przycisk to gadżet. Akordy z jedynki zostały, ale obok nich pojawiły się
   skróty na D-padzie, żeby „collapse complex multi-button actions" do jednego
   wciśnięcia.
2. **Oba przyciski są reklamowane jako coś innego.** Gracz czyta na liście, że △ to
   INTERACT, a ○ to SUIT ON / OFF, więc trzymając je razem spodziewa się czegokolwiek
   poza laserem.

---

## 3. Rzeczy do przemyślenia, nie błędy

### 3.1 L3 i R3 w walce

Iron Man ma oba gadżety na wciśnięciach gałek, Iron Spider ma na R3 nogi. Konwencja
w branży: **kliknięcia gałek trzymają tryby ruchu, nie ataki.** Anthem ma na L3 lot,
na R3 zawis; Marvel's Avengers przełącza Iron Manowi lot na L3; Warframe ma na L3
dopalacz. DMC5 trzyma L3/R3 wyłącznie przy kamerze i celu — żadnego ataku.

XAG 107 dopuszcza kliknięcie gałki, o ile **da się je przemapować** i **nie trzeba go
trzymać**. Nasze są tapami, nie trzymaniami, więc pod tym względem są w porządku. Nie
da się ich jednak przemapować, bo gra nie ma remapowania w ogóle.

**Ocena:** obronne, ale to najsłabszy punkt układu. Anthem — najbliższy odpowiednik —
wysłał lot na L3 *i* opcję hold/toggle do tego, bo samo L3 okazało się za mało.
Warframe zapakował na L3 dopalacz i blink naraz i gracze do dziś zgłaszają, że im się
mylą. To jest ostrzeżenie, nie zakaz.

### 3.2 Akord R1+L1 u Spider-Mana

`spider_pilot.gd:214`. To dokładnie ten sam akord, który Insomniac miał w Spider-Manie 1
na rzucanie przedmiotami, więc ma precedens — ale w dwójce dostał alternatywę na
jedno wciśnięcie. Warto dołożyć drugą drogę, nie usuwać obecnej: kto już się nauczył
dwóch rąk, niech zostanie przy dwóch rękach.

### 3.3 Czego gracz nie odkryje sam

Lista w menu stroju (`menu.gd:334`) **nie wymienia**: R1/L1 jako repulsorów w locie
(są, ale opisane bez kontekstu), L3/R3 jako gadżetów, akordu na laser, ani niczego
Spider-Mana — Spider-Man nie ma własnej listy w ogóle. Najbardziej złożone wejście
w grze (akord) nie jest pokazane nigdzie.

Wytyczna [Game Accessibility Guidelines — „Indicate / allow reminder of controls during
gameplay"](https://gameaccessibilityguidelines.com/indicate-allow-reminder-of-controls-during-gameplay/)
stawia to jako wymaganie, nie polish: gracz musi móc **wrócić** do listy w trakcie gry,
nie tylko zobaczyć ją raz w tutorialu. Spider-Man 2 trzyma pełny układ w menu pauzy pod
„Controller Layout".

---

## 4. Proponowany układ

Kolejność wg tego, ile zmienia. Każda zmiana mówi, co wypycha i gdzie to ląduje.

### Musi się zmienić

| # | Zmiana | Dlaczego | Koszt |
|---|---|---|---|
| 1 | START wypada z `"menu"` | OPTIONS odpala dziś pauzę i menu stroju naraz | żaden — touchpad i MISC1 zostają |
| 2 | **L2 (trzymane) = celowanie** na obu postaciach | Jurek o to prosił, glif już to obiecuje, a L2 jest puste; triggery w każdej porównywanej grze trzymają celowanie i ogień | żaden — L2 nic nie robi |
| 3 | **Laser z nadgarstka na △**, akord znika | △ jest wolne (INTERACT nie istnieje), a akord łamie XAG 107 i kłóci się z tym, co gracz przeczytał na liście | INTERACT wypada z listy sterowania — i tak nic nie robił |
| 4 | **○ = zdjęcie stroju** naprawdę zaimplementowane | już jest na liście jako SUIT ON / OFF, a Jurek prosił o to osobno | ○ przestaje być częścią akordu, bo akordu nie ma |
| 5 | `GLYPH` dostaje `heavy`, `light`, `dodge`, `ui_back_pad` | prompty Spider-Mana rysują dziś `?` | żaden |
| 6 | Lista sterowania **generowana z `BUTTONS`/`GLYPH`**, osobna dla każdej postaci | dziś jest pisana ręcznie i już kłamie w trzech miejscach; XAG 107 wymaga, żeby prompty odpowiadały realnym bindom | trochę kodu raz |

### Warto rozważyć

| # | Zmiana | Dlaczego | Koszt |
|---|---|---|---|
| 7 | **L2 + R1** jako druga droga do chwytu przedmiotu u Spider-Mana | jedno wciśnięcie zamiast akordu, obok istniejącego | R1+L1 zostaje dla tych, którzy się nauczyli |
| 8 | Gadżety na **L2 (trzymane) + ✕/○/□/△** zamiast L3/R3 | wzorzec ze Spider-Mana 2; zdejmuje ataki z gałek i otwiera miejsce na cztery gadżety zamiast dwóch | L2 robiłoby dwie rzeczy (celowanie i modyfikator) — do rozstrzygnięcia dopiero, gdy gadżetów będzie więcej niż dwa |
| 9 | Remapowanie w opcjach | GAG stawia to na poziomie **BASIC** — najniższym z możliwych | ekran opcji, który i tak jest dziś zaślepką |
| 10 | Ekran z pełnym układem pada w **pauzie**, nie tylko w menu stroju | menu stroju jest Iron Mana; Spider-Man nie ma dziś gdzie tego przeczytać | jeden ekran |

### Czego NIE ruszać

- **Latanie na gałkach, nie na triggerze.** Jurek odrzucił to wprost: „R2 do
  naddźwiękowej, a latanie to po prostu gałki i ✕ do góry". Konwencja też jest po jego
  stronie — Anthem prowadzi lot lewą gałką, Avengers wznosi Iron Mana na ✕.
- **R2 jako naddźwiękowa u Iron Mana i huśtanie u Spider-Mana.** Oba to „trzymaj, żeby
  jechać szybciej", czyli dokładnie to, co R2 robi w Spider-Manie i w Astro Botcie.
- **✕ jako skok i wznoszenie.** Zgadza się z Anthemem, Avengers i Astro Botem —
  a Astro Bot pokazuje, że zlepienie jednego czasownika ruchu z jednym ofensywnym na
  jednym przycisku (tam: unoszenie i laser w stopach) jest wzorcem, który się sprawdza,
  nie przeciążeniem.

---

## 5. Źródła

- [Xbox Accessibility Guideline 107 — Input](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/107) — zakaz wymaganych akordów, wymóg remapowania, wymóg zgodności promptów z bindami
- [Game Accessibility Guidelines — remappable controls](https://gameaccessibilityguidelines.com/allow-controls-to-be-remapped-reconfigured/) i [reminder of controls during gameplay](https://gameaccessibilityguidelines.com/indicate-allow-reminder-of-controls-during-gameplay/)
- [EA — Controlling Your Javelin on PS4 (Anthem)](https://www.ea.com/able/news/javelin-controls-ps4) — jedyne oficjalne źródło na układ lotu w grze tego typu
- [SpecialEffect — Marvel's Spider-Man controls walkthrough](https://gameaccess.info/marvels-spider-man-miles-morales-controls-walkthrough-video/) — układ spisany z ekranu samej gry
- [Outsider Gaming — Spider-Man 2 controls (PS5)](https://outsidergaming.com/spider-man-2-complete-controls-guide-for-ps5/) — modyfikator L1/R1 + przycisk twarzy zamiast akordów
- [PlayStation — PS5 button functions](https://www.playstation.com/en-us/support/hardware/ps5-button-functions/) — ✕ zatwierdza, ○ anuluje, OPTIONS otwiera menu
- [Game8 — Marvel's Avengers, umiejętność Flight](https://game8.co/games/Marvels-Avengers/archives/295141) — lot Iron Mana na L3, zawis na trzymanym ✕

Dwie uwagi o jakości źródeł: **Iron Man VR nie jest punktem odniesienia dla DualShocka** —
wymaga dwóch PS Move i nie obsługuje pada w ogóle. A dla Marvel's Avengers nie istnieje
żadna oficjalna lista sterowania; przewodniki fanowskie przeczą sobie w niemal każdym
wierszu, więc wiarygodne są tam tylko wiersze o locie.
