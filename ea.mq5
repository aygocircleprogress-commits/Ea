//+------------------------------------------------------------------+
//| SMC_XAUUSD_EA.mq5                                                |
//| SMC XAUUSD EA v2.63 - Dual Direction OB + FVG LIMIT             |
//| M5 OB -> displacement+volume FVG -> 50% OB limit; RR customizable |
//| CATATAN: parameter default = titik awal uji, bukan hasil optimasi|
//+------------------------------------------------------------------+
#property copyright "SMC XAUUSD EA"
#property version   "2.63"
#property description "XAUUSD v2.63 | Trend + countertrend OB/FVG limit | user-set RR | no breakeven"

#include <Trade\Trade.mqh>

//--- Input (PRD bagian 10)
input group "Risiko & eksekusi | RR USER - tanpa otomatis breakeven"
input double InpFixedLot            = 0.01;   // Lot tetap manual (tanpa auto-sizing)
input double InpPipSizePrice        = 1.00;   // USER convention: 1 pip=1.00 XAUUSD price (50 pip=$50 move)
input double InpMaxSLPips           = 50.0;   // Maksimum jarak SL (pip menurut InpPipSizePrice)
input double InpTargetRR            = 2.00;   // RR USER (contoh 1.0, 1.5, 2.0, 3.5, 5.0) semua mode, bukan RR fixed
input double InpMaxSpreadPips       = 1.50;   // Batas spread $1.50; tetap sama dlm satuan harga dari v2.20
input int    InpSLBufferTicks       = 2;
input int    InpOrderExpiryMinutes  = 90;
input int    InpSetupMaxAgeMinutes  = 240;
input int    InpCooldownMinutes     = 5;
input long   InpMagicNumber         = 26081163; // Magic khusus v2.63; isolasi dari order v2.62
input group "Struktur & zona"
input double InpPDBand              = 0.05;   // No-trade 45%-55%
input int    InpHTFSwingLeftRight   = 3;
input int    InpLTFSwingLeftRight   = 2;
input int    InpVolumeLookback      = 20;
input double InpFVGVolumeMultiplier = 1.10;
input int    InpDisplacementATRPeriod = 14;
input double InpDisplacementATRMult = 1.00;
input double InpMinImpulseBodyFraction = 0.55;
input double InpMinFVGATRFrac       = 0.06;
input double InpRejectionWickToBody = 1.00;
input double InpRejectionCloseBand  = 0.30;
input int    InpSweepMSSMaxBars     = 8;
input int    InpZoneMaxAgeHours     = 72;     // (tambahan) umur maks FVG HTF
input int    InpInitScanBars        = 120;     // (tambahan) scan awal FVG HTF
input group "Aggressive v2.30 (default aktif)"
input bool   InpAggressiveMode        = true; // jika false: mesin BALANCED / STRICT v2.10
input bool   InpAggressiveFixedSL     = true; // Wajib gunakan jarak SL tetap, bukan swing M1
input double InpAggressiveSLPips      = 50.0; // 50 * 1.00 = jarak harga $50.00; ubah konvensi pip jika perlu
input double InpAggressiveNearATR     = 1.50; // jarak maksimum harga ke AOI dalam ATR M5
input double InpAggressiveMinVolRatio = 0.75; // tick/real volume impuls M5 vs rata-rata
input double InpAggressiveM1BodyATR   = 0.20; // displacement candle M1 minimal pecahan ATR
input int    InpAggressiveMaxDaily    = 10;   // batas jumlah deal masuk per hari server
input int    InpAggressiveStopBars    = 3;    // dipakai hanya bila InpAggressiveFixedSL=false
input int    InpAggressiveScanM5      = 28;   // cari OB/FVG M5 terbaru
input group "Selective v2.40 (default aktif)"
input bool   InpSelectiveMode          = true;  // true=quality entry; false=aggressive lama (berisiko)
input group "OB + FVG Limit v2.63 (default aktif)"
input bool   InpOBFVGEntryMode         = true;  // TRUE = HANYA limit OB yg memiliki FVG, bukan market di CISD
input int    InpOBFVGScanM5            = 45;    // cari 45 candle M5 terakhir
input int    InpOBFVGMaxAgeM5Bars      = 30;    // zona valid maksimum 150 menit
input int    InpOBSearchPriorBars      = 5;     // cari last opposite candle sebelum displacement
input double InpOBFVGEntryDepth        = 0.50;  // 0=distal OB, 0.5=midpoint, 1=proximal (mirrored)
input double InpOBFVGMaxGapOB_ATR      = 3.00;  // jarak FVG dari OB max 3x ATR M5
input double InpOBFVGMaxTravelATR      = 5.00;  // jangan pasang limit sangat jauh dari harga
input bool   InpOBFVGRequireUntouched  = true;  // first mitigation only (berdasar candle M5 CLOSED)
input bool   InpOBFVGRequireUnfilledFVG= true;  // FVG belum fully mitigated oleh candle M5 CLOSED
input bool   InpOBFVGRequireBOS        = true;  // wajib M5 BOS searah H1/M30
input int    InpOBFVGBOSLinkBars       = 12;    // BOS harus berkaitan waktu dengan FVG (max 60m)
input double InpOBFVGDistalBufferPrice = 0.20;  // fixed SL harus di luar distal OB (satuan harga)
input group "Countertrend retracement v2.63 (M5 OB+FVG LIMIT)"
input bool   InpEnableCounterTrend       = true;   // BUY saat tren H1 SELL dan sebaliknya, dengan konfirmasi reversal
input bool   InpCTPreferM30Reversal     = true;   // ketika M30 melawan H1, cari RETRACEMENT lebih dahulu
input bool   InpCTRequireM30Opposite    = false;  // opsional: M30 harus menunjukkan arah retracement
input bool   InpCTRequireExtremeM15     = true;   // OB di bagian atas/bawah dealing range M15 historis
input int    InpCTRangeM15Bars          = 32;     // range 8 jam M15 pada saat OB muncul
input double InpCTExtremeFraction       = 0.40;   // SELL upper 40%% range, BUY lower 40%% range
input int    InpCTOrderExpiryMinutes    = 45;     // pending countertrend tidak dibiarkan terlalu lama

input int    InpSelectiveMaxDaily      = 3;     // tidak lebih dari 3 posisi baru per hari server
input int    InpSelectiveMaxLossStreak = 2;     // hentikan entry setelah 2 loss beruntun hari itu
input double InpSelectiveDailyLossPct  = 3.0;   // stop apabila realized P/L harian <= -3% balance
input double InpSelectiveRiskPct       = 2.0;   // risiko SL tiap posisi <=2% equity (bukan auto lot)
input int    InpSelectiveLossPauseMin  = 120;   // tunggu 120 menit setelah rugi
input int    InpSelectiveZoneWaitMin   = 180;   // jangan entry ulang AOI sama dalam 3 jam
input double InpSelectiveNearATR       = 0.75;  // harga harus masih dekat AOI <= 0.75 ATR M5
input int    InpSelectiveTouchBars     = 4;     // wajib AOI diretest di 4 candle M1 tertutup terakhir
input int    InpSelectiveBOSBars       = 30;    // M5 BOS tertutup dalam 30 candle M5 terakhir
input double InpSelectiveM5VolRatio    = 1.00;  // AOI volume >= 1.00x rata-rata
input double InpSelectiveM1VolRatio    = 1.05;  // M1 trigger volume >= 1.05x rata-rata
input double InpSelectiveM1MinBodyATR  = 0.35;  // breakout candle body >= 0.35 ATR M1
input double InpSelectiveM1MaxBodyATR  = 1.80;  // hindari entry saat candle terlalu jauh
input bool   InpSelectiveUseSession    = false; // opsional; jam SERVER bukan WIB
input int    InpSelectiveSessionStart  = 7;     // jam server, inklusif
input int    InpSelectiveSessionEnd    = 20;    // jam server, eksklusif
input group "Quality gate SELECTIVE v2.63"
input bool   InpQualityRecentM5BOS        = true;  // BOS yang sudah terlalu lama tidak dipakai
input int    InpQualityBOSMaxAgeM5Bars   = 18;    // BOS maksimal 18 M5 bar yang lalu (90 menit)
input bool   InpQualityStrongM1Rejection = true;  // rejection wajib penutupan kuat & konfirmasi mikro
input double InpQualityRejMinBodyATR     = 0.20;  // minimal tubuh rejection M1 relatif ATR
input double InpQualityMaxChaseM1ATR     = 2.00;  // harga entry maksimum 2 ATR M1 dari tepi AOI
input group "Mode sinyal (Balanced / Strict)"
input bool   InpStrictMode            = false; // strict: H1+M30 PD, sweep, BOS, OB, M3, volume M1
input bool   InpRequireM30PD          = false; // balanced: M30 boleh netral, TIDAK boleh berlawanan
input bool   InpRequireM15BOS         = false;
input bool   InpRequireM3MSS          = false;
input bool   InpRequireIDMSweep       = false; // balanced: MSS tanpa sweep boleh, ditandai SOFT
input bool   InpRequireM1Volume       = false; // volume HTF & M5 TETAP wajib
input bool   InpRequireOB             = false; // balanced: OB M15/M5 ATAU FVG M5
input bool   InpUseOBDistalSL         = false; // default SL di rejection M1; OB distal sering >50 pip
input int    InpMaxAOIAttempts        = 5;
input int    InpZoneRetryMinutes      = 3;
input group "Tampilan & log"
input bool   InpShowDashboard       = true;
input bool   InpWriteCSVLog         = true;
input bool   InpDrawZones            = true;
input int    InpMaxDrawnZones        = 6;
input int    InpPanelLeft           = 12;
input int    InpPanelTop            = 25;

//--- State machine
enum EState { S0_WAIT_DATA, S1_WAIT_BIAS, S2_WAIT_AOI, S3_WAIT_M15_M5, S4_WAIT_M3,
              S5_WAIT_M1, S6_RISK_CHECK, S7_LIMIT_ACTIVE, S8_POSITION_ACTIVE, S9_COOLDOWN };

struct FVG  { double lo, hi; datetime born; double volRatio; bool real; };
struct Rng  { bool ok; double lo, hi; };
struct Zone { string id; ENUM_TIMEFRAMES tf; int dir; double lo, hi; datetime born;
              bool touched; bool dead; double volRatio; bool real; int attempts; datetime lastAttempt; };
struct Seq  { datetime sweepT; datetime mssT; double sweepExt; double lhLevel; };
struct M1Res{ double level; double rejExt; datetime rejT; double volRatio; bool real; };
struct OBFVGPair
{
   bool ok; int dir;
   double obLo,obHi,fvgLo,fvgHi,entry,volRatio;
   bool realVolume;
   datetime obTime,fvgBorn;
   string key;
};

struct Setup{ bool active; string id; int dir; string zoneId; double zlo, zhi; datetime aoiTime;
              double pdH1, pdM30; string route;
              datetime bosT, m15Sweep, m15Mss, m5Sweep, m5Mss, m3Mss, fvg5Born;
              double obLo, obHi, fvg5lo, fvg5hi, fvg5Ratio; bool fvg5Real;
              double m1Level, m1Ratio; bool m1Real; bool hasOB, hasFVG5, softStructure; };

//--- Global
CTrade   g_trade;
double   g_tick = 0, g_pip = 0;
int      g_state = S0_WAIT_DATA;
datetime g_lastM1 = 0, g_lastH1 = 0, g_lastM30 = 0, g_cooldownUntil = 0, g_pendExpire = 0;
bool     g_ready = false, g_manual = false, g_hasPend = false, g_hasPos = false;
ulong    g_pendTicket = 0, g_lastTicket = 0;
uint     g_lastRet = 0;
string   g_reason = "", g_reasonLogged = "", g_logFile = "SMC_XAUUSD_v263_CUSTOM_RR_log.csv";
double   g_planEntry = 0, g_planSL = 0, g_planTP = 0, g_planSLpips = 0, g_planRR = 0, g_planLoss = 0, g_lastSpread = 0;
Zone     g_zones[];
int      g_newTouched[];
Setup    g_setup;
string   g_prefix = "";
datetime g_nextStopAlignmentCheck=0, g_nextOBPendingCheck=0;
int      g_rollingWins=0, g_rollingLosses=0, g_rollingScratch=0;
datetime g_lastPerfScan=0;
bool     g_zoneRefresh = true;
int      g_aggBiasH1=0, g_aggBiasM30=0, g_aggDir=0;
bool     g_aggAOIVisible=false;
double   g_aggAOILo=0, g_aggAOIHi=0, g_aggAOIVol=0;
string   g_aggAOIType="", g_aggSignal="";
bool     g_pairVisible=false;
double   g_pairFVGLo=0, g_pairFVGHi=0, g_pairVol=0;
int      g_aggConfirmed=0, g_aggOrders=0;
string   g_selLastZoneKey="", g_selBOSState="WAITING", g_selTouchState="WAITING";
string   g_entryModel="WAITING";          // TREND FOLLOW / COUNTERTREND RETRACE
string   g_ctDiagnostic="WAITING";     // alasan dan lokasi M15 countertrend
bool     g_ctActive=false;
double   g_ctRangeFraction=-1.0;
datetime g_selLastZoneTime=0;
int      g_selEntries=0,g_selLossStreak=0;
double   g_selDayPnL=0.0, g_selRiskPct=0.0;


// Diagnostik funnel (dicetak di OnDeinit)
int      g_fZone = 0, g_fTouch = 0, g_fAOI = 0, g_fS3 = 0, g_fS4 = 0, g_fS5 = 0, g_fPlaced = 0;
string   g_rcName[];
int      g_rcCnt[];
void CountR(string k)
{
   for(int i = 0; i < ArraySize(g_rcName); i++)
      if(g_rcName[i] == k) { g_rcCnt[i]++; return; }
   int n = ArraySize(g_rcName);
   ArrayResize(g_rcName, n + 1); ArrayResize(g_rcCnt, n + 1);
   g_rcName[n] = k; g_rcCnt[n] = 1;
}

//+------------------------------------------------------------------+
//| Helper umum                                                      |
//+------------------------------------------------------------------+
double Px(double v, int dir) { return dir > 0 ? v : -v; }
double NormTick(double p)  { return NormalizeDouble(MathRound(p / g_tick) * g_tick, _Digits); }
double FloorTick(double p) { return NormalizeDouble(MathFloor(p / g_tick + 1e-9) * g_tick, _Digits); }
double CeilTick(double p)  { return NormalizeDouble(MathCeil(p / g_tick - 1e-9) * g_tick, _Digits); }

void ClearSetup()
{
   g_setup.active = false; g_setup.id = ""; g_setup.dir = 0; g_setup.zoneId = "";
   g_setup.route = ""; g_setup.zlo = 0; g_setup.zhi = 0; g_setup.aoiTime = 0;
   g_setup.pdH1 = -1; g_setup.pdM30 = -1;
   g_setup.bosT = 0; g_setup.fvg5Born = 0; g_setup.m15Sweep = 0; g_setup.m15Mss = 0;
   g_setup.m5Sweep = 0; g_setup.m5Mss = 0; g_setup.m3Mss = 0;
   g_setup.obLo = 0; g_setup.obHi = 0; g_setup.fvg5lo = 0; g_setup.fvg5hi = 0;
   g_setup.fvg5Ratio = 0; g_setup.fvg5Real = false;
   g_setup.m1Level = 0; g_setup.m1Ratio = 0; g_setup.m1Real = false;
   g_setup.hasOB = false; g_setup.hasFVG5 = false; g_setup.softStructure = false;
   g_planEntry = 0; g_planSL = 0; g_planTP = 0; g_planSLpips = 0;
   g_planRR = 0; g_planLoss = 0;
}

void LogCSV(string ev, string reason, string details = "")
{
   if(!InpWriteCSVLog) return;
   int h = FileOpen(g_logFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE, ';');
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0)
      FileWrite(h, "ServerTime", "SetupID", "Dir", "State", "Event", "Reason", "Route", "Entry",
                "SLPips", "PlannedRR", "Lot", "Spread", "Ticket", "Retcode", "Details");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), g_setup.id, g_setup.dir,
             EnumToString((EState)g_state), ev, reason, g_setup.route,
             DoubleToString(g_planEntry, _Digits), DoubleToString(g_planSLpips, 1),
             DoubleToString(g_planRR, 2), DoubleToString(InpFixedLot, 2),
             DoubleToString(g_lastSpread, 1), (string)g_lastTicket, (string)g_lastRet, details);
   FileClose(h);
}

void SetReason(string code)
{
   g_reason = code;
   CountR(code);
   if(code != g_reasonLogged) { g_reasonLogged = code; LogCSV("SKIP", code); }
}

//+------------------------------------------------------------------+
//| Data seri: dimuat sebagai series (0 = bar berjalan).             |
//| dir<0 => data DICERMINKAN (harga dinegasikan) sehingga seluruh   |
//| logika deteksi cukup ditulis untuk skenario BUY/bullish.         |
//+------------------------------------------------------------------+
bool LoadRates(ENUM_TIMEFRAMES tf, int count, int dir, MqlRates &r[])
{
   ArraySetAsSeries(r, true);
   int got = CopyRates(_Symbol, tf, 0, count, r);
   if(got < count) return false;
   if(dir < 0)
      for(int i = 0; i < got; i++)
      {
         double h = r[i].high, l = r[i].low;
         r[i].open = -r[i].open; r[i].close = -r[i].close;
         r[i].high = -l;         r[i].low = -h;
      }
   return true;
}

// ATR rata-rata TR bar shift+1 .. shift+period (hanya histori sebelum bar 'shift')
double ATRAt(const MqlRates &r[], int shift, int period)
{
   if(ArraySize(r) < shift + period + 3) return 0;
   double s = 0;
   for(int i = shift + 1; i <= shift + period; i++)
   {
      double pc = r[i + 1].close;
      s += MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
   }
   return s / period;
}

bool VolInfo(const MqlRates &r[], int B, int lb, double &ratio, bool &real)
{
   if(ArraySize(r) < B + lb + 2) return false;
   bool allReal = (r[B].real_volume > 0);
   double sR = 0, sT = 0;
   for(int i = B + 1; i <= B + lb; i++)
   {
      if(r[i].real_volume <= 0) allReal = false;
      sR += (double)r[i].real_volume; sT += (double)r[i].tick_volume;
   }
   double avg, vb;
   if(allReal) { avg = sR / lb; vb = (double)r[B].real_volume; real = true; }
   else        { avg = sT / lb; vb = (double)r[B].tick_volume; real = false; }
   if(avg <= 0 || vb <= 0) return false;
   ratio = vb / avg;
   return true;
}

