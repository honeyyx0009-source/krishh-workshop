# Gold Straddle Scalper HFT — MT5 Expert Advisor

**File:** `GoldStraddleScalperHFT.mq5`

Dono side pending order (Buy Stop + Sell Stop) lagane wala breakout scalper. Jo order trigger hota hai, uska SL automatically opposite order ke level par hota hai, phir turant breakeven aur step-wise trailing se profit lock hota jaata hai. Position close hone ke baad loop dobara chalta hai.

---

## Logic flow (exactly jaisa aapne bataya)

```
1. Market ke dono side pending order (MID price ko anchor maankar):
      anchor     = (Ask + Bid) / 2
      BUY  STOP  = anchor + 100 points
      SELL STOP  = anchor - 100 points
      width      = EXACTLY 200 points  ($2.00)  <- spread ka koi asar nahi

2. Dono orders par SL PEHLE SE hi opposite order ke level par set hota hai:
      BUY STOP  ka SL  = Sell Stop ka price   -> SL distance exactly $2.00
      SELL STOP ka SL  = Buy Stop ka price    -> SL distance exactly $2.00

3. Koi bhi trigger hua (maan lo BUY):
      -> SELL STOP pending order turant DELETE
      -> Us position ka SL wahi hai jahan Sell Stop tha  ✔

4. Thoda bhi favour me move hua (default 15 points):
      -> SL BREAKEVEN par shift  ->  position safe, loss ka risk khatam

5. Aage move kiya to STEP LADDER se profit lock hota jaata hai:
      30 pts profit -> SL par 5 pts lock
      50 pts        -> 20 pts lock
      70 pts        -> 40 pts lock
      100 pts       -> 68 pts lock
      140 pts       -> 105 pts lock
      200 pts       -> 160 pts lock
      200+ pts      -> classic trailing, price se 40 pts peeche chalta hai

6. Breakeven ke baad market reverse aaya:
      -> SL breakeven par hit -> NO LOSS NO PROFIT close

7. Breakeven tak hi nahi pahuncha aur market ulta chala gaya:
      -> SL (opposite level) hit -> position loss me close

8. Position close (profit ya loss, koi bhi) ->  dobara 2 pending orders -> LOOP
```

**Ek important baat:** SL ko pending order par hi attach kiya gaya hai (broker side). Iska matlab agar aapka VPS/internet/terminal band ho jaye ya EA hat jaye, tab bhi position broker ke server par protected rahegi. Ye "EA se SL lagana" se zyada safe design hai.

---

## Install

1. MetaTrader 5 kholein → **File → Open Data Folder**
2. `MQL5/Experts/` folder me `GoldStraddleScalperHFT.mq5` copy karein
3. MetaEditor me file kholein → **F7** (Compile). 0 errors aana chahiye.
4. MT5 me Navigator refresh karein → EA ko **XAUUSD M1** chart par drag karein
5. Toolbar me **Algo Trading** button ON hona chahiye (green)
6. EA properties me `Allow Algo Trading` tick karein

**Backtest ke liye:** Strategy Tester → Model = **Every tick based on real ticks** (M1 OHLC se test na karein, pending order trigger sahi simulate nahi hoga).

---

## Auto broker adaptation (2 / 3 / 5 digit)

EA khud symbol ki properties padhta hai aur "1 point" ko normalize karta hai, taaki har broker par same behaviour mile:

| Broker quote | Digits | Raw point | EA ka 1 point | 100 EA points |
|---|---|---|---|---|
| `1912.34` | 2 | 0.01 | 0.01 | $1.00 move |
| `1912.345` | 3 | 0.001 | 0.01 | $1.00 move |
| `1.23456` | 5 | 0.00001 | 0.0001 | 100 pips |
| `1.2345` | 4 | 0.0001 | 0.0001 | 100 pips |

Iske alawa auto-detect hota hai:
- **Symbol suffix** — `XAUUSD.m`, `XAUUSD.a`, `GOLD#`, `XAUUSDpro` sab chalega
- **Stops level** — agar aapka distance/breakeven broker ke minimum se chhota hai, EA khud usko badha dega (log me batata hai)
- **Freeze level** — freeze zone me modify/delete skip ho jaata hai
- **Filling mode** — FOK / IOC / RETURN automatically try karke jo chale wo use karta hai
- **Lot min / step / max** — lot normalize hota hai
- **Symbol auto-find** — `Symbol selection mode = Auto-detect Gold` set karein to EA khud gold symbol dhoondh lega

---

