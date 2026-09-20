# Mark Zero — audyt sterowania padem

Data: 2026-09-20 · Godot 4.6.2 · kod: `Mark Zero/game`
Zakres lektury: `scripts/core/pad.gd`, `scripts/suit/suit_pilot.gd`, `scripts/suit/gadgets.gd`,
`scripts/spider/spider_pilot.gd`, `scripts/spider/spider_combat.gd`, `scripts/ui/hud.gd`,
`scripts/ui/visor.gd`, `scripts/ui/menu.gd`, `scripts/ui/main_menu.gd`, `scripts/ui/pause_menu.gd`,
`scripts/ui/button_prompt.gd`, `scripts/world/prop.gd`, `scripts/world/arena.gd`, `project.godot`.

**To jest audyt. Nie zmieniono ani jednej linii kodu.** Każde zdanie o tym, co gra robi
teraz, ma odnośnik `plik:linia`. Komentarze w tym repo bywają sprzeczne z kodem — gdzie tak
jest, opisuję kod, a komentarz wymieniam jako osobny problem.

> Ten plik **zastępuje** wcześniejszy audyt z commita `f57cff5`, pisany pod stan kodu
> `3e2f46c`. Tamta wersja jest w historii gita (`git show f57cff5:docs/controls-audit.md`).
> Zdążyła się zdezaktualizować w co najmniej jednym miejscu: podawała, że L2 u Iron Mana nie
> robi nic, podczas gdy dziś to celowanie ze spowolnieniem czasu (`suit_pilot.gd:225, 307`).

---

## 1. Stan faktyczny — pełny mapping

### Warstwa wspólna (`pad.gd`)

`BUTTONS` mapuje nazwę akcji na **listę** indeksów przycisków (`pad.gd:28-50`); `GLYPH` to
osobna tabela napisów pokazywanych graczowi (`pad.gd:58-64`). Deadzone 0.18 z reskalowaniem
(`pad.gd:69, 112-118`), krzywa looka kwadratowa (`pad.gd:72, 130-137`), triggery czytane
analogowo z progiem 0.06 (`pad.gd:74, 139-151`).

W `project.godot` **nie ma sekcji `[input]`**, więc obowiązują wbudowane akcje Godota.
Sprawdziłem je uruchamiając pusty projekt na tym samym silniku (4.6.2):

```
ui_accept => ["Enter", "Kp Enter", "Space"]
ui_cancel => ["Escape"]
ui_up     => ["Up", "D-pad Up", "Left Stick Y -1.0"]
ui_down   => ["Down", "D-pad Down", "Left Stick Y +1.0"]
```

Czyli `ui_accept`/`ui_cancel` **nie mają** bindów padowych — i dobrze, bo inaczej ○ (dodge)
pauzowałoby grę. Ale `ui_up`/`ui_down` **mają** D-pad i lewą gałkę, co ma znaczenie w menu.

### IRON MAN — stan obecny

| Input | Co robi | Tap / hold / kombinacja | Źródło |
|---|---|---|---|
| L STICK | na ziemi: chód (obie osie). W powietrzu: oś Y = ciąg do przodu / retro, oś X = ślizg boczny | analog, ciągły | `pad.gd:126`, `suit_pilot.gd:224, 285, 309-313` |
| L STICK puszczony w locie | AUTO-HAMOWANIE (retro burn, do 0.55 mocy) | automat, bez przycisku | `suit_pilot.gd:293-300` |
| R STICK | obrót ciała; spowalniany „tarciem" aim-assistu na celu | analog, ciągły | `suit_pilot.gd:216-220` |
| R2 (analog, próg 0.35) | SUPERSONIC boost; zablokowany na mk1 | hold | `suit_pilot.gd:302` |
| L2 (analog, próg 0.25) | AIM — `Engine.time_scale = 0.22` | hold | `suit_pilot.gd:225, 307` |
| R1 | prawy repulsor | **tap** (just_pressed + bufor 0.22 s) | `suit_pilot.gd:449-459`, `pad.gd:29` |
| L1 | lewy repulsor | **tap** | jw., `pad.gd:30` |
| □ SQUARE | shoulder turret — wysuwa się ~0.33 s i strzela póki trzymasz | **hold** | `suit_pilot.gd:488-497`, `pad.gd:31` |
| ✕ CROSS **lub** D-PAD ↑ | kopniak startowy z ziemi, potem wznoszenie; trzymanie = „nie jestem pieszo" | tap = start, hold = wznoszenie | `suit_pilot.gd:278-283, 320`, `pad.gd:39` |
| D-PAD ↓ | opadanie | hold | `suit_pilot.gd:320`, `pad.gd:42` |
| △ + ○ **równocześnie** | wrist laser (tylko gdy naładowany) | **hold obu naraz** | `suit_pilot.gd:509`, `pad.gd:43-44` |
| L3 | gadget defensywny danego stroju (BULWARK / STABILISERS / CHAFF / PHASE / NANO SHIELD) | tap | `suit_pilot.gd:270-271`, `gadgets.gd:15-26, 103` |
| R3 | gadget ofensywny (SCRAP BURST / SONIC PULSE / MICRO-SALVO / SHATTER / NANO BLADE) | tap | `suit_pilot.gd:272-273`, `gadgets.gd:15-26` |
| TOUCHPAD / MISC1 / OPTIONS | menu stroju | tap | `pad.gd:38`, `suit_pilot.gd:250` |
| OPTIONS | pause menu — **i równocześnie** menu stroju, patrz wyżej | tap | `pad.gd:47`, `pause_menu.gd:33`, `arena.gd:34-36` |
| △ samo | **nic** (akcja `interact` zadeklarowana, nikt jej nie czyta) | — | `pad.gd:43` |
| ○ samo | **nic** (akcja `suit_toggle` zadeklarowana, nikt jej nie czyta) | — | `pad.gd:44` |

Hover nie ma przycisku — stabilizator trzyma pozycję sam, gdy puścisz gałkę
(`flight_model.gd:385-411`). Akcja nazywa się `hover`, ale robi gadget.

### SPIDER-MAN / IRON SPIDER — stan obecny