//+------------------------------------------------------------------+
//| FVG bullish (ruang cermin). A=c+2, B=c+1, C=c semuanya sudah close|
//+------------------------------------------------------------------+
bool CheckFVGBull(const MqlRates &r[], ENUM_TIMEFRAMES tf, int c, FVG &f, string &why, bool volumeRequired = true)
{
   int B = c + 1, A = c + 2;
   if(c < 1 || ArraySize(r) < B + MathMax(InpVolumeLookback, InpDisplacementATRPeriod) + 4)
   { why = "DATA_MISSING"; return false; }
   double atr = ATRAt(r, B, InpDisplacementATRPeriod);
   if(atr <= 0) { why = "DATA_MISSING"; return false; }
   double gap = r[c].low - r[A].high;
   if(gap < MathMax(2 * g_tick, InpMinFVGATRFrac * atr)) { why = "FVG_GAP"; return false; }
   double body = r[B].close - r[B].open, rng = r[B].high - r[B].low;
   if(body <= 0 || rng <= 0)                         { why = "FVG_IMPULSE"; return false; }
   if(body < InpDisplacementATRMult * atr)           { why = "FVG_IMPULSE"; return false; }
   if(body / rng < InpMinImpulseBodyFraction)        { why = "FVG_IMPULSE"; return false; }
   double ratio = 0; bool real = false;
   bool volOK = VolInfo(r, B, InpVolumeLookback, ratio, real);
   if(volumeRequired && (!volOK || ratio < InpFVGVolumeMultiplier))
   { why = "NO_VOLUME_CONFIRM"; return false; }
   f.lo = r[A].high; f.hi = r[c].low;
   f.born = r[c].time + PeriodSeconds(tf);
   f.volRatio = ratio; f.real = real;
   why = "";
   return true;
}

//+------------------------------------------------------------------+
//| Pivot terkonfirmasi (kiri L, kanan R). Urut dari terbaru.        |
//| Pivot di shift i baru valid bila i-R >= 1 (sisi kanan sudah close)|
//+------------------------------------------------------------------+
int FindPivots(const MqlRates &r[], int L, int R, bool high, int &out[], int maxN)
{
   int n = ArraySize(r), cnt = 0;
   ArrayResize(out, 0);
   for(int i = R + 1; i < n - L && cnt < maxN; i++)
   {
      bool ok = true;
      if(high)
      {
         for(int k = 1; k <= L && ok; k++) if(r[i + k].high >= r[i].high) ok = false;
         for(int k = 1; k <= R && ok; k++) if(r[i - k].high >  r[i].high) ok = false;
      }
      else
      {
         for(int k = 1; k <= L && ok; k++) if(r[i + k].low <= r[i].low) ok = false;
         for(int k = 1; k <= R && ok; k++) if(r[i - k].low <  r[i].low) ok = false;
      }
      if(ok) { ArrayResize(out, cnt + 1); out[cnt] = i; cnt++; }
   }
   return cnt;
}

//+------------------------------------------------------------------+
//| Dealing range & premium/discount (ruang harga nyata)             |
//+------------------------------------------------------------------+
Rng BuildRange(ENUM_TIMEFRAMES tf, double price)
{
   Rng g; g.ok = false; g.lo = 0; g.hi = 0;
   MqlRates r[];
   if(!LoadRates(tf, InpAggressiveMode ? 125 : 300, 1, r)) return g;
   int ph[], pl[];
   int L = InpHTFSwingLeftRight;
   int nh = FindPivots(r, L, L, true,  ph, 12);
   int nl = FindPivots(r, L, L, false, pl, 12);
   double hi = 0, lo = 0; bool fh = false, fl = false;
   for(int i = 0; i < nh; i++) if(r[ph[i]].high > price) { hi = r[ph[i]].high; fh = true; break; }
   for(int i = 0; i < nl; i++) if(r[pl[i]].low  < price) { lo = r[pl[i]].low;  fl = true; break; }
   if(fh && fl && hi > lo) { g.ok = true; g.hi = hi; g.lo = lo; }
   return g;
}

double PDPos(ENUM_TIMEFRAMES tf, double price, bool &valid)
{
   Rng g = BuildRange(tf, price);
   valid = g.ok;
   if(!g.ok) return -1;
   return (price - g.lo) / (g.hi - g.lo);
}

int BiasOf(double pos)   // +1 discount (BUY), -1 premium (SELL), 0 netral
{
   if(pos < 0) return 0;
   if(pos <= 0.5 - InpPDBand) return 1;
   if(pos >= 0.5 + InpPDBand) return -1;
   return 0;
}

// H1 menentukan bias utama. M30 boleh netral dalam BALANCED, tetapi
// M30 yang berlawanan memblokir. STRICT wajib PD searah di kedua timeframe.
bool PDPass(int dir, double price, double &pH1, double &pM30, string &why)
{
   bool v1, v2;
   pH1 = PDPos(PERIOD_H1, price, v1);
   pM30 = PDPos(PERIOD_M30, price, v2);
   if(!v1) { why = "WAIT_H1_RANGE"; return false; }
   int b1 = BiasOf(pH1), b2 = v2 ? BiasOf(pM30) : 0;
   if(b1 != dir) { why = (b1 == 0 ? "H1_NEUTRAL" : "H1_BIAS_OPPOSITE"); return false; }
   bool both = InpStrictMode || InpRequireM30PD;
   if(both && !v2) { why = "WAIT_M30_RANGE"; return false; }
   if(b2 == -dir) { why = "M30_BIAS_CONFLICT"; return false; }
   if(both && b2 != dir) { why = "M30_NEUTRAL"; return false; }
   why = "";
   return true;
}

//+------------------------------------------------------------------+
//| Registry FVG HTF (H1 & M30)                                      |
//+------------------------------------------------------------------+
int FindZone(string id)
{
   for(int i = 0; i < ArraySize(g_zones); i++) if(g_zones[i].id == id) return i;
   return -1;
}

void ScanTF(ENUM_TIMEFRAMES tf, int cFrom, int cTo)
{
   for(int d = 1; d >= -1; d -= 2)
   {
      MqlRates r[];
      if(!LoadRates(tf, cTo + 60, d, r)) continue;
      for(int c = cTo; c >= cFrom; c--)
      {
         FVG f; string w;
         if(!CheckFVGBull(r, tf, c, f, w)) continue;
         string id = StringFormat("%s_%s_%I64d", EnumToString(tf), d > 0 ? "B" : "S", (long)r[c + 1].time);
         if(FindZone(id) >= 0) continue;
         Zone z;
         z.id = id; z.tf = tf; z.dir = d;
         z.lo = (d > 0) ? f.lo : -f.hi;
         z.hi = (d > 0) ? f.hi : -f.lo;
         z.born = f.born; z.touched = false; z.dead = false;
         z.volRatio = f.volRatio; z.real = f.real; z.attempts = 0; z.lastAttempt = 0;
         for(int k = c - 1; k >= 1; k--)   // evaluasi retroaktif: invalidasi saja
         {
            // ponytail: touch retroaktif dihapus; touch ditangani UpdateZones realtime
            if(r[k].close < f.lo) { z.dead = true; break; }
         }
         int n = ArraySize(g_zones);
         ArrayResize(g_zones, n + 1);
         g_zones[n] = z;
         g_zoneRefresh = true;
         g_fZone++;
      }
   }
}

void PruneZones()
{
   int n = ArraySize(g_zones), j = 0;
   for(int i = 0; i < n; i++)
      if(!g_zones[i].dead) { if(i != j) g_zones[j] = g_zones[i]; j++; }
   ArrayResize(g_zones, j);
}

void UpdateZones()
{
   ArrayResize(g_newTouched, 0);
   datetime h1 = iTime(_Symbol, PERIOD_H1, 0), m30 = iTime(_Symbol, PERIOD_M30, 0);
   if(h1 != g_lastH1)   { g_lastH1 = h1;   ScanTF(PERIOD_H1, 1, 1); }
   if(m30 != g_lastM30) { g_lastM30 = m30; ScanTF(PERIOD_M30, 1, 1); }
   PruneZones(); // hapus zona mati dari siklus sebelumnya (sebelum membuat indeks kandidat)

   datetime bt = iTime(_Symbol, PERIOD_M1, 1);
   double lo = iLow(_Symbol, PERIOD_M1, 1), hi = iHigh(_Symbol, PERIOD_M1, 1);
   double cl = iClose(_Symbol, PERIOD_M1, 1);
   datetime now = TimeCurrent();
   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(g_zones[i].dead) continue;
      if(now - g_zones[i].born > (long)InpZoneMaxAgeHours * 3600)
      { g_zones[i].dead = true; g_zoneRefresh = true; continue; }
      if(bt < g_zones[i].born) continue;
      bool touch = (lo <= g_zones[i].hi && hi >= g_zones[i].lo);
      bool dead = (g_zones[i].dir > 0) ? (cl < g_zones[i].lo) : (cl > g_zones[i].hi);
      if(dead) { g_zones[i].dead = true; g_zoneRefresh = true; continue; }
      if(!touch) continue;
      if(!g_zones[i].touched) { g_zones[i].touched = true; g_fTouch++; }
      // Jangan menghanguskan zona ketika PD/struktur belum sesuai.
      if(g_zones[i].attempts >= InpMaxAOIAttempts) continue;
      if(g_zones[i].lastAttempt > 0 &&
         now - g_zones[i].lastAttempt < InpZoneRetryMinutes * 60) continue;
      int n = ArraySize(g_newTouched);
      ArrayResize(g_newTouched, n + 1);
      g_newTouched[n] = i;
   }
   // Pilih kandidat AOI TERDEKAT, bukan sekadar zona tertua.
   double mid = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
   for(int i = 0; i < ArraySize(g_newTouched); i++)
      for(int j = i + 1; j < ArraySize(g_newTouched); j++)
      {
         int a = g_newTouched[i], b = g_newTouched[j];
         double da = MathAbs(mid - (g_zones[a].lo + g_zones[a].hi) * 0.5);
         double db = MathAbs(mid - (g_zones[b].lo + g_zones[b].hi) * 0.5);
         if(db < da) { g_newTouched[i] = b; g_newTouched[j] = a; }
      }
}

//+------------------------------------------------------------------+
//| Rute bias & target (ERL->IRL, IRL->ERL, IRL->IRL)                |
//+------------------------------------------------------------------+
bool ERLSweep(int dir)
{
   MqlRates r[];
   if(!LoadRates(PERIOD_H1, 300, dir, r)) return false;
   int pl[], L = InpHTFSwingLeftRight;
   int n = FindPivots(r, L, L, false, pl, 6);
   for(int i = 0; i < n; i++)
   {
      double piv = r[pl[i]].low;
      int start = MathMin(pl[i] - L - 1, 8);
      for(int s = start; s >= 1; s--)
         if(r[s].low < piv - g_tick && r[s].close > piv) return true;
   }
   return false;
}

bool NearestZone(int dir, double entry, string excludeId, int wantDir, double &tgt)
{
   double best = DBL_MAX; bool found = false;
   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(g_zones[i].dead || g_zones[i].id == excludeId) continue;
      if(wantDir != 0 && g_zones[i].dir != wantDir) continue;
      double edge = (dir > 0) ? g_zones[i].lo : g_zones[i].hi;
      double dst = (edge - entry) * dir;
      if(dst > 0 && dst < best) { best = dst; tgt = edge; found = true; }
   }
   return found;
}