## Main parameters

### 2. Straddle Setup
| Parameter | Default | Kaam |
|---|---|---|
| `InpDistancePoints` | 100 | Har pending order ka anchor se distance. 120 bhi kar sakte hain. Width = iska 2× |
| `InpExactWidth` | **true** | Dono legs mid price par anchor → width हमेशा exactly `2 × distance`. `false` = purana ask/bid mode (spread width me add ho jaata hai) |
| `InpRecenterPending` | true | Price drift ho jaye to pending orders ko re-center karta hai (width exact rehti hai) |
| `InpRecenterDriftPts` | 40 | Straddle ka centre itna drift hone par re-center |
| `InpPauseAfterCloseSecs` | 1 | Close ke baad naya straddle lagane se pehle pause |

### 4. Stop Loss
| Parameter | Default | Kaam |
|---|---|---|
| `InpSLFromOpposite` | **true** | SL = opposite pending order ka level (aapka logic) |
| `InpSLExtraBufferPts` | 0 | Opposite level se thoda aur door SL chahiye to |
| `InpFallbackSLPoints` | 0 | `InpSLFromOpposite=false` karein to yahan fixed SL points daalein |

### 5. Breakeven
| Parameter | Default | Kaam |
|---|---|---|
| `InpBETriggerPoints` | 15 | Itne points profit par SL breakeven par jaayega |
| `InpBELockPoints` | 0 | 0 = exact entry (true no-loss-no-profit). Commission cover karna ho to 2-3 rakhein. |

### 6. Step Ladder Trailing
| Parameter | Default | Kaam |
|---|---|---|
| `InpLadder` | `30:5,50:20,70:40,100:68,140:105,200:160` | `trigger:lock` pairs. Aap jitne steps chahein add karein. |
| `InpTrailStartPoints` | 200 | Iske baad classic trailing shuru |
| `InpTrailDistancePts` | 40 | Classic trailing me price se SL ka distance |
| `InpTrailStepPoints` | 5 | SL kam se kam itna improve hone par hi modify hoga (broker spam se bachne ke liye) |

Ladder format: `profit_trigger : locked_profit`, dono EA points me. `locked_profit` hamesha `trigger` se chhota hona chahiye, warna wo step ignore ho jaayega (log me warning aayegi).

### 3. Lot / Risk
- `InpLotMode = Fixed lot` → `InpFixedLot` use hoga (default 0.01)
- `InpLotMode = Risk percent` → `InpRiskPercent` % balance risk karke lot khud calculate hoga (SL distance ke hisaab se)

### 7 & 8. Filters aur Guards
- `InpMaxSpreadPoints` = 40 → spread jyada ho to naya straddle nahi lagega (news spike protection)
- `InpUseTimeFilter`, `InpStartHour`, `InpEndHour` → sirf specific hours me trade
- `InpFridayStop` + `InpFridayStopHour` → Friday late me naye cycle band
- `InpMaxDailyLossPct` / `InpMaxDailyProfitPct` / `InpMaxTradesPerDay` → daily limits (0 = off)

---

## Speed (HFT side)

- `InpUseTimerEngine = true` + `InpTimerMs = 100` → 100 ms ka timer, tick ke saath-saath bhi chalta hai. Sannata (low tick) me bhi SL management rukta nahi.
- `OnTradeTransaction` handler se **order fill hote hi** opposite pending delete hota hai — tick ka wait nahi.
- Sab order requests par retry + filling-mode fallback + requote handling lagi hui hai.

---

## Chart panel

EA chart par live status dikhata hai:

```
════ GOLD STRADDLE SCALPER (HFT) ════
Symbol      : XAUUSD   digits=2   1 pt = 0.01
Bid/Ask     : 3421.55 / 3421.78   spread = 23.0 pts
Distance    : 100.0 pts each side  ->  target width 200.0 pts
Live width  : 2.00   (buy SL dist 2.00 / sell SL dist 2.00)  [EXACT mode]
Breakeven   : ON @ 15.0 pts (lock 0.0)
Ladder      : 30>5 50>20 70>40 100>68 140>105 200>160
Classic tr. : ON  start 200  dist 40  step 5
Lot         : fixed 0.01
Cycles done : 12    Trades today : 12    Day P/L : 4.85
Status      : IN POSITION BUY  entry=3422.78  profit=41.0 pts  SL=3422.98
```

---

## ⚠️ Risk — ye zaroor padhein

Is logic me **risk aur reward asymmetric hai**, aur ye jaan-boojh kar aapke design ke mutabik hai:

