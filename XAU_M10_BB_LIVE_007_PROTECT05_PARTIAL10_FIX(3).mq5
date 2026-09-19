//+------------------------------------------------------------------+
//| XAU_M10_BB_LIVE_007_PROTECT05_PARTIAL10_FIX.mq5                            |
//| Forward-test EA: NEW-A +0.5R protect / +1.0R split                   |
//| M10 dual BB -> +0.95R extension -> 0.10R pullback -> countertrend|
//| SL2R; +0.5R arms +0.25R SL; +1R closes 0.01; final target          |
//| = signal close + countertrend 0.90R                              |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input double Lots=0.02;
input bool EnableLiveOrders=false;
input long MagicNumber=95011007;
input double ExtensionR=0.95;
input double PullbackR=0.10;
input double InitialSL_R=2.0;
input double ProtectTriggerR=0.50;
input double PartialTriggerR=1.0;
input double ProtectR=0.25;
input double SignalOppositeTP_R=0.90;
input int MaxExtensionHours=72;
input int MaxPullbackHours=72;
input int MaxPositionHours=168;

int h20=INVALID_HANDLE,h4=INVALID_HANDLE;
datetime lastbar=0;

struct Setup{
 datetime sig,ct,exp;
 int sd;
 double R,o,h,l,c,extreme;
 bool ext;
};
Setup S[];

bool protection_armed=false;
bool managed_partial=false;
datetime tracked_entry_time=0;
double tracked_entry=0,tracked_R=0,tracked_sigclose=0;
int tracked_dir=0;

string GVKey(string name){
 return "LIVE007_"+IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+_Symbol+"_"+
        IntegerToString((int)MagicNumber)+"_"+name;
}
void SaveTrack(){
 GlobalVariableSet(GVKey("ENTRY_TIME"),(double)tracked_entry_time);
 GlobalVariableSet(GVKey("ENTRY"),tracked_entry);
 GlobalVariableSet(GVKey("R"),tracked_R);
 GlobalVariableSet(GVKey("SIGCLOSE"),tracked_sigclose);
 GlobalVariableSet(GVKey("DIR"),(double)tracked_dir);
 GlobalVariableSet(GVKey("PROTECTED"),protection_armed?1.0:0.0);
 GlobalVariableSet(GVKey("PARTIAL"),managed_partial?1.0:0.0);
 GlobalVariablesFlush();
}
bool LoadTrack(){
 if(!GlobalVariableCheck(GVKey("R")))return false;
 tracked_entry_time=(datetime)GlobalVariableGet(GVKey("ENTRY_TIME"));
 tracked_entry=GlobalVariableGet(GVKey("ENTRY"));
 tracked_R=GlobalVariableGet(GVKey("R"));
 tracked_sigclose=GlobalVariableGet(GVKey("SIGCLOSE"));
 tracked_dir=(int)GlobalVariableGet(GVKey("DIR"));
 protection_armed=GlobalVariableGet(GVKey("PROTECTED"))>0.5;
 managed_partial=GlobalVariableGet(GVKey("PARTIAL"))>0.5;
 return tracked_entry_time>0 && tracked_entry>0 && tracked_R>0 && (tracked_dir==1||tracked_dir==-1);
}
void ClearTrack(){
 string names[]={"ENTRY_TIME","ENTRY","R","SIGCLOSE","DIR","PROTECTED","PARTIAL"};
 for(int i=0;i<ArraySize(names);i++)GlobalVariableDel(GVKey(names[i]));
}
bool TradeResultOK(){
 uint rc=trade.ResultRetcode();
 return rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL ||
        rc==TRADE_RETCODE_PLACED || rc==TRADE_RETCODE_NO_CHANGES;
}

void DS(int i){int n=ArraySize(S);for(int j=i;j<n-1;j++)S[j]=S[j+1];ArrayResize(S,n-1);}
bool OwnPosition(ulong &ticket){
 for(int i=PositionsTotal()-1;i>=0;i--){
  ulong t=PositionGetTicket(i);
  if(t>0 && PositionSelectByTicket(t) &&
     PositionGetString(POSITION_SYMBOL)==_Symbol &&
     (long)PositionGetInteger(POSITION_MAGIC)==MagicNumber){ticket=t;return true;}
 }
 return false;
}
void ResetTrack(){protection_armed=false;managed_partial=false;tracked_entry_time=0;tracked_entry=tracked_R=tracked_sigclose=0;tracked_dir=0;}