bool PickTarget(int dir, double entry, double sl, double &tp, string &route)
{
   double R = MathAbs(entry - sl);
   if(R <= 0) return false;
   double buf = InpSLBufferTicks * g_tick, want = InpTargetRR * R;
   string order[3]; int n = 0;
   if(ERLSweep(dir)) order[n++] = "ERL_IRL";
   order[n++] = "IRL_ERL";
   order[n++] = "IRL_IRL";
   for(int i = 0; i < n; i++)
   {
      double tgt = 0; bool ok = false;
      if(order[i] == "ERL_IRL")      ok = NearestZone(dir, entry, g_setup.zoneId, -dir, tgt);
      else if(order[i] == "IRL_ERL") { Rng g = BuildRange(PERIOD_H1, entry);
                                       if(g.ok) { tgt = (dir > 0) ? g.hi : g.lo; ok = ((tgt - entry) * dir > 0); } }
      else                           ok = NearestZone(dir, entry, g_setup.zoneId, 0, tgt);
      if(!ok) continue;
      double avail = (tgt - entry) * dir - buf;
      // RR adalah target tetap, BUKAN "maksimum RR". Jangan diam-diam potong TP
      // ke liquidity target bila RR pilihan pengguna tidak tersedia.
      if(avail + g_tick * 0.51 < want) continue;
      double t = (dir > 0) ? FloorTick(entry + want) : CeilTick(entry - want);
      double rr = MathAbs(t - entry) / R;
      if(rr < InpTargetRR - g_tick / R - 1e-8 || rr > InpTargetRR + g_tick / R + 1e-8) continue;
      if((t - entry) * dir > avail + g_tick * 0.51) continue;
      tp = t; route = order[i]; g_planRR = rr;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Tahap M15/M5: sweep IDM -> MSS (ruang cermin, bullish)           |
//+------------------------------------------------------------------+
bool SweepMSS(ENUM_TIMEFRAMES tf, int dir, datetime minTime, Seq &o, string &why)
{
   MqlRates r[];
   if(!LoadRates(tf, 200, dir, r)) { why = "DATA_MISSING"; return false; }
   int L = InpLTFSwingLeftRight, R = L;
   int pl[], ph[];
   int nl = FindPivots(r, L, R, false, pl, 8);
   int nh = FindPivots(r, L, R, true,  ph, 12);
   bool swept = false;
   for(int i = 0; i < nl; i++)
   {
      int ip = pl[i]; double piv = r[ip].low;
      for(int s = ip - R - 1; s >= 1; s--)
      {
         if(r[s].time < minTime) continue;
         if(r[s].low < piv - g_tick)
         {
            swept = true;
            int bb = -1;                                   // close kembali <= 2 candle
            for(int k = 0; k <= 2; k++)
            { int idx = s - k; if(idx < 1) break; if(r[idx].close > piv) { bb = idx; break; } }
            if(bb < 0) break;
            double ext = r[s].low;
            for(int k = s; k >= bb; k--) ext = MathMin(ext, r[k].low);
            double lh = 0; bool fl = false;                // lower high terakhir yang sudah confirmed
            for(int j = 0; j < nh; j++)
               if(ph[j] - R >= s) { lh = r[ph[j]].high; fl = true; break; }
            if(!fl) break;
            for(int m = bb; m >= 1; m--)
            {
               if(s - m > InpSweepMSSMaxBars) break;
               if(r[m].close > lh && r[m].close > r[m].open)
               {
                  double atr = ATRAt(r, m, InpDisplacementATRPeriod);
                  if(atr > 0 && (r[m].close - r[m].open) >= InpDisplacementATRMult * atr)
                  {
                     o.sweepT = r[s].time; o.mssT = r[m].time;
                     o.sweepExt = Px(ext, dir); o.lhLevel = Px(lh, dir);
                     why = "";
                     return true;
                  }
               }
            }
            continue;   // coba pivot berikutnya
         }
      }
   }
   why = swept ? "MSS_MISSING" : "IDM_NOT_SWEPT";
   return false;
}

bool MSSOnly(ENUM_TIMEFRAMES tf, int dir, datetime minTime, datetime &mssT)
{
   MqlRates r[];
   if(!LoadRates(tf, 150, dir, r)) return false;
   int L = InpLTFSwingLeftRight, R = L, ph[];
   int nh = FindPivots(r, L, R, true, ph, 12);
   for(int m = 1; m <= 40; m++)
   {
      if(r[m].time < minTime) break;
      double lh = 0; bool fl = false;
      for(int j = 0; j < nh; j++) if(ph[j] - R > m) { lh = r[ph[j]].high; fl = true; break; }
      if(!fl) continue;
      if(r[m].close > lh && r[m].close > r[m].open)
      {
         double atr = ATRAt(r, m, InpDisplacementATRPeriod);
         if(atr > 0 && (r[m].close - r[m].open) >= InpDisplacementATRMult * atr) { mssT = r[m].time; return true; }
      }
   }
   return false;
}

bool M15BOS(int dir, datetime beforeT, datetime &bosT)
{
   MqlRates r[];
   if(!LoadRates(PERIOD_M15, 150, dir, r)) return false;
   int L = InpLTFSwingLeftRight, R = L, pl[];
   int n = FindPivots(r, L, R, false, pl, 10);
   for(int i = 0; i < n; i++)
   {
      double piv = r[pl[i]].low;
      for(int s = pl[i] - R - 1; s >= 1; s--)
         if(r[s].close < piv && r[s].time <= beforeT) { bosT = r[s].time; return true; }
   }
   return false;
}

// OB terakhir sebelum MSS, timeframe disesuaikan dengan asal MSS.
bool FindOB(ENUM_TIMEFRAMES tf, int dir, datetime mssT, double &lo, double &hi)
{
   MqlRates r[];
   if(!LoadRates(tf, 160, dir, r)) return false;
   int m = iBarShift(_Symbol, tf, mssT, false);
   if(m < 1 || m > 55) return false;
   for(int k = m + 1; k <= m + 7 && k < ArraySize(r); k++)
   {
      if(r[k].close < r[k].open)
      {
         double zl = r[k].low, zh = r[k].high;
         bool invalid = false;
         for(int j = k - 1; j >= 1; j--)
            if(r[j].close < zl) { invalid = true; break; }
         if(invalid) continue;
         lo = (dir > 0) ? zl : -zh;
         hi = (dir > 0) ? zh : -zl;
         return true;
      }
   }
   return false;
}

bool M5FVG(int dir, datetime minTime, FVG &out, string &why)
{
   MqlRates r[];
   if(!LoadRates(PERIOD_M5, 120, dir, r)) { why = "DATA_MISSING"; return false; }
   bool volFail = false;
   for(int c = 1; c <= 20; c++)
   {
      if(r[c].time < minTime) break;
      FVG f; string w;
      if(CheckFVGBull(r, PERIOD_M5, c, f, w))
      {
         out.lo = (dir > 0) ? f.lo : -f.hi; out.hi = (dir > 0) ? f.hi : -f.lo;
         out.born = f.born; out.volRatio = f.volRatio; out.real = f.real;
         return true;
      }
      if(w == "NO_VOLUME_CONFIRM") volFail = true;
   }
   why = volFail ? "NO_VOLUME_CONFIRM" : "M5_FVG_MISSING";
   return false;
}

//+------------------------------------------------------------------+
//| Trigger M1: rejection -> impuls B -> FVG(A=rejection,B,C) + CISD |
//+------------------------------------------------------------------+
// Cari rejection M1 DI DALAM OB M15/M5 ATAU FVG M5;
// setelahnya harus ada FVG M1 + CISD, tidak harus persis tiga candle adjacent.
bool M1Trigger(int dir, double obLo, double obHi, datetime minTime, M1Res &o, string &why)
{
   MqlRates r[];
   if(!LoadRates(PERIOD_M1, 180, dir, r)) { why = "DATA_MISSING_M1"; return false; }
   double bLo = (dir > 0) ? obLo : -obHi, bHi = (dir > 0) ? obHi : -obLo;
   double fLo = (dir > 0) ? g_setup.fvg5lo : -g_setup.fvg5hi;
   double fHi = (dir > 0) ? g_setup.fvg5hi : -g_setup.fvg5lo;
   why = "M1_REJECTION_MISSING";
   for(int rj = 3; rj <= 35; rj++)
   {
      if(r[rj].time < minTime) break;
      double op = r[rj].open, cl = r[rj].close, hi = r[rj].high, lo = r[rj].low;
      double range = hi - lo, body = MathAbs(cl - op);
      if(range <= 0) continue;
      double wick = MathMin(op, cl) - lo;
      if(wick < InpRejectionWickToBody * MathMax(body, g_tick)) continue;
      if(cl < lo + (1.0 - InpRejectionCloseBand) * range) continue;
      bool inOB = g_setup.hasOB && lo <= bHi && hi >= bLo;
      bool inFVG = g_setup.hasFVG5 && lo <= fHi && hi >= fLo;
      if(!inOB && !inFVG) continue;
      why = "M1_FVG_MISSING";

      // CISD = close melewati open candle tertua dari rangkaian bearish sebelum rejection.
      int k = (cl < op) ? rj : rj + 1;
      int oldest = -1;
      while(k < ArraySize(r) - 2 && r[k].close < r[k].open)
      { oldest = k; k++; }
      if(oldest < 0) { why = "CISD_UNCONFIRMED"; continue; }
      double cisd = r[oldest].open;
      bool broken = false;
      for(int m = rj - 1; m >= MathMax(1, rj - 10); m--)
         if(r[m].close > cisd + g_tick) { broken = true; break; }
      if(!broken) { why = "CISD_UNCONFIRMED"; continue; }

      for(int fc = MathMax(1, rj - 9); fc <= rj - 2; fc++)
      {
         FVG f; string fw;
         if(!CheckFVGBull(r, PERIOD_M1, fc, f, fw, InpStrictMode || InpRequireM1Volume))
         { if(fw == "NO_VOLUME_CONFIRM") why = fw; continue; }
         // Jangan gunakan FVG yang sudah terlalu lama untuk pending retracement.
         if(fc > 8) continue;
         o.level = Px(cisd, dir); o.rejExt = Px(lo, dir); o.rejT = r[rj].time;
         o.volRatio = f.volRatio; o.real = f.real;
         why = "";
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Eksekusi: validasi risiko lalu pasang SATU limit order           |
//+------------------------------------------------------------------+
bool VolumeValid()
{
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(InpFixedLot < mn - 1e-12 || InpFixedLot > mx + 1e-12) return false;
   if(st > 0 && MathAbs((InpFixedLot - mn) / st - MathRound((InpFixedLot - mn) / st)) > 1e-6) return false;
   return true;
}

bool SendLimit(int dir, double entry, double sl, double tp, datetime expiry, string comment)
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   long exModes = SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
   bool specified = ((exModes & SYMBOL_EXPIRATION_SPECIFIED) != 0);
   ENUM_ORDER_TYPE_TIME tt = ORDER_TIME_GTC;
   if(specified) tt = ORDER_TIME_SPECIFIED;
   else if((exModes & SYMBOL_EXPIRATION_GTC) != 0) tt = ORDER_TIME_GTC;
   else if((exModes & SYMBOL_EXPIRATION_DAY) != 0) tt = ORDER_TIME_DAY;
   datetime ex = specified ? expiry : 0;
   ENUM_ORDER_TYPE_FILLING fills[3] = { ORDER_FILLING_RETURN, ORDER_FILLING_IOC, ORDER_FILLING_FOK };
   for(int i = 0; i < 3; i++)
   {
      g_trade.SetTypeFilling(fills[i]);
      bool sent = (dir > 0) ? g_trade.BuyLimit(InpFixedLot, entry, _Symbol, sl, tp, tt, ex, comment)
                            : g_trade.SellLimit(InpFixedLot, entry, _Symbol, sl, tp, tt, ex, comment);
      g_lastRet = g_trade.ResultRetcode(); g_lastTicket = g_trade.ResultOrder();
      if((g_lastRet == TRADE_RETCODE_DONE || g_lastRet == TRADE_RETCODE_PLACED) && g_lastTicket > 0) return true;
      if(g_lastRet != TRADE_RETCODE_INVALID_FILL) break;
      if(!sent && i == 2) break;
   }
   return false;
}

bool RiskAndPlace(M1Res &m, double &outEntry, double &outSL, double &outTP)
{
   int dir = g_setup.dir;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_lastSpread = (ask - bid) / g_pip;

   double entry = NormTick(m.level);
   string why; double pH1, pM30;
   if(!PDPass(dir, entry, pH1, pM30, why)) { SetReason(why); return false; }   // cek ulang dgn harga pending
   g_setup.pdH1 = pH1; g_setup.pdM30 = pM30;

   double buf = InpSLBufferTicks * g_tick;
   // SMC M1 entry: invalidasi di rejection M1. OB M15 hanya dipakai jika diminta.
   double distal = m.rejExt;
   if(InpUseOBDistalSL && g_setup.hasOB)
      distal = dir > 0 ? MathMin(distal, g_setup.obLo) : MathMax(distal, g_setup.obHi);
   double sl = (dir > 0) ? FloorTick(distal - buf) : CeilTick(distal + buf);
   double slPips = MathAbs(entry - sl) / g_pip;
   g_planEntry = entry; g_planSLpips = slPips;
   double capPips = MathMin(InpMaxSLPips, 50.0);
   if(slPips <= 0 || (entry - sl) * dir <= 0) { SetReason("INVALID_LIMIT_PRICE"); return false; }
   if(slPips > capPips + 1e-9)                { SetReason("SL_OVER_50"); return false; }

   double tp = 0; string route = "";
   if(!PickTarget(dir, entry, sl, tp, route)) { g_planRR = 0; SetReason("RR_UNDER_1"); return false; }
   g_setup.route = route;

   if(dir > 0 ? !(entry < ask) : !(entry > bid)) { SetReason("INVALID_LIMIT_PRICE"); return false; }
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL ||
      !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   { SetReason("TRADE_DISABLED"); return false; }
   double lvl = MathMax((double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                        (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * _Point;
   bool stopsOk = (dir > 0) ? ((ask - entry) >= lvl && (entry - sl) >= lvl && (tp - entry) >= lvl)
                            : ((entry - bid) >= lvl && (sl - entry) >= lvl && (entry - tp) >= lvl);
   if(!stopsOk) { SetReason("BROKER_STOPS"); return false; }
   if(g_lastSpread > InpMaxSpreadPips) { SetReason("SPREAD_HIGH"); return false; }
   if(!VolumeValid()) { SetReason("INVALID_VOLUME"); return false; }
   if((SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE) & SYMBOL_ORDER_LIMIT) == 0)
   { SetReason("LIMIT_NOT_ALLOWED"); return false; }
   double margin = 0;
   if(!OrderCalcMargin(dir > 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT, _Symbol, InpFixedLot, entry, margin) ||
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   { SetReason("MARGIN_LOW"); return false; }
   double pl = 0;   // hanya informasi dashboard
   if(OrderCalcProfit(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, InpFixedLot, entry, sl, pl)) g_planLoss = pl;
   outEntry = entry; outSL = sl; outTP = tp;
   g_planEntry = entry; g_planSL = sl; g_planTP = tp;
   return true;
}

//+------------------------------------------------------------------+
//| Eksposur: pending/posisi EA vs posisi manual/EA lain             |
//+------------------------------------------------------------------+
void ScanExposure()
{
   g_hasPend = false; g_hasPos = false; g_manual = false; g_pendTicket = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      // Semua pending tipe, termasuk STOP/STOP_LIMIT, adalah eksposur.
      if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
      { g_hasPend = true; g_pendTicket = t; }
      else g_manual = true;
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) g_hasPos = true;
      else g_manual = true;
   }
}

// Reconstruct distal OB from the pending order comment after terminal restart.
// If the broker strips the comment, the EA still manages expiry and SL/TP,
// but cannot reconstruct structural OB invalidation; check Journal on restart.
void RestoreOBFVGOrderContext()
{
   if(g_setup.active || g_pendTicket==0 || !OrderSelect(g_pendTicket)) return;
   string cm=OrderGetString(ORDER_COMMENT);
   bool ct=(StringFind(cm,"CTOB")==0);
   bool tf=(StringFind(cm,"TFOB")==0);
   if(!ct && !tf) return;
   if(StringLen(cm)<7) return;
   string suffix=StringSubstr(cm,5);
   datetime born=(datetime)StringToInteger(suffix);
   if(born<=0) return;
   int bs=iBarShift(_Symbol,PERIOD_M5,born,false);
   if(bs<0) return;
   double lo=iLow(_Symbol,PERIOD_M5,bs), hi=iHigh(_Symbol,PERIOD_M5,bs);
   if(lo<=0 || hi<=lo) return;
   g_setup.active=true;
   g_setup.dir=StringSubstr(cm,4,1)=="B"?1:-1;
   g_setup.id=cm;
   g_setup.route=ct?"COUNTERTREND_M5_MSS_OB_FVG_LIMIT":"TREND_H1_M30_BOS_OB_FVG_LIMIT";
   g_setup.zoneId=cm;
   g_setup.aoiTime=born;
   g_setup.zlo=lo;g_setup.zhi=hi;
   g_setup.obLo=lo;g_setup.obHi=hi;g_setup.hasOB=true;
   g_entryModel=ct?"COUNTERTREND RETRACE":"TREND FOLLOW";
   g_ctActive=ct;
   g_zoneRefresh=true;
}

void SyncState()
{
   ScanExposure();
   if(g_hasPos)
   {
      if(g_state != S8_POSITION_ACTIVE) { g_state = S8_POSITION_ACTIVE; LogCSV("FILL", ""); }
      return;
   }
   if(g_hasPend && g_pendTicket > 0)
   {
      if(g_state != S7_LIMIT_ACTIVE) g_state = S7_LIMIT_ACTIVE;
      RestoreOBFVGOrderContext();
      if(g_planEntry <= 0 && OrderSelect(g_pendTicket))
      {
         string cm=OrderGetString(ORDER_COMMENT);
         if(StringFind(cm,"CTOB")==0)
         {g_entryModel="COUNTERTREND RETRACE";g_ctActive=true;}
         else if(StringFind(cm,"TFOB")==0)
         {g_entryModel="TREND FOLLOW";g_ctActive=false;}
         g_planEntry = OrderGetDouble(ORDER_PRICE_OPEN);
         g_planSL = OrderGetDouble(ORDER_SL);
         g_planTP = OrderGetDouble(ORDER_TP);
         if(g_pip > 0) g_planSLpips = MathAbs(g_planEntry-g_planSL)/g_pip;
         if(g_planSLpips > 0) g_planRR = MathAbs(g_planTP-g_planEntry)/MathAbs(g_planEntry-g_planSL);
         g_zoneRefresh = true;
      }
      datetime expiry = g_pendExpire;
      if(OrderSelect(g_pendTicket))
      {
         datetime expServer = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
         datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         if(expServer > 0) expiry = expServer;
         else if(setupTime > 0)
         {
            string cm=OrderGetString(ORDER_COMMENT);
            int minutes=(StringFind(cm,"CTOB")==0)?InpCTOrderExpiryMinutes:InpOrderExpiryMinutes;
            expiry=setupTime+minutes*60;
         }
      }
      if(expiry > 0 && TimeCurrent() >= expiry)
      {
         bool canceled = g_trade.OrderDelete(g_pendTicket);
         g_lastRet = g_trade.ResultRetcode();
         if(canceled && g_lastRet == TRADE_RETCODE_DONE)
            LogCSV("CANCEL", "PENDING_EXPIRED");
         else LogCSV("CANCEL_FAIL", "PENDING_EXPIRED", g_trade.ResultRetcodeDescription());
      }
      return;
   }
   if(g_state == S7_LIMIT_ACTIVE || g_state == S8_POSITION_ACTIVE)
   {
      LogCSV("CLOSED_OR_CANCELLED", "");
      g_state = S9_COOLDOWN;
      g_cooldownUntil = TimeCurrent() + InpCooldownMinutes * 60;
      g_pendExpire = 0;
      ClearSetup();
      g_ctActive=false;
      g_entryModel="WAITING";
      g_zoneRefresh = true;
   }
}

void CheckPendingInvalidation()
{
   if(g_state != S7_LIMIT_ACTIVE || !g_hasPend || g_pendTicket == 0 || !OrderSelect(g_pendTicket)) return;
   ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   if(ot != ORDER_TYPE_BUY_LIMIT && ot != ORDER_TYPE_SELL_LIMIT) return;
   int dir = (ot == ORDER_TYPE_BUY_LIMIT) ? 1 : -1;
   double price = OrderGetDouble(ORDER_PRICE_OPEN);
   bool validH1;
   double p1 = PDPos(PERIOD_H1, price, validH1);
   bool cancel = (validH1 && BiasOf(p1) == -dir);
   string code = cancel ? "H1_BIAS_REVERSED" : "";
   if(g_setup.active)
   {
      double cl = iClose(_Symbol, PERIOD_M1, 1);
      if((dir > 0 && cl < g_setup.zlo) || (dir < 0 && cl > g_setup.zhi))
      { cancel = true; code = "AOI_INVALID"; }
      if(g_setup.hasOB && ((dir > 0 && cl < g_setup.obLo) || (dir < 0 && cl > g_setup.obHi)))
      { cancel = true; code = "OB_INVALID"; }
   }
   if(cancel)
   {
      bool deleted = g_trade.OrderDelete(g_pendTicket);
      g_lastRet = g_trade.ResultRetcode();
      LogCSV(deleted && g_lastRet == TRADE_RETCODE_DONE ? "CANCEL" : "CANCEL_FAIL",
             code, g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| AOI & mesin state                                                |
//+------------------------------------------------------------------+
bool TryActivateAOI(int zi)
{
   int dir = g_zones[zi].dir;
   double price = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / 2.0;
   double pH1, pM30; string why;
   if(!PDPass(dir, price, pH1, pM30, why)) { CountR("AOI_FAIL:" + why); SetReason(why); return false; }
   Rng g = BuildRange(PERIOD_H1, price);
   if(!g.ok) { CountR("AOI_FAIL:WAIT_RANGE"); SetReason("WAIT_RANGE"); return false; }
   g_zones[zi].attempts++;
   g_zones[zi].lastAttempt = TimeCurrent();
   g_zoneRefresh = true;
   g_reason = "";
   g_setup.active = true; g_setup.dir = dir; g_setup.zoneId = g_zones[zi].id;
   g_setup.zlo = g_zones[zi].lo; g_setup.zhi = g_zones[zi].hi;
   g_setup.aoiTime = iTime(_Symbol, PERIOD_M1, 1);
   g_setup.pdH1 = pH1; g_setup.pdM30 = pM30; g_setup.route = "";
   g_setup.id = StringFormat("SMC%s%I64d", dir > 0 ? "B" : "S", (long)g_setup.aoiTime);
   g_state = S3_WAIT_M15_M5;
   g_fAOI++;
   LogCSV("AOI_ACTIVE", "", g_zones[zi].id + " vol=" + DoubleToString(g_zones[zi].volRatio, 2) +
          (g_zones[zi].real ? " VOLUME_REAL" : " VOLUME_TICK_PROXY"));
   return true;
}

void ResetSetup(string code)
{
   LogCSV("RESET", code);
   ClearSetup();
   g_zoneRefresh = true;
   g_state = S2_WAIT_AOI;
}

void StageM15M5()
{
   int dir = g_setup.dir;
   string w15 = "", w5 = "";
   Seq q15, q5;
   q15.sweepT = 0; q15.mssT = 0; q15.sweepExt = 0; q15.lhLevel = 0;
   q5.sweepT = 0; q5.mssT = 0; q5.sweepExt = 0; q5.lhLevel = 0;
   bool has15 = SweepMSS(PERIOD_M15, dir, g_setup.aoiTime - PeriodSeconds(PERIOD_M15), q15, w15);
   bool has5 = SweepMSS(PERIOD_M5, dir, g_setup.aoiTime - PeriodSeconds(PERIOD_M5), q5, w5);
   bool soft = false;
   if(!has15 && !has5 && !InpStrictMode && !InpRequireIDMSweep)
   {
      datetime mt = 0;
      if(MSSOnly(PERIOD_M5, dir, g_setup.aoiTime - PeriodSeconds(PERIOD_M5), mt))
      { has5 = true; q5.mssT = mt; soft = true; }
      else if(MSSOnly(PERIOD_M15, dir, g_setup.aoiTime - PeriodSeconds(PERIOD_M15), mt))
      { has15 = true; q15.mssT = mt; soft = true; }
   }
   if(InpStrictMode && (!has15 || !has5))
   { SetReason("STRICT_NEEDS_M15_AND_M5_MSS"); return; }
   if(!has15 && !has5) { SetReason("WAIT_MSS_IDM_M15_M5"); return; }

   datetime mssRef = has5 ? q5.mssT : q15.mssT;
   datetime bos = 0;
   bool hasBOS = M15BOS(dir, mssRef, bos);
   if((InpStrictMode || InpRequireM15BOS) && !hasBOS)
   { SetReason("M15_BOS_MISSING"); return; }

   double olo = 0, ohi = 0;
   bool hasOB = false;
   if(has15) hasOB = FindOB(PERIOD_M15, dir, q15.mssT, olo, ohi);
   if(!hasOB && has5) hasOB = FindOB(PERIOD_M5, dir, q5.mssT, olo, ohi);
   if((InpStrictMode || InpRequireOB) && !hasOB)
   { SetReason("OB_MISSING"); return; }

   datetime fvgMin = has5 ? (q5.sweepT > 0 ? q5.sweepT : q5.mssT) : g_setup.aoiTime;
   FVG f; string fw = "";
   if(!M5FVG(dir, fvgMin, f, fw)) { SetReason(fw); return; }
   g_setup.bosT = bos;
   g_setup.m15Sweep = has15 ? q15.sweepT : 0;
   g_setup.m15Mss = has15 ? q15.mssT : 0;
   g_setup.m5Sweep = has5 ? q5.sweepT : 0;
   g_setup.m5Mss = has5 ? q5.mssT : 0;
   g_setup.hasOB = hasOB; g_setup.hasFVG5 = true;
   g_setup.obLo = olo; g_setup.obHi = ohi;
   g_setup.fvg5lo = f.lo; g_setup.fvg5hi = f.hi; g_setup.fvg5Born = f.born;
   g_setup.fvg5Ratio = f.volRatio; g_setup.fvg5Real = f.real;
   g_setup.softStructure = soft;
   g_zoneRefresh = true;
   g_state = (InpStrictMode || InpRequireM3MSS) ? S4_WAIT_M3 : S5_WAIT_M1;
   g_fS3++;
   g_reason = "";
   LogCSV("STRUCTURE_OK", "", StringFormat("M15_MSS=%s M5_MSS=%s BOS=%s OB=%s M5FVG=[%.2f..%.2f] vol=%.2f %s",
      TimeToString(q15.mssT, TIME_MINUTES), TimeToString(q5.mssT, TIME_MINUTES),
      hasBOS ? "YES" : "OPTIONAL", hasOB ? "YES" : "FVG_ONLY", f.lo, f.hi, f.volRatio, soft ? "SOFT_MSS" : "SWEEP_MSS"));
}


//+------------------------------------------------------------------+
//| AGGRESSIVE v2.20. Price-action SMC berbasis candle tertutup.      |
//| Jalur ini TIDAK mengubah BALANCED dan STRICT dari v2.10.         |
//| Market execution hanya sesudah AOI + M1 directional confirmation.|
//+------------------------------------------------------------------+
int AggStructureBias(ENUM_TIMEFRAMES tf)
{
   MqlRates r[];
   if(!LoadRates(tf, 32, 1, r)) return 0;
   // Bias dari perpindahan close 5 candle TF vs close terakhir, bukan PD dua TF wajib.
   double now=r[1].close, prior=r[6].close;
   if(now > prior + g_tick) return 1;
   if(now < prior - g_tick) return -1;
   if(r[1].close > r[1].open) return 1;
   if(r[1].close < r[1].open) return -1;
   return 0;
}

// Volume untuk konfirmasi impulse M5 pada AOI. Tick-volume proxy saat real-volume absen.
bool AggVolOK(const MqlRates &r[], int idx, double &ratio)
{
   ratio=0;
   bool real=false;
   if(!VolInfo(r,idx,InpVolumeLookback,ratio,real)) return false;
   return ratio>=InpAggressiveMinVolRatio;
}

// Ambil AOI relevan, prioritas: FVG HTF -> FVG M5 -> OB M5.
// AOI boleh dekat harga, tidak wajib tepat disentuh pada candle M1 yang sama.
bool AggFindAOI(int dir, double price, double &zl, double &zh, string &kind, double &vol)
{
   MqlRates r[];
   if(!LoadRates(PERIOD_M5, 90, dir, r)) return false;
   double atr=ATRAt(r,1,InpDisplacementATRPeriod);
   if(atr<=0) return false;
   double tolerance=InpAggressiveNearATR*atr;
   double best=DBL_MAX;
   bool found=false;
   zl=0; zh=0; vol=0; kind="";
   // Confirmed higher-TF FVG zones (born<=now, alive, direction matched).
   for(int i=0;i<ArraySize(g_zones);i++)
   {
      if(g_zones[i].dead || g_zones[i].dir!=dir) continue;
      if(TimeCurrent()-g_zones[i].born > (long)InpZoneMaxAgeHours*3600) continue;
      double low=g_zones[i].lo, high=g_zones[i].hi;
      double dist=(price<low ? low-price : price>high ? price-high : 0);
      if(dist>tolerance || dist>=best) continue;
      best=dist; zl=low; zh=high;
      kind=EnumToString(g_zones[i].tf)+" FVG"; vol=g_zones[i].volRatio;
      found=true;
   }
   // Search M5 gaps, with M5 impulse and volume; relaxed versus HTF FVG gate.
   int maxScan=MathMin(InpAggressiveScanM5,55);
   for(int c=1;c<=maxScan;c++)
   {
      int b=c+1, a=c+2;
      double gap=r[c].low-r[a].high;
      double imp=r[b].close-r[b].open;
      double vr=0;
      if(gap<g_tick || imp<atr*0.30 || !AggVolOK(r,b,vr)) continue;
      double low=Px(r[a].high,dir), high=Px(r[c].low,dir);
      if(dir<0) { low=Px(r[c].low,dir); high=Px(r[a].high,dir); }
      if(low>=high) continue;
      double dist=price<low ? low-price : price>high ? price-high : 0;
      if(dist>tolerance || dist>=best) continue;
      // Reject breached FVG since formation (in mirrored coordinates).
      bool broken=false;
      for(int j=c-1;j>=1;j--) if(r[j].close<r[a].high) { broken=true; break; }
      if(broken) continue;
      best=dist; zl=low; zh=high; kind="M5 FVG"; vol=vr; found=true;
   }
   // Search order block: last opposite M5 candle immediately before bullish impulse.
   for(int c=2;c<=maxScan;c++)
   {
      if(!(r[c].close<r[c].open && r[c-1].close>r[c-1].open)) continue;
      double impulse=r[c-1].close-r[c-1].open, vr=0;
      if(impulse < 0.25*atr || !AggVolOK(r,c-1,vr)) continue;
      double low=Px(r[c].low,dir), high=Px(r[c].high,dir);
      if(dir<0) { low=Px(r[c].high,dir); high=Px(r[c].low,dir); }
      if(low>=high) continue;
      double dist=price<low ? low-price : price>high ? price-high : 0;
      if(dist>tolerance || dist>=best) continue;
      bool broken=false;
      // OB invalid after price closes through distal boundary.
      for(int j=c-1;j>=1;j--) if(r[j].close < r[c].low) { broken=true; break; }
      if(broken) continue;
      best=dist; zl=low; zh=high; kind="M5 OB"; vol=vr; found=true;
   }
   return found;
}

// Trigger M1: satu candle displacement arah bias ATAU break high/low M1 sebelumnya.
// Tidak wajib rantai rejection+CISD+FVG M1 yang langka pada BALANCED.
bool AggM1Signal(int dir, string &pattern, double &stopExtreme)
{
   MqlRates r[];
   if(!LoadRates(PERIOD_M1,48,dir,r)) return false;
   double atr=ATRAt(r,1,InpDisplacementATRPeriod);
   if(atr<=0) return false;
   double body=r[1].close-r[1].open;
   double range=r[1].high-r[1].low;
   if(body<=0 || range<=0) return false;
   bool impulse=(body>=InpAggressiveM1BodyATR*atr && body/range>=0.45 &&
                 r[1].close>=r[1].low+0.65*range);
   bool breakHigh=(r[1].close > r[2].high+g_tick && body/range>=0.35);
   if(!impulse && !breakHigh) return false;
   pattern=breakHigh?"M1_BREAK":"M1_IMPULSE";
   int n=MathMax(2,MathMin(6,InpAggressiveStopBars));
   double ext=r[1].low;
   for(int i=2;i<=n;i++) ext=MathMin(ext,r[i].low);
   stopExtreme=Px(ext,dir);
   return true;
}

// Batas intraday dihitung dari deal masuk ber-Magic Number di hari server sekarang.
int AggDealsToday()
{
   datetime now=TimeCurrent();
   MqlDateTime d; TimeToStruct(now,d);
   d.hour=0; d.min=0; d.sec=0;
   datetime start=StructToTime(d);
   if(!HistorySelect(start,now)) return -1;
   int n=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber) continue;
      long en=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(en==DEAL_ENTRY_IN || en==DEAL_ENTRY_INOUT) n++;
   }
   return n;
}

bool AggMarketSend(int dir,double sl,double tp,string tag)
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetDeviationInPoints(30);
   bool sent=(dir>0) ? g_trade.Buy(InpFixedLot,_Symbol,0,sl,tp,tag)
                     : g_trade.Sell(InpFixedLot,_Symbol,0,sl,tp,tag);
   g_lastRet=g_trade.ResultRetcode();
   g_lastTicket=g_trade.ResultDeal();
   // MQL5: CTrade.Buy/Sell return true != proven fill: inspect retcode and deal.
   if(sent && (g_lastRet==TRADE_RETCODE_DONE || g_lastRet==TRADE_RETCODE_DONE_PARTIAL)
      && g_trade.ResultDeal()>0) return true;
   LogCSV("ORDER_REJECTED","MARKET_REJECTED",g_trade.ResultRetcodeDescription());
   PrintFormat("SMC Agg market rejected: %s retcode=%u deal=%I64u",g_trade.ResultRetcodeDescription(),g_lastRet,g_trade.ResultDeal());
   return false;
}

// Re-sinkronkan SL/TP terhadap HARGA FILL aktual (slippage), maksimal setiap 20 detik.
// Hanya posisi yang dibuat mode FIXED SL versi ini dengan prefix comment F50.
// Jangan pernah melebarkan SL melewati 50 pip dari harga entry aktual.
void AlignAggressiveSLToFill()
{
   if(!InpAggressiveMode || !InpAggressiveFixedSL) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      string comment=PositionGetString(POSITION_COMMENT);
      if(StringFind(comment,"F50")!=0) continue;  // lindungi posisi mode/versi lain
      long type=PositionGetInteger(POSITION_TYPE);
      int dir=(type==POSITION_TYPE_BUY)?1:-1;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double oldSL=PositionGetDouble(POSITION_SL),oldTP=PositionGetDouble(POSITION_TP);
      if(entry<=0 || oldSL<=0 || oldTP<=0) return;
      double dist=InpAggressiveSLPips*g_pip;
      double sl=dir>0?CeilTick(entry-dist):FloorTick(entry+dist);
      double R=MathAbs(entry-sl);
      double activeRR=InpTargetRR;
      double tp=dir>0?CeilTick(entry+activeRR*R):FloorTick(entry-activeRR*R);
      g_planEntry=entry; g_planSL=oldSL; g_planTP=oldTP;
      g_planSLpips=MathAbs(entry-oldSL)/g_pip;
      if(MathAbs(entry-oldSL)>g_tick*0.5)
         g_planRR=MathAbs(entry-oldTP)/MathAbs(entry-oldSL);
      g_zoneRefresh=true;
      // Jangan melebarkan SL yang sudah diperketat secara manual atau di terminal.
      // Penyesuaian ini khusus koreksi awal akibat slippage pada order legacy.
      if((oldSL-sl)*dir > g_tick*0.5)
      {
         return;
      }
      // Sudah selaras terhadap fill; tampilkan nilai live di dashboard.
      if(MathAbs(sl-oldSL)<g_tick*0.5 && MathAbs(tp-oldTP)<g_tick*0.5) return;
      double maxAllowed=InpMaxSLPips*g_pip;
      if(R>maxAllowed+g_tick*0.51 || R>50.0*g_pip+g_tick*0.51) return;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double minDist=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                    SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point+g_tick;
      // Hindari modify kalau pasar sudah masuk freeze/stops level.
      if((dir>0 && (sl>bid-minDist || tp<bid+minDist)) ||
         (dir<0 && (sl<ask+minDist || tp>ask-minDist)))
      {
         g_reason="SL_ALIGN_BLOCKED_BY_BROKER";
         return;
      }
      bool sent=g_trade.PositionModify(ticket,sl,tp);
      g_lastRet=g_trade.ResultRetcode();
      if(sent && g_lastRet==TRADE_RETCODE_DONE)
      {
         g_planSL=sl; g_planTP=tp;
         g_planSLpips=MathAbs(entry-sl)/g_pip;
         g_planRR=MathAbs(entry-tp)/MathAbs(entry-sl);
         double profitAtSL=0;
         if(OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,InpFixedLot,entry,sl,profitAtSL))
            g_planLoss=profitAtSL;
         LogCSV("SL_ALIGNED_FILL","",StringFormat("fill=%.2f sl=%.2f tp=%.2f actualSL=%.3f pip",entry,sl,tp,g_planSLpips));
      }
      else
      {
         g_reason="SL_ALIGN_REJECTED";
         PrintFormat("SMC v2.63: SL alignment failed for ticket %I64u code=%u (%s)",ticket,g_lastRet,g_trade.ResultRetcodeDescription());
      }
      return;
   }
}


// Rekonstruksi trade plan dari posisi broker setelah EA direstart.
// RR rencana dihitung dari jarak risiko awal (input SL fixed bila aktif).
void RefreshActivePositionPlan()
{
   if(!g_hasPos) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      string cm=PositionGetString(POSITION_COMMENT);
      if(StringFind(cm,"CTOB")==0) {g_entryModel="COUNTERTREND RETRACE";g_ctActive=true;}
      else if(StringFind(cm,"TFOB")==0) {g_entryModel="TREND FOLLOW";g_ctActive=false;}
      double fill=PositionGetDouble(POSITION_PRICE_OPEN);
      double stop=PositionGetDouble(POSITION_SL);
      double target=PositionGetDouble(POSITION_TP);
      if(fill<=0 || stop<=0 || target<=0) return;
      if(MathAbs(g_planEntry-fill)>g_tick*0.5 ||
         MathAbs(g_planSL-stop)>g_tick*0.5 || MathAbs(g_planTP-target)>g_tick*0.5)
         g_zoneRefresh=true;
      g_planEntry=fill;g_planSL=stop;g_planTP=target;
      g_planSLpips=MathAbs(fill-stop)/g_pip;
      double initialR=InpAggressiveMode && InpAggressiveFixedSL ?
                      InpAggressiveSLPips*g_pip : MathAbs(fill-stop);
      if(initialR>0) g_planRR=MathAbs(target-fill)/initialR;
      return;
   }
}

// Winrate berdasarkan posisi yang ditutup, memasukkan komisi + fee + swap.
// Mengelompokkan deal per POSITION_ID agar entry commission tidak hilang.
// P/L nyaris nol dilabeli FLAT (hasil bersih mendekati nol).
void RefreshPerformanceStats()
{
   if(TimeCurrent()-g_lastPerfScan<30) return;
   g_lastPerfScan=TimeCurrent();
   g_rollingWins=0;g_rollingLosses=0;g_rollingScratch=0;
   datetime now=TimeCurrent();
   if(!HistorySelect(now-30*86400,now)) return;
   long ids[]; double pnl[]; bool closed[];
   int n=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0 || HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol ||
         HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber) continue;
      long id=HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      if(id<=0) continue;
      int idx=-1;
      for(int j=0;j<n;j++) if(ids[j]==id){idx=j;break;}
      if(idx<0)
      {
         idx=n++;
         ArrayResize(ids,n);ArrayResize(pnl,n);ArrayResize(closed,n);
         ids[idx]=id;pnl[idx]=0;closed[idx]=false;
      }
      pnl[idx]+=HistoryDealGetDouble(ticket,DEAL_PROFIT)+
                HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
                HistoryDealGetDouble(ticket,DEAL_SWAP)+
                HistoryDealGetDouble(ticket,DEAL_FEE);
      long en=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_OUT_BY || en==DEAL_ENTRY_INOUT)
         closed[idx]=true;
   }
   for(int i=0;i<n;i++)
   {
      if(!closed[i]) continue;
      if(pnl[i]>0.01) g_rollingWins++;
      else if(pnl[i]<-0.01) g_rollingLosses++;
      else g_rollingScratch++;
   }
}