| Input | Co robi | Tap / hold / kombinacja | Źródło |
|---|---|---|---|
| L STICK | chód / sterowanie huśtawką; **zablokowany** gdy trwa cios lub dodge | analog | `spider_pilot.gd:176, 325-327` |
| R STICK | look | analog | `spider_pilot.gd:177` |
| R2 (próg 0.35) | web swing — trzymasz, wisisz; puszczasz, spadasz. Sam wybiera rękę | **hold** | `spider_pilot.gd:433-436` |
| L2 (próg 0.35) | AIM (`time_scale = 0.35`) **ORAZ w tej samej klatce** wall-run | hold, dwie rzeczy naraz | `spider_pilot.gd:201-202` i `333` |
| R1 | prawa sieć | tap (bufor 0.22 s) | `spider_pilot.gd:248` |
| L1 | lewa sieć | tap | jw. |
| L1 + R1 **równocześnie** | złap przedmiot, zacznij się kręcić; puszczenie = rzut w najbliższego wroga | **hold obu naraz** | `spider_pilot.gd:214, 219-241` |
| □ SQUARE | tap = mocny cios (**odpala się przy PUSZCZENIU**), hold ≥0.22 s = launcher | tap / hold | `spider_combat.gd:121-136` |
| △ TRIANGLE | lekki atak / web-strike zip | tap, odpala natychmiast | `spider_pilot.gd:342`, `spider_combat.gd:137` |
| ○ CIRCLE | dodge, kierunek z lewej gałki (w tył = backflip) | tap | `spider_pilot.gd:345`, `spider_combat.gd:117, 216-231` |
| ✕ CROSS **lub** D-PAD ↑ | skok z ziemi / **air hop ×2** / odbicie od ściany / **przyciąganie liny** | tap | `spider_pilot.gd:195, 311, 328, 332` |
| D-PAD ↓ | wypuszczanie liny | hold | `spider_pilot.gd:195` |
| R3 | wypad czterech nóg (atak obszarowy, też do tyłu) | tap | `spider_pilot.gd:370-374` |
| L3 | **nic** | — | brak czytelnika |
| TOUCHPAD / MISC1 / OPTIONS | menu | tap | `spider_pilot.gd:189` |

---

## 2. Jak to robią gry, które to mają dobrze zrobione

### Marvel's Spider-Man (PS4/PS5)