- **Loss** = opposite level tak = distance × 2 = **exactly 200 points ($2.00 on gold)**
- **Breakeven** sirf 15 points par mil jaata hai

Iska matlab: EA jyadatar trades ko breakeven par bacha lega, lekin jab loss hoga wo bada hoga. Isliye:

1. **Pehle demo par kam se kam 2-4 hafte chalayein.** Gold M1 par spread aur slippage results ko bohot badalta hai.
2. `InpFixedLot` chhota rakhein (0.01) jab tak aap live statistics na dekh lein.
3. Agar SL kam karna ho: `InpSLFromOpposite = false` karein aur `InpFallbackSLPoints = 80` (ya jo chahein) set karein. Tab SL opposite level par nahi, entry se fixed distance par lagega.
4. **Spike me dono order trigger ho sakte hain** (hedging account par). EA aisi surat me dono positions ko manage karta hai, par ye risk exist karta hai — `InpMaxSpreadPoints` isi liye lagaya hai.
5. Broker ka **"minimum time between orders" / scalping restriction** check kar lein. Kuch brokers is tarah ke straddle-on-news style ko allow nahi karte.

Ye ek tool hai, guaranteed profit system nahi. Backtest + demo forward test ke bina live paisa na lagayein.

---

## Optimization ke liye suggested ranges

| Parameter | Range | Step |
|---|---|---|
| `InpDistancePoints` | 60 – 200 | 10 |
| `InpBETriggerPoints` | 8 – 40 | 2 |
| `InpTrailDistancePts` | 20 – 80 | 5 |
| `InpMaxSpreadPoints` | 20 – 60 | 5 |

Ladder string ko tester optimize nahi kar sakta (string hai), usko manually 2-3 variations se test karein.


---

## Changelog

### v1.01 — Exact width fix

**Bug:** Har naye straddle ka width thoda-thoda badal raha tha, aur SL 2.00 ki jagah 2.02 / 2.05 / 2.07 lag raha tha.

**Cause:** Dono legs ke alag-alag anchor the:

```
BUY STOP  = Ask + 100 pts
SELL STOP = Bid - 100 pts
-------------------------------------
width     = 200 pts + SPREAD   ← spread har tick par badalta hai!
```

Gold ka spread 2–7 points ke beech jhoolta rehta hai, aur wahi seedha width (aur isliye SL distance) me add ho raha tha. Iske upar `NormalizeDouble` ka rounding bhi ±1 tick jodta tha.

**Fix — teen cheezein:**

1. **Single anchor.** Dono legs ab ek hi mid price se nikalte hain, isliye spread cancel ho jaata hai:
   ```
   anchor    = (Ask + Bid) / 2
   BUY STOP  = anchor + d
   SELL STOP = anchor - d
   width     = 2d   (bilkul exact)
   ```
2. **Integer tick math.** Prices ab doubles me add nahi hote — sab kuch *whole ticks* me count hota hai (`PriceToTicks` / `TicksToPrice`), phir price me convert hota hai. Isse floating point drift ka ±1 tick error bhi khatam ho gaya.
3. **Symmetric expansion.** Agar broker ka stops level distance ko badhane par majboor kare, to sirf `d` badhta hai — kabhi ek side nahi. Width `2d` hi rehti hai.

Saath me:
- **Re-center bhi exact hai.** Pehle re-center apna alag hisaab lagata tha; ab wahi `ComputeStraddleLevels()` use karta hai. Agar do legs me se ek modify fail ho jaye, EA straddle ko delete karke fresh rebuild karta hai (lopsided width kabhi nahi rehne deta).
- **Self-verification.** Order lagne ke baad EA broker se actual prices wapas padhta hai aur width verify karta hai. Log me:
  ```
  NEW STRADDLE  bid=3421.64 ask=3421.70 spread=6.0 pts | BUYSTOP 3422.67 | SELLSTOP 3420.67 | lot=0.01
                WIDTH = 2.00 (200.0 pts) | BUY SL 3420.67 (dist 2.00) | SELL SL 3422.67 (dist 2.00)
  ```
  Agar broker ne kuch adjust kiya to `WARNING: broker adjusted the straddle!` aayega.
- **Panel me live width** dikhta hai, to aap real time me confirm kar sakte hain.

**Note:** `InpSymmetricFromMid` input hata diya gaya hai, uski jagah `InpExactWidth` (default `true`) hai. EA re-attach karte waqt inputs ek baar check kar lein.