//+------------------------------------------------------------------+
//| SELECTIVE v2.63: filter SMC untuk menghindari chasing candle      |
//| Semua keputusan berdasarkan candle yang SUDAH close.             |
//+------------------------------------------------------------------+
// Trend H1/M30 diselaraskan memakai close vs SMA20/50, slope SMA20.
// Filter momentum, bukan klaim mendeteksi order institusi.
int SelectiveTrend(ENUM_TIMEFRAMES tf)
{
   MqlRates r[];
   if(!LoadRates(tf,75,1,r)) return 0;
   double sma20=0,sma50=0,prev20=0;
   for(int i=1;i<=50;i++)
   {
      sma50+=r[i].close;
      if(i<=20) sma20+=r[i].close;
   }
   for(int i=2;i<=21;i++) prev20+=r[i].close;
   sma20/=20.0; sma50/=50.0; prev20/=20.0;
   if(r[1].close>sma20 && sma20>sma50 && sma20>prev20) return 1;
   if(r[1].close<sma20 && sma20<sma50 && sma20<prev20) return -1;
   return 0;
}

// BOS / MSS proxy: close candle M5 menembus swing pivot yang SUDAH terkonfirmasi.
bool SelectiveM5BOS(int dir,datetime &bosTime)
{
   MqlRates r[];
   if(!LoadRates(PERIOD_M5,160,dir,r)) return false;
   int piv[], L=MathMax(2,InpLTFSwingLeftRight);
   int np=FindPivots(r,L,L,true,piv,25);
   for(int i=0;i<np;i++)
   {
      int p=piv[i];
      int first=MathMin(p-L-1,InpSelectiveBOSBars);
      for(int b=first;b>=1;b--)
      {
         if(InpQualityRecentM5BOS && b>InpQualityBOSMaxAgeM5Bars) continue;
         // CROSSING yang baru terjadi, bukan sekadar harga yang tetap di atas pivot lama.
         // r[b+1] adalah candle SEBELUM breakout (bar lebih tua pada time series).
         if(r[b].close>r[p].high+g_tick && r[b+1].close<=r[p].high+g_tick &&
            r[b].close>r[b].open)
         {
            bosTime=r[b].time;
            return true;
         }
      }
   }
   return false;
}

// AOI disentuh oleh candle M1 yang tertutup; sinyal M1 harus bereaksi
// ke arah bias, bukan hanya 'candle besar dekat AOI'.
bool SelectiveM1Rejection(int dir,double zl,double zh,string &signal,
                          datetime &touchT,double &volRatio)
{
   MqlRates r[];
   if(!LoadRates(PERIOD_M1,90,dir,r)) return false;
   double atr=ATRAt(r,1,InpDisplacementATRPeriod);
   if(atr<=0) return false;
   int touchShift=-1;
   for(int i=1;i<=InpSelectiveTouchBars;i++)
   {
      // M1 dalam harga asli untuk tes kontak dengan AOI asli.
      double low=dir>0?r[i].low:-r[i].high;
      double high=dir>0?r[i].high:-r[i].low;
      double close=dir>0?r[i].close:-r[i].close;
      if(low<=zh+g_tick && high>=zl-g_tick &&
         (dir>0 ? close>=zl-g_tick : close<=zh+g_tick))
      { touchShift=i; break; }
   }
   if(touchShift<0) return false;
   touchT=r[touchShift].time;
   double body=r[1].close-r[1].open;
   double range=r[1].high-r[1].low;
   if(body<=0 || range<=0) return false;
   if(body>InpSelectiveM1MaxBodyATR*atr) return false; // jangan kejar FOMO
   bool breakPrev=(body>=InpSelectiveM1MinBodyATR*atr &&
                   body/range>=0.50 && r[1].close>r[2].high+g_tick &&
                   r[1].close>=r[1].low+0.7*range);
   double lowerWick=MathMin(r[1].open,r[1].close)-r[1].low;
   bool rej=(touchShift==1 && lowerWick>=MathMax(body*0.8,g_tick) &&
             r[1].close>=r[1].low+0.75*range && r[1].close>r[1].open);
   if(InpQualityStrongM1Rejection && rej)
   {
      // Mencegah entry pada doji hijau / wick pantulan yang belum menunjukkan follow-through.
      rej=(body>=InpQualityRejMinBodyATR*atr &&
           r[1].close>r[2].close+g_tick);
   }
   if(!breakPrev && !rej) return false;
   bool real=false;
   if(!VolInfo(r,1,InpVolumeLookback,volRatio,real) ||
      volRatio<InpSelectiveM1VolRatio) return false;
   signal=breakPrev?"M1_RETEST_BREAK":"M1_REJECTION";
   return true;
}