Najlepsze źródło to [GameAccess by SpecialEffect — nagranie ekranu sterowania Miles Morales](https://gameaccess.info/marvels-spider-man-miles-morales-controls-walkthrough-video/)
(fundacja filmuje **własny ekran sterowania gry**; Insomniac nie publikuje listy).

| Input | Funkcja |
|---|---|
| **R2 (hold)** | **web-swing, free-run, parkour, wall-run — CAŁA trawersacja na jednym triggerze. Nie ma osobnego sprintu.** |
| ✕ | skok / point launch · **R2 + ✕** = wysoki wyskok z huśtawki |
| ○ | dodge |
| □ | atak podstawowy (tap = combo, hold = launcher) |
| **△** | **web-strike (tap) / web-yank, web-throw (hold)** |
| **L1 (hold)** | koło gadżetów |
| R1 (tap) | strzał wybranym gadżetem / oplatanie siecią |
| **L1 + R1** | podnieś i rzuć przedmiotem z otoczenia |
| L2 (hold) | celowanie |
| L2 + R2 | zip do punktu |
| L3 | perch na krawędzi / dive w powietrzu |
| R3 | pokaż cel / skan |
| D-pad ↓ / ↑ | leczenie / aparat |
| TOUCHPAD naciśnięty | mapa · OPTIONS: pauza |

Potwierdzenie (gorsze źródła, miejscami sprzeczne): [Outsider Gaming](https://outsidergaming.com/marvels-spider-man-complete-controls-guide-for-ps4/),
[Magic Game World](https://www.magicgameworld.com/marvels-spider-man-ps4-controls/).

Dwie rzeczy warte zapamiętania: **wszystko, co jest „poruszaniem się szybko", siedzi na R2**,
a L3/R3 dostają funkcje, których nigdy nie używasz w środku walki (perch, marker).

### Marvel's Spider-Man 2 (PS5) — jak Insomniac rozwiązał „za dużo czasowników"

To jest najważniejszy wzorzec w całym tym raporcie.

| Input | Funkcja |
|---|---|
| R2 (hold) | swing / parkour |
| △ | web-strike · **hold w powietrzu = Web Wings** |
| **L1 tap = parry · L1 HOLD + przycisk twarzy = jedna z 4 umiejętności** | |
| **R1 tap = sieć · R1 HOLD + przycisk twarzy = jeden z 4 gadżetów** | |
| L2 | celowanie |
| L3 / R3 | perch-dive / skan (L3+R3 = Symbiote Surge) |
| D-pad ←/→ | **skróty przypisane przez gracza** |

Źródła: [Outsider Gaming SM2](https://outsidergaming.com/spider-man-2-complete-controls-guide-for-ps5/),
[Shacknews](https://www.shacknews.com/article/137455/controls-moves-spider-man-2).

Zamiast dokładać kombinacje i kliknięcia gałek, Insomniac zrobił **radial: przytrzymany bumper
plus przycisk twarzy**. Osiem umiejętności na dwóch przyciskach, zero akordów.
Do tego oficjalnie ([PlayStation Blog, 2023-09-28](https://blog.playstation.com/2023/09/28/marvels-spider-man-2-builds-on-accessibility-in-previous-titles-and-introduces-new-features/))
dorzucili profile pozwalające **przypisać dwie komendy do jednego przycisku**, zamianę
„repeated button presses → holds" oraz skróty na D-padzie **wprost dla graczy, którym trudno
naciskać kilka przycisków naraz**. Czyli sam autor `L1+R1` uznał ten wzorzec za problem
i dał z niego wyjście.
Pełna lista sterowania siedzi u nich **w menu pauzy pod „Controller Layout"**.

### Marvel's Avengers — Iron Man

✕ (krótkie przytrzymanie / w powietrzu) = **hover**, ✕ trzymane = wznoszenie, **○ trzymane =
opadanie**, **L3 w powietrzu = przełącznik trybu lotu**, lewa gałka do przodu = prędkość,
prawa steruje. Nie ma throttle'a na triggerze.
Źródło: [Game8 — Flight skill](https://game8.co/games/Marvels-Avengers/archives/295141),
[Gamer Tweak](https://gamertweak.com/marvels-avengers-iron-man-guide/).

**To jest dokładnie to, co Jurek wymyślił sam**: ✕ do góry, gałki sterują, trigger nie jest
throttle'em. Kierunek Mark Zero jest tu zgodny z najbliższym możliwym punktem odniesienia.
Różnica: tam opadanie jest na ○, żeby kciuk został przy gałkach — tu jest na D-padzie.

> Uwaga o jakości: poza wierszami o locie źródła o Avengers **sprzeczają się ze sobą**
> (sprint na L3 vs L2, repulsor na L2+R3 vs D-pad → vs R2). Crystal Dynamics nie opublikowało
> listy sterowania. Ufać tylko wierszom o locie.

### Marvel's Iron Man VR — **nie jest punktem odniesienia dla pada**

[Oficjalna strona PlayStation](https://www.playstation.com/en-us/games/marvels-iron-man-vr/):
gra **wymaga dwóch kontrolerów PS Move** i nie obsługuje DualShocka. Lot to trzymanie obu
triggerów i kierowanie dłońmi; unibeam to trzymanie ✕ na jednym Move i ○ na drugim
([Push Square](https://www.pushsquare.com/guides/marvels-iron-man-vr-tips-and-tricks-for-beginners)).
Jedyna rzecz stąd użyteczna dla nas to ostrzeżenie: recenzent [UploadVR](https://www.uploadvr.com/iron-man-vr-review/)
po **dziesięciu godzinach** dalej mylił obrót, cios i hover, bo wszystkie siedziały obok siebie
na jednej ręce. Upychanie sąsiadujących czasowników trybu na jednym kciuku nie przestaje boleć
po przyzwyczajeniu.

### Anthem — źródło oficjalne, EA

[EA — „Controlling Your Javelin on PlayStation 4"](https://www.ea.com/able/news/javelin-controls-ps4):

| Input | Funkcja |
|---|---|
| **L3** | sprint na ziemi / **LOT w powietrzu** |
| **R3** | **hover** |
| ✕ | skok / **wyjście z lotu** |
| Lewa gałka | ruch; **throttle i przechylenie w locie** |
| L2 / R2 | celowanie / ogień |
| **L1 / R1 / L1+R1** | **umiejętność 1 / 2 / 3** |
| D-pad ↑ | ultimate |
| ○ (+ prawa gałka) | unik, też w powietrzu |

Lot na gałce, nie na triggerze — znowu zgodne z decyzją Jurka. I rzecz kluczowa:
[EA Able — Anthem accessibility](https://www.ea.com/able/resources/anthem/ps4/features)
pokazuje, że tryb lotu ma **przełącznik hold/toggle**, tak samo sprint i zoom, plus osobny
suwak czułości w locie. Czyli gra, która postawiła lot na kliku gałki, **musiała** dołożyć
opcję, żeby nie trzeba było tego trzymać.

> Sprzeczność: [Gamepressure](https://www.gamepressure.com/anthem/controls/z1bd56) podaje
> zupełnie inną tabelę niż EA. Ufać EA.

### Warframe / Archwing

Ogólny layout: [oficjalna strona Digital Extremes](https://support.warframe.com/hc/en-us/articles/203730010-PlayStation-Button-Assignments)
— L2/R2 celowanie i ogień, **cztery umiejętności na czterech przesunięciach po touchpadzie**,
OPTIONS → Controls → pełny remapping.
Archwing ([wiki](https://wiki.warframe.com/w/Archwing_Maneuvers), tylko wiki): **L3 =
dopalacz, podwójne L3 = blink**, ✕ = w górę, L1 = w dół. Nie ma hovera ani hamulca.
Gracze zgłaszają mylne odpalenia, bo L3 dźwiga i dopalacz, i blink, a L1 opadanie
([forum](https://forums.warframe.com/topic/1196478-archwing-controls-ps4controller/), niska jakość).
To jest ten sam rodzaj błędu co **D2** niżej: dwie funkcje na jednym przycisku, rozróżniane
kontekstem, którego gracz nie widzi.

### Devil May Cry 5

△ = melee, □ = broń palna, ✕ = skok, R1 hold = lock-on, ○ = umiejętność charakterystyczna
postaci, L1 = Devil Trigger, **L3 = zmiana celu, R3 = wyśrodkowanie kamery**, TOUCHPAD = taunt,
D-pad = wybór stylu (Dante). Pełny remapping w opcjach.
Źródła: [Gamer Guides](https://www.gamerguides.com/devil-may-cry-5/guide/the-basics/gameplay/controls),
[GameAccess by SpecialEffect](https://gameaccess.info/devil-may-cry-5-controls-walkthrough/).

Wniosek strukturalny: **przyciski twarzy = czasowniki ataku + skok + special postaci;
bumpery i triggery = stany modalne; L3/R3 = wyłącznie kamera, nigdy atak; touchpad = rzecz
bez konsekwencji.**

### Astro Bot (PS5, 2024)

✕ = skok, **trzymane w powietrzu = hover ~2 s**; □ = cios, hold = wirujący atak; L2/R2 zależne
od power-upu; pod wodą ○ opada, ✕ wznosi.
Źródła: [Shacknews](https://www.shacknews.com/article/141300/controls-moves-abilities-astro-bot),
[Game8](https://game8.co/games/Astro-Bot/archives/472018).

Ważna korekta do założenia z briefu: **laser Astro nie jest na triggerze.** Hover i laser to
ten sam input — trzymane ✕ odpala dysze, które jednocześnie unoszą i ranią to, co pod spodem.
Oficjalny [PS Blog](https://blog.playstation.com/2024/06/12/astro-bot-hands-on-report/) nazywa
to „versatile laser-hover ability". Czyli **zlepienie jednego czasownika ruchu z jednym
czasownikiem ataku na jednym przycisku jest wzorcem, który się sprzedał i spodobał** — problem
zaczyna się dopiero przy sąsiadujących czasownikach **zmiany trybu**, jak w Iron Man VR.

### Ergonomia — co mówią źródła, nie ja

Podział kontrolera na trzy strefy:

- **Primary** — przyciski twarzy i gałki: akcje o wysokiej częstotliwości (skok, strzał, ruch).
- **Secondary** — bumpery i triggery: akcje ciągłe, analogowe, taktyczne (celowanie, gaz, blok).
- **Tertiary** — **D-pad, kliknięcia gałek (L3/R3) i przyciski środkowe: akcje okazjonalne** —
  mapa, zmiana broni, latarka.

[How Controller Ergonomics Guide Game Button Mapping](https://salivity.github.io/game-development/article/how-controller-ergonomics-guide-game-button-mapping)
(blog, nie dokument oficjalny — traktować jako uporządkowanie konwencji, nie dowód).
Ten sam tekst: współczesne projekty świadomie unikają **claw grip** (podwijania palców
wskazujących do przycisków twarzy przy kciukach na gałkach) i przechodzą z holdów na toggle.

**Xbox Accessibility Guideline 107** — to jest dokument oficjalny, Microsoft
([link](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/107)):

- „**Avoid introducing mechanics where a player is required to press two buttons simultaneously
  to activate a function.**"
- Gry „should not require the use of two analog sticks (or an analog stick and directional pad)
  to complete mechanics" — **to trafia wprost w D7**.
- Wymagany klik gałki „should be able to be remapped to another button".
- Remapować należy **akcje, nie przyciski**: jeśli podnoszenie to A+B, gracz musi móc przypisać
  „podnieś" do samego X.
- „Players should be given the option to remap all of the controls **within the game itself**."
- Przemapowane sterowanie musi być „represented correctly across any hints, tips, tutorials,
  or controller map schemes" — **czyli prompty muszą lecieć z bindów, nie z wpisanych na sztywno
  napisów**.
- Zapamiętywanie kombinacji („X + X + RT + A") jest osobną barierą **poznawczą**, obok motorycznej.

Game Accessibility Guidelines, cytaty dosłowne:

- „Holding requires much greater motor ability than pressing, **particularly on buttons that
  require more strength to operate, such as L3/R3 (pushing in the sticks)**" —
  [avoid requiring buttons to be held down](https://gameaccessibilityguidelines.com/avoid-provide-alternatives-to-requiring-buttons-to-be-held-down/)
- „Ensure that multiple simultaneous actions are not required, and included only as a
  supplementary / alternative input method" ([link](https://gameaccessibilityguidelines.com/ensure-that-multiple-simultaneous-actions-eg-click-drag-or-swipe-are-not-required-and-included-only-as-a-supplementary-alternative-input-method/))
- „**Allow controls to be remapped / reconfigured**" — Motor, **Basic**, czyli najniższy próg
  ([link](https://gameaccessibilityguidelines.com/allow-controls-to-be-remapped-reconfigured/));
  ta sama strona nazywa remapping „one of the best value accessibility features"
- „Ensure controls are as simple as possible" (Basic): „avoid using buttons/keys just because
  they're there"
- „**Indicate / allow reminder of controls during gameplay**" (Cognitive, Intermediate) —
  [link](https://gameaccessibilityguidelines.com/indicate-allow-reminder-of-controls-during-gameplay/),
  z cytatem gracza: „I can't remember which of six buttons uses my magic doobers"
- „Include interactive tutorials" (Cognitive, **Basic**) —
  [link](https://gameaccessibilityguidelines.com/include-interactive-tutorials/)

### Czy L3/R3 nadaje się pod umiejętność bojową?

Uczciwa odpowiedź, poparta źródłami: **tylko jeśli (a) to tap, nie hold, (b) da się to
przemapować, (c) nie jest to akcja o wysokiej częstotliwości.** Trzymane L3/R3 łamie dwie
wytyczne naraz (GAG o holdach + XAG 107 o remappingu kliku gałki). Anthem — najbliższy
odpowiednik projektowy — postawił lot na L3 **i musiał dołożyć opcję hold/toggle**. DMC5 i
Spider-Man trzymają na L3/R3 wyłącznie kamerę i markery.

> Do odnotowania: popularna teza, że L3-sprint niszczy kciuki i gałki, **nie ma źródła
> medycznego ani platformowego** — istnieją tylko wątki na forach. Nie opieram na niej oceny.
> Tak samo claw grip: żadne kontrolowane badanie nie wykazało, że powoduje uraz
> ([1HP, fizjoterapeuta](https://1-hp.org/blog/optimizeyoursurroundings/the-claw-grip-a-powerful-tool-or-your-hands-worst-nightmare/)
> twierdzi nawet, że sam w sobie nie jest groźny). Audytowalny jest **projekt, który zmusza do
> claw**, nie hipotetyczna kontuzja.

### Accept / back / pauza / touchpad

Od PS5 Sony ujednoliciło **✕ = zatwierdź, ○ = cofnij we wszystkich regionach**, łącznie z
Japonią, gdzie przez 26 lat było odwrotnie. Aktualne oficjalne brzmienie, bez zastrzeżeń
regionalnych: ✕ „select the highlighted item", ○ „cancel a command"
([PS5 button functions](https://www.playstation.com/en-us/support/hardware/ps5-button-functions/)).
Relacje o samej zmianie: [Kotaku](https://kotaku.com/sony-is-changing-the-confirm-and-cancel-buttons-in-japa-1845273030),
[VGC](https://www.videogameschronicle.com/news/after-26-years-ps5-will-make-x-its-default-select-button-in-japan/),
[GamesRadar](https://www.gamesradar.com/ps5s-x-and-circle-buttons-are-switching-uses-in-japan-but-only-for-the-hardware/).

> Zastrzeżenie: **nie istnieje pierwotne źródło** (post PS Blog ani komunikat prasowy) o tej
> zmianie — wszystkie relacje wywodzą się z wypowiedzi rzecznika dla japońskich mediów, a
> GamesRadar twierdzi, że dotyczy to tylko UI systemu, nie gier.

„OPTIONS = pauza" to **konwencja de facto**, nie udokumentowany wymóg — Sony mówi tylko, że
Options „displays the options menu", a TRC są pod NDA. Touchpad tak samo: jedyne oficjalne
zdanie to „use for gameplay functions". **Mark Zero jest tu zgodny** z praktyką
(`pad.gd:48-49`, `menu.gd:229`, `main_menu.gd:266`).

### Cztery wzorce, które trzymają się we wszystkich powyższych grach

1. **Triggery biorą celowanie i ogień albo podtrzymywaną trawersację; bumpery biorą
   umiejętności.** Zgadzają się Anthem, Warframe, DMC5 i Spider-Man — to najsilniejsza zbieżność
   w całym materiale.
2. **Kliknięcia gałek biorą TRYBY poruszania się, nigdy ataki.**
3. **Gdy braknie przycisków, robi się radial na przytrzymanym bumperze, a nie akord.**
4. **Zlepienie jednego czasownika ruchu z jednym czasownikiem ataku na jednym przycisku jest
   w porządku** (Astro). Boli dopiero upychanie obok siebie czasowników zmiany trybu.

---

## 3. Ocena — gdzie się zgadza, gdzie się rozjeżdża

### Zgodne z konwencją (i nie ruszać)

- **Lot na gałkach, ✕ do góry, R2 tylko na supersonic.** To jest dokładnie schemat Iron Mana
  z Marvel's Avengers i filozofia lotu z Anthem. Decyzja Jurka była dobra.
- **Web swing na R2 przytrzymanym.** Marvel's Spider-Man ma tam całą trawersację.
- **✕ = select, ○ = back, OPTIONS = pauza, TOUCHPAD = ekran dodatkowy.** Standard.
- **Analogowe triggery zamiast progów zero-jedynkowych**, deadzone z reskalowaniem, krzywa
  looka. To są rzeczy, o których większość małych projektów zapomina.
- **Bufor 0.22 s na strzały** — poprawne rozwiązanie „nie da się rapid-strzelać".
- **L1/R1 = dwie ręce, dwie bronie.** Czytelne i symetryczne u obu postaci.

### MUSI SIĘ ZMIENIĆ — to jest zepsute

**D1. OPTIONS otwiera dwa menu naraz.**
`BUTTONS["menu"]` zawiera `JOY_BUTTON_START` (`pad.gd:38`), a `BUTTONS["pause"]` to też
`JOY_BUTTON_START` (`pad.gd:47`). `suit_pilot.gd:250` / `spider_pilot.gd:189` otwierają menu
stroju, a `pause_menu.gd:33` w tej samej chwili przełącza pauzę (PauseMenu jest w scenie,
`arena.gd:34-36`). Dwa panele na raz, oba czytają lewą gałkę do nawigacji. To nie jest kwestia
gustu, to błąd.

**D2. Na Spider-Manie ✕ jednocześnie przyciąga linę i zużywa air hop.**
`spider_pilot.gd:195` liczy `reel` z akcji `up`; `spider_pilot.gd:311` wydaje air hop przy
`just_pressed("up")`, gdy `not model.grounded`. W trakcie huśtania nie jesteś na ziemi — więc
każde naciśnięcie ✕ żeby podciągnąć się na linie **kradnie jeden z dwóch skoków w powietrzu**.
Gracz nie ma jak tego zauważyć, poza tym, że „czasem skoki się kończą".

**D3. Na Spider-Manie L2 to celowanie ORAZ wall-run.**
`spider_pilot.gd:201` ustawia `aiming` z `Pad.retro()`, `spider_pilot.gd:333` ustawia
`wall_run` z **tego samego odczytu i tego samego progu**. Efekt: każde wbiegnięcie na ścianę
odbywa się w slow motion (`time_scale = 0.35`), a każde celowanie przy ścianie zamienia się w
bieg. Komentarz w `spider_pilot.gd:178-180` mówi, że L2 „przestało" być drugą siecią — ale nie
zauważa, że nadal robi dwie rzeczy.

**D4. Wrist laser wymaga trzymania △ + ○ równocześnie.**
`suit_pilot.gd:509`. Kciuk prawej ręki musi przycisnąć dwa sąsiednie przyciski twarzy i je
trzymać — co znaczy, że **w trakcie lasera nie ma go na prawej gałce**, więc nie patrzysz.
To dokładnie „multiple simultaneous actions" z GAG i „avoid mechanics where a player is
required to press two buttons simultaneously" z XAG 107. Ludzka ręka to wykona (△ i ○ sąsiadują),
ale kosztem całej kontroli kamery. Do tego nie ma o tym ani słowa nigdzie w grze.

**D5. Chwytanie przedmiotów na L1 + R1 gubi sieć.**
Tu trzeba być uczciwym: **sam bind jest zgodny z konwencją** — Marvel's Spider-Man ma na
`L1 + R1` dokładnie „podnieś i rzuć przedmiotem". Zepsuta jest implementacja.
`spider_pilot.gd:214` sprawdza `both` przed pętlą pojedynczych bumperów, ale `just_pressed`
działa na klatkę: jeśli naciśniesz L1 klatkę wcześniej niż R1 (czyli prawie zawsze), ta
wcześniejsza klatka **wystrzeliwuje sieć** i zużywa web fluid. Komentarz w `spider_pilot.gd:211`
twierdzi, że kolejność sprawdzania to załatwia. Nie załatwia. Dodatkowo, jeśli w zasięgu nie ma
przedmiotu (`_reach_for_prop()` zwraca null), obie sieci lecą mimo to.
Warto też wiedzieć, że **Insomniac sam się z tego wzorca wycofał**: w Spider-Man 2 akordy
zastąpił radialem na przytrzymanym bumperze i dołożył skróty na D-padzie wprost dla graczy,
którym trudno naciskać kilka przycisków naraz. Czyli minimum to naprawić buforowanie; lepiej
przenieść całą akcję na jeden przycisk.

**D6. L3/R3 w walce.**
Iron Man: R3 = gadget ofensywny, w tym NANO BLADE z cooldownem **4 sekundy** i obrażeniami 200
(`gadgets.gd:40`) — czyli przycisk, którym zabijasz, wciskany co cztery sekundy.
Spider-Man: R3 = wypad nóg, jedyny atak odpowiadający na kogoś za plecami
(`spider_pilot.gd:370`), więc z definicji używany reaktywnie w środku walki.
To jest strefa **tertiary** — mapa, marker, latarka. Marvel's Spider-Man daje na R3 „pokaż
marker celu", DMC5 „zmień cel", Anthem tryb lotu. Odpowiedź na pytanie z briefu — „czy L3/R3
nadaje się na umiejętność używaną w walce" — brzmi: **nie w tym przypadku.** Warunki, pod
którymi klik gałki jest akceptowalny (tap zamiast holdu, możliwość przemapowania, niska
częstotliwość — patrz §2), Mark Zero spełnia tylko pierwszy. Remappingu nie ma w ogóle, a
NANO BLADE z 4-sekundowym cooldownem i wypad nóg jako odpowiedź na atak z tyłu to definicja
akcji o wysokiej częstotliwości. Do tego klik R3 **psuje celowanie tą samą gałką w tej samej
chwili, w której go potrzebujesz**. Gadget defensywny na L3 (cooldown 8–12 s, jeden tap) jest
na granicy akceptowalności; NANO BLADE i wypad nóg nie są.

**D7. Opadanie Iron Mana na D-PAD ↓ jest nie do pogodzenia z lotem.**
`suit_pilot.gd:320`. W locie **lewa gałka JEST throttle'em** (`suit_pilot.gd:285, 309-313`).
D-pad obsługuje ten sam kciuk. Czyli nie da się jednocześnie opadać i regulować prędkości —
trzeba wybrać. Xbox Accessibility Guideline 107 mówi to wprost: gra „should not require the
use of two analog sticks (**or an analog stick and directional pad**) to complete mechanics".
Marvel's Avengers ma opadanie na ○ właśnie dlatego. Komentarz w `pad.gd:40-41` chwali się, że
przeniesienie z L1 na D-pad rozwiązało konflikt — rozwiązało konflikt z repulsorem i zrobiło
gorszy konflikt z lotem.

**D8. Ekran CONTROLS kłamie i jest niekompletny.**
`menu.gd:322-332`. Lista zawiera `["suit_toggle", "SUIT ON / OFF"]` i `["interact", "INTERACT"]`
— **obie te akcje nie mają w grze żadnego czytelnika** (poza kombinacją lasera). Gracz dostaje
napis „○ SUIT ON / OFF", naciska ○ i nic się nie dzieje.
Nie ma na liście: D-PAD ↓ (opadanie), L3, R3 (oba gadżety), wrist lasera, auto-hamowania.
`_draw_controls` **nie rozgałęzia się na bohatera**, w przeciwieństwie do `_draw_bay`
(`menu.gd:260-265`) — więc grający Spider-Manem ogląda listę sterowania Iron Mana. Spider-Man
nie ma w grze **żadnego** opisu swojego sterowania. Zakładka CONTROLS jest piąta z pięciu
(`menu.gd:42`), czyli cztery naciśnięcia R1 od wejścia.

**D9. Gadżety są niewidzialne.**
`gadgets.gd:47` deklaruje sygnał `used(key, label)`. Przeszukałem całe `scripts/` — **nikt go
nie podłącza**. HUD nie pokazuje ani nazwy gadżetu, ani cooldownu, ani że w ogóle istnieje
(`hud.gd` nie zna słowa „gadget"). Dodano je dzisiaj i nie ma szans, żeby gracz się o nich
dowiedział inaczej niż przez przypadkowe kliknięcie gałki.

**D10. Prompt „L1 + R1" wisi nad przedmiotami także dla Iron Mana.**
`prop.gd:73` tworzy `ButtonPrompt.new(["L1", "+", "R1"])` na sztywno, a `prop.gd:144-148`
wybiera **pierwszego gracza z grupy `player`**, nie sprawdzając, kim jest. Iron Man nie ma
`_reach_for_prop` — nie może podnieść niczego. Gra mówi mu, żeby wcisnął dwa przyciski, które
u niego strzelają z dwóch repulsorów.

### Rozbieżności bronione — zostawić

- **△ i ○ znaczą co innego u obu bohaterów.** Iron Man nie ma melee, Spider-Man nie ma tarczy.
  Nic się tu nie zderza, komentarz w `pad.gd:32-34` ma rację.
- **R2 = supersonic vs. web swing.** Zupełnie różne rzeczy, ale u obu znaczy „ruszaj się
  szybciej". Spójne na poziomie intencji, a to jest poziom, który gracz odczuwa.
- **Auto-hamowanie bez przycisku** (`suit_pilot.gd:293-300`) — ujęty przycisk, nie dodany.
  Odpowiednik toggle'a zamiast holda z rekomendacji GAG.
- **Aim na L2 spowalniający czas u obu** — spójne i zgodne z Marvel's Spider-Man.

### Drobniejsze, ale realne

- **□ u Spider-Mana odpala cios przy puszczeniu**, nie przy naciśnięciu
  (`spider_combat.gd:130-136`). Każdy zwykły cios ma opóźnienie długości twojego tapnięcia.
  W Marvel's Spider-Man □ to podstawowy atak reagujący natychmiast. Do tego u Iron Mana □ to
  turret (hold) — ten sam przycisk ma u dwóch bohaterów dwie różne mechaniki czasowe.
- **Nazwy akcji są historyczne i mylą.** `hover` = gadget defensywny, `faceplate` = gadget
  ofensywny (`pad.gd:45-46`). `GLYPH` nadal mówi `"hover": "L3"`, `"faceplate": "R3"`
  (`pad.gd:61`). Hover jest automatyczny (`flight_model.gd:385-411`), przyłbica nie istnieje.
  Gdyby ktoś kiedyś wyświetlił te glify, opisałyby nieistniejące funkcje.
- **`GLYPH` nie ma wpisu dla `down`** — jest `"down": "D-PAD ↓"`, ale nic tego nie rysuje.
  Brak też wpisów dla gadżetów i lasera, więc nie da się ich zaprompować nawet gdyby ktoś chciał.
- **Pause menu nie ma podpowiedzi na ekranie** (`pause_menu.gd:94-111` rysuje tylko „PAUSED" i
  pozycje) i **nie da się z niego wyjść na ○** — tylko OPTIONS (`pause_menu.gd:33`, `56`).
  Main menu obiecuje „○ / ESC BACK" (`main_menu.gd:266`), więc gra uczy zasady, której sama
  nie dotrzymuje w drugim menu.
- **Zero remappingu.** Ekran OPTIONS mówi wprost „not yet" (`main_menu.gd:263-265`).
  GAG stawia remapping jako wymaganie **Basic**, nie zaawansowane.
- **D-PAD ↑ dubluje ✕** w akcji `up` (`pad.gd:39`). U Iron Mana nieszkodliwe, u Spider-Mana
  powiela problem D2 i zajmuje kierunek, który przydałby się na coś innego.

### Ręka ludzka — które pary trzeba ścisnąć naraz

| Para | Kto | Da się fizycznie? | Werdykt |
|---|---|---|---|
| △ + ○ (hold) | Iron Man, wrist laser | Tak, jeden kciuk na dwóch sąsiednich | Da się, ale **kciuk znika z prawej gałki** — tracisz kamerę na cały czas trwania ruchu |
| L1 + R1 (hold) | Spider-Man, chwyt przedmiotu | Tak, dwa palce wskazujące, bez wysiłku | Ergonomicznie OK, **logicznie zepsute** (D5) |
| D-pad ↓ + L stick | Iron Man, opadanie w locie | **Nie** — jeden kciuk, dwa urządzenia | To jest prawdziwy claw-grip problem tej gry |
| L3 + R stick | Iron Man, gadget w locie | Klik L3 jest lewym kciukiem, ale zaburza lewą gałkę | Do przyjęcia dla cooldownu 8–12 s |
| R3 + R stick | oba, gadget ofensywny / nogi | Klik R3 **psuje celowanie tą samą gałką** | Nie do przyjęcia przy cooldownie 4 s |

---

## 4. Propozycja nowego mappingu

Ograniczenia zachowane: wszystko mieści się na DS4 (bez paddle'i, touchpad tylko jako zwykłe
naciśnięcie), **lot zostaje na gałkach, ✕ do góry, R2 tylko na supersonic**.

Zasada porządkująca, spójna między bohaterami:
**R1/L1 = broń dystansowa · □ = duży, podtrzymywany atak · ○ = „uciec z linii ognia" ·
✕ = w górę · △ = sygnaturowy special · D-pad = rzeczy na cooldownie · L3/R3 = puste.**

### IRON MAN — proponowany

| Input | Nowa funkcja | Zmiana | Uzasadnienie w jednej linii |
|---|---|---|---|
| ○ CIRCLE | **opadanie** (hold) | z D-PAD ↓ | Jedyna zmiana, która pozwala opadać i sterować prędkością równocześnie — tak robi Marvel's Avengers. |
| △ TRIANGLE | **gadget ofensywny** | z R3 | Atak należy do strefy primary; zdejmuje klik gałki z przycisku, którym się zabija. |
| D-PAD ← | **gadget defensywny** | z L3 | Cooldown 8–12 s = akcja okazjonalna = strefa tertiary, i D-pad jest pewniejszy niż klik gałki. |
| D-PAD → | **wrist laser** (tap, gdy naładowany) | z △ + ○ | Likwiduje jedyną kombinację u Iron Mana; ruch i tak dalej prowadzi się sam (`suit_pilot.gd:513-533`), więc tap wystarcza. |
| D-PAD ↓ | **wolne** | — | Zwolnione przez ○. |
| L3 / R3 | **niezbindowane** (opcjonalnie R3 = wyśrodkuj kamerę) | — | Zgodnie z tym, co robią Spider-Man i DMC5. |
| ✕ / L/R stick / R2 / L2 / R1 / L1 / □ | bez zmian | — | Te są dobre. |
| OPTIONS | **tylko pauza** | usunąć `JOY_BUTTON_START` z `menu` | Naprawia D1. |
| TOUCHPAD | menu stroju | — | Konwencja PS. |

Koszt: znika D-PAD ↓ jako opadanie i △+○ jako laser. Nic nie zostaje bez miejsca — dwa
kierunki D-pada były wolne, △ i ○ były martwe.

### SPIDER-MAN — proponowany

| Input | Nowa funkcja | Zmiana | Uzasadnienie w jednej linii |
|---|---|---|---|
| R2 | swing **oraz wall-run** | wall-run z L2 | Marvel's Spider-Man trzyma całą trawersację na R2; uwalnia L2 do jednej rzeczy. |
| L2 | **wyłącznie celowanie** | usunąć `wall_run` | Koniec ze slow motion przy każdej ścianie (D3). |
| D-PAD ↑ / ↓ | **przyciąganie / wypuszczanie liny**, jako osobne akcje | ↑ odłączone od `up` | Rozdziela lin od skoków — naprawia D2, najbardziej mylący błąd u tej postaci. |
| ✕ CROSS | skok / air hop / odbicie od ściany — **tylko z ✕** | usunąć D-PAD ↑ z `up` | jw. |
| △ TRIANGLE (hold przy przedmiocie) | **chwyć i rozkręć, puść = rzut** | z L1 + R1 | Kasuje kombinację i stray-web (D5); △ to dokładnie ten przycisk, na którym Marvel's Spider-Man ma web yank/throw. |
| D-PAD → | **wypad nóg** | z R3 | Zdejmuje atak z kliku gałki; nogi to atak obszarowy, nie wymaga jednoczesnego celowania. |
| □ SQUARE | cios odpala się **przy naciśnięciu**, hold dalej = launcher | `spider_combat.gd:130-136` | Podstawowy atak nie może czekać na puszczenie palca. |
| L3 / R3 / D-PAD ← | **wolne** | — | Rezerwa na przyszłe rzeczy; lepiej puste niż zajęte źle. |
| R1 / L1 / ○ / gałki | bez zmian | — | Dobre. |
| OPTIONS | tylko pauza | jw. | Naprawia D1. |

Koszt: L1+R1 przestaje cokolwiek znaczyć jako para (to zysk), R3 się zwalnia, D-pad ← zostaje
wolny. Nic nie traci miejsca.

### Kolejność wdrażania — od największej różnicy

1. **D1** OPTIONS otwierające dwa menu — jedna linia w `pad.gd:38`.
2. **D2** ✕ kradnący air hopy przy linie — osobne akcje `reel_in`/`reel_out`.
3. **D7** opadanie Iron Mana na ○.
4. **D3** wall-run z L2 na R2.
5. **D8 + D9** ekran CONTROLS per bohater + gadżety widoczne na HUD.
6. **D4** laser z △+○ na D-PAD →.
7. **D5** chwyt z L1+R1 na hold △.
8. **D6** gadżety i nogi z L3/R3 na △ i D-pad.
9. **D10** prompt przedmiotu tylko dla Spider-Mana.
10. Reszta drobnych (□ na naciśnięcie, nazwy akcji, podpowiedzi w pause menu).

### Warianty do rozważenia zamiast powyższego

**Wariant „radial", czyli jak zrobił to Spider-Man 2.** Zamiast rozrzucać gadżety po △ i
D-padzie: **przytrzymany L1 + przycisk twarzy**. Iron Man dostaje wtedy cztery sloty zamiast
dwóch (gadget defensywny, ofensywny, laser i jeszcze jedno wolne miejsce), a D-pad zostaje
całkiem pusty. Koszt: L1 przestaje być lewym repulsorem, gdy jest trzymany — czyli trzeba
zdecydować, że repulsory idą na R1 i R2 albo że L1 tapnięty strzela, a przytrzymany otwiera
radial (u Insomniaca dokładnie tak działa: `R1` tap = sieć, `R1` hold = gadżety).
To jest projekt na więcej niż jedno popołudnie, ale **skaluje się** — jeśli każdy z pięciu
strojów ma kiedyś dostać trzeci czy czwarty gadżet, żadna inna z propozycji tego nie udźwignie.

### Warte rozważenia, ale nie pilne

- **Remapping** w OPTIONS — GAG stawia to jako **Basic**, XAG 107 wymaga remappingu
  **wewnątrz gry**, a PS5 i tak nie przemapuje OPTIONS ani touchpada. Dziś jest tam „not yet".
- **Hold/toggle dla aim** na L2 i dla turret na □, jak Anthem daje dla lotu i sprintu.
- **Zamiana gadżetów miejscami** (defensywny na △, ofensywny na D-pad ←), jeśli po testach
  okaże się, że tarcza musi być bardziej reaktywna niż atak. Sprawdzić czuciem, nie na papierze.
- **L3 = wyśrodkuj kamerę / R3 = znacznik celu** — dokładnie to, co robią DMC5 i Spider-Man;
  konwencjonalne, nieszkodliwe wypełnienie zwolnionych klików.
- **Prompty budowane z `PadInput.glyph()`, nigdy ze stringów** — XAG 107 wymaga, żeby po
  przemapowaniu wszystkie podpowiedzi pokazywały nowy przycisk. Dziś `prop.gd:73` ma `"L1"`
  wpisane na sztywno, więc każda zmiana bindu rozjedzie się z ekranem.

---

## 5. Discoverability — czy glify mówią prawdę

| Co gra pokazuje | Gdzie | Czy zgadza się z kodem |
|---|---|---|
| „✕ SELECT ○ BACK" w menu stroju | `menu.gd:229` | ✅ `pad.gd:48-49` |
| „L1 ◀ ▶ R1" nad zakładkami | `menu.gd:216` | ✅ `menu.gd:127-134` |
| „STICK / ARROWS MOVE · ✕ / ENTER SELECT" w main menu | `main_menu.gd:251` | ✅ |
| „○ / ESC BACK" w OPTIONS main menu | `main_menu.gd:266` | ✅ `main_menu.gd:199` |
| „○ SUIT ON / OFF" w CONTROLS | `menu.gd:326` | ❌ **akcja bez czytelnika** |
| „△ INTERACT" w CONTROLS | `menu.gd:327` | ❌ **akcja bez czytelnika** |
| „L1 + R1" nad przedmiotem | `prop.gd:73` | ⚠️ prawda tylko dla Spider-Mana, pokazywane obu (`prop.gd:144-148`) |
| Lista CONTROLS ogólnie | `menu.gd:322-332` | ❌ Iron Man only, brak D-pad ↓, L3, R3, lasera |

**Zbindowane i nigdzie niepokazane:** D-PAD ↓ (opadanie / wypuszczanie liny), L3, R3 (oba
gadżety, wypad nóg), wrist laser (△+○), R2 jako swing, L2 jako wall-run, auto-hamowanie,
air hopy, przyciąganie liny, launcher na przytrzymanym □. To jest większość gry.

**Pokazane i nieistniejące:** SUIT ON / OFF, INTERACT.

Nic z tego nowy gracz nie odkryje sam. Najgorsze przypadki to **wrist laser** (nikt nie
naciśnie △ i ○ razem bez podpowiedzi) i **gadżety** (nikt nie klika gałek na próbę).

### Co z tym zrobić

1. `_draw_controls` musi rozgałęziać się na `active_hero` — wzorzec jest już w tym pliku
   (`menu.gd:260-265`) i wystarczy go powtórzyć.
2. Lista ma wymieniać **każdy** bind, łącznie z D-padem i gadżetami; usunąć dwie martwe pozycje.
3. CONTROLS na pierwszą lub drugą zakładkę zamiast piątej (`menu.gd:42`).
4. Podłączyć `gadgets.used` do HUD-u i narysować dwa wskaźniki cooldownu z glifem przycisku i
   nazwą z `gadgets.label()` (`gadgets.gd:69-72`) — inaczej system dodany dzisiaj nie istnieje
   dla gracza.
5. `ButtonPrompt` w `prop.gd` budować z `PadInput.glyph()` zamiast ze stringów, i pokazywać
   tylko temu graczowi, który może podnieść.
6. Uzupełnić `GLYPH` o brakujące wpisy i przemianować `hover`/`faceplate` na `gadget_def`/
   `gadget_off`, żeby nazwa i funkcja znów się zgadzały.
7. Pause menu: dopisać linijkę „✕ SELECT · ○ BACK" i obsłużyć ○.
8. **Pełną listę sterowania wsadzić do menu PAUZY, nie tylko do menu stroju** — dokładnie tam
   trzyma ją Spider-Man 2 („Controller Layout"), bo to jest miejsce, do którego gracz sięga,
   gdy czegoś nie pamięta. GAG, Cognitive: „Indicate / allow reminder of controls **during
   gameplay**".
9. GAG, Cognitive, Basic: „Include interactive tutorials" — krótka karta sterowania przy
   pierwszym spawnie danym bohaterem, z możliwością wywołania jej ponownie, załatwiłaby całą
   resztę. Ćwiczenie w kontekście obciąża pamięć mniej niż przeczytana lista.

---

## Podsumowanie w trzech zdaniach

Szkielet sterowania jest dobry i zgodny z tym, co robią duże gry: lot na gałkach z ✕ do góry
jest dokładnie schematem Iron Mana z Marvel's Avengers (i filozofią lotu z Anthem), swing na
R2 jest dokładnie schematem Marvel's Spider-Man, chwyt na L1+R1 też, a ✕/○ w menu są zgodne
z tym, co Sony ujednoliciło w 2020. Decyzja Jurka o gałkach zamiast throttle'a na triggerze
była trafna i nie ma powodu jej ruszać.
Zepsute są szczegóły, i to te, które gracz odczuwa jako „sterowanie jest dziwne": dwa menu na
jednym przycisku, ✕ zjadające skoki przy linie, slow motion przy każdej ścianie, laser na
dwóch przyciskach naraz i opadanie na D-padzie, którego nie da się użyć w locie.
Największy pojedynczy problem nie jest jednak w bindach, tylko w tym, że **ekran sterowania
opisuje dwie funkcje, których nie ma, i pomija większość tych, które są** — a gadżety dodane
dzisiaj nie mają w grze ani jednego piksela.