void NewBar(){
 datetime q=iTime(_Symbol,PERIOD_M10,0); if(!q||q==lastbar)return; lastbar=q;
 datetime st=iTime(_Symbol,PERIOD_M10,1);
 double o=iOpen(_Symbol,PERIOD_M10,1),h=iHigh(_Symbol,PERIOD_M10,1),l=iLow(_Symbol,PERIOD_M10,1),c=iClose(_Symbol,PERIOD_M10,1);
 double u20[1],d20[1],u4[1],d4[1];
 if(CopyBuffer(h20,1,1,1,u20)!=1||CopyBuffer(h20,2,1,1,d20)!=1||
    CopyBuffer(h4,1,1,1,u4)!=1||CopyBuffer(h4,2,1,1,d4)!=1)return;
 bool bull=c>o&&h>=u20[0]&&h>=u4[0], bear=c<o&&l<=d20[0]&&l<=d4[0];
 if(!bull&&!bear)return;
 double R=MathAbs(c-o);if(R<=0)return;
 int n=ArraySize(S);ArrayResize(S,n+1);
 S[n].sig=st;S[n].ct=st+PeriodSeconds(PERIOD_M10);S[n].exp=S[n].ct+MaxExtensionHours*3600;
 S[n].sd=bull?1:-1;S[n].R=R;S[n].o=o;S[n].h=h;S[n].l=l;S[n].c=c;S[n].extreme=c;S[n].ext=false;
 Print("LIVE007 | SIGNAL | ",bull?"BULL":"BEAR"," R=",DoubleToString(R,2));
}