// Total entry, realized P/L, dan loss streak memakai HISTORY deal EA ini.
// Komisi masuk dihitung juga dalam P/L harian, loss streak via exit deal.
bool SelectiveDayStats(int &entries,int &streak,double &net,datetime &lastLoss)
{
   entries=0;streak=0;net=0;lastLoss=0;
   datetime now=TimeCurrent();
   MqlDateTime d;TimeToStruct(now,d);
   d.hour=0;d.min=0;d.sec=0;
   datetime dayStart=StructToTime(d);
   // Kumpulan posisi (entry+exit+komisi) agar hasil posisi nyaris nol tidak dianggap
   // profit/loss hanya dari DEAL_PROFIT pada penutupan.
   // Lookback 90 hari mendukung posisi yang dibuka sebelum hari ini.
   if(!HistorySelect(now-90*86400,now)) return false;
   long ids[];
   double totals[];
   datetime exits[];
   int n=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0 || HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol ||
         HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber) continue;
      datetime when=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      long en=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      double money=HistoryDealGetDouble(ticket,DEAL_PROFIT)+
                   HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
                   HistoryDealGetDouble(ticket,DEAL_SWAP)+
                   HistoryDealGetDouble(ticket,DEAL_FEE);
      if(when>=dayStart)
      {
         net+=money;
         if(en==DEAL_ENTRY_IN || en==DEAL_ENTRY_INOUT) entries++;
      }
      long id=HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      if(id<=0) continue;
      int idx=-1;
      for(int k=0;k<n;k++) if(ids[k]==id){idx=k;break;}
      if(idx<0)
      {
         idx=n++;
         ArrayResize(ids,n);ArrayResize(totals,n);ArrayResize(exits,n);
         ids[idx]=id;totals[idx]=0;exits[idx]=0;
      }
      totals[idx]+=money;
      if(en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_OUT_BY || en==DEAL_ENTRY_INOUT)
         if(when>exits[idx]) exits[idx]=when;
   }
   for(int i=0;i<n;i++)
      if(exits[i]>=dayStart && totals[i]<-0.01 && exits[i]>lastLoss)
         lastLoss=exits[i];
   // Telusuri posisi closed dari TERBARU menuju TERLAMA.
   // Hasil netral menghentikan rangkaian loss, seperti trade non-loss.
   datetime prior=now+1;
   for(int rank=0;rank<n;rank++)
   {
      int idx=-1;
      for(int j=0;j<n;j++)
         if(exits[j]>=dayStart && exits[j]<prior && (idx<0 || exits[j]>exits[idx])) idx=j;
      if(idx<0) break;
      if(totals[idx]<-0.01) streak++;
      else break;
      prior=exits[idx];
   }
   return true;
}

string SelectiveZoneKey(string kind,double lo,double hi)
{
   return StringFormat("%s:%I64d:%I64d",kind,(long)MathRound(lo/g_tick),(long)MathRound(hi/g_tick));
}

//+------------------------------------------------------------------+
//| v2.63: FIND A REAL OB -> DISPLACEMENT -> FVG CAUSAL PAIR         |
//| Confirmed M5 bars only. In SELL, mirrored prices become BUY logic.|
//| CISD / sweep are NOT triggers and NOT entry prices.              |
//+------------------------------------------------------------------+
bool FindLinkedOBFVG(int dir, datetime bos, OBFVGPair &o, string &reason, bool requireLinkedBOS=false)
{
   o.ok=false; reason="OBFVG_NO_VALID_PAIR";
   MqlRates r[];
   if(!LoadRates(PERIOD_M5, 180, dir, r)) {reason="OBFVG_DATA_MISSING";return false;}
   double atr=ATRAt(r,1,InpDisplacementATRPeriod);
   if(atr<=0) {reason="OBFVG_ATR_UNAVAILABLE";return false;}
   double current= r[1].close;  // CLOSED M5 candle, no lookahead
   int maxC=MathMin(InpOBFVGScanM5,InpOBFVGMaxAgeM5Bars);
   for(int c=1;c<=maxC;c++)
   {
      int b=c+1;
      FVG gap;string why="";
      if(!CheckFVGBull(r,PERIOD_M5,c,gap,why,true)) continue; // volume REQUIRED
      // The BOS must belong to the same recent displacement leg, not a
      // structure break hours before this OB/FVG pair formed.
      if((InpOBFVGRequireBOS || requireLinkedBOS) && bos>0 &&
         MathAbs((double)((long)gap.born-(long)bos)) >
            (double)InpOBFVGBOSLinkBars*PeriodSeconds(PERIOD_M5)) continue;
      double atrFormation=ATRAt(r,b,InpDisplacementATRPeriod);
      if(atrFormation<=0) continue;
      // FVG becomes invalid after complete mitigation through its lower edge.
      bool filled=false;
      for(int j=c-1;j>=1;j--)
         if(r[j].low <= gap.lo-g_tick*0.5) {filled=true;break;}
      if(InpOBFVGRequireUnfilledFVG && filled) continue;
      // Choose LAST bearish candle directly before the displacement (the first
      // opposing candle encountered while walking back from B).
      int lastOpp=-1;
      for(int k=b+1;k<=b+InpOBSearchPriorBars && k<ArraySize(r);k++)
         if(r[k].close<r[k].open) {lastOpp=k;break;}
      if(lastOpp<0) continue;
      double obLow=r[lastOpp].low, obHigh=r[lastOpp].high;
      if(obHigh<=obLow || obHigh-obLow>5.0*atrFormation) continue;
      double separation=MathMax(0.0,gap.lo-obHigh);
      if(separation>InpOBFVGMaxGapOB_ATR*atrFormation) continue;
      bool invalid=false,retouched=false;
      // After the OB formed, a close below distal invalidates the zone.
      // A touched order block AFTER FVG C closes is not a fresh first mitigation.
      for(int j=lastOpp-1;j>=1;j--)
      {
         if(r[j].close < obLow-g_tick*0.5) {invalid=true;break;}
         if(j<c && r[j].low<=obHigh+g_tick*0.5) retouched=true;
      }
      if(invalid || (InpOBFVGRequireUntouched && retouched)) continue;
      double desired=obLow+InpOBFVGEntryDepth*(obHigh-obLow);
      // Require market to be above the OB for BUY (mirrored condition for SELL).
      // No market fallback and do not chase a zone already entered.
      if(current<=obHigh+g_tick || current-desired>InpOBFVGMaxTravelATR*atr) continue;
      double realOBLo=dir>0?obLow:-obHigh;
      double realOBHi=dir>0?obHigh:-obLow;
      double realFVGLo=dir>0?gap.lo:-gap.hi;
      double realFVGHi=dir>0?gap.hi:-gap.lo;
      double entry=dir>0?FloorTick(desired):CeilTick(-desired);
      if(entry<=0 || realOBLo<=0 || realFVGLo<=0) continue;
      o.ok=true;o.dir=dir;
      o.obLo=realOBLo;o.obHi=realOBHi;
      o.fvgLo=realFVGLo;o.fvgHi=realFVGHi;
      o.entry=entry;o.volRatio=gap.volRatio;o.realVolume=gap.real;
      o.obTime=r[lastOpp].time;o.fvgBorn=gap.born;
      o.key=StringFormat("OBFVG_%s_%I64d_%I64d",dir>0?"B":"S",
                         (long)r[lastOpp].time,(long)r[b].time);
      reason="";
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| v2.63: setup trend maupun countertrend memakai OB + FVG M5 yang |
//| sama. Countertrend HARUS reversal M5, dan lokasi OB diverifikasi |
//| terhadap M15 candles yang SUDAH closed pada waktu pembentukan OB.|
//+------------------------------------------------------------------+
bool CTLocationPass(int dir,const OBFVGPair &zone,double &fraction,string &why)
{
   fraction=-1.0; why="";
   if(!InpCTRequireExtremeM15) return true;
   MqlRates r[];
   int count=InpCTRangeM15Bars+80;
   if(!LoadRates(PERIOD_M15,count,1,r)) {why="CT_M15_DATA_MISSING";return false;}
   int shift=iBarShift(_Symbol,PERIOD_M15,zone.obTime,false);
   if(shift<0) {why="CT_M15_TIME_UNAVAILABLE";return false;}
   shift=MathMax(1,shift); // exclude currently forming M15 candle
   if(shift+InpCTRangeM15Bars>ArraySize(r)) {why="CT_M15_RANGE_MISSING";return false;}
   double hi=-DBL_MAX,lo=DBL_MAX;
   for(int j=shift;j<shift+InpCTRangeM15Bars;j++)
   {
      hi=MathMax(hi,r[j].high);
      lo=MathMin(lo,r[j].low);
   }
   if(hi<=lo+g_tick) {why="CT_M15_RANGE_FLAT";return false;}
   fraction=(zone.entry-lo)/(hi-lo);
   if(dir>0 && fraction>InpCTExtremeFraction)
   {why="CT_NOT_AT_M15_DISCOUNT";return false;}
   if(dir<0 && fraction<1.0-InpCTExtremeFraction)
   {why="CT_NOT_AT_M15_PREMIUM";return false;}
   return true;
}

bool TryOBFVGCandidate(int dir,bool isCT,int h1,int m30,OBFVGPair &zone,
                      datetime &bos,double &location,string &why)
{
   bos=0; location=-1.0; why="";
   if(dir==0) {why="OBFVG_DIRECTION_UNKNOWN";return false;}
   if(isCT)
   {
      if(!InpEnableCounterTrend || h1==0 || dir!=-h1)
      {why="CT_DISABLED_OR_NO_H1_TREND";return false;}
      if(InpCTRequireM30Opposite && m30!=dir)
      {why="CT_WAIT_M30_OPPOSITE";return false;}
   }
   else if(h1==0 || m30!=h1 || dir!=h1)
   {why="TF_WAIT_H1_M30_ALIGNMENT";return false;}

   // M5 close benar-benar menembus pivot (MSS/BOS proxy) di arah entry.
   // Countertrend tidak diperbolehkan melewati filter ini meskipun input
   // BOS biasa dibuat optional.
   if((isCT || InpOBFVGRequireBOS) && !SelectiveM5BOS(dir,bos))
   {why=isCT?"CT_WAIT_M5_MSS_BOS":"TF_WAIT_M5_BOS";return false;}
   if(!FindLinkedOBFVG(dir,bos,zone,why,isCT)) return false;
   if(isCT && !CTLocationPass(dir,zone,location,why)) return false;
   return true;
}

bool CancelOBFVGPending(string reason)
{
   if(g_pendTicket==0 || !OrderSelect(g_pendTicket)) return false;
   bool sent=g_trade.OrderDelete(g_pendTicket);
   g_lastRet=g_trade.ResultRetcode();
   LogCSV(sent&&g_lastRet==TRADE_RETCODE_DONE?"OBFVG_CANCEL":"OBFVG_CANCEL_REJECT",
          reason,g_trade.ResultRetcodeDescription());
   if(sent && g_lastRet==TRADE_RETCODE_DONE) {g_zoneRefresh=true;return true;}
   return false;
}

void CheckOBFVGPending()
{
   if(!InpOBFVGEntryMode || !g_hasPend || g_pendTicket==0 || !OrderSelect(g_pendTicket)) return;
   ENUM_ORDER_TYPE typ=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   if(typ!=ORDER_TYPE_BUY_LIMIT && typ!=ORDER_TYPE_SELL_LIMIT) return;
   int dir=typ==ORDER_TYPE_BUY_LIMIT?1:-1;
   // Preserve broker position; only cancel our own pending order.
   if(OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) return;
   int h1=SelectiveTrend(PERIOD_H1),m30=SelectiveTrend(PERIOD_M30);
   // Order comment survives EA restart in most brokers. When broker truncates
   // comments, g_setup.route is used while the EA has not restarted.
   string comment=OrderGetString(ORDER_COMMENT);
   bool isCT=(StringFind(comment,"CTOB")==0) ||
             (g_setup.active && StringFind(g_setup.route,"COUNTERTREND")>=0);
   if(isCT)
   {
      // Countertrend is deliberately opposite H1. Never cancel just because
      // H1/M30 is opposite, otherwise these orders would always be cancelled.
      if(!InpEnableCounterTrend) {CancelOBFVGPending("CT_MODE_DISABLED");return;}
   }
   else if((h1!=0 && h1!=dir) || (m30!=0 && m30!=dir))
   {CancelOBFVGPending("OBFVG_HTF_REVERSED");return;}
   if(g_setup.active && g_setup.hasOB)
   {
      double cl=iClose(_Symbol,PERIOD_M5,1);
      if((dir>0 && cl<g_setup.obLo-g_tick) || (dir<0 && cl>g_setup.obHi+g_tick))
      {CancelOBFVGPending("OBFVG_DISTAL_BROKEN");return;}
      // First-touch-only execution: if price already tested proximal OB
      // on a CLOSED M5 bar after placing the limit, but midpoint did not fill,
      // retire the pending instead of trading a later second/third mitigation.
      if(InpOBFVGRequireUntouched)
      {
         datetime orderAt=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
         datetime barClose=iTime(_Symbol,PERIOD_M5,1)+PeriodSeconds(PERIOD_M5);
         if(orderAt>0 && barClose>orderAt)
         {
            double lo=iLow(_Symbol,PERIOD_M5,1),hi=iHigh(_Symbol,PERIOD_M5,1);
            if((dir>0 && lo<=g_setup.obHi+g_tick) ||
               (dir<0 && hi>=g_setup.obLo-g_tick))
            {CancelOBFVGPending("OBFVG_FIRST_TOUCH_MISSED_LIMIT");return;}
         }
      }
   }
}

// M5-anchored OB+FVG: limit order is placed BEFORE retest, not on CISD.
// All account risk and daily guards from SELECTIVE are retained.
void RunOBFVGLimit()
{
   if(g_state==S7_LIMIT_ACTIVE || g_state==S8_POSITION_ACTIVE) return;
   if(g_state==S9_COOLDOWN)
   {
      if(TimeCurrent()<g_cooldownUntil) {SetReason("OBFVG_COOLDOWN");return;}
      g_state=S2_WAIT_AOI;
   }
   ScanExposure();
   if(g_manual || g_hasPend || g_hasPos) {SetReason("EXPOSURE_EXISTS");return;}
   int entries=0,streak=0;double dayNet=0;datetime lastLoss=0;
   if(!SelectiveDayStats(entries,streak,dayNet,lastLoss))
   {SetReason("OBFVG_HISTORY_UNAVAILABLE");return;}
   g_selEntries=entries;g_selLossStreak=streak;g_selDayPnL=dayNet;
   if(entries>=InpSelectiveMaxDaily) {SetReason("OBFVG_DAILY_CAP");return;}
   if(streak>=InpSelectiveMaxLossStreak) {SetReason("OBFVG_STREAK_STOP");return;}
   double bal=AccountInfoDouble(ACCOUNT_BALANCE),eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal<=0 || eq<=0) {SetReason("OBFVG_ACCOUNT_ERROR");return;}
   if(dayNet<=-InpSelectiveDailyLossPct*bal/100.0)
   {SetReason("OBFVG_DAILY_LOSS_STOP");return;}
   if(lastLoss>0 && TimeCurrent()<lastLoss+InpSelectiveLossPauseMin*60)
   {SetReason("OBFVG_LOSS_PAUSE");return;}
   if(InpSelectiveUseSession)
   {
      MqlDateTime tm;TimeToStruct(TimeCurrent(),tm);
      bool inSession=InpSelectiveSessionStart<InpSelectiveSessionEnd ?
       (tm.hour>=InpSelectiveSessionStart && tm.hour<InpSelectiveSessionEnd) :
       (tm.hour>=InpSelectiveSessionStart || tm.hour<InpSelectiveSessionEnd);
      if(!inSession) {SetReason("OBFVG_OUT_OF_SESSION");return;}
   }
   g_aggBiasH1=SelectiveTrend(PERIOD_H1);
   g_aggBiasM30=SelectiveTrend(PERIOD_M30);
   int h1=g_aggBiasH1,m30=g_aggBiasM30;
   if(h1==0)
   {g_aggAOIVisible=false;g_pairVisible=false;g_selBOSState="WAIT H1 TREND";
    g_ctDiagnostic="HTF H1 NEUTRAL";SetReason("OBFVG_H1_TREND_UNKNOWN");g_zoneRefresh=true;return;}

   // Ketika M30 menentang H1, utamakan setup retracement.
   // Saat M30 searah H1, utamakan trend continuation namun masih boleh
   // mengambil countertrend bila ada struktur reversal M5 + OB/FVG valid.
   bool ctFirst=InpEnableCounterTrend && InpCTPreferM30Reversal && m30==-h1;
   OBFVGPair zone;
   datetime bos=0;
   double loc=-1.0;
   string why="",whyTF="",whyCT="";
   bool found=false,isCT=false;
   if(ctFirst)
   {
      found=TryOBFVGCandidate(-h1,true,h1,m30,zone,bos,loc,whyCT);
      if(found) isCT=true;
      else found=TryOBFVGCandidate(h1,false,h1,m30,zone,bos,loc,whyTF);
   }
   else
   {
      found=TryOBFVGCandidate(h1,false,h1,m30,zone,bos,loc,whyTF);
      if(!found && InpEnableCounterTrend)
      {found=TryOBFVGCandidate(-h1,true,h1,m30,zone,bos,loc,whyCT);if(found)isCT=true;}
   }
   if(!found)
   {
      g_aggAOIVisible=false;g_pairVisible=false;g_zoneRefresh=true;
      g_selBOSState="M5 STRUCTURE / LINKED FVG WAIT";
      g_selTouchState="WAIT FRESH OB+FVG";
      g_ctDiagnostic=InpEnableCounterTrend?whyCT:"CT DISABLED";
      g_entryModel="WAIT BOTH MODES";
      g_ctActive=false;
      SetReason(whyCT!=""?whyCT:(whyTF!=""?whyTF:"OBFVG_NO_VALID_PAIR"));return;
   }
   g_aggDir=zone.dir;
   g_ctActive=isCT;
   g_ctRangeFraction=isCT?loc:-1.0;
   g_entryModel=isCT?"COUNTERTREND RETRACE":"TREND FOLLOW";
   g_ctDiagnostic=isCT?(loc>=0?StringFormat("M15 EXTREME %.0f%%",loc*100.0):"M15 FILTER OPTIONAL"):
                           "TF H1/M30 ALIGNED";
   g_selBOSState=bos>0?TimeToString(bos,TIME_DATE|TIME_MINUTES):"OPTIONAL";
   g_aggAOIVisible=true;g_aggAOILo=zone.obLo;g_aggAOIHi=zone.obHi;
   g_aggAOIType=isCT?"CT M5 OB + FVG":"TF M5 OB + FVG";g_aggAOIVol=zone.volRatio;
   g_pairVisible=true;g_pairFVGLo=zone.fvgLo;g_pairFVGHi=zone.fvgHi;g_pairVol=zone.volRatio;
   g_selTouchState=isCT?"CT LIMIT 50% OB / FIRST RETEST":"TF LIMIT 50% OB / FIRST RETEST";g_zoneRefresh=true;
   if(g_selLastZoneKey==zone.key && TimeCurrent()-g_selLastZoneTime<InpSelectiveZoneWaitMin*60)
   {SetReason("OBFVG_ALREADY_ATTEMPTED");return;}
   int dir=g_aggDir;
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK),bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(ask<=bid || bid<=0) {SetReason("OBFVG_NO_QUOTES");return;}
   g_lastSpread=(ask-bid)/g_pip;
   if(g_lastSpread>InpMaxSpreadPips) {SetReason("OBFVG_SPREAD_HIGH");return;}
   double entry=zone.entry;
   double minStop=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                  SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point+g_tick;
   if((dir>0 && (entry>=ask-minStop || bid<=zone.obHi+g_tick)) ||
      (dir<0 && (entry<=bid+minStop || ask>=zone.obLo-g_tick)))
   {SetReason("OBFVG_LIMIT_TOO_CLOSE_OR_ZONE_TOUCHED");return;}
   double slD=InpAggressiveSLPips*g_pip;
   double sl=dir>0?CeilTick(entry-slD):FloorTick(entry+slD);
   double riskD=MathAbs(entry-sl);
   if((entry-sl)*dir<=0 || riskD/g_pip>InpMaxSLPips+g_tick/g_pip ||
      MathAbs(riskD-slD)>g_tick+1e-7)
   {SetReason("OBFVG_FIXED_SL_INVALID");return;}
   // Enforce structural coherence: fixed SL must lie beyond distal OB.
   if((dir>0 && sl>=zone.obLo-InpOBFVGDistalBufferPrice) ||
      (dir<0 && sl<=zone.obHi+InpOBFVGDistalBufferPrice))
   {SetReason("OBFVG_FIXED_SL_INSIDE_OB");return;}
   double tp=dir>0?CeilTick(entry+InpTargetRR*riskD):FloorTick(entry-InpTargetRR*riskD);
   if(riskD<minStop || MathAbs(tp-entry)<minStop ||
      (tp-entry)*dir<=0) {SetReason("OBFVG_BROKER_STOP_DISTANCE");return;}
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL ||
      !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {SetReason("OBFVG_TRADE_DISABLED");return;}
   long mode=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
   if((mode & SYMBOL_ORDER_LIMIT)==0 || (mode & SYMBOL_ORDER_SL)==0 || (mode & SYMBOL_ORDER_TP)==0)
   {SetReason("OBFVG_LIMIT_NOT_ALLOWED");return;}
   if(!VolumeValid()) {SetReason("OBFVG_INVALID_LOT");return;}
   double margin=0,loss=0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,InpFixedLot,entry,margin) ||
      margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {SetReason("OBFVG_MARGIN_INSUFFICIENT");return;}
   if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,InpFixedLot,entry,sl,loss))
   {SetReason("OBFVG_RISK_CALC_FAILED");return;}
   g_selRiskPct=MathAbs(loss)/eq*100.0;
   if(loss>=0 || g_selRiskPct>InpSelectiveRiskPct)
   {SetReason("OBFVG_RISK_TOO_HIGH");return;}
   if(dayNet+loss<-InpSelectiveDailyLossPct*bal/100.0)
   {SetReason("OBFVG_DAILY_RISK_BUDGET");return;}
   ClearSetup();
   g_setup.active=true;g_setup.dir=dir;g_setup.zoneId=zone.key;
   g_setup.zlo=zone.obLo;g_setup.zhi=zone.obHi;
   g_setup.obLo=zone.obLo;g_setup.obHi=zone.obHi;g_setup.hasOB=true;
   g_setup.fvg5lo=zone.fvgLo;g_setup.fvg5hi=zone.fvgHi;g_setup.hasFVG5=true;
   g_setup.fvg5Ratio=zone.volRatio;g_setup.fvg5Real=zone.realVolume;
   g_setup.fvg5Born=zone.fvgBorn;g_setup.aoiTime=zone.obTime;
   g_setup.bosT=bos;
   g_setup.route=isCT?"COUNTERTREND_M5_MSS_OB_FVG_LIMIT":"TREND_H1_M30_BOS_OB_FVG_LIMIT";
   // Short comment prefix explicitly identifies countertrend even after EA restart.
   g_setup.id=StringFormat("%s%s%I64d",isCT?"CTOB":"TFOB",dir>0?"B":"S",(long)zone.obTime);
   g_planEntry=entry;g_planSL=sl;g_planTP=tp;
   g_planSLpips=riskD/g_pip;g_planRR=MathAbs(tp-entry)/riskD;g_planLoss=loss;
   datetime expiry=TimeCurrent()+(isCT?InpCTOrderExpiryMinutes:InpOrderExpiryMinutes)*60;
   g_pendExpire=expiry;
   LogCSV("OBFVG_SIGNAL","",StringFormat("mode=%s H1=%d M30=%d locM15=%.2f OB[%.3f..%.3f] FVG[%.3f..%.3f] vol=%.2f entry=%.3f sl=%.3f tp=%.3f RR_CONFIG=%.2f RR_PLAN=%.2f risk=%.2f%%",
      g_entryModel,h1,m30,loc,zone.obLo,zone.obHi,zone.fvgLo,zone.fvgHi,zone.volRatio,entry,sl,tp,InpTargetRR,g_planRR,g_selRiskPct));
   if(SendLimit(dir,entry,sl,tp,expiry,g_setup.id))
   {
      g_state=S7_LIMIT_ACTIVE;g_fPlaced++;
      g_selLastZoneKey=zone.key;g_selLastZoneTime=TimeCurrent();
      g_reason="";
      LogCSV("OBFVG_LIMIT_PLACED","",StringFormat("ticket=%I64u expiry=%s firstTouch=%s rrSet=%.2f rrOrder=%.3f",g_lastTicket,
        TimeToString(expiry,TIME_DATE|TIME_MINUTES),InpOBFVGRequireUntouched?"Y":"N",InpTargetRR,g_planRR));
   }
   else
   {
      LogCSV("OBFVG_LIMIT_REJECTED","BROKER_REJECT",g_trade.ResultRetcodeDescription());
      ClearSetup();g_state=S9_COOLDOWN;
      g_cooldownUntil=TimeCurrent()+MathMax(5,InpCooldownMinutes)*60;
      g_reason="OBFVG_BROKER_REJECT";
   }
   g_zoneRefresh=true;
}

void RunSelective()
{
   if(g_state==S7_LIMIT_ACTIVE || g_state==S8_POSITION_ACTIVE) return;
   if(g_state==S9_COOLDOWN)
   {
      if(TimeCurrent()<g_cooldownUntil) { SetReason("SEL_COOLDOWN"); return; }
      g_state=S2_WAIT_AOI;
   }
   ScanExposure();
   if(g_manual || g_hasPend || g_hasPos) { SetReason("EXPOSURE_EXISTS"); return; }

   int entries=0,streak=0;
   double dayNet=0;
   datetime lastLoss=0;
   if(!SelectiveDayStats(entries,streak,dayNet,lastLoss))
   { SetReason("SEL_HISTORY_UNAVAILABLE"); return; }
   g_selEntries=entries;g_selLossStreak=streak;g_selDayPnL=dayNet;
   if(entries>=InpSelectiveMaxDaily) { SetReason("SEL_DAILY_TRADE_CAP"); return; }
   if(streak>=InpSelectiveMaxLossStreak) { SetReason("SEL_LOSS_STREAK_STOP"); return; }
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal<=0 || equity<=0) { SetReason("SEL_ACCOUNT_DATA"); return; }
   if(dayNet<=-InpSelectiveDailyLossPct*bal/100.0)
   { SetReason("SEL_DAILY_LOSS_STOP"); return; }
   if(lastLoss>0 && TimeCurrent()<lastLoss+InpSelectiveLossPauseMin*60)
   { SetReason("SEL_LOSS_PAUSE"); return; }

   if(InpSelectiveUseSession)
   {
      MqlDateTime tm;TimeToStruct(TimeCurrent(),tm);
      bool inSession;
      if(InpSelectiveSessionStart<InpSelectiveSessionEnd)
         inSession=(tm.hour>=InpSelectiveSessionStart && tm.hour<InpSelectiveSessionEnd);
      else
         inSession=(tm.hour>=InpSelectiveSessionStart || tm.hour<InpSelectiveSessionEnd);
      if(!inSession) { SetReason("SEL_OUT_OF_SESSION"); return; }
   }
   g_aggBiasH1=SelectiveTrend(PERIOD_H1);
   g_aggBiasM30=SelectiveTrend(PERIOD_M30);
   g_aggDir=(g_aggBiasH1!=0 && g_aggBiasH1==g_aggBiasM30) ? g_aggBiasH1 : 0;
   if(g_aggDir==0)
   {
      g_aggAOIVisible=false;g_selBOSState="WAIT TREND";g_selTouchState="WAIT AOI";
      g_zoneRefresh=true;SetReason("SEL_H1_M30_NOT_ALIGNED");return;
   }

   datetime bos=0;
   if(!SelectiveM5BOS(g_aggDir,bos))
   { g_selBOSState="WAIT M5 BOS";SetReason("SEL_M5_BOS_MISSING");return; }
   g_selBOSState=TimeToString(bos,TIME_DATE|TIME_MINUTES);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK),bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(ask<=bid || bid<=0) { SetReason("NO_QUOTES"); return; }
   g_lastSpread=(ask-bid)/g_pip;
   if(g_lastSpread>InpMaxSpreadPips) { SetReason("SPREAD_HIGH");return; }
   double price=(g_aggDir>0)?ask:bid;
   double zl=0,zh=0,vr=0;
   string kind="";
   if(!AggFindAOI(g_aggDir,(ask+bid)*0.5,zl,zh,kind,vr))
   {g_aggAOIVisible=false;g_zoneRefresh=true;SetReason("SEL_WAIT_AOI");return;}
   g_aggAOIVisible=true;g_aggAOILo=zl;g_aggAOIHi=zh;
   g_aggAOIType=kind;g_aggAOIVol=vr;g_zoneRefresh=true;
   if(vr<InpSelectiveM5VolRatio) {SetReason("SEL_AOI_VOLUME_LOW");return;}
   MqlRates m5[];
   if(!LoadRates(PERIOD_M5,45,1,m5)) {SetReason("DATA_MISSING");return;}
   double atr5=ATRAt(m5,1,InpDisplacementATRPeriod);
   if(atr5<=0) {SetReason("DATA_MISSING");return;}
   double dist=(price<zl)?zl-price:(price>zh?price-zh:0);
   if(dist>InpSelectiveNearATR*atr5) {SetReason("SEL_TOO_FAR_FROM_AOI");return;}

   string pattern="";
   datetime touchT=0;
   double v1=0;
   if(!SelectiveM1Rejection(g_aggDir,zl,zh,pattern,touchT,v1))
   { g_selTouchState="WAIT RETEST + REJECTION"; SetReason("SEL_WAIT_M1_RETEST_REJECT");return; }
   MqlRates m1q[];
   if(!LoadRates(PERIOD_M1,40,1,m1q)) {SetReason("DATA_MISSING");return;}
   double atr1q=ATRAt(m1q,1,InpDisplacementATRPeriod);
   if(atr1q<=0) {SetReason("DATA_MISSING");return;}
   double chase=price<zl?zl-price:(price>zh?price-zh:0.0);
   if(chase>InpQualityMaxChaseM1ATR*atr1q)
   {SetReason("SEL_CHASING_AOI");return;}
   g_selTouchState=TimeToString(touchT,TIME_DATE|TIME_MINUTES);
   // Jangan membeli sebelum M5 BOS; konfirmasi BOS harus mendahului retest M1.
   if(bos>touchT) {SetReason("SEL_BOS_AFTER_TOUCH");return;}
   string key=SelectiveZoneKey(kind,zl,zh);
   if(key==g_selLastZoneKey && TimeCurrent()-g_selLastZoneTime<InpSelectiveZoneWaitMin*60)
   {SetReason("SEL_ZONE_REENTRY_COOLDOWN");return;}

   // Stop tetap EXACT 50 user-pip (50.00 harga jika g_pip=1.0).
   if(!InpAggressiveFixedSL) {SetReason("SEL_REQUIRES_FIXED_SL");return;}
   int dir=g_aggDir;
   double stopD=InpAggressiveSLPips*g_pip;
   double sl=dir>0?CeilTick(price-stopD):FloorTick(price+stopD);
   double R=MathAbs(price-sl);
   double slPips=R/g_pip;
   if((price-sl)*dir<=0 || slPips>InpMaxSLPips+g_tick/g_pip ||
      MathAbs(slPips-InpAggressiveSLPips)>g_tick/g_pip+1e-7)
   {SetReason("SEL_FIXED_SL_MISMATCH");return;}
   double tp=dir>0?CeilTick(price+InpTargetRR*R):FloorTick(price-InpTargetRR*R);
   double stop=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point+g_tick;
   if((dir>0 && (sl>bid-stop || tp<bid+stop)) ||
      (dir<0 && (sl<ask+stop || tp>ask-stop)))
   {SetReason("SEL_BROKER_STOPS");return;}
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL ||
      !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {SetReason("TRADE_DISABLED");return;}
   long mode=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
   if((mode & SYMBOL_ORDER_MARKET)==0 || (mode & SYMBOL_ORDER_SL)==0 || (mode & SYMBOL_ORDER_TP)==0)
   {SetReason("BROKER_MARKET_SLTP_DISABLED");return;}
   if(!VolumeValid()) {SetReason("INVALID_VOLUME");return;}
   double margin=0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,InpFixedLot,price,margin) ||
      margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) {SetReason("MARGIN_LOW");return;}
   double loss=0;
   if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,InpFixedLot,price,sl,loss))
   {SetReason("SEL_RISK_CALC_FAILED");return;}
   g_selRiskPct=MathAbs(loss)/equity*100.0;
   if(loss>=0 || g_selRiskPct>InpSelectiveRiskPct)
   {SetReason("SEL_RISK_PERCENT_HIGH");return;}
   // Guard against placing a trade that would exceed remaining daily loss budget.
   // This is an estimate only: slippage and commission can exceed the budget.
   if(dayNet+loss < -InpSelectiveDailyLossPct*bal/100.0)
   {SetReason("SEL_DAILY_RISK_BUDGET");return;}

   ClearSetup();
   g_setup.active=true;g_setup.dir=dir;g_setup.zoneId=kind;
   g_setup.zlo=zl;g_setup.zhi=zh;
   g_setup.aoiTime=iTime(_Symbol,PERIOD_M1,1);
   g_setup.bosT=bos;
   g_setup.id=StringFormat("F50Q%s%I64d",dir>0?"B":"S",(long)g_setup.aoiTime);
   g_setup.route="SELECTIVE_M5_BOS_AOI_RETEST";
   if(kind=="M5 OB") {g_setup.hasOB=true;g_setup.obLo=zl;g_setup.obHi=zh;}
   else {g_setup.hasFVG5=true;g_setup.fvg5lo=zl;g_setup.fvg5hi=zh;g_setup.fvg5Ratio=vr;}
   g_planEntry=price;g_planSL=sl;g_planTP=tp;g_planSLpips=slPips;
   g_planRR=MathAbs(tp-price)/R;g_planLoss=loss;
   g_aggSignal=pattern;g_aggConfirmed++;
   LogCSV("SEL_SIGNAL",pattern,StringFormat("BOS=%s TOUCH=%s AOI=%s[%.2f..%.2f] vol5=%.2f vol1=%.2f risk=%.2f%%",
      TimeToString(bos,TIME_DATE|TIME_MINUTES),TimeToString(touchT,TIME_DATE|TIME_MINUTES),kind,zl,zh,vr,v1,g_selRiskPct));
   if(AggMarketSend(dir,sl,tp,g_setup.id))
   {
      g_state=S8_POSITION_ACTIVE;g_aggOrders++;g_fPlaced++;
      g_selLastZoneKey=key;g_selLastZoneTime=TimeCurrent();
      g_reason="";g_planEntry=g_trade.ResultPrice()>0?g_trade.ResultPrice():price;
      AlignAggressiveSLToFill();
      LogCSV("SELECTIVE_FILLED",pattern,StringFormat("entry=%.2f sl=%.2f tp=%.2f risk=%.2f%%",
         g_planEntry,g_planSL,g_planTP,g_selRiskPct));
   }
   else
   {
      ClearSetup();g_state=S9_COOLDOWN;
      g_cooldownUntil=TimeCurrent()+MathMax(5,InpCooldownMinutes)*60;
      g_reason="MARKET_REJECTED";
   }
   g_zoneRefresh=true;
}