bool SendEntry(int i,MqlTick &tk){
 ulong old; if(OwnPosition(old)){DS(i);return false;} // strict own-Magic MAX1; consume setup
 int dir=-S[i].sd; double R=S[i].R;
 double entry=(dir==1?tk.ask:tk.bid);
 double sl=entry-dir*InitialSL_R*R;
 double finaltp=S[i].c+dir*SignalOppositeTP_R*R;
 trade.SetExpertMagicNumber(MagicNumber);
 trade.SetTypeFillingBySymbol(_Symbol);
 bool ok=false;
 if(EnableLiveOrders){
  ok=(dir==1)?trade.Buy(Lots,_Symbol,0,sl,finaltp,"LIVE007_P05P10")
             :trade.Sell(Lots,_Symbol,0,sl,finaltp,"LIVE007_P05P10");
 }else{
  Print("LIVE007 | DRY ENTRY | ",dir==1?"BUY":"SELL"," entry~",DoubleToString(entry,_Digits),
        " R=",DoubleToString(R,2)," SL=",DoubleToString(sl,_Digits)," finalTP=",DoubleToString(finaltp,_Digits));
  DS(i);return false;
 }
 if(!ok){Print("LIVE007 | ENTRY FAILED | retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());DS(i);return false;}
 ulong t;
 if(OwnPosition(t)&&PositionSelectByTicket(t)){
  tracked_entry=PositionGetDouble(POSITION_PRICE_OPEN);
  tracked_entry_time=(datetime)PositionGetInteger(POSITION_TIME);
 }else{tracked_entry=entry;tracked_entry_time=(datetime)(tk.time_msc/1000);}
 tracked_R=R;tracked_sigclose=S[i].c;tracked_dir=dir;protection_armed=false;managed_partial=false;
 SaveTrack();
 Print("LIVE007 | ENTRY OK | ",dir==1?"BUY":"SELL"," entry=",DoubleToString(tracked_entry,_Digits),
       " R=",DoubleToString(R,2)," lots=",DoubleToString(Lots,2));
 DS(i);return true;
}

void ManageSetups(MqlTick &tk){
 datetime now=(datetime)(tk.time_msc/1000);
 for(int i=ArraySize(S)-1;i>=0;i--){
  if(now<S[i].ct)continue;
  double px=S[i].sd==1?tk.bid:tk.ask;
  if(!S[i].ext){
   if(now>S[i].exp){DS(i);continue;}
   double ext=S[i].c+S[i].sd*ExtensionR*S[i].R;
   if(S[i].sd==1?px>=ext:px<=ext){S[i].ext=true;S[i].extreme=px;S[i].exp=now+MaxPullbackHours*3600;Print("LIVE007 | EXT HIT");}
  }else{
   if(now>S[i].exp){DS(i);continue;}
   if(S[i].sd==1&&px>S[i].extreme)S[i].extreme=px;
   if(S[i].sd==-1&&px<S[i].extreme)S[i].extreme=px;
   double tr=S[i].extreme-S[i].sd*PullbackR*S[i].R;
   if(S[i].sd==1?px<=tr:px>=tr){Print("LIVE007 | PB CONFIRM");SendEntry(i,tk);}
  }
 }
}

void ManageOwn(MqlTick &tk){
 ulong ticket;
 if(!OwnPosition(ticket)){
  if(tracked_entry_time!=0){ClearTrack();ResetTrack();}
  return;
 }
 if(!PositionSelectByTicket(ticket))return;

 int dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
 double entry=PositionGetDouble(POSITION_PRICE_OPEN);
 double vol=PositionGetDouble(POSITION_VOLUME);

 if(tracked_entry_time==0){
  // Restart/re-attach recovery. Prefer the exact state saved at entry.
  if(LoadTrack() && tracked_dir==dir && MathAbs(tracked_entry-entry)<=MathMax(_Point*10,0.02)){
   Print("LIVE007 | RECOVERY OK | saved state restored | entry=",DoubleToString(tracked_entry,_Digits),
         " R=",DoubleToString(tracked_R,2)," protected=",protection_armed?"YES":"NO",
         " partial=",managed_partial?"YES":"NO");
  }else{
   // Fallback for positions opened by older builds: infer R from the current SL.
   tracked_entry_time=(datetime)PositionGetInteger(POSITION_TIME);
   tracked_entry=entry; tracked_dir=dir;
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   bool initial_sl=(sl>0 && (dir==1?sl<entry:sl>entry));
   bool locked_sl=(sl>0 && (dir==1?sl>entry:sl<entry));
   if(initial_sl)tracked_R=MathAbs(entry-sl)/InitialSL_R;
   else if(locked_sl){tracked_R=MathAbs(sl-entry)/ProtectR;protection_armed=true;}
   if(tracked_R<=0){
    Print("LIVE007 | RECOVERY FAILED | R cannot be reconstructed; manual management required.");
    return;
   }
   if(tp>0)tracked_sigclose=tp-dir*SignalOppositeTP_R*tracked_R;
   double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   managed_partial=(vol<Lots-vstep/2.0);
   SaveTrack();
   Print("LIVE007 | RECOVERY FALLBACK OK | R=",DoubleToString(tracked_R,2),
         " protected=",protection_armed?"YES":"NO"," partial=",managed_partial?"YES":"NO");
  }
 }

 datetime now=(datetime)(tk.time_msc/1000);
 if(now>tracked_entry_time+MaxPositionHours*3600){
  if(EnableLiveOrders && trade.PositionClose(ticket))Print("LIVE007 | TIMEOUT CLOSE");
  return;
 }
 if(tracked_R<=0)return;

 double px=dir==1?tk.bid:tk.ask;
 double protect_trigger=tracked_entry+dir*ProtectTriggerR*tracked_R;
 double partial_trigger=tracked_entry+dir*PartialTriggerR*tracked_R;
 double lock=tracked_entry+dir*ProtectR*tracked_R;

 // Stage 1: once +0.5R is reached, protect the WHOLE 0.02 position at +0.25R.
 if(!protection_armed){
  bool reached05=dir==1?px>=protect_trigger:px<=protect_trigger;
  if(!reached05)return;

  if(!EnableLiveOrders){
   Print("LIVE007 | DRY PROTECT | +0.5R reached; would move whole-position SL to +0.25R");
   protection_armed=true;
  }else{
   trade.SetExpertMagicNumber(MagicNumber);
   double tp=PositionGetDouble(POSITION_TP);
   if(!trade.PositionModify(ticket,lock,tp) || !TradeResultOK()){
    Print("LIVE007 | PROTECT MODIFY FAILED | ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
    return; // retry on later ticks; do not mark armed until broker accepts it
   }
   protection_armed=true;
   SaveTrack();
   Print("LIVE007 | PROTECT ARMED | +0.5R reached; whole SL=",DoubleToString(lock,_Digits),
         " | volume=",DoubleToString(vol,2));
  }
 }

 // Stage 2: at +1.0R, close half (0.01 from 0.02). Runner keeps +0.25R SL.
 if(managed_partial)return;
 bool reached10=dir==1?px>=partial_trigger:px<=partial_trigger;
 if(!reached10)return;

 double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
 double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
 double half=MathFloor((vol/2.0)/vstep+1e-8)*vstep;
 if(half<vmin)half=vmin;
 double remain=vol-half;
 if(remain+1e-8<vmin){
  Print("LIVE007 | PARTIAL IMPOSSIBLE | volume=",DoubleToString(vol,2));
  return;
 }

 if(!EnableLiveOrders){
  Print("LIVE007 | DRY PARTIAL | +1.0R reached; would close ",DoubleToString(half,2),
        " and keep runner SL +0.25R");
  managed_partial=true;
  return;
 }

 trade.SetExpertMagicNumber(MagicNumber);
 double before_vol=vol;
 if(!trade.PositionClosePartial(ticket,half) || !TradeResultOK()){
  Print("LIVE007 | PARTIAL FAILED | ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
  return;
 }

 // IMPORTANT: on a hedging account the remaining position may no longer be
 // selectable by the original ticket immediately after a partial close.
 // Mark the partial as completed first so it can never fire repeatedly.
 // Re-find the surviving own-Magic position instead of assuming the old ticket survives.
 ulong runner_ticket=0;
 if(!OwnPosition(runner_ticket) || !PositionSelectByTicket(runner_ticket)){
  Print("LIVE007 | PARTIAL VERIFY FAILED | close request accepted but runner not found; check account history.");
  return;
 }

 double tp=PositionGetDouble(POSITION_TP);
 double runner_vol=PositionGetDouble(POSITION_VOLUME);
 if(runner_vol>=before_vol-vstep/2.0){
  Print("LIVE007 | PARTIAL VERIFY FAILED | volume unchanged at ",DoubleToString(runner_vol,2),
        " | retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
  return;
 }
 managed_partial=true;
 SaveTrack();

 // A partial close inherits the position's existing SL/TP. Re-sending the same
 // stops can be rejected as INVALID_STOPS when price is close to TP, so verify
 // the inherited protection instead of submitting a redundant modification.
 double runner_sl=PositionGetDouble(POSITION_SL);
 bool lock_kept=(runner_sl>0 && (dir==1?runner_sl>=lock-_Point:runner_sl<=lock+_Point));
 if(!lock_kept){
  Print("LIVE007 | RUNNER PROTECTION WARNING | inherited SL=",DoubleToString(runner_sl,_Digits),
        " expected=",DoubleToString(lock,_Digits)," | manual check required");
  return;
 }

 Print("LIVE007 | PARTIAL OK | closed=",DoubleToString(half,2),
       " runner=",DoubleToString(runner_vol,2),
       " inherited_lock=",DoubleToString(runner_sl,_Digits),
       " finalTP=",DoubleToString(tp,_Digits));
}
int OnInit(){
 if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){
  Print("LIVE007 INIT FAILED: HEDGING account required.");return INIT_FAILED;
 }
 h20=iBands(_Symbol,PERIOD_M10,20,0,2.0,PRICE_CLOSE);
 h4=iBands(_Symbol,PERIOD_M10,4,0,4.0,PRICE_OPEN);
 if(h20==INVALID_HANDLE||h4==INVALID_HANDLE)return INIT_FAILED;
 trade.SetExpertMagicNumber(MagicNumber);
 Print("LIVE007 P05/P10 | START | M10 | PB=0.10R | SL=2R | Lots=",DoubleToString(Lots,2),
       " | Magic=",MagicNumber," | orders=",EnableLiveOrders?"ENABLED":"DRY");
 Print("LIVE007 | EXIT | +0.5R whole-position SL -> +0.25R; +1.0R close half; runner +0.25R; final signal-close opposite 0.90R");
 return INIT_SUCCEEDED;
}
void OnTick(){
 MqlTick tk;if(!SymbolInfoTick(_Symbol,tk))return;
 NewBar();
 ManageSetups(tk);   // same ordering principle as validator
 ManageOwn(tk);
}
void OnDeinit(const int reason){
 if(h20!=INVALID_HANDLE)IndicatorRelease(h20);
 if(h4!=INVALID_HANDLE)IndicatorRelease(h4);
}
//+------------------------------------------------------------------+