void RunAggressive()
{
   if(g_state==S7_LIMIT_ACTIVE || g_state==S8_POSITION_ACTIVE) return;
   if(g_state==S9_COOLDOWN)
   {
      if(TimeCurrent()<g_cooldownUntil) { SetReason("COOLDOWN"); return; }
      g_state=S2_WAIT_AOI;
   }
   ScanExposure();
   if(g_manual || g_hasPend || g_hasPos) { SetReason("EXPOSURE_EXISTS"); return; }
   int deals=AggDealsToday();
   if(deals<0) { SetReason("HISTORY_UNAVAILABLE"); return; }
   if(deals>=InpAggressiveMaxDaily) { SetReason("DAILY_LIMIT_REACHED"); return; }

   g_aggBiasH1=AggStructureBias(PERIOD_H1);
   g_aggBiasM30=AggStructureBias(PERIOD_M30);
   // Direction H1 dominan. Bila H1 mendatar, M30 menjadi penentu.
   g_aggDir=g_aggBiasH1!=0 ? g_aggBiasH1 : g_aggBiasM30;
   if(g_aggDir==0) { SetReason("WAIT_H1_M30_DIRECTION"); return; }
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK),bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(bid<=0 || ask<=bid) { SetReason("NO_QUOTES"); return; }
   g_lastSpread=(ask-bid)/g_pip;
   if(g_lastSpread>InpMaxSpreadPips) { SetReason("SPREAD_HIGH"); return; }
   double mid=(ask+bid)*0.5,zl=0,zh=0,vr=0;
   string kind="";
   if(!AggFindAOI(g_aggDir,mid,zl,zh,kind,vr))
   { g_aggAOIVisible=false; g_zoneRefresh=true; SetReason("WAIT_NEAR_FVG_OR_OB"); return; }
   g_aggAOIVisible=true; g_aggAOILo=zl; g_aggAOIHi=zh;
   g_aggAOIType=kind; g_aggAOIVol=vr; g_zoneRefresh=true;
   string pat=""; double extreme=0;
   if(!AggM1Signal(g_aggDir,pat,extreme)) { SetReason("WAIT_M1_IMPULSE_OR_BREAK"); return; }
   g_aggSignal=pat; g_aggConfirmed++;

   int dir=g_aggDir;
   double price=dir>0?ask:bid;
   // v2.30: 50 pip adalah jarak TETAP dari entry, BUKAN batas maksimum swing M1.
   // Definisi pengguna: InpPipSizePrice=1.00 -> 50 pip = beda harga 50.00.
   // Ceil BUY/Floor SELL menjaga jarak SL tidak > batas akibat pembulatan tick.
   double stopBuffer=MathMax(InpSLBufferTicks*g_tick,g_tick);
   double sl;
   if(InpAggressiveFixedSL)
   {
      double slDistance=InpAggressiveSLPips*g_pip;
      sl=dir>0?CeilTick(price-slDistance):FloorTick(price+slDistance);
   }
   else
      sl=dir>0?FloorTick(extreme-stopBuffer):CeilTick(extreme+stopBuffer);
   if((price-sl)*dir<=0) { SetReason("INVALID_M1_STOP"); return; }
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point+g_tick;
   // SL broker dibandingkan terhadap Bid untuk BUY dan Ask untuk SELL.
   // Jangan diam-diam melebarkan SL fixed untuk memenuhi stops level.
   if(dir>0 && sl>bid-stops) { SetReason("BROKER_STOPS_FIXED_SL"); return; }
   if(dir<0 && sl<ask+stops) { SetReason("BROKER_STOPS_FIXED_SL"); return; }
   double R=MathAbs(price-sl), slPips=R/g_pip;
   g_planEntry=price; g_planSL=sl; g_planSLpips=slPips;
   double tickTolerance=g_tick/g_pip + 1e-8;
   if(slPips>InpMaxSLPips+tickTolerance || slPips>50.0+tickTolerance)
   { SetReason("SL_OVER_50"); return; }
   if(InpAggressiveFixedSL && MathAbs(slPips-InpAggressiveSLPips)>tickTolerance)
   { SetReason("FIXED_SL_DISTANCE_MISMATCH"); return; }
   if(R<g_tick || slPips<=0) { SetReason("STOP_TOO_CLOSE"); return; }
   double tp=(dir>0) ? CeilTick(price+InpTargetRR*R):FloorTick(price-InpTargetRR*R);
   if(dir>0 && tp<bid+stops) { SetReason("BROKER_TP_STOPS"); return; }
   if(dir<0 && tp>ask-stops) { SetReason("BROKER_TP_STOPS"); return; }
   double actualRR=MathAbs(tp-price)/R;
   if(MathAbs(actualRR-InpTargetRR)>g_tick/R+1e-6) { SetReason("RR_INVALID"); return; }
   g_planRR=actualRR; g_planTP=tp;

   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL ||
      !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)
      || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   { SetReason("TRADE_DISABLED"); return; }
   long orderMode=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
   if((orderMode & SYMBOL_ORDER_MARKET)==0 || (orderMode & SYMBOL_ORDER_SL)==0 ||
      (orderMode & SYMBOL_ORDER_TP)==0) { SetReason("BROKER_MARKET_SLTP_DISABLED"); return; }
   if(!VolumeValid()) { SetReason("INVALID_VOLUME"); return; }
   double margin=0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,InpFixedLot,price,margin)
      || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { SetReason("MARGIN_LOW"); return; }
   double loss=0;
   if(OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,InpFixedLot,price,sl,loss))
      g_planLoss=loss;

   ClearSetup();
   g_setup.active=true; g_setup.dir=dir; g_setup.zoneId=kind;
   g_setup.zlo=zl; g_setup.zhi=zh;
   g_setup.aoiTime=iTime(_Symbol,PERIOD_M1,1);
   g_setup.id=StringFormat("%s%s%I64d",InpAggressiveFixedSL?"F50":"AGG",dir>0?"B":"S",(long)g_setup.aoiTime);
   g_setup.route="AGG_"+kind+"_FIXED_RR";
   if(kind=="M5 OB") { g_setup.hasOB=true; g_setup.obLo=zl; g_setup.obHi=zh; }
   else if(kind=="M5 FVG") { g_setup.hasFVG5=true; g_setup.fvg5lo=zl; g_setup.fvg5hi=zh; g_setup.fvg5Ratio=vr; }
   g_planEntry=price; g_planSL=sl; g_planTP=tp;
   g_planSLpips=slPips; g_planRR=actualRR; g_planLoss=loss;
   g_fAOI++; g_fS3++; g_fS5++;
   LogCSV("AGG_SIGNAL",pat,StringFormat("%s AOI [%.2f..%.2f] vol=%.2f H1=%d M30=%d",kind,zl,zh,vr,g_aggBiasH1,g_aggBiasM30));
   if(AggMarketSend(dir,sl,tp,g_setup.id))
   {
      g_state=S8_POSITION_ACTIVE; g_aggOrders++; g_fPlaced++;
      g_reason="";
      g_planEntry=g_trade.ResultPrice()>0?g_trade.ResultPrice():price;
      AlignAggressiveSLToFill();
      LogCSV("MARKET_FILLED","",StringFormat("%s fill=%.2f SL=%.2f TP=%.2f SLpriceDist=%.2f userPips=%.2f",pat,
             g_planEntry,g_planSL,g_planTP,MathAbs(g_planEntry-g_planSL),g_planSLpips));
   }
   else
   {
      // Tidak mengulang order berkali-kali pada candle yang sama.
      ClearSetup(); g_state=S9_COOLDOWN;
      g_cooldownUntil=TimeCurrent()+MathMax(1,InpCooldownMinutes)*60;
      g_reason="MARKET_REJECTED";
   }
   g_zoneRefresh=true;
}

void OnNewM1()
{
   g_zoneRefresh = true;
   UpdateZones();
   SyncState();
   if(InpAggressiveMode)
   {
      if(InpSelectiveMode && InpOBFVGEntryMode) RunOBFVGLimit();
      else if(InpSelectiveMode) RunSelective();
      else RunAggressive();
      if(InpShowDashboard) UpdateDashboard();
      return;
   }
   if(g_manual)
   {
      if(g_state >= S3_WAIT_M15_M5 && g_state <= S6_RISK_CHECK) ResetSetup("EXPOSURE_EXISTS");
      SetReason("EXPOSURE_EXISTS");
      return;
   }
   if(g_state == S9_COOLDOWN)
   {
      if(TimeCurrent() >= g_cooldownUntil) g_state = S2_WAIT_AOI; else return;
   }
   if(g_state == S1_WAIT_BIAS) g_state = S2_WAIT_AOI;
   CheckPendingInvalidation();

   if(g_state == S2_WAIT_AOI)
   {
      for(int i = 0; i < ArraySize(g_newTouched); i++)
         if(TryActivateAOI(g_newTouched[i])) break;
   }
   // invalidasi setup aktif S3..S5
   if(g_state >= S3_WAIT_M15_M5 && g_state <= S5_WAIT_M1)
   {
      int zi = FindZone(g_setup.zoneId);
      double cl = iClose(_Symbol, PERIOD_M1, 1);
      if(zi < 0 || g_zones[zi].dead)                          { ResetSetup("AOI_INVALID"); return; }
      if(TimeCurrent() - g_setup.aoiTime > (long)InpSetupMaxAgeMinutes * 60) { ResetSetup("SETUP_TIMEOUT"); return; }
      if(g_state >= S4_WAIT_M3 && g_setup.hasOB &&
         ((g_setup.dir > 0 && cl < g_setup.obLo) || (g_setup.dir < 0 && cl > g_setup.obHi)))
      { ResetSetup("STRUCTURE_INVALID"); return; }
   }
   if(g_state == S3_WAIT_M15_M5) StageM15M5();
   if(g_state == S4_WAIT_M3)
   {
      datetime refT = g_setup.m15Mss > g_setup.m5Mss ? g_setup.m15Mss : g_setup.m5Mss;
      datetime m3t = 0;
      if(MSSOnly(PERIOD_M3, g_setup.dir, refT, m3t))
      {
         g_setup.m3Mss = m3t;
         g_state = S5_WAIT_M1;
         g_fS4++;
         LogCSV("M3_MSS_OK", "");
      }
      else SetReason("M3_MSS_MISSING");
   }
   if(g_state == S5_WAIT_M1)
   {
      M1Res m; string w; double pEntry = 0, pSL = 0, pTP = 0;
      datetime triggerStart = g_setup.fvg5Born > g_setup.aoiTime ? g_setup.fvg5Born : g_setup.aoiTime;
      if(M1Trigger(g_setup.dir, g_setup.obLo, g_setup.obHi, triggerStart, m, w))
      {
         g_setup.m1Level = m.level; g_setup.m1Ratio = m.volRatio; g_setup.m1Real = m.real;
         g_state = S6_RISK_CHECK;
         g_fS5++;
         ScanExposure();
         bool ok = !g_hasPend && !g_hasPos && !g_manual;
         if(!ok) { ResetSetup("EXPOSURE_EXISTS"); }
         else if(RiskAndPlace(m, pEntry, pSL, pTP))
         {
            double entry = pEntry, sl = pSL, tp = pTP; int dir = g_setup.dir;
            g_pendExpire = TimeCurrent() + InpOrderExpiryMinutes * 60;
            if(SendLimit(dir, entry, sl, tp, g_pendExpire, g_setup.id))
            {
               g_state = S7_LIMIT_ACTIVE;
               g_fPlaced++;
               g_reason = "";
               g_zoneRefresh = true;
               LogCSV("LIMIT_PLACED", "", StringFormat("SL=%.2f TP=%.2f estLoss=%.2f vol5=%.2f/%s vol1=%.2f/%s",
                      sl, tp, g_planLoss, g_setup.fvg5Ratio, g_setup.fvg5Real ? "REAL" : "TICK",
                      m.volRatio, m.real ? "REAL" : "TICK"));
            }
            else { LogCSV("ORDER_REJECTED", "ORDER_REJECTED", g_trade.ResultRetcodeDescription()); ResetSetup("ORDER_REJECTED"); }
         }
         else ResetSetup(g_reason);
      }
      else SetReason(w);
   }
   if(InpShowDashboard) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
// UI berbasis native MT5 chart objects. Tidak menggunakan Comment().
void UIBox(string key, int x, int y, int w, int h, color bg, color border)
{
   string n = g_prefix + "UI_" + key;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, border);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}
void UILabel(string key, string val, int x, int y, color fg, int size=9, string font="Consolas")
{
   string n = g_prefix + "UI_" + key;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetString(0, n, OBJPROP_FONT, font);
   ObjectSetString(0, n, OBJPROP_TEXT, val);
}
string ShortTime(datetime t)
{
   if(t <= 0) return "--";
   return TimeToString(t, TIME_DATE | TIME_MINUTES);
}
string BiasText(double pd)
{
   if(pd < 0) return "NO RANGE";
   int b = BiasOf(pd);
   return b > 0 ? "BUY  / DISCOUNT" : b < 0 ? "SELL / PREMIUM" : "NEUTRAL / EQ";
}
color BiasColor(double pd)
{
   if(pd < 0) return C'133,148,168';
   int b = BiasOf(pd);
   return b > 0 ? C'75,221,177' : b < 0 ? C'255,118,137' : C'255,198,91';
}
string StateText()
{
   if(!g_ready) return "WARMUP DATA";
   if(g_manual && !g_hasPos && !g_hasPend) return "EXTERNAL EXPOSURE";
   if(InpAggressiveMode && InpSelectiveMode && g_state==S2_WAIT_AOI)
      return g_reason=="" ? "SELECTIVE SCANNING" : g_reason;
   if(InpAggressiveMode && g_state==S2_WAIT_AOI)
   {
      if(g_reason=="WAIT_M1_IMPULSE_OR_BREAK") return "WAITING M1 SIGNAL";
      if(g_reason=="SPREAD_HIGH") return "SPREAD FILTER";
      if(g_reason=="SL_OVER_50") return "SL FILTER";
      return "SEARCHING M5 AOI";
   }
   switch((EState)g_state)
   {
      case S0_WAIT_DATA:       return "LOADING HISTORY";
      case S1_WAIT_BIAS:       return "H1 / M30 BIAS";
      case S2_WAIT_AOI:        return "WAITING AOI TOUCH";
      case S3_WAIT_M15_M5:     return "WAITING MSS + FVG";
      case S4_WAIT_M3:        return "WAITING M3 MSS";
      case S5_WAIT_M1:        return "WAITING M1 CISD";
      case S6_RISK_CHECK:     return "RISK VALIDATION";
      case S7_LIMIT_ACTIVE:   return "LIMIT ORDER ACTIVE";
      case S8_POSITION_ACTIVE:return "POSITION ACTIVE";
      case S9_COOLDOWN:       return "COOLDOWN";
   }
   return "IDLE";
}
void UpdateDashboard()
{
   if(!InpShowDashboard) return;
   RefreshActivePositionPlan();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid = (ask + bid) * 0.5;
   if(g_pip > 0) g_lastSpread = (ask - bid) / g_pip;
   bool v1=false, v2=false;
   double p1 = -1, p2 = -1;
   if(g_ready) { p1 = PDPos(PERIOD_H1, mid, v1); p2 = PDPos(PERIOD_M30, mid, v2); }
   int x=InpPanelLeft, y=InpPanelTop, w=432;
   color bg=C'14,23,35', line=C'48,62,81', text=C'220,232,245';
   color muted=C'142,163,185', cyan=C'74,196,240', green=C'75,221,177';
   UIBox("SHADOW",x+3,y+4,w,652,C'8,12,20',C'8,12,20');
   UIBox("PANEL",x,y,w,650,bg,line);
   UIBox("HEAD",x+1,y+1,w-2,52,C'23,38,55',C'23,38,55');
   UIBox("ACCENT",x+1,y+1,5,52,cyan,cyan);
   UILabel("TITLE","S M C    /    X A U U S D",x+17,y+9,C'245,249,255',14,"Arial");
   UILabel("SUB","SMART MONEY EXECUTION    |    v2.63",x+18,y+33,muted,8,"Consolas");
   int yy=y+64;
   UILabel("MODE",StringFormat("%s    %s",_Symbol,InpAggressiveMode ? (InpSelectiveMode ? (InpOBFVGEntryMode ? "OB+FVG TF/CT" : "SELECTIVE (OLD)") : "AGGRESSIVE (LEGACY)") : (InpStrictMode ? "STRICT" : "BALANCED")),x+15,yy,cyan,10);
   UILabel("STATE",StateText(),x+177,yy,green,9);
   UIBox("DIV1",x+13,y+91,w-26,1,line,line);
   UILabel("BIASHEAD","01   HIGHER TIMEFRAME BIAS",x+15,y+103,cyan,9);
   UILabel("H1TITLE","H1",x+17,y+128,muted,9);
   string h1text=InpAggressiveMode ? StringFormat("MOM %s  |  PD %s %.0f%%",
          g_aggBiasH1>0?"BUY":g_aggBiasH1<0?"SELL":"--",BiasText(p1),p1<0?0:p1*100)
          : StringFormat("%-20s %6.1f%%",BiasText(p1),p1<0?0:p1*100);
   UILabel("H1",h1text,x+64,y+128,InpAggressiveMode?cyan:BiasColor(p1),8);
   UILabel("M30TITLE","M30",x+17,y+150,muted,9);
   string m30text=InpAggressiveMode ? StringFormat("MOM %s  |  PD %s %.0f%%",
          g_aggBiasM30>0?"BUY":g_aggBiasM30<0?"SELL":"--",BiasText(p2),p2<0?0:p2*100)
          : StringFormat("%-20s %6.1f%%",BiasText(p2),p2<0?0:p2*100);
   UILabel("M30",m30text,x+64,y+150,InpAggressiveMode?cyan:BiasColor(p2),8);
   UIBox("DIV2",x+13,y+176,w-26,1,line,line);
   UILabel("AOIHEAD","02   AREA OF INTEREST",x+15,y+190,cyan,9);
   string aoiStr="WAITING FOR CONFIRMED FVG";
   string aoiPrice="No valid zone in range";
   if(g_setup.active)
   {
      aoiStr=StringFormat("%s  %s",g_setup.dir>0 ? "BUY" : "SELL",g_setup.zoneId);
      aoiPrice=(InpAggressiveMode?"ACTIVE MTF AOI: ":"ACTIVE HTF FVG: ")+
                DoubleToString(g_setup.zlo,_Digits)+" - "+DoubleToString(g_setup.zhi,_Digits);
   }
   else if(InpAggressiveMode && g_aggAOIVisible)
   {
      aoiStr=StringFormat("%s  %s  VOL %.2fx",g_aggDir>0?"BUY":"SELL",g_aggAOIType,g_aggAOIVol);
      aoiPrice=StringFormat("NEAR AOI: %.2f - %.2f",g_aggAOILo,g_aggAOIHi);
   }
   else
   {
      double best = DBL_MAX;
      for(int i=0;i<ArraySize(g_zones);i++)
      {
         if(g_zones[i].dead || TimeCurrent()-g_zones[i].born > (long)InpZoneMaxAgeHours*3600) continue;
         double dist = mid < g_zones[i].lo ? g_zones[i].lo-mid : mid > g_zones[i].hi ? mid-g_zones[i].hi : 0;
         if(dist < best)
         {
            best=dist;
            aoiStr=(g_zones[i].dir>0?"BUY":"SELL")+" / "+EnumToString(g_zones[i].tf);
            aoiPrice="NEAREST FVG: "+DoubleToString(g_zones[i].lo,_Digits)+" - "+DoubleToString(g_zones[i].hi,_Digits);
         }
      }
   }
   if(InpAggressiveMode && InpSelectiveMode && InpOBFVGEntryMode && g_ctActive)
      aoiStr="RETRACE " + aoiStr;
   UILabel("AOIID",aoiStr,x+16,y+214,g_setup.active?green:muted,8);
   UILabel("AOIPRICE",aoiPrice,x+16,y+234,text,9);
   UILabel("AOIMODE","ROUTE: "+(g_setup.route==""?(InpAggressiveMode?(InpSelectiveMode&&InpOBFVGEntryMode?g_entryModel:"MARKET ON M1 CONFIRM"):"PENDING CONFIRMATION"):g_setup.route),x+16,y+252,muted,8);
   UIBox("DIV3",x+13,y+274,w-26,1,line,line);
   UILabel("STRUCTHEAD","03   MARKET STRUCTURE / TRIGGER",x+15,y+286,cyan,9);
   UILabel("BOS",InpAggressiveMode?(InpSelectiveMode ? "M5 BOS : "+g_selBOSState : "BOS M15 : OPTIONAL (AGG)"):"BOS M15      : "+ShortTime(g_setup.bosT),x+16,y+309,g_setup.bosT>0?green:muted,8);
   UILabel("MSS15",InpAggressiveMode?(InpSelectiveMode&&InpOBFVGEntryMode?"SIGNAL: "+g_entryModel:"MSS M15 : OPTIONAL"):"MSS M15      : "+ShortTime(g_setup.m15Mss),x+16,y+327,g_setup.m15Mss>0?green:muted,8);
   UILabel("MSS5",InpAggressiveMode?(InpSelectiveMode&&InpOBFVGEntryMode?
      "CT FILTER : "+g_ctDiagnostic:
      "M5 FVG VOL: "+DoubleToString(g_aggAOIVol,2)+"x"):
      "MSS M5       : "+ShortTime(g_setup.m5Mss),x+16,y+345,g_ctActive?green:muted,8);
   UILabel("MSS3",InpAggressiveMode?(InpSelectiveMode ? "OB RETEST : "+g_selTouchState : "M1 TRIGGER : "+(g_aggSignal==""?"WAITING":g_aggSignal)):
      "MSS M3       : "+((InpStrictMode||InpRequireM3MSS)?ShortTime(g_setup.m3Mss):"OPTIONAL"), x+16,y+363,g_setup.m3Mss>0?green:muted,8);
   UILabel("ZONE5",g_setup.hasFVG5?StringFormat("M5 FVG %.2f - %.2f  VOL %.2fx %s",g_setup.fvg5lo,g_setup.fvg5hi,g_setup.fvg5Ratio,g_setup.fvg5Real?"REAL":"TICK"):
      (InpAggressiveMode?(InpSelectiveMode&&InpOBFVGEntryMode&&g_pairVisible?
       StringFormat("M5 FVG %.2f - %.2f VOL %.2fx",g_pairFVGLo,g_pairFVGHi,g_pairVol):
       (g_aggAOIVisible?"ACTIVE: "+g_aggAOIType:"M5 FVG: WAIT OB+FVG PAIR")):"M5 FVG: WAITING"),x+16,y+382,g_setup.hasFVG5?green:muted,8);
   UILabel("ZONEOB",g_setup.hasOB?StringFormat("OB %.2f - %.2f",g_setup.obLo,g_setup.obHi):
      (InpAggressiveMode?"OB: REQUIRE FVG + DISPLACEMENT":"OB: WAITING / OPTIONAL"),x+16,y+400,muted,8);
   UIBox("DIV4",x+13,y+422,w-26,1,line,line);
   UILabel("RISKHEAD","04   TRADE PLAN & DIAGNOSTICS",x+15,y+434,cyan,9);
   UILabel("ENTRY",StringFormat("ENTRY %.2f   SL %.2f   TP %.2f",g_planEntry,g_planSL,g_planTP),x+16,y+456,text,8);
   UILabel("RISK",StringFormat("INIT SL %.1f pip | RR SET %.2f | RR PLAN %.2f",
         (InpAggressiveMode&&InpAggressiveFixedSL?InpAggressiveSLPips:g_planSLpips),
         InpTargetRR,g_planRR>0?g_planRR:InpTargetRR),
         x+16,y+473,muted,8);
   string why = g_reason == "" ? "WAITING SIGNAL" : g_reason;
   UILabel("REASON",StringFormat("SPRD %.1f/%.1f pip  |  %s",g_lastSpread,InpMaxSpreadPips,why),x+16,y+491,
      g_reason==""?green:C'255,198,91',8);
   string funnelText=InpAggressiveMode ?
      StringFormat("LEGACY: M1_CONF %d  FILLS %d / DAILY %d",g_aggConfirmed,g_aggOrders,AggDealsToday()) :
      StringFormat("FUNNEL: Z%d AOI%d MSS%d M1%d LIMIT%d",g_fZone,g_fAOI,g_fS3,g_fS5,g_fPlaced);
   if(InpAggressiveMode && InpSelectiveMode && InpOBFVGEntryMode)
      funnelText=StringFormat("OB+FVG LIMITS %d | ENTRIES %d | PENDING %s",
                              g_fPlaced,g_selEntries,g_hasPend?"YES":"NO");
   UILabel("FUNNEL",funnelText,x+16,y+516,muted,8);
   if(InpAggressiveMode && InpSelectiveMode)
   {
      UILabel("SEL_STATS",StringFormat("DAY %d/%d | LOSS STREAK %d/%d | NET %.2f",
         g_selEntries,InpSelectiveMaxDaily,g_selLossStreak,InpSelectiveMaxLossStreak,g_selDayPnL),
         x+16,y+538,muted,8);
      UILabel("SEL_RISK",StringFormat("RISK %.2f%% / %.2f%% MAX | LOSS PAUSE %d min",
         g_selRiskPct,InpSelectiveRiskPct,InpSelectiveLossPauseMin),
         x+16,y+557,muted,8);
   }
   UILabel("RRMODE",StringFormat("TP = RR USER %.2f x RISIKO | SL AWAL TETAP",InpTargetRR),
      x+16,y+582,cyan,8);
   int completed=g_rollingWins+g_rollingLosses+g_rollingScratch;
   double winrate=completed>0?100.0*g_rollingWins/completed:0.0;
   UILabel("STATS",StringFormat("CLOSED 30d %d | W %d  L %d  FLAT %d | NET WR %.1f%%",
       completed,g_rollingWins,g_rollingLosses,g_rollingScratch,winrate),
       x+16,y+604,muted,8);
   ChartRedraw(0);
}

void DrawPriceZone(string key, datetime t1, datetime t2, double lo, double hi, color clr)
{
   if(lo <= 0 || hi <= lo || t1 <= 0 || t2 <= t1) return;
   string n=g_prefix+"ZONE_"+key;
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,hi,t2,lo);
   else { ObjectMove(0,n,0,t1,hi); ObjectMove(0,n,1,t2,lo); }
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FILL,true);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}
void DrawPriceLine(string key, double price, color clr, ENUM_LINE_STYLE style)
{
   string n=g_prefix+"LINE_"+key;
   if(price <= 0) { ObjectDelete(0,n); return; }
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,n,OBJPROP_PRICE,price);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_STYLE,style);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}
void UpdateZoneDrawings()
{
   if(!InpDrawZones) return;
   ObjectsDeleteAll(0,g_prefix+"ZONE_",0,-1);
   datetime now=TimeCurrent();
   int sec=PeriodSeconds(_Period); if(sec<=0) sec=60;
   datetime future=now+(datetime)(sec*48);
   int drawn=0;
   // Sort visual secara pragmatis: area HTF aktif dan area-area valid terbaru.
   for(int i=ArraySize(g_zones)-1;i>=0 && drawn<InpMaxDrawnZones;i--)
   {
      if(g_zones[i].dead || now-g_zones[i].born > (long)InpZoneMaxAgeHours*3600) continue;
      string k=IntegerToString(drawn);
      DrawPriceZone("HTF_"+k,g_zones[i].born,future,g_zones[i].lo,g_zones[i].hi,
         g_zones[i].dir>0?C'21,75,65':C'90,40,58');
      drawn++;
   }
   if(InpAggressiveMode && g_aggAOIVisible)
      DrawPriceZone("AGG_AOI",now-(datetime)(PeriodSeconds(PERIOD_M5)*InpAggressiveScanM5),future,
                    g_aggAOILo,g_aggAOIHi,C'30,101,125');
   if(InpAggressiveMode && InpSelectiveMode && InpOBFVGEntryMode && g_pairVisible)
      DrawPriceZone("CANDIDATE_FVG",now-(datetime)(PeriodSeconds(PERIOD_M5)*InpOBFVGScanM5),future,
                    g_pairFVGLo,g_pairFVGHi,C'24,96,147');
   if(g_setup.active)
   {
      DrawPriceZone("ACTIVE_AOI",g_setup.aoiTime,future,g_setup.zlo,g_setup.zhi,
         g_setup.dir>0?C'32,126,94':C'153,60,78');
      if(g_setup.hasOB) DrawPriceZone("ORDER_BLOCK",g_setup.aoiTime,future,g_setup.obLo,g_setup.obHi,C'72,60,122');
      if(g_setup.hasFVG5) DrawPriceZone("FVG_M5",g_setup.aoiTime,future,g_setup.fvg5lo,g_setup.fvg5hi,C'24,96,147');
   }
   DrawPriceLine("ENTRY",g_planEntry,C'94,214,243',STYLE_SOLID);
   DrawPriceLine("STOP",g_planSL,C'244,95,113',STYLE_DASH);
   DrawPriceLine("TARGET",g_planTP,C'73,211,164',STYLE_DASH);
   g_zoneRefresh = false;
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Init / loop / transaksi                                          |
//+------------------------------------------------------------------+
bool TryInitData()
{
   ENUM_TIMEFRAMES tfs[6] = { PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M3, PERIOD_M1 };
   int needed[6] = { 300, 300, 200, 200, 160, 180 };
   if(InpAggressiveMode)
   {
      needed[0]=135; needed[1]=135; needed[2]=85;
      needed[3]=(InpSelectiveMode?160:90); needed[4]=0; needed[5]=90;
   }
   for(int i = 0; i < 6; i++)
   {
      // M3 adalah konfirmasi opsional dalam BALANCED: jangan tahan seluruh EA karena data M3 kosong.
      if(i == 4 && (InpAggressiveMode || (!InpStrictMode && !InpRequireM3MSS))) continue;
      if(Bars(_Symbol, tfs[i]) < needed[i]) return false;
      MqlRates t[];
      if(CopyRates(_Symbol, tfs[i], 0, needed[i], t) < needed[i]) return false;
   }
   int scanBars=InpAggressiveMode?MathMin(55,InpInitScanBars):InpInitScanBars;
   ScanTF(PERIOD_H1, 1, scanBars);
   ScanTF(PERIOD_M30, 1, scanBars);
   g_lastH1 = iTime(_Symbol, PERIOD_H1, 0);
   g_lastM30 = iTime(_Symbol, PERIOD_M30, 0);
   g_lastM1 = iTime(_Symbol, PERIOD_M1, 0);
   g_ready = true;
   g_state = S2_WAIT_AOI;
   SyncState();
   PrintFormat("SMC v2.63 READY | HTF zones=%d | mode=%s | pipPrice=%.2f | fixedSL=%.1f | RR_TARGET=%.2f", ArraySize(g_zones),
               InpAggressiveMode ? (InpSelectiveMode ? (InpOBFVGEntryMode ? "OB+FVG TF/CT" : "SELECTIVE (OLD)") : "AGGRESSIVE (LEGACY)") : (InpStrictMode ? "STRICT" : "BALANCED"),
               g_pip, InpAggressiveSLPips,InpTargetRR);
   return true;
}

int OnInit()
{
   string nm = _Symbol; StringToUpper(nm);
   string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string prof = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   string desc = SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION); StringToUpper(desc);
   string path = SymbolInfoString(_Symbol, SYMBOL_PATH);        StringToUpper(path);
   double px   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool nameOk   = (StringFind(nm, "XAUUSD") == 0);               // nama dasar wajib XAUUSD (sufiks broker boleh)
   bool profOk   = (prof == "USD");
   bool metaGold = (base == "XAU") || StringFind(desc, "GOLD") >= 0 || StringFind(desc, "XAU") >= 0 ||
                   StringFind(path, "GOLD") >= 0 || StringFind(path, "XAU") >= 0;
   // Sebagian broker melaporkan base=USD untuk emas: fallback sanity harga (emas >> perak/forex)
   bool priceOk  = (px <= 0 || (px > 500.0 && px < 50000.0));
   Print("Symbol check: ", _Symbol, " base=", base, " profit=", prof, " desc=", desc, " path=", path, " bid=", px);
   if(!nameOk || !profOk || !(metaGold || priceOk))
   {
      Print("NOT_XAUUSD: simbol ", _Symbol, " base=", base, " profit=", prof, " -> EA ditolak.");
      Alert("SMC EA: simbol bukan XAUUSD (NOT_XAUUSD). EA tidak aktif.");
      return INIT_FAILED;
   }
   g_tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tick <= 0) g_tick = _Point;
   g_pip = InpPipSizePrice;
   PrintFormat("SMC v2.63 UNIFIED TP CONFIG: InpTargetRR=%.2f (applies to OB+FVG Limit, Selective, Aggressive, Balanced/Strict)",InpTargetRR);
   PrintFormat("SMC v2.63 SL CONFIG | 1 user pip=%.3f XAUUSD price | 50 pip=%.3f price | fixed=%s | spread cap=%.3f price",
               g_pip,50.0*g_pip,InpAggressiveFixedSL?"YES":"NO",InpMaxSpreadPips*g_pip);
   if(g_pip <= 0) { Print("InpPipSizePrice harus > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxSLPips <= 0 || InpMaxSLPips > 50.0) { Print("InpMaxSLPips harus 0 < x <= 50"); return INIT_PARAMETERS_INCORRECT; }
   if(!MathIsValidNumber(InpTargetRR) || InpTargetRR < 0.25 || InpTargetRR > 20.0)
   { Print("InpTargetRR harus di antara 0.25 hingga 20.0 (contoh: 1.5, 2.0, 3.5, 5.0)"); return INIT_PARAMETERS_INCORRECT; }
   if(InpFixedLot <= 0 || !VolumeValid())
   { Print("Lot ", InpFixedLot, " tidak valid untuk broker (min/max/step). Tidak diubah otomatis."); return INIT_PARAMETERS_INCORRECT; }
   if(InpAggressiveFixedSL && (InpAggressiveSLPips<=0 || InpAggressiveSLPips>InpMaxSLPips || InpAggressiveSLPips>50.0))
   { Print("InpAggressiveSLPips harus <= InpMaxSLPips dan <= 50"); return INIT_PARAMETERS_INCORRECT; }
   if(InpAggressiveNearATR<=0 || InpAggressiveNearATR>5 ||
      InpAggressiveMinVolRatio<0 || InpAggressiveMinVolRatio>5 ||
      InpAggressiveM1BodyATR<=0 || InpAggressiveM1BodyATR>3 ||
      InpAggressiveMaxDaily<1 || InpAggressiveMaxDaily>100 ||
      InpAggressiveStopBars<2 || InpAggressiveStopBars>6 ||
      InpAggressiveScanM5<4 || InpAggressiveScanM5>55) return INIT_PARAMETERS_INCORRECT;
   if(InpSelectiveMode && (!InpAggressiveMode || !InpAggressiveFixedSL ||
      InpSelectiveMaxDaily<1 || InpSelectiveMaxDaily>30 ||
      InpSelectiveMaxLossStreak<1 || InpSelectiveMaxLossStreak>10 ||
      InpSelectiveDailyLossPct<=0 || InpSelectiveDailyLossPct>20 ||
      InpSelectiveRiskPct<=0 || InpSelectiveRiskPct>10 ||
      InpSelectiveLossPauseMin<0 || InpSelectiveZoneWaitMin<0 ||
      InpSelectiveNearATR<=0 || InpSelectiveNearATR>5 ||
      InpSelectiveTouchBars<1 || InpSelectiveTouchBars>12 ||
      InpSelectiveBOSBars<5 || InpSelectiveBOSBars>70 ||
      InpSelectiveM5VolRatio<0 || InpSelectiveM5VolRatio>5 ||
      InpSelectiveM1VolRatio<0 || InpSelectiveM1VolRatio>5 ||
      InpSelectiveM1MinBodyATR<=0 || InpSelectiveM1MaxBodyATR<=InpSelectiveM1MinBodyATR ||
      InpSelectiveSessionStart<0 || InpSelectiveSessionStart>23 ||
      InpSelectiveSessionEnd<0 || InpSelectiveSessionEnd>23))
   {Print("Invalid Selective configuration");return INIT_PARAMETERS_INCORRECT;}
   if(InpCTRangeM15Bars<8 || InpCTRangeM15Bars>65 ||
      InpCTExtremeFraction<=0.05 || InpCTExtremeFraction>0.50 ||
      InpCTOrderExpiryMinutes<5 || InpCTOrderExpiryMinutes>InpOrderExpiryMinutes)
   {Print("Invalid countertrend parameters");return INIT_PARAMETERS_INCORRECT;}
   if(InpOBFVGScanM5<5 || InpOBFVGScanM5>65 ||
      InpOBFVGMaxAgeM5Bars<2 || InpOBFVGMaxAgeM5Bars>65 ||
      InpOBFVGBOSLinkBars<1 || InpOBFVGBOSLinkBars>60 ||
      InpOBSearchPriorBars<1 || InpOBSearchPriorBars>10 ||
      InpOBFVGEntryDepth<0.0 || InpOBFVGEntryDepth>1.0 ||
      InpOBFVGMaxGapOB_ATR<=0.0 || InpOBFVGMaxGapOB_ATR>10.0 ||
      InpOBFVGMaxTravelATR<=0.0 || InpOBFVGMaxTravelATR>15.0 ||
      InpOBFVGDistalBufferPrice<0.0 || InpOrderExpiryMinutes<5 || InpOrderExpiryMinutes>1440)
   {Print("Invalid OB+FVG limit parameters");return INIT_PARAMETERS_INCORRECT;}
   if(InpQualityBOSMaxAgeM5Bars<1 || InpQualityBOSMaxAgeM5Bars>70 ||
      InpQualityRejMinBodyATR<0.0 || InpQualityRejMinBodyATR>3.0 ||
      InpQualityMaxChaseM1ATR<=0 || InpQualityMaxChaseM1ATR>10.0)
   {Print("Invalid v2.63 quality parameters");return INIT_PARAMETERS_INCORRECT;}
   if(InpPDBand < 0 || InpPDBand >= 0.5 || InpHTFSwingLeftRight < 1 || InpLTFSwingLeftRight < 1 ||
      InpZoneRetryMinutes < 0 || InpMaxAOIAttempts < 1 || InpInitScanBars < 1 || InpInitScanBars > 220 ||
      InpVolumeLookback < 3 || InpVolumeLookback > 50 ||
      InpDisplacementATRPeriod < 3 || InpDisplacementATRPeriod > 50 || InpMaxDrawnZones < 0 ||
      InpRejectionCloseBand <= 0 || InpRejectionCloseBand >= 1 || InpMinFVGATRFrac < 0)
   { Print("Parameter struktur/volume/visual tidak valid"); return INIT_PARAMETERS_INCORRECT; }
   g_prefix = StringFormat("SMC263_%I64d_", InpMagicNumber);
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetAsyncMode(false);
   ClearSetup();
   g_state = S0_WAIT_DATA;
   TryInitData();
   if(InpShowDashboard || InpDrawZones) EventSetTimer(3);
   if(InpShowDashboard) UpdateDashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix, 0, -1);
   Comment("");
   PrintFormat("FUNNEL zona=%d sentuhan_pertama=%d AOI_aktif=%d lolos_M15M5=%d lolos_M3=%d trigger_M1=%d limit_terpasang=%d",
               g_fZone, g_fTouch, g_fAOI, g_fS3, g_fS4, g_fS5, g_fPlaced);
   for(int i = 0; i < ArraySize(g_rcName); i++)
      PrintFormat("ALASAN %-28s = %d", g_rcName[i], g_rcCnt[i]);
}

void OnTick()
{
   if(!g_ready) { if(!TryInitData()) return; }
   SyncState();                                       // rekonsiliasi pending/posisi + expiry cadangan
   if(InpAggressiveMode && InpSelectiveMode && InpOBFVGEntryMode && g_hasPend &&
      TimeCurrent()>=g_nextOBPendingCheck)
   {
      g_nextOBPendingCheck=TimeCurrent()+20;
      CheckOBFVGPending();
   }
   if(InpAggressiveMode && InpAggressiveFixedSL && g_hasPos && TimeCurrent()>=g_nextStopAlignmentCheck)
   {
      g_nextStopAlignmentCheck=TimeCurrent()+20;
      AlignAggressiveSLToFill();
   }
   datetime t = iTime(_Symbol, PERIOD_M1, 0);
   if(t != g_lastM1) { g_lastM1 = t; OnNewM1(); }     // semua keputusan struktur hanya pada bar yang sudah close
}

void OnTimer()
{
   if(!g_ready) TryInitData();
   RefreshPerformanceStats();
   if(InpShowDashboard) UpdateDashboard();
   if(InpDrawZones && g_zoneRefresh) UpdateZoneDrawings();
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.symbol != _Symbol) return;
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
   {
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
      long en = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      g_lastTicket = trans.order;
      LogCSV(en == DEAL_ENTRY_IN ? "DEAL_IN" : "DEAL_OUT", "",
             StringFormat("price=%.2f profit=%.2f", HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                          HistoryDealGetDouble(trans.deal, DEAL_PROFIT)));
   }
   else if(trans.type == TRADE_TRANSACTION_REQUEST && result.retcode != 0 &&
           result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
   {
      g_lastRet = result.retcode;
      LogCSV("SERVER_REJECT", "ORDER_REJECTED", (string)result.retcode);
   }
}
//+------------------------------------------------------------------+
